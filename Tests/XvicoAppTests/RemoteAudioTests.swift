import XCTest
import AVFoundation
@testable import XvicoApp

final class RemoteAudioTests: XCTestCase {
    // 440Hz synthetic tone encoded with official Opus 1.6.1, restricted lowdelay,
    // 16kHz mono 20ms. No user or remote microphone recording is used here.
    private let toneHex = "b87b5af3f6a1db150c1207826c0faff5d2103fce0af468da6fd16e3bf113de73f0443360c7f8810314c09fa5e98aaaefdca075aea5e14f2ecfb0a1"
    private var tone: Data {
        stride(from: 0, to: toneHex.count, by: 2).reduce(into: Data()) { result, offset in
            let first = toneHex.index(toneHex.startIndex, offsetBy: offset)
            result.append(UInt8(toneHex[first..<toneHex.index(first, offsetBy: 2)], radix: 16)!)
        }
    }
    private func report(sequence: UInt16 = 0) -> Data {
        var result = Data([0x12, 0x34, UInt8(sequence & 255), UInt8(sequence >> 8), UInt8(tone.count)])
        result.append(tone); result.append(Data(repeating: 0, count: 100 - result.count)); return result
    }
    func testNotificationParserRejectsWrongReportsAndPadding() throws {
        let frame = try RemoteOpusFrame.parse(report(sequence: 65535))
        XCTAssertEqual(frame.sequence, 65535); XCTAssertEqual(frame.packet, tone)
        XCTAssertThrowsError(try RemoteOpusFrame.parse(report(), reportID: 0xFF))
        XCTAssertThrowsError(try RemoteOpusFrame.parse(Data([0xB8, 0])))
        var bad = report(); bad[99] = 1
        XCTAssertThrowsError(try RemoteOpusFrame.parse(bad))
        XCTAssertEqual(try RemoteOpusFrame.parse(Data([0xFA]) + report()).packet, tone)
    }
    func testOfficialOpusDecodesNonSilentSpeechReadyPCM() throws {
        let decoder = try RemoteAudioDecoder()
        let buffer = try decoder.decode(tone)
        XCTAssertEqual(buffer.frameLength, 320)
        XCTAssertEqual(buffer.format.sampleRate, 16000)
        let samples = buffer.floatChannelData![0]
        let energy = (0..<320).reduce(Float(0)) { $0 + samples[$1] * samples[$1] }
        XCTAssertGreaterThan(energy, 0.01)
        XCTAssertEqual(try decoder.decode(nil).frameLength, 320)
    }
    func testDuplicateWrapGapAndSessionResetAreBounded() throws {
        let stream = try RemoteAudioStream()
        func frame(_ seq: UInt16, _ session: UInt16 = 1) -> RemoteOpusFrame { .init(session: session, sequence: seq, packet: tone) }
        XCTAssertEqual(try stream.ingest(frame(65535)).count, 1)
        XCTAssertTrue(try stream.ingest(frame(65535)).isEmpty)
        XCTAssertEqual(try stream.ingest(frame(0)).count, 1)
        XCTAssertEqual(try stream.ingest(frame(2)).count, 2)
        XCTAssertTrue(try stream.ingest(frame(1)).isEmpty)
        XCTAssertEqual(try stream.ingest(frame(300)).count, 1)
        XCTAssertEqual(try stream.ingest(frame(0, 2)).count, 1)
        XCTAssertEqual(stream.concealedFrames, 1); XCTAssertEqual(stream.duplicateFrames, 2)
    }
    func testIPCHandlesArbitrarilySplitPackets() throws {
        var message = Data([UInt8(tone.count), 0, 1, 0, 7, 0]); message.append(tone)
        var parser = RemoteVoiceIPC()
        var frames: [RemoteOpusFrame] = []
        for byte in message { frames += try parser.ingest(Data([byte])) }
        XCTAssertEqual(frames, [.init(session: 1, sequence: 7, packet: tone)])
        XCTAssertThrowsError(try parser.ingest(Data([255, 255, 0, 0, 0, 0])))
    }
    func testIPCDecodesMultipleFramesInOnePipeRead() throws {
        var messages = Data()
        let expected = (0..<20).map { sequence -> RemoteOpusFrame in
            messages.append(Data([UInt8(tone.count), 0, 1, 0, UInt8(sequence), 0]))
            messages.append(tone)
            return .init(session: 1, sequence: UInt16(sequence), packet: tone)
        }
        var parser = RemoteVoiceIPC()
        XCTAssertEqual(try parser.ingest(messages), expected)
    }
    func testIPCContinuousStreamWithSplitHeadersAndPartialTails() throws {
        var messages = Data()
        var expected: [RemoteOpusFrame] = []
        for sequence in 0..<500 {
            messages.append(Data([UInt8(tone.count), 0, 2, 0, UInt8(sequence & 255), UInt8(sequence >> 8)]))
            messages.append(tone)
            expected.append(.init(session: 2, sequence: UInt16(sequence), packet: tone))
        }
        for chunkSize in [1, 5, 7, 64, 101, 4096] {
            var parser = RemoteVoiceIPC()
            var received: [RemoteOpusFrame] = []
            for offset in stride(from: 0, to: messages.count, by: chunkSize) {
                received += try parser.ingest(messages.subdata(in: offset..<min(messages.count, offset + chunkSize)))
            }
            XCTAssertEqual(received, expected, "Pipe chunk \(chunkSize)")
        }
    }
    func testIPCMalformedFrameAfterValidFrameThrowsAndCanRestart() throws {
        var valid = Data([UInt8(tone.count), 0, 1, 0, 7, 0]); valid.append(tone)
        var parser = RemoteVoiceIPC()
        XCTAssertThrowsError(try parser.ingest(valid + Data([255, 255, 0, 0, 0, 0])))
        XCTAssertEqual(try parser.ingest(valid), [.init(session: 1, sequence: 7, packet: tone)])
    }
    func testRepeatedHoldsRestartSequenceOnSameCaptureConnection() throws {
        let stream = try RemoteAudioStream()
        for _ in 0..<5 {
            stream.beginUtterance()
            for sequence in 0..<300 {
                let frame = RemoteOpusFrame(session: 1, sequence: UInt16(sequence), packet: tone)
                XCTAssertEqual(try stream.ingest(frame).count, 1)
                XCTAssertTrue(try stream.ingest(frame).isEmpty)
            }
        }
        XCTAssertEqual(stream.decodedFrames, 1500)
        XCTAssertEqual(stream.duplicateFrames, 1500)
        XCTAssertEqual(stream.concealedFrames, 0)
    }
}
