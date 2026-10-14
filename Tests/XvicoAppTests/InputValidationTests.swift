import XCTest
import XvicoBluetooth
@testable import XvicoApp

final class InputValidationTests: XCTestCase {
    func testBluetoothParserAcceptsSlicesAndRejectsInvalidOffsets() throws {
        let storage = Data([9, 9, 1, 0x34, 0x12, 0xB8])
        let layout = VoicePacketLayout(typeByteOffset: 0, sequenceByteOffset: 1,
            payloadOffset: 3, primaryTypeValues: [1], continuationTypeValues: [], metadataTypeValues: [])
        let parsed = try VoicePacketParser(layout: layout).parse(storage.dropFirst(2))
        XCTAssertEqual(parsed.sequence, 0x1234)
        XCTAssertEqual(parsed.payload, Data([0xB8]))
        for (type, payload) in [(-1, 0), (0, -1), (Int.max, 0), (0, Int.max)] {
            let invalid = VoicePacketLayout(typeByteOffset: type, sequenceByteOffset: nil,
                payloadOffset: payload, primaryTypeValues: [], continuationTypeValues: [], metadataTypeValues: [])
            XCTAssertThrowsError(try VoicePacketParser(layout: invalid).parse(Data([1, 2])))
        }
    }
    func testImportedSettingsRejectCrashInducingNumericValues() throws {
        for key in ["volumeScrollStep", "pointerSensitivity", "ringSensitivity", "ringRadius", "scrollSensitivity"] {
            for value in ["1e308", "-1e308", "-1"] {
                let data = Data("{\"\(key)\":\(value)}".utf8)
                XCTAssertThrowsError(try JSONDecoder().decode(XvicoSettings.self, from: data), "\(key)=\(value)")
            }
        }
        let defaults = XvicoSettings()
        XCTAssertEqual(try JSONDecoder().decode(XvicoSettings.self, from: JSONEncoder().encode(defaults)), defaults)
    }
}
