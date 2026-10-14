// Xvico's bounded, administrator-approved Apple PacketLogger capture session.
// No daemon, HAL plug-in, microphone fallback, activation or network access.
import Foundation
import Darwin

private enum CaptureError: Error { case invalidArguments, invalidDirectory, untrustedRuntime, invalidPreferences, metadataWrite }
private let debugURL = URL(fileURLWithPath: "/Library/Preferences/com.apple.MobileBluetooth.debug.plist")
private let debugDomain = "/Library/Preferences/com.apple.MobileBluetooth.debug"
private var interrupted: sig_atomic_t = 0

private func run(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
    process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
    process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
    try process.run(); process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw CaptureError.untrustedRuntime }
}
private func readPreferences() throws -> [String: Any] {
    let p = Process(); let pipe = Pipe()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults"); p.arguments = ["export", debugDomain, "-"]
    p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
    try p.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
    if p.terminationStatus != 0 && !FileManager.default.fileExists(atPath: debugURL.path) { return [:] }
    guard let value = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { throw CaptureError.invalidPreferences }
    return value
}
private func writePreferences(_ value: [String: Any]) throws {
    let data = try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
    let temporary = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("xvibe-pref-\(UUID()).plist")
    try data.write(to: temporary, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
    defer { try? FileManager.default.removeItem(at: temporary) }
    try run("/usr/bin/defaults", ["import", debugDomain, temporary.path])
    try FileManager.default.setAttributes([.ownerAccountID: 0, .groupOwnerAccountID: 0, .posixPermissions: 0o644], ofItemAtPath: debugURL.path)
    try? run("/usr/bin/killall", ["-30", "bluetoothd"])
}
private func verifyAppleRuntime(_ root: URL) throws {
    for (path, id) in [("Resources/packetlogger", "com.apple.packetlogger"), ("Frameworks/PacketDecoder.framework", "com.apple.PacketDecoder")] {
        try run("/usr/bin/codesign", ["--verify", "--strict", "--all-architectures", "-R", "=identifier \"\(id)\" and anchor apple", root.appendingPathComponent(path).path])
    }
}

@main
enum XvibeVoiceCapture {
    static func main() throws {
        let args = CommandLine.arguments
        guard (args.count == 5 || args.count == 6 && args[5] == "--compat-diagnostics"), getuid() == 0, let uid = UInt32(args[3]), uid >= 500,
              let appPID = Int32(args[4]), appPID > 1, let owner = getpwuid(uid) else { throw CaptureError.invalidArguments }
        let home = String(cString: owner.pointee.pw_dir)
        let compatDiagnostics = args.count == 6
        let lock = open("/var/run/work.xvibe.diagnostic.lock", O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw CaptureError.invalidArguments }
        defer { close(lock) }
        signal(SIGTERM) { _ in interrupted = 1 }; signal(SIGINT) { _ in interrupted = 1 }
        let ownerGroup = UInt32(owner.pointee.pw_gid)
        let session = URL(fileURLWithPath: args[2]).standardizedFileURL
        let expected = URL(fileURLWithPath: home).appendingPathComponent("Library/Caches/Xvibe/VoiceSessions").standardizedFileURL
        guard session.deletingLastPathComponent() == expected, UUID(uuidString: session.lastPathComponent) != nil,
              session.resolvingSymlinksInPath() == session else { throw CaptureError.invalidDirectory }
        let attributes = try FileManager.default.attributesOfItem(atPath: session.path)
        guard (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == uid,
              attributes[.type] as? FileAttributeType == .typeDirectory else { throw CaptureError.invalidDirectory }
        let sessionDirectory = try SessionDirectory(session, ownerUID: uid)
        let runtime = URL(fileURLWithPath: args[1]).standardizedFileURL
        try verifyAppleRuntime(runtime)
        var template = Array("/private/var/tmp/xvibe-voice.XXXXXX".utf8CString)
        guard let pointer = mkdtemp(&template) else { throw CaptureError.invalidDirectory }
        let privateDirectory = URL(fileURLWithPath: String(cString: pointer))
        defer { try? FileManager.default.removeItem(at: privateDirectory) }
        try FileManager.default.setAttributes([.posixPermissions: 0o711], ofItemAtPath: privateDirectory.path)
        // Freeze the signed Apple components into a root-owned private directory
        // before invoking them as root. Clear inherited DYLD environment variables.
        let protectedRuntime = privateDirectory.appendingPathComponent("Runtime")
        let fm = FileManager.default
        try fm.createDirectory(at: protectedRuntime, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        for relative in ["Resources/packetlogger", "Frameworks/PacketDecoder.framework"] {
            let target = protectedRuntime.appendingPathComponent(relative)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: runtime.appendingPathComponent(relative), to: target)
        }
        if let entries = fm.enumerator(at: protectedRuntime, includingPropertiesForKeys: nil) {
            for case let path as URL in entries {
                var info = stat()
                guard lstat(path.path, &info) == 0 else { throw CaptureError.invalidDirectory }
                if info.st_mode & S_IFMT == S_IFLNK {
                    guard path.resolvingSymlinksInPath().path.hasPrefix(protectedRuntime.path + "/"),
                          lchown(path.path, 0, 0) == 0 else { throw CaptureError.invalidDirectory }
                } else {
                    guard info.st_mode & S_IFMT == S_IFDIR || info.st_mode & S_IFMT == S_IFREG else { throw CaptureError.invalidDirectory }
                    try fm.setAttributes([.ownerAccountID: 0, .groupOwnerAccountID: 0,
                        .posixPermissions: info.st_mode & S_IFMT == S_IFDIR || info.st_mode & 0o111 != 0 ? 0o755 : 0o644], ofItemAtPath: path.path)
                }
            }
        }
        try fm.setAttributes([.ownerAccountID: 0, .groupOwnerAccountID: 0, .posixPermissions: 0o755], ofItemAtPath: protectedRuntime.path)
        try verifyAppleRuntime(protectedRuntime)
        let trace = privateDirectory.appendingPathComponent("remote.pklg")
        let original = try readPreferences()
        let originalTraces = original["HCITraces"]
        let existed = FileManager.default.fileExists(atPath: debugURL.path)
        defer {
            if var current = try? readPreferences() {
                current["HCITraces"] = originalTraces
                if !existed && current.isEmpty {
                    try? run("/usr/bin/defaults", ["delete", debugDomain])
                    try? FileManager.default.removeItem(at: debugURL)
                }
                else { try? writePreferences(current) }
                try? run("/usr/bin/killall", ["-30", "bluetoothd"])
            }
        }
        var enabled = original
        var traces = originalTraces as? [String: Any] ?? [:]
        for key in ["StackDebugEnabled", "HCIAclData", "HCILiveTraces", "HIDTrace", "RawAudioTrace", "HCISignaling"] { traces[key] = true }
        traces["HCIFileTraces"] = false
        enabled["HCITraces"] = traces
        if compatDiagnostics {
            let keys = ["StackDebugEnabled", "HCILiveTraces", "HCIFileTraces", "RawAudioTrace", "HIDTrace", "HCISkipAuth"]
            var arguments = ["write", debugDomain, "HCITraces", "-dict"]
            for key in keys { arguments += [key, "-bool", "true"] }
            try run("/usr/bin/defaults", arguments)
            let readBack = try readPreferences()["HCITraces"] as? [String: Any] ?? [:]
            guard keys.allSatisfy({ (readBack[$0] as? Bool) == true }) else { throw CaptureError.invalidPreferences }
            try run("/usr/bin/killall", ["-30", "bluetoothd"])
        } else { try writePreferences(enabled) }
        umask(0o077)
        let capture = Process()
        capture.executableURL = protectedRuntime.appendingPathComponent("Resources/packetlogger")
        capture.arguments = ["convert", "-o", trace.path]
        capture.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        capture.standardOutput = FileHandle.nullDevice; capture.standardError = FileHandle.nullDevice
        try capture.run()
        defer { if capture.isRunning { capture.terminate(); capture.waitUntilExit() } }
        let limit = Date().addingTimeInterval(3600)
        let firstPacketDeadline = Date().addingTimeInterval(15)
        var ready = false
        while capture.isRunning && interrupted == 0 && Date() < limit && kill(appPID, 0) == 0 {
            if sessionDirectory.exists("stop") { break }
            let traceSize = (try? FileManager.default.attributesOfItem(atPath: trace.path)[.size] as? NSNumber)?.intValue ?? 0
            if !ready && Date() > firstPacketDeadline && traceSize == 0 {
                throw NSError(domain: "XvibeVoiceCapture", code: 10, userInfo: [NSLocalizedDescriptionKey:
                    "Apple PacketLogger 未收到任何蓝牙记录。请确认 Siri Remote 已连接，然后重新启动兼容语音采集。无需先安装蓝牙诊断配置。"])
            }
            if !ready && traceSize >= 13 {
                guard chown(trace.path, uid, ownerGroup) == 0 else { throw CaptureError.invalidDirectory }
                let metadata = try JSONSerialization.data(withJSONObject: ["capture": trace.path])
                try sessionDirectory.create("ready.json", data: metadata)
                ready = true
            }
            usleep(100_000)
        }
        if !ready { throw CaptureError.metadataWrite }
    }
}
