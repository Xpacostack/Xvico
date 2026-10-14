// Xvico adaptation of the GPL-3.0 SiriRemoteVibe packet reader. See LICENSE/SOURCE.md.
import Foundation
import Darwin

@main
enum XvibeFrameReader {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw Failure.invalidArguments }
        let input = try FileHandle(forReadingFrom: URL(fileURLWithPath: CommandLine.arguments[1]))
        defer { try? input.close() }
        let extractor = PklgVoiceExtractor()
        let output = FileHandle.standardOutput
        while true {
            let bytes = try input.read(upToCount: 65_536) ?? Data()
            for frame in extractor.ingest(bytes) where frame.opusPayload.count <= 95 {
                let handle = UInt16(frame.connectionHandle.dropFirst(2), radix: 16) ?? 0
                // IPC carries only extracted Opus, never arbitrary Bluetooth records.
                var packet = Data()
                for value in [UInt16(frame.opusPayload.count), handle, frame.sequence] {
                    packet.append(UInt8(value & 0xFF)); packet.append(UInt8(value >> 8))
                }
                packet.append(frame.opusPayload)
                try output.write(contentsOf: packet)
            }
            if bytes.isEmpty {
                guard FileManager.default.fileExists(atPath: CommandLine.arguments[1]) else { return }
                usleep(10_000)
            }
        }
    }
    enum Failure: Error { case invalidArguments }
}
