import AppKit
import XCTest
@testable import XvicoApp

@MainActor
final class CodexTaskRingTests: XCTestCase {
    private var defaults: UserDefaults!
    private var domain = ""
    private var model: AppModel!
    private var events: [CGEvent] = []
    private var timestamp = 1.0
    private let digitCodes: [Int64] = [18, 19, 20, 21, 23, 22, 26, 28, 25]

    override func setUp() async throws {
        domain = "XvicoTests.CodexRing.\(UUID())"
        defaults = UserDefaults(suiteName: domain)!
        model = AppModel(defaults: defaults, observeSystem: false,
                         accessibilityCheck: { true }, eventPoster: { self.events.append($0) })
        let scene = XvicoScene(name: "Codex", bundleID: "com.openai.codex", color: "blue", bindings: [:])
        model.scenes = [scene]
        model.scenes[0].ringAction = .codexTasks
        model.settings.autoSwitchScenes = true
        model.settings.ringAction = .scroll
        model.settings.ringSensitivity = 1
        model.settings.wheelStyle = .continuous
        model.currentBundleID = "com.openai.codex"
    }
    override func tearDown() async throws {
        model.stopControl()
        defaults.removePersistentDomain(forName: domain)
        model = nil; defaults = nil; events = []
    }
    private func step(_ direction: Double) {
        for angle in [0, 0.31 * direction] {
            timestamp += 0.01
            model.handleTouch(.init(x: 0.5 + 0.4 * cos(angle), y: 0.5 + 0.4 * sin(angle),
                                    touching: true, timestamp: timestamp))
        }
        timestamp += 0.01
        model.handleTouch(.init(x: 0.9, y: 0.5, touching: false, timestamp: timestamp))
    }
    func testEverySlotOneThroughNineAndReverseEmitPairedCommandDigitEvents() {
        // Establish slot 1 at the lower bound, then traverse all nine slots.
        step(-1)
        for _ in 0..<8 { step(1) }
        for _ in 0..<8 { step(-1) }
        let expected = digitCodes + Array(digitCodes.dropLast().reversed())
        let downs = events.filter { $0.type == .keyDown }
        let ups = events.filter { $0.type == .keyUp }
        XCTAssertEqual(downs.map { $0.getIntegerValueField(.keyboardEventKeycode) }, expected)
        XCTAssertEqual(ups.map { $0.getIntegerValueField(.keyboardEventKeycode) }, expected)
        for event in downs + ups {
            XCTAssertTrue(event.flags.contains(.maskCommand))
            XCTAssertFalse(event.flags.contains(.maskAlternate))
            XCTAssertFalse(event.flags.contains(.maskControl))
            XCTAssertFalse(event.flags.contains(.maskShift))
        }
        XCTAssertFalse(events.contains { $0.type == .scrollWheel })
        XCTAssertEqual(events.last?.type, .flagsChanged)
        XCTAssertFalse(events.last!.flags.contains(.maskCommand), "Command must be released after switching")
    }
    func testBoundaryNeverProducesZeroOrTenAndLiftDoesNotResetSlotCounter() {
        for _ in 0..<14 { step(1) }
        XCTAssertEqual(events.filter { $0.type == .keyDown }.last?.getIntegerValueField(.keyboardEventKeycode), 25)
        events.removeAll()
        step(-1)
        XCTAssertEqual(events.first { $0.type == .keyDown }?.getIntegerValueField(.keyboardEventKeycode), 28,
                       "A new contact continues from slot 9 to slot 8")
        for _ in 0..<14 { step(-1) }
        let codes = events.filter { $0.type == .keyDown }.map { $0.getIntegerValueField(.keyboardEventKeycode) }
        XCTAssertTrue(codes.allSatisfy { digitCodes.contains($0) })
        XCTAssertEqual(codes.last, 18)
    }
    func testForegroundSceneOverrideAndDisabledSceneFallBackToScrolling() {
        XCTAssertEqual(model.effectiveRingAction, .codexTasks)
        step(1)
        XCTAssertTrue(events.contains { $0.type == .keyDown })
        events.removeAll()
        model.currentBundleID = "org.example.other"
        step(1)
        XCTAssertFalse(events.contains { $0.type == .keyDown })
        XCTAssertTrue(events.contains { $0.type == .scrollWheel })
        events.removeAll()
        model.currentBundleID = "com.openai.codex"
        model.scenes[0].enabled = false
        step(1)
        XCTAssertFalse(events.contains { $0.type == .keyDown })
        XCTAssertTrue(events.contains { $0.type == .scrollWheel })
    }
    func testSceneConfiguredAsScrollDoesNotSwitchTasksDespiteGlobalTaskMode() {
        model.settings.ringAction = .codexTasks
        model.scenes[0].ringAction = .scroll
        XCTAssertEqual(model.effectiveRingAction, .scroll)
        step(1)
        XCTAssertFalse(events.contains { $0.type == .keyDown })
        XCTAssertTrue(events.contains { $0.type == .scrollWheel })
    }
}
