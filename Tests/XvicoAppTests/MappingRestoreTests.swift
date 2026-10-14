import AppKit
import XCTest
@testable import XvicoApp

@MainActor
final class MappingRestoreTests: XCTestCase {
    private var domain = ""
    private var defaults: UserDefaults!
    private var model: AppModel!
    private var events: [CGEvent] = []

    override func setUp() async throws {
        domain = "XvicoMappingRestore.\(UUID())"
        defaults = UserDefaults(suiteName: domain)!
        model = makeModel()
    }
    override func tearDown() async throws {
        model.stopControl()
        defaults.removePersistentDomain(forName: domain)
        model = nil; defaults = nil; events = []
    }
    private func makeModel() -> AppModel {
        AppModel(defaults: defaults, observeSystem: false, accessibilityCheck: { true }, eventPoster: { self.events.append($0) })
    }

    func testRestoreRecoversMediaAndMouseRuntimeWhileRetainingScenesAndPreferences() throws {
        model.applyPreset(ScenePreset.all.first { $0.id == "codex" }!, bundleID: "com.openai.codex")
        model.currentBundleID = "com.openai.codex"
        model.settings.volumeKeyMode = .microphone
        model.settings.interfaceLanguage = .french
        model.settings.pointerSensitivity = 1.7
        model.settings.launchAtLogin = true
        model.settings.showDockIcon = false
        defaults.set("Fn", forKey: "xvibe.voice.inputMethodTriggerKey")
        let oldScenes = model.scenes
        model.restoreInitialRemoteMapping()
        XCTAssertNil(model.activeScene)
        XCTAssertTrue(model.scenes.allSatisfy { !$0.enabled })
        XCTAssertEqual(model.scenes.map(\.bindings), oldScenes.map(\.bindings))
        XCTAssertEqual(model.settings.volumeKeyMode, .key)
        XCTAssertEqual(model.effectiveRingAction, .scroll)
        XCTAssertEqual(model.runtimeBinding(for: .center).action, .click)
        XCTAssertEqual(model.settings.interfaceLanguage, .french)
        XCTAssertEqual(model.settings.pointerSensitivity, 1.7)
        XCTAssertTrue(model.settings.launchAtLogin)
        XCTAssertFalse(model.settings.showDockIcon)
        XCTAssertEqual(defaults.string(forKey: "xvibe.voice.inputMethodTriggerKey"), "Fn")
        XCTAssertTrue(model.running)
        for (key, code) in [(RemoteKey.volumeUp, 0), (.volumeDown, 1), (.mute, 7)] {
            events = []
            model.handleRemotePress(key, pressed: true); model.handleRemotePress(key, pressed: false)
            let media = try events.map { try XCTUnwrap(NSEvent(cgEvent: $0)) }
            XCTAssertEqual(media.count, 2)
            XCTAssertTrue(media.allSatisfy { $0.type == .systemDefined && $0.subtype.rawValue == 8 })
            XCTAssertEqual(media.map(\.data1), [(code << 16) | 0xA00, (code << 16) | 0xB00])
        }
        events = []
        model.handleRemotePress(.center, pressed: true); model.handleRemotePress(.center, pressed: false)
        XCTAssertEqual(events.map(\.type), [.leftMouseDown, .leftMouseUp])
    }

    func testRestoreAndUndoSurviveRelaunchAndRepeatedResetDoesNotOverwriteSnapshot() {
        model.settings.globalBindings[RemoteKey.menu.rawValue] = .init(action: .key, value: "F7")
        model.settings.volumeKeyMode = .scroll
        model.settings.autoSwitchScenes = false
        let previous = RemoteMappingConfiguration(model.settings)
        let scenes = model.scenes
        model.restoreInitialRemoteMapping()
        model.restoreInitialRemoteMapping()
        let restored = makeModel()
        defer { restored.stopControl() }
        XCTAssertEqual(RemoteMappingConfiguration(restored.settings), .initial)
        XCTAssertTrue(restored.scenes.allSatisfy { !$0.enabled })
        XCTAssertTrue(restored.canUndoMappingRestore)
        restored.settings.interfaceLanguage = .japanese
        restored.undoInitialRemoteMappingRestore()
        XCTAssertEqual(RemoteMappingConfiguration(restored.settings), previous)
        XCTAssertEqual(restored.scenes, scenes)
        XCTAssertEqual(restored.settings.interfaceLanguage, .japanese)
        XCTAssertFalse(restored.canUndoMappingRestore)
        let relaunched = makeModel()
        defer { relaunched.stopControl() }
        XCTAssertEqual(RemoteMappingConfiguration(relaunched.settings), previous)
        XCTAssertFalse(relaunched.canUndoMappingRestore)
    }

