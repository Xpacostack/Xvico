import XCTest
import AppKit
@testable import XvicoApp

final class MouseClickSequenceTests: XCTestCase {
    func testPairsResetAndRequireBothTimeAndPosition() {
        var sequence = MouseClickSequence()
        let p = CGPoint(x: 50, y: 50)
        XCTAssertEqual(sequence.click(at: p, time: 1, interval: 0.5), 1)
        XCTAssertEqual(sequence.click(at: CGPoint(x: 58, y: 50), time: 1.5, interval: 0.5), 2)
        XCTAssertEqual(sequence.click(at: p, time: 1.6, interval: 0.5), 1)
        XCTAssertEqual(sequence.click(at: p, time: 2.2, interval: 0.5), 1)
        XCTAssertEqual(sequence.click(at: CGPoint(x: 59, y: 50), time: 2.3, interval: 0.5), 1)
        XCTAssertEqual(sequence.click(at: p, time: 2, interval: 0.5), 1, "Negative elapsed time resets")
    }
    @MainActor func testHardwareCenterLeftDownAndUpShareCountButRightStaysSingle() {
        let domain = "XvicoMouseAudit.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        var time = 10.0
        var events: [CGEvent] = []
        let model = AppModel(defaults: defaults, observeSystem: false, accessibilityCheck: { true },
                             eventPoster: { events.append($0) }, mouseClickTime: { time })
        defer { model.stopControl() }
        model.settings.autoSwitchScenes = false
        model.settings.ringToggleKey = ""
        model.settings.globalBindings[RemoteKey.center.rawValue] = .init(action: .click, value: "Return")
        for _ in 0..<3 {
            model.handleHIDUsage(page: 12, usage: 128, pressed: true)
            model.handleHIDUsage(page: 12, usage: 128, pressed: false)
            time += 0.01
        }
        XCTAssertEqual(events.map { $0.getIntegerValueField(.mouseEventClickState) }, [1, 1, 2, 2, 1, 1])
        events = []
        model.settings.globalBindings[RemoteKey.center.rawValue] = .init(action: .click, value: "Return", mouseButton: .right)
        for _ in 0..<2 {
            model.handleRemotePress(.center, pressed: true); model.handleRemotePress(.center, pressed: false)
            time += 0.01
        }
        XCTAssertEqual(events.map { $0.getIntegerValueField(.mouseEventClickState) }, [1, 1, 1, 1])
    }
    func testTaskRingUsesRecoveredPointThreeThreshold() {
        var processor = RemoteGestureProcessor()
        var settings = XvicoSettings(); settings.ringSensitivity = 1
        func sample(_ angle: Double) -> RemoteTouchSample {
            .init(x: 0.5 + 0.4 * cos(angle), y: 0.5 + 0.4 * sin(angle), touching: true)
        }
        _ = processor.process(sample(0), settings: settings, mode: .codexTasks)
        XCTAssertTrue(processor.process(sample(0.20), settings: settings, mode: .codexTasks).isEmpty)
        XCTAssertEqual(processor.process(sample(0.31), settings: settings, mode: .codexTasks), [.taskStep(1)])
    }
    @MainActor func testTaskRingClampsAtFirstAndNinthTaskInsteadOfWrapping() {
        let domain = "XvicoTaskAudit.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        var events: [CGEvent] = []
        let model = AppModel(defaults: defaults, observeSystem: false, accessibilityCheck: { true }, eventPoster: { events.append($0) })
        defer { model.stopControl() }
        let index = model.scenes.firstIndex { $0.bundleID == "com.openai.codex" }!
        model.currentBundleID = "com.openai.codex"
        model.scenes[index].ringAction = .codexTasks
        model.settings.ringSensitivity = 1
        func rotate(_ direction: Double) {
            model.handleTouch(.init(x: 0.9, y: 0.5, touching: false))
            for i in 0..<30 {
                let angle = Double(i) * 0.31 * direction
                model.handleTouch(.init(x: 0.5 + 0.4 * cos(angle), y: 0.5 + 0.4 * sin(angle), touching: true))
            }
        }
        rotate(1)
        let forward = events.filter { $0.type == .keyDown }.map { $0.getIntegerValueField(.keyboardEventKeycode) }
        XCTAssertEqual(forward.first, 19, "First forward step selects task 2")
        XCTAssertEqual(Array(forward.suffix(10)), Array(repeating: 25, count: 10), "Ninth task remains task 9")
        events = []
        rotate(-1)
        let backward = events.filter { $0.type == .keyDown }.map { $0.getIntegerValueField(.keyboardEventKeycode) }
        XCTAssertEqual(Array(backward.suffix(10)), Array(repeating: 18, count: 10), "First task remains task 1")
    }
}
