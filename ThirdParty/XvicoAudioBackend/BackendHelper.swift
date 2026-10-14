import Foundation
import Darwin

private let fm = FileManager.default
private let root = URL(fileURLWithPath: "/Library/Application Support/Xvibe/AudioBackend")
private let driver = URL(fileURLWithPath: "/Library/Audio/Plug-Ins/HAL/XvibeMicrophone.driver")
private let service = "system/work.xvibe.audio"
private let plist = URL(fileURLWithPath: "/Library/LaunchDaemons/work.xvibe.audio.plist")
private let identity = BackendSigningIdentity.fingerprint
private let voiceRoot = URL(fileURLWithPath: VoiceHelperContract.root)
private let voicePlist = URL(fileURLWithPath: "/Library/LaunchDaemons/\(VoiceHelperContract.label).plist")
private func fail(_ text: String) throws -> Never {
    throw NSError(domain: "XvicoBackend", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
}
@discardableResult private func command(_ path: String, _ args: [String], required: Bool = true) throws -> Int32 {
    let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
    p.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
    p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
    try p.run(); p.waitUntilExit()
    if required && p.terminationStatus != 0 { try fail("后端操作失败：\(URL(fileURLWithPath: path).lastPathComponent) 状态 \(p.terminationStatus)") }
    return p.terminationStatus
}
private func verify(_ url: URL) throws {
    try command("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-R", "=certificate leaf = H\"\(identity)\"", url.path])
}
private func owned(_ url: URL) throws {
    try fm.setAttributes([.ownerAccountID: 0, .groupOwnerAccountID: 0, .posixPermissions: 0o755], ofItemAtPath: url.path)
    if let e = fm.enumerator(at: url, includingPropertiesForKeys: nil) {
        for case let p as URL in e {
            let a = try fm.attributesOfItem(atPath: p.path)
            if a[.type] as? FileAttributeType == .typeSymbolicLink { continue }
            try fm.setAttributes([.ownerAccountID: 0, .groupOwnerAccountID: 0], ofItemAtPath: p.path)
        }
    }
}

private func protectedDirectory(_ url: URL) throws {
    if !fm.fileExists(atPath: url.path) {
        try fm.createDirectory(at: url, withIntermediateDirectories: false,
            attributes: [.ownerAccountID: 0, .groupOwnerAccountID: 0, .posixPermissions: 0o755])
    }
    var value = stat()
    guard lstat(url.path, &value) == 0, value.st_mode & S_IFMT == S_IFDIR,
          value.st_uid == 0, value.st_mode & 0o022 == 0 else { try fail("语音服务安装目录权限无效") }
}

