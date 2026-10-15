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

    func testDragAccelerationPreservesFinePlacementAndExtendsFastSwipes() {
        for step in [0.002, 0.025] {
            var original = RemotePointerMotionFilter(), accelerated = RemotePointerMotionFilter()
            var originalDistance = 0.0, acceleratedDistance = 0.0
            for i in 0..<15 {
                let point = sample(0.2 + Double(i) * step, 1 + Double(i) / 60)
                let a = original.process(point, sensitivity: 1)
                let b = accelerated.process(point, sensitivity: 1, dragAcceleration: 1.6)
                originalDistance += a?.x ?? 0; acceleratedDistance += b?.x ?? 0
                XCTAssertEqual(a == nil, b == nil)
            }
            if step < 0.01 { XCTAssertEqual(originalDistance, acceleratedDistance, accuracy: 0.0001) }
            else { XCTAssertEqual(acceleratedDistance / originalDistance, 1.6, accuracy: 0.001) }
            // Stopping does not replay filtered motion or add inertial dragging.
            XCTAssertNil(accelerated.process(sample(0.2 + 14 * step, 1.25), sensitivity: 1, dragAcceleration: 1.6))
        }
    }

    func testDragGainDoesNotAffectUnheldPointerAndOneRestoresOldDrag() {
        var baseline = RemoteGestureProcessor(), boosted = RemoteGestureProcessor(), drag = RemoteGestureProcessor()
        var settings = XvicoSettings(); settings.ringEnabled = false; settings.dragAcceleration = 1
        var faster = settings; faster.dragAcceleration = 2.5
        for i in 0..<15 {
            let point = sample(0.2 + Double(i) * 0.025, 1 + Double(i) / 60)
            let expected = baseline.process(point, settings: settings, mode: .scroll)
            XCTAssertEqual(boosted.process(point, settings: faster, mode: .scroll), expected)
            XCTAssertEqual(drag.process(point, settings: settings, mode: .scroll, dragging: true), expected)
        }
    }

    func testDragAcrossRingNeverScrollsAndRecontactDoesNotJump() {
        var processor = RemoteGestureProcessor()
        let settings = XvicoSettings()
        var outputs: [RemoteGestureOutput] = []
        for i in 0..<15 {
            outputs += processor.process(.init(x: 0.9, y: 0.25 + Double(i) * 0.025, touching: true,
                                                timestamp: 1 + Double(i) / 60),
                                         settings: settings, mode: .codexTasks, dragging: true)
        }
        XCTAssertFalse(outputs.isEmpty)
        XCTAssertTrue(outputs.allSatisfy { if case .pointer = $0 { return true }; return false })
        XCTAssertTrue(processor.process(.init(x: 0.9, y: 0.6, touching: false, timestamp: 1.3),
                                        settings: settings, mode: .codexTasks, dragging: true).isEmpty)
        XCTAssertTrue(processor.process(sample(0.1, 1.4), settings: settings, mode: .codexTasks, dragging: true).isEmpty)
    }

    func testDragAccelerationSettingsMigrateRoundTripAndRejectInvalidValues() throws {
        let old = try JSONDecoder().decode(XvicoSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(old.dragAcceleration, 1.6)
        var settings = old; settings.dragAcceleration = 2.1
        XCTAssertEqual(try JSONDecoder().decode(XvicoSettings.self, from: JSONEncoder().encode(settings)), settings)
        for value in [0.99, 2.51] {
            XCTAssertThrowsError(try JSONDecoder().decode(XvicoSettings.self, from: Data("{\"dragAcceleration\":\(value)}".utf8)))
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
