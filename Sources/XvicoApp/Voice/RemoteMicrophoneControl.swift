import Foundation
import IOKit

// The GPL-licensed device operation runs in its own executable. This app speaks
// only a two-command process protocol and receives an IOReturn status as hex.
enum RemoteMicrophoneControl {
    static func setEnabled(_ enabled: Bool) -> IOReturn {
        let executable = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/VoiceTools/XvicoMicrophoneControl")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { return kIOReturnNotFound }
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = [enabled ? "enable" : "disable"]
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let text = String(data: data, encoding: .utf8),
                  let result = UInt32(text.trimmingCharacters(in: .whitespacesAndNewlines), radix: 16) else {
                return kIOReturnError
            }
            return IOReturn(bitPattern: result)
        } catch { return kIOReturnError }
    }
}
