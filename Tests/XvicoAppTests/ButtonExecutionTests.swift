import AppKit
import XCTest
@testable import XvicoApp

@MainActor
final class ButtonExecutionTests: XCTestCase {
    private var domain: String!
    private var defaults: UserDefaults!
    private var model: AppModel!
    private var events: [CGEvent] = []
    private var microphoneChanges: [Int] = []

    override func setUp() async throws {
        domain = "XvicoButtonExecution.\(UUID())"
        defaults = UserDefaults(suiteName: domain)!
        model = AppModel(defaults: defaults, observeSystem: false, accessibilityCheck: { true },
            eventPoster: { [weak self] in self?.events.append($0) },
            microphoneSwitcher: { [weak self] in self?.microphoneChanges.append($0); return "Test" })
        model.settings.autoSwitchScenes = false
        model.settings.ringToggleKey = ""
    }

    override func tearDown() async throws {
        model.stopControl(); model = nil
        defaults.removePersistentDomain(forName: domain)
        events = []; microphoneChanges = []
    }

    private var keyboard: [CGEvent] { events.filter { $0.type == .keyDown || $0.type == .keyUp } }

    func testVolumeKeyReleasesOriginalShortcutAfterModeAndBindingChange() {
        model.settings.globalBindings[RemoteKey.volumeUp.rawValue] = .init(action: .key, value: "A", modifiers: [.control])
        model.handleRemotePress(.volumeUp, pressed: true)
        model.settings.volumeKeyMode = .scroll
        model.settings.globalBindings[RemoteKey.volumeUp.rawValue] = .init(action: .key, value: "B")
        model.handleRemotePress(.volumeUp, pressed: false)
        XCTAssertEqual(keyboard.map(\.type), [.keyDown, .keyUp])
        XCTAssertEqual(keyboard.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [0, 0])
        XCTAssertEqual(events.filter { $0.type == .flagsChanged }.count, 2)
        XCTAssertFalse(events.last!.flags.contains(.maskControl))
        XCTAssertFalse(model.isHoldingRemoteButton)
    }

    func testSpecialVolumeModeOwnsPhysicalPairAcrossModeChangeAndDuplicateDown() {
        model.settings.volumeKeyMode = .microphone
        model.handleRemotePress(.volumeUp, pressed: true)
        model.handleRemotePress(.volumeUp, pressed: true)
        model.settings.volumeKeyMode = .key
        model.settings.globalBindings[RemoteKey.volumeUp.rawValue] = .init(action: .key, value: "B")
        model.handleRemotePress(.volumeUp, pressed: false)
        model.handleRemotePress(.volumeUp, pressed: false)
        XCTAssertEqual(microphoneChanges, [-1])
        XCTAssertTrue(events.isEmpty)
        model.handleRemotePress(.volumeUp, pressed: true)
        model.handleRemotePress(.volumeUp, pressed: false)
        XCTAssertEqual(keyboard.map(\.type), [.keyDown, .keyUp])
        XCTAssertEqual(keyboard.first?.getIntegerValueField(.keyboardEventKeycode), 11)
    }

    func testIdenticalSiriBindingsInDifferentScenesDoNotBecomeDouble() async throws {
        var binding = KeyBinding(action: .key, value: "A", doubleClickEnabled: true, doubleClickValue: "B",
            doubleClickOverride: .custom)
        binding.longPressOverride = .disabled
        model.scenes = [
            .init(name: "First", bundleID: "test.first", color: "blue", bindings: [RemoteKey.voice.rawValue: binding]),
            .init(name: "Second", bundleID: "test.second", color: "blue", bindings: [RemoteKey.voice.rawValue: binding])
        ]
        model.settings.autoSwitchScenes = true
        model.currentBundleID = "test.first"
        model.handleRemotePress(.voice, pressed: true); model.handleRemotePress(.voice, pressed: false)
        model.currentBundleID = "test.second"
        model.handleRemotePress(.voice, pressed: true); model.handleRemotePress(.voice, pressed: false)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(keyboard.filter { $0.type == .keyDown }.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [0, 0])
        XCTAssertEqual(keyboard.map(\.type), [.keyDown, .keyUp, .keyDown, .keyUp])
    }

    func testStopCancelsPendingSingleAndLongTasksBeforeNewControlSession() async throws {
        model.settings.globalBindings[RemoteKey.voice.rawValue] = .init(action: .key, value: "A", doubleClickEnabled: true, doubleClickValue: "B")
        model.settings.globalBindings[RemoteKey.menu.rawValue] = .init(action: .key, value: "A", longPressEnabled: true, longPressValue: "F7")
        model.handleRemotePress(.voice, pressed: true); model.handleRemotePress(.voice, pressed: false)
        model.handleRemotePress(.menu, pressed: true)
        model.stopControl()
        // Do not open a real HID manager from the test process.
        model.running = true
        model.settings.globalBindings[RemoteKey.menu.rawValue] = .init(action: .key, value: "C")
        model.handleRemotePress(.menu, pressed: false)
        model.handleRemotePress(.menu, pressed: true); model.handleRemotePress(.menu, pressed: false)
        try await Task.sleep(nanoseconds: 450_000_000)
        XCTAssertEqual(keyboard.map(\.type), [.keyDown, .keyUp])
        XCTAssertEqual(keyboard.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [8, 8])
        XCTAssertFalse(model.isHoldingRemoteButton)
    }

    func testLongShortcutReleasesCapturedKeyAndRightModifierAfterEdit() async throws {
        var binding = KeyBinding(action: .key, value: "A", longPressEnabled: true,
            longPressValue: "F7", longPressModifiers: [.option])
        binding.longPressRightModifiers = [.option]
        model.settings.globalBindings[RemoteKey.menu.rawValue] = binding
        model.handleRemotePress(.menu, pressed: true)
        model.settings.globalBindings[RemoteKey.menu.rawValue] = .init(action: .key, value: "B")
        try await Task.sleep(nanoseconds: 420_000_000)
        model.handleRemotePress(.menu, pressed: false)
        XCTAssertEqual(keyboard.map(\.type), [.keyDown, .keyUp])
        XCTAssertEqual(keyboard.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [98, 98])
        XCTAssertEqual(events.filter { $0.type == .flagsChanged }.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [61, 61])
        XCTAssertFalse(events.last!.flags.contains(.maskAlternate))
    }

    func testDisconnectClosesConsumedVoiceOnceAndDropsPendingMapping() async throws {
        var voiceEdges: [Bool] = []
        model.siriVoiceHandler = { voiceEdges.append($0); return true }
        model.settings.globalBindings[RemoteKey.menu.rawValue] = .init(action: .key, value: "A", longPressEnabled: true, longPressValue: "F7")
        model.handleRemotePress(.voice, pressed: true)
        model.handleRemotePress(.menu, pressed: true)
        model.handleRemoteInputLoss()
        model.handleRemoteInputLoss()
        model.handleRemotePress(.voice, pressed: false)
        model.handleRemotePress(.menu, pressed: false)
        try await Task.sleep(nanoseconds: 450_000_000)
        XCTAssertEqual(voiceEdges, [true, false])
        XCTAssertTrue(events.isEmpty)
        XCTAssertFalse(model.isHoldingRemoteButton)
    }
}