    func testPresetInheritsVolumeAndSiriAndSwitchesBackToGlobalOutsideApp() {
        model.settings.globalBindings[RemoteKey.voice.rawValue] = .init(action: .key, value: "F6")
        model.applyPreset(ScenePreset.all.first { $0.id == "codex" }!, bundleID: "com.openai.codex")
        model.currentBundleID = "com.openai.codex"
        XCTAssertEqual(model.runtimeBinding(for: .center).value, "Return")
        XCTAssertEqual(model.runtimeBinding(for: .voice).value, "F6")
        XCTAssertEqual(model.runtimeBinding(for: .volumeUp).value, "Volume Up")
        XCTAssertTrue(model.runtimeBinding(for: .volumeDown).enabled)
        XCTAssertEqual(model.effectiveRingAction, .codexTasks)
        model.currentBundleID = "com.apple.finder"
        XCTAssertNil(model.activeScene)
        XCTAssertEqual(model.runtimeBinding(for: .center).action, .click)
        XCTAssertEqual(model.effectiveRingAction, .scroll)
        model.currentBundleID = "com.openai.codex"
        XCTAssertNotNil(model.activeScene)
        XCTAssertEqual(model.runtimeBinding(for: .center).action, .key)
        model.restoreInitialRemoteMapping()
        let index = model.scenes.firstIndex { $0.bundleID == "com.openai.codex" }!
        model.scenes[index].enabled = true
        XCTAssertEqual(model.effectiveRingAction, .codexTasks)
        XCTAssertEqual(model.runtimeBinding(for: .volumeUp).value, "Volume Up")
        model.currentBundleID = "com.apple.finder"
        XCTAssertNil(model.activeScene)
    }

    func testResetReleasesHeldOutputsAndCancelsDelayedTapWithoutStoppingControl() async throws {
        model.settings.globalBindings[RemoteKey.menu.rawValue] = .init(action: .key, value: "F5", modifiers: [.command])
        model.handleRemotePress(.menu, pressed: true)
        XCTAssertTrue(model.isHoldingRemoteButton)
        model.restoreInitialRemoteMapping()
        XCTAssertFalse(model.isHoldingRemoteButton)
        XCTAssertTrue(events.contains { $0.type == .keyUp && $0.getIntegerValueField(.keyboardEventKeycode) == 96 })
        XCTAssertTrue(model.running)
        model.settings.globalBindings[RemoteKey.voice.rawValue] = RemoteKey.voice.referenceBinding
        events = []
        model.handleRemotePress(.voice, pressed: true); model.handleRemotePress(.voice, pressed: false)
        model.settings.volumeKeyMode = .scroll // Ensure the second reset is actionable.
        model.restoreInitialRemoteMapping()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(events.isEmpty, "A cancelled delayed Fn tap must not reach the input method after reset")
    }

    func testUndoKeepsLaterSceneEditsAndDoesNotResurrectDeletedScenes() {
        let deleted = model.scenes[0].id
        model.restoreInitialRemoteMapping()
        model.scenes.removeAll { $0.id == deleted }
        let id = model.addScene(for: .init(id: "org.example.new", name: "New", url: nil))
        model.setSceneBinding(.init(action: .key, value: "F8"), key: .menu, sceneID: id)
        model.undoInitialRemoteMappingRestore()
        XCTAssertFalse(model.scenes.contains { $0.id == deleted })
        XCTAssertEqual(model.sceneBinding(for: .menu, sceneID: id).value, "F8")
    }
}
