import XCTest
import AppKit
@testable import XvicoApp

final class PointerStabilityTests: XCTestCase {
    private func sample(_ x: Double, _ time: Double) -> RemoteTouchSample {
        .init(x: x, y: 0.5, touching: true, timestamp: time)
    }
    func testClickSuppressesSmallDisturbanceButClearDragUnlocksImmediately() {
        var stabilizer = PointerClickStabilizer()
        stabilizer.press(at: sample(0.5, 1))
        XCTAssertTrue(stabilizer.suppresses(sample(0.502, 1.01)))
        XCTAssertFalse(stabilizer.suppresses(sample(0.53, 1.02)))
        XCTAssertFalse(stabilizer.suppresses(sample(0.531, 1.03)))
        stabilizer.release(at: sample(0.531, 1.03))
        XCTAssertFalse(stabilizer.suppresses(sample(0.532, 1.04)))
    }
    func testClickFreezeExpiresAndReleaseCannotExtendItIndefinitely() {
        var stabilizer = PointerClickStabilizer()
        stabilizer.press(at: sample(0.5, 1))
        XCTAssertTrue(stabilizer.suppresses(sample(0.501, 1.02)))
        stabilizer.release(at: sample(0.501, 1.02))
        XCTAssertTrue(stabilizer.suppresses(sample(0.502, 1.04)))
        XCTAssertFalse(stabilizer.suppresses(sample(0.503, 1.09)))
        stabilizer.press(at: sample(0.5, 2))
        XCTAssertFalse(stabilizer.suppresses(sample(0.501, 2.13)))
    }
    func testPausedFramesReanchorWithoutReplayingClickMovement() {
        var processor = RemoteGestureProcessor()
        var settings = XvicoSettings(); settings.ringEnabled = false
        for i in 0..<8 { _ = processor.process(sample(0.5 + Double(i) * 0.004, Double(i) * 0.01), settings: settings, mode: .scroll) }
        XCTAssertTrue(processor.process(sample(0.535, 0.08), settings: settings, mode: .scroll, pointerPaused: true).isEmpty)
        XCTAssertTrue(processor.process(sample(0.535, 0.09), settings: settings, mode: .scroll).isEmpty)
        let outputs = processor.process(sample(0.555, 0.10), settings: settings, mode: .scroll)
        XCTAssertTrue(outputs.contains { if case .pointer = $0 { return true }; return false })
    }
    func testProfilesAreOrderedWhileLegacySettingsDefaultToOriginalCurve() throws {
        let settings = try JSONDecoder().decode(XvicoSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings.pointerProfile, .balanced)
        for speed in [0.01, 0.3, 1.0, 3.0] {
            XCTAssertLessThan(PointerResponseProfile.precise.gain(at: speed), PointerResponseProfile.balanced.gain(at: speed))
            XCTAssertGreaterThan(PointerResponseProfile.fast.gain(at: speed), PointerResponseProfile.balanced.gain(at: speed))
        }
        var legacy = RemotePointerMotionFilter(), balanced = RemotePointerMotionFilter()
        for i in 0..<12 {
            let point = sample(0.4 + Double(i) * 0.005, Double(i) / 60)
            let a = legacy.process(point, sensitivity: 1), b = balanced.process(point, sensitivity: 1, profile: .balanced)
            XCTAssertEqual(a?.x, b?.x); XCTAssertEqual(a?.y, b?.y)
        }
    }

    @MainActor
    func testCenterPressRetainsPairedMouseEventsAndDeliberateDrag() {
        let domain = "Xvico.ClickStability.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        var events: [CGEvent] = []
        let model = AppModel(defaults: defaults, observeSystem: false, accessibilityCheck: { true },
                             eventPoster: { events.append($0) })
        defer { model.stopControl() }
        model.settings.autoSwitchScenes = false; model.settings.ringEnabled = false
        model.settings.globalBindings[RemoteKey.center.rawValue] = .init(action: .click, value: "")
        for i in 0..<8 { model.handleTouch(sample(0.4 + Double(i) * 0.004, 1 + Double(i) * 0.01)) }
        events.removeAll()
        model.handleRemotePress(.center, pressed: true)
        model.handleTouch(sample(0.429, 1.08))
        XCTAssertEqual(events.map(\.type), [.leftMouseDown])
        model.handleTouch(sample(0.46, 1.09))
        XCTAssertTrue(events.contains { $0.type == .leftMouseDragged })
        model.handleRemotePress(.center, pressed: false)
        XCTAssertEqual(events.last?.type, .leftMouseUp)
        model.handleTouch(sample(0.465, 1.10))
        XCTAssertEqual(events.last?.type, .mouseMoved)
    }
}