private func hardenPayload(_ url: URL) throws {
    try fm.setAttributes([.ownerAccountID: 0, .groupOwnerAccountID: 0, .posixPermissions: 0o700], ofItemAtPath: url.path)
    guard let entries = fm.enumerator(at: url, includingPropertiesForKeys: nil) else { try fail("无法检查语音组件") }
    for case let path as URL in entries {
        var info = stat()
        guard lstat(path.path, &info) == 0 else { try fail("无法检查语音组件权限") }
        if info.st_mode & S_IFMT == S_IFLNK {
            guard path.resolvingSymlinksInPath().path.hasPrefix(url.path + "/") else { try fail("语音组件包含外部链接") }
            guard lchown(path.path, 0, 0) == 0 else { try fail("无法保护语音组件链接") }
        } else {
            guard info.st_mode & S_IFMT == S_IFDIR || info.st_mode & S_IFMT == S_IFREG else { try fail("语音组件类型无效") }
            let executable = info.st_mode & S_IFMT == S_IFDIR || info.st_mode & 0o111 != 0
            try fm.setAttributes([.ownerAccountID: 0, .groupOwnerAccountID: 0,
                .posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: path.path)
        }
    }
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
}

private func runtimeSource(app: URL, uid: uid_t) throws -> URL {
    guard uid >= 500, let user = getpwuid(uid),
          let source = VoiceRuntimeLocation.resolve(app: app, home: URL(fileURLWithPath: String(cString: user.pointee.pw_dir))) else {
        try fail("请先在语音设置中导入官方 Apple 运行时")
    }
    return source
}

private func copyAppleRuntime(from source: URL, to destination: URL) throws {
    try fm.createDirectory(at: destination, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    for (relative, _) in VoiceRuntimeLocation.components {
        let target = destination.appendingPathComponent(relative)
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: source.appendingPathComponent(relative), to: target)
    }
    try hardenPayload(destination)
    for (relative, identifier) in VoiceRuntimeLocation.components {
        try command("/usr/bin/codesign", ["--verify", "--deep", "--strict", "--all-architectures", "-R",
            "=identifier \"\(identifier)\" and anchor apple", destination.appendingPathComponent(relative).path])
    }
}

private func installVoiceService(from app: URL, uid: uid_t) throws {
    guard !fm.fileExists(atPath: plist.path) else { try fail("请先停止临时语音采集") }
    try verify(app)
    let parent = voiceRoot.deletingLastPathComponent()
    try protectedDirectory(parent.deletingLastPathComponent())
    try protectedDirectory(parent)
    let stage = parent.appendingPathComponent(".voice-service-stage-\(UUID())")
    let previous = parent.appendingPathComponent(".voice-service-previous-\(UUID())")
    try fm.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? fm.removeItem(at: stage) }
    let resources = app.appendingPathComponent("Contents/Resources")
    for name in [VoiceHelperContract.executable, "XvibeBackendRunner", "XvibeAudioRouter", "libopus.0.dylib"] {
        try fm.copyItem(at: resources.appendingPathComponent("AudioBackend/\(name)"), to: stage.appendingPathComponent(name))
        try verify(stage.appendingPathComponent(name))
    }
    try fm.copyItem(at: resources.appendingPathComponent("VoiceTools/XvibeVoiceCapture"), to: stage.appendingPathComponent("XvibeVoiceCapture"))
    try verify(stage.appendingPathComponent("XvibeVoiceCapture"))
    let runtime = stage.appendingPathComponent("PacketLoggerRuntime")
    try copyAppleRuntime(from: runtimeSource(app: app, uid: uid), to: runtime)
    try hardenPayload(stage)
    // Verify copied code after it is in root-only staging. No user-writable
    // executable or caller-selected command is ever run by the service.
    for name in [VoiceHelperContract.executable, "XvibeBackendRunner", "XvibeAudioRouter", "XvibeVoiceCapture", "libopus.0.dylib"] {
        try verify(stage.appendingPathComponent(name))
    }
    let previousPlist = try? Data(contentsOf: voicePlist)
    if fm.fileExists(atPath: voiceRoot.path) {
        try protectedDirectory(voiceRoot)
        try verify(voiceRoot.appendingPathComponent(VoiceHelperContract.executable))
    }
    if try command("/bin/launchctl", ["print", "system/\(VoiceHelperContract.label)"], required: false) == 0 {
        try command("/bin/launchctl", ["bootout", "system/\(VoiceHelperContract.label)"])
    }
    var replaced = false
    var installedNew = false
    do {
        if fm.fileExists(atPath: voiceRoot.path) { try fm.moveItem(at: voiceRoot, to: previous); replaced = true }
        try fm.moveItem(at: stage, to: voiceRoot)
        installedNew = true
        let value: [String: Any] = ["Label": VoiceHelperContract.label,
            "ProgramArguments": [voiceRoot.appendingPathComponent(VoiceHelperContract.executable).path],
            "MachServices": [VoiceHelperContract.label: true], "RunAtLoad": false,
            "KeepAlive": false, "ProcessType": "Background", "ExitTimeOut": 25,
            "AssociatedBundleIdentifiers": ["work.xvibe.remote"]]
        try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0).write(to: voicePlist, options: .atomic)
        try fm.setAttributes([.ownerAccountID: 0, .groupOwnerAccountID: 0, .posixPermissions: 0o644], ofItemAtPath: voicePlist.path)
        try command("/bin/launchctl", ["bootstrap", "system", voicePlist.path])
    } catch {
        try? command("/bin/launchctl", ["bootout", "system/\(VoiceHelperContract.label)"], required: false)
        if installedNew { try? fm.removeItem(at: voiceRoot) }
        if replaced { try? fm.moveItem(at: previous, to: voiceRoot) }
        if let previousPlist {
            try? previousPlist.write(to: voicePlist, options: .atomic)
            try? fm.setAttributes([.ownerAccountID: 0, .groupOwnerAccountID: 0, .posixPermissions: 0o644], ofItemAtPath: voicePlist.path)
            try? command("/bin/launchctl", ["bootstrap", "system", voicePlist.path])
        } else { try? fm.removeItem(at: voicePlist) }
        throw error
    }
    if replaced { try fm.removeItem(at: previous) }
}

