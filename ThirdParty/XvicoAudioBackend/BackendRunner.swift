import Foundation
import Darwin
private var interrupted: sig_atomic_t = 0
@main enum BackendRunner {
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 5, ["standard", "compat"].contains(args[4]), getuid() == 0, let uid = UInt32(args[2]), uid >= 500, let pid = Int32(args[3]), pid > 1, kill(pid, 0) == 0 else { return }
        // Both the legacy session launcher and the persistent service use a
        // root-owned, signature-verified payload beside this executable.
        let root = URL(fileURLWithPath: args[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        let session = URL(fileURLWithPath: args[1])
        let sessionDirectory = try SessionDirectory(session, ownerUID: uid)
        signal(SIGTERM) { _ in interrupted = 1 }; signal(SIGINT) { _ in interrupted = 1 }
        let capture = Process(); capture.executableURL = root.appendingPathComponent("XvibeVoiceCapture")
        capture.arguments = [root.appendingPathComponent("PacketLoggerRuntime").path, args[1], args[2], args[3]]
        if args[4] == "compat" { capture.arguments?.append("--compat-diagnostics") }
        capture.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        capture.standardOutput = FileHandle.nullDevice; capture.standardError = FileHandle.nullDevice
        let router = Process()
        defer {
            try? sessionDirectory.create("stop")
            if router.isRunning { router.terminate(); router.waitUntilExit() }
            if capture.isRunning { capture.waitUntilExit() }
            try? sessionDirectory.create("backend-ended")
        }
        try capture.run()
        // A manually started session lasts until stop, client loss or child failure.
        while capture.isRunning && interrupted == 0 && kill(pid, 0) == 0 {
            if sessionDirectory.exists("stop") { break }
            if router.executableURL == nil,
               let data = try? sessionDirectory.read("ready.json"),
               let metadata = try? JSONSerialization.jsonObject(with: data) as? [String: String], let trace = metadata["capture"] {
                guard trace.hasPrefix("/private/var/tmp/xvibe-voice."), trace.hasSuffix("/remote.pklg") else { break }
                router.executableURL = root.appendingPathComponent("XvibeAudioRouter")
                router.arguments = ["--pklg", trace, "--quiet"]
                router.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
                router.standardOutput = FileHandle.nullDevice; router.standardError = FileHandle.nullDevice
                try router.run()
            }
            if router.executableURL != nil && !router.isRunning { break }
            usleep(100_000)
        }
    }
}