private func removeVoiceService() throws {
    if fm.fileExists(atPath: voiceRoot.path) {
        try protectedDirectory(voiceRoot)
        try verify(voiceRoot.appendingPathComponent(VoiceHelperContract.executable))
    }
    if try command("/bin/launchctl", ["print", "system/\(VoiceHelperContract.label)"], required: false) == 0 {
        try command("/bin/launchctl", ["bootout", "system/\(VoiceHelperContract.label)"])
    }
    if fm.fileExists(atPath: voicePlist.path) { try fm.removeItem(at: voicePlist) }
    if fm.fileExists(atPath: voiceRoot.path) { try fm.removeItem(at: voiceRoot) }
}
private func checkAudioHealth() throws {
    var highSamples = 0
    for _ in 0..<25 {
        let p = Process(); let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/bin/ps"); p.arguments = ["-axo", "pcpu,comm"]
        p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        try p.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        let cpus = (String(data: data, encoding: .utf8) ?? "").split(separator: "\n").compactMap { line -> Double? in
            let parts = line.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            guard parts.count == 2, parts[1].hasSuffix("/coreaudiod") else { return nil }
            return Double(parts[0])
        }
        guard !cpus.isEmpty else { usleep(1_000_000); continue }
        highSamples = cpus.contains { $0 >= 85 } ? highSamples + 1 : 0
        if highSamples >= 3 { try fail("系统音频持续高负载，已触发安装回滚") }
        usleep(1_000_000)
    }
}
@main enum BackendHelper {
    static func main() throws {
        guard getuid() == 0 else { try fail("需要系统管理员批准") }
        let args = CommandLine.arguments
        guard args.count >= 2 else { try fail("缺少操作") }
        let lock = open("/var/run/work.xvico.voice-service.install.lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else { try fail("其他后台操作尚未完成，请稍后重试") }
        defer { close(lock) }
        switch args[1] {
        case "install-service":
            guard args.count == 4, let uid = UInt32(args[3]), uid >= 500 else { try fail("缺少源应用路径或用户身份") }
            try installVoiceService(from: URL(fileURLWithPath: args[2]).standardizedFileURL, uid: uid)
        case "remove-service":
            guard args.count == 2 else { try fail("无效服务移除请求") }
            try removeVoiceService()
        case "install":
            guard args.count == 3 else { try fail("缺少源应用路径") }
            let app = URL(fileURLWithPath: args[2]).standardizedFileURL
            try verify(app)
            guard !fm.fileExists(atPath: root.path), !fm.fileExists(atPath: driver.path) else { try fail("后端已经存在，请先卸载后再安装") }
            let staged = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("xvibe-backend-\(UUID())")
            try fm.createDirectory(at: staged, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            defer { try? fm.removeItem(at: staged) }
            let resources = app.appendingPathComponent("Contents/Resources")
            let payload = staged.appendingPathComponent("AudioBackend")
            try fm.copyItem(at: resources.appendingPathComponent("AudioBackend"), to: payload)
            for name in ["XvibeVoiceCapture", "XvibeFrameReader"] {
                try fm.copyItem(at: resources.appendingPathComponent("VoiceTools/\(name)"), to: payload.appendingPathComponent(name))
                try verify(payload.appendingPathComponent(name))
            }
            // The HAL device can be installed before the optional runtime is
            // imported. Capture verifies and stages it separately when needed.
            for name in ["XvibeAudioRouter", "XvibeBackendRunner", "XvibeMicrophone.driver", "libopus.0.dylib"] { try verify(payload.appendingPathComponent(name)) }
            try fm.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createDirectory(at: driver.deletingLastPathComponent(), withIntermediateDirectories: true)
            var installedDriver = false
            do {
                try fm.copyItem(at: payload.appendingPathComponent("XvibeMicrophone.driver"), to: driver); installedDriver = true
                try fm.moveItem(at: payload, to: root)
                try owned(root); try owned(driver)
                try command("/usr/bin/killall", ["coreaudiod"], required: false)
                try checkAudioHealth()
            } catch {
                if installedDriver { try? fm.removeItem(at: driver) }
                try? fm.removeItem(at: root)
                try? command("/usr/bin/killall", ["coreaudiod"], required: false)
                throw error
            }
        case "rebrand":
            guard args.count == 3, !fm.fileExists(atPath: plist.path) else {
                try fail("请先停止语音采集，再更新麦克风名称")
            }
            let app = URL(fileURLWithPath: args[2]).standardizedFileURL
            try verify(app)
            try verify(driver)
            let replacement = app.appendingPathComponent("Contents/Resources/AudioBackend/XvibeMicrophone.driver")
            try verify(replacement)
            let oldInfo = NSDictionary(contentsOf: driver.appendingPathComponent("Contents/Info.plist"))
            let newInfo = NSDictionary(contentsOf: replacement.appendingPathComponent("Contents/Info.plist"))
            guard oldInfo?["CFBundleIdentifier"] as? String == "work.xvibe.microphone",
                  newInfo?["CFBundleIdentifier"] as? String == "work.xvibe.microphone",
                  newInfo?["CFBundleDisplayName"] as? String == "Xvico Microphone" else {
                try fail("麦克风组件身份不匹配，未更新")
            }
            // Keep the plug-in path, UID, factory UUID and shared-memory contract.
            // Only the displayed brand changes; no capture or diagnostic setup runs.
            let parent = root
            let staged = parent.appendingPathComponent(".xvico-microphone-stage-\(UUID()).driver")
            let previous = parent.appendingPathComponent(".xvico-microphone-previous-\(UUID()).driver")
            try fm.copyItem(at: replacement, to: staged)
            defer { try? fm.removeItem(at: staged) }
            try verify(staged); try owned(staged)
            try fm.moveItem(at: driver, to: previous)
            do {
                try fm.moveItem(at: staged, to: driver)
                try command("/usr/bin/killall", ["coreaudiod"], required: false)
                try checkAudioHealth()
            } catch {
                if fm.fileExists(atPath: driver.path) { try? fm.removeItem(at: driver) }
                try fm.moveItem(at: previous, to: driver)
                try? command("/usr/bin/killall", ["coreaudiod"], required: false)
                throw error
            }
            try fm.removeItem(at: previous)
        case "uninstall":
            try removeVoiceService()
            try command("/bin/launchctl", ["bootout", service], required: false)
            if fm.fileExists(atPath: plist.path) { try fm.removeItem(at: plist) }
            if fm.fileExists(atPath: driver.path) { try verify(driver); try fm.removeItem(at: driver) }
            if fm.fileExists(atPath: root.path) { try verify(root.appendingPathComponent("XvibeBackendRunner")); try fm.removeItem(at: root) }
            try command("/usr/bin/killall", ["coreaudiod"], required: false)
        case "session":
            guard args.count == 7, ["standard", "compat"].contains(args[6]), let uid = UInt32(args[3]), uid >= 500, let pid = Int32(args[4]), pid > 1,
                  let user = getpwuid(uid), kill(pid, 0) == 0 else { try fail("无效会话") }
            let session = URL(fileURLWithPath: args[2]).standardizedFileURL
            let expected = URL(fileURLWithPath: String(cString: user.pointee.pw_dir)).appendingPathComponent("Library/Caches/Xvibe/VoiceSessions")
            guard session.deletingLastPathComponent() == expected, session.resolvingSymlinksInPath() == session,
                  UUID(uuidString: session.lastPathComponent) != nil else { try fail("无效会话目录") }
            let sessionDirectory = try SessionDirectory(session, ownerUID: uid)
            try verify(root.appendingPathComponent("XvibeBackendRunner"))
            guard !fm.fileExists(atPath: plist.path) else { try fail("已有后端会话运行，请先停止") }
            // Update only session executables from the verified app. The HAL
            // bundle stays loaded; no reinstall or system-audio restart is needed.
            let app = URL(fileURLWithPath: args[5]).standardizedFileURL
            try verify(app)
            let runtimeStage = root.appendingPathComponent(".runtime-\(UUID())")
            let runtimePrevious = root.appendingPathComponent(".runtime-old-\(UUID())")
            let runtime = root.appendingPathComponent("PacketLoggerRuntime")
            defer { try? fm.removeItem(at: runtimeStage) }
            try copyAppleRuntime(from: runtimeSource(app: app, uid: uid), to: runtimeStage)
            var savedRuntime = false
            if fm.fileExists(atPath: runtime.path) { try fm.moveItem(at: runtime, to: runtimePrevious); savedRuntime = true }
            do { try fm.moveItem(at: runtimeStage, to: runtime) }
            catch {
                if savedRuntime { try? fm.moveItem(at: runtimePrevious, to: runtime) }
                throw error
            }
            if savedRuntime { try? fm.removeItem(at: runtimePrevious) }
            for (relative, name) in [("VoiceTools/XvibeVoiceCapture", "XvibeVoiceCapture"), ("AudioBackend/XvibeBackendRunner", "XvibeBackendRunner")] {
                let staged = root.appendingPathComponent(".update-\(UUID())")
                defer { try? fm.removeItem(at: staged) }
                try fm.copyItem(at: app.appendingPathComponent("Contents/Resources/\(relative)"), to: staged)
                try verify(staged); try owned(staged)
                guard rename(staged.path, root.appendingPathComponent(name).path) == 0 else { try fail("无法更新会话组件") }
            }
            let value: [String: Any] = ["Label": "work.xvibe.audio", "ProgramArguments": [root.appendingPathComponent("XvibeBackendRunner").path, session.path, args[3], args[4], args[6]], "RunAtLoad": true, "KeepAlive": false, "ProcessType": "Background", "ExitTimeOut": 10]
            try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0).write(to: plist, options: .atomic)
            try fm.setAttributes([.ownerAccountID: 0, .groupOwnerAccountID: 0, .posixPermissions: 0o644], ofItemAtPath: plist.path)
            defer {
                try? command("/bin/launchctl", ["bootout", service], required: false)
                try? fm.removeItem(at: plist)
            }
            try command("/bin/launchctl", ["bootstrap", "system", plist.path])
            let deadline = Date().addingTimeInterval(3600)
            while Date() < deadline && kill(pid, 0) == 0 && !sessionDirectory.exists("stop") {
                if sessionDirectory.exists("backend-ended") { break }
                usleep(200_000)
            }
            try? sessionDirectory.create("stop")
            // Give the daemon's capture child time to restore diagnostic settings.
            for _ in 0..<40 {
                if sessionDirectory.exists("backend-ended") { break }
                usleep(200_000)
            }
        default: try fail("不支持的操作")
        }
    }
}
