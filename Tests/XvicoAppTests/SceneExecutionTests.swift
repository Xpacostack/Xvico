import XCTest
import AppKit
@testable import XvicoApp

@MainActor
final class SceneExecutionTests: XCTestCase {
    private var domain = ""
    private var defaults: UserDefaults!
    private var events: [CGEvent] = []
    private var model: AppModel!
    override func setUp() async throws {
        domain = "XvicoScenes.\(UUID())"; defaults = UserDefaults(suiteName: domain)!
        model = AppModel(defaults: defaults, observeSystem: false, accessibilityCheck: { true }, eventPoster: { self.events.append($0) })
    }
    override func tearDown() async throws { model.stopControl(); defaults.removePersistentDomain(forName: domain); model = nil; defaults = nil; events = [] }
    func testAddingAnApplicationDoesNotDuplicateOrEraseItsMapping() {
        let app = ApplicationChoice(id: "org.example.editor", name: "Editor", url: nil)
        let id = model.addScene(for: app)
        model.setSceneBinding(.init(action: .key, value: "F6"), key: .menu, sceneID: id)
        XCTAssertEqual(model.addScene(for: app), id)
        XCTAssertEqual(model.scenes.filter { $0.bundleID == app.id }.count, 1)
        XCTAssertEqual(model.sceneBinding(for: .menu, sceneID: id).value, "F6")
    }
    func testSceneEditorChangesActualMouseAndKeyboardExecutionWithoutSelectingMapping() {
        let id = model.addScene(for: .init(id: "org.example.editor", name: "Editor", url: nil))
        model.currentBundleID = "org.example.editor"
        model.setSceneBinding(.init(action: .click, value: "Return"), key: .center, sceneID: id)
        model.handleHIDUsage(page: 12, usage: 128, pressed: true)
        model.handleHIDUsage(page: 12, usage: 128, pressed: false)
        XCTAssertEqual(events.map(\.type), [.leftMouseDown, .leftMouseUp])
        XCTAssertTrue(events.allSatisfy { $0.getIntegerValueField(.mouseEventClickState) == 1 })
        events = []
        model.setSceneBinding(.init(action: .key, value: "Return"), key: .center, sceneID: id)
        model.handleHIDUsage(page: 12, usage: 128, pressed: true)
        model.handleHIDUsage(page: 12, usage: 128, pressed: false)
        XCTAssertEqual(events.map(\.type), [.keyDown, .keyUp])
        XCTAssertEqual(events[0].getIntegerValueField(.keyboardEventKeycode), 36)
    }
    func testSceneDisableAndAutoSwitchOffRestoreGlobalExecution() {
        let id = model.addScene(for: .init(id: "org.example.editor", name: "Editor", url: nil))
        model.settings.globalBindings[RemoteKey.menu.rawValue] = .init(action: .key, value: "F1")
        model.setSceneBinding(.init(action: .key, value: "F2"), key: .menu, sceneID: id)
        model.currentBundleID = "org.example.editor"
        XCTAssertEqual(model.runtimeBinding(for: .menu).value, "F2")
        let index = model.scenes.firstIndex { $0.id == id }!
        model.scenes[index].enabled = false
        XCTAssertEqual(model.runtimeBinding(for: .menu).value, "F1")
        model.scenes[index].enabled = true; model.settings.autoSwitchScenes = false
        XCTAssertEqual(model.runtimeBinding(for: .menu).value, "F1")
    }
    func testImportedCenterReturnRemainsReturnWithoutSpecialOverride() {
        let id = model.scenes.first { $0.bundleID == "com.openai.codex" }!.id
        model.setSceneBinding(.init(action: .key, value: "Return"), key: .center, sceneID: id)
        let restored = AppModel(defaults: defaults, observeSystem: false, eventPoster: { _ in })
        defer { restored.stopControl() }
        restored.currentBundleID = "com.openai.codex"
        XCTAssertEqual(restored.runtimeBinding(for: .center).action, .key)
        XCTAssertEqual(restored.runtimeBinding(for: .center).value, "Return")
    }
    func testPresetStaysEditableAndWheelOverridesPersist() {
        model.applyPreset(ScenePreset.all.first { $0.id == "video" }!, bundleID: "org.example.browser")
        let id = model.scenes.first { $0.bundleID == "org.example.browser" }!.id
        model.setSceneBinding(.init(action: .click, value: "Return", mouseButton: .right), key: .center, sceneID: id)
        model.setSceneRing(.scroll, for: id); model.setSceneWheel(.stepped, for: id)
        let restored = AppModel(defaults: defaults, observeSystem: false, eventPoster: { _ in })
        defer { restored.stopControl() }
        restored.currentBundleID = "org.example.browser"
        XCTAssertEqual(restored.runtimeBinding(for: .center).mouseButton, .right)
        XCTAssertEqual(restored.effectiveWheelStyle, .stepped)
        restored.setSceneWheel(nil, for: id); restored.settings.wheelStyle = .continuous
        XCTAssertEqual(restored.effectiveWheelStyle, .continuous)
        XCTAssertEqual(restored.effectiveRingAction, .scroll)
    }
    func testQuickActionConfigurationUsesSameKeyboardPath() {
        let id = model.addScene(for: .init(id: "org.example.editor", name: "Editor", url: nil))
        model.currentBundleID = "org.example.editor"
        model.setSceneBinding(KeyboardQuickAction.missionControl.applying(to: .init(action: .key, value: "M")), key: .mute, sceneID: id)
        model.handleHIDUsage(page: 12, usage: 226, pressed: true)
        model.handleHIDUsage(page: 12, usage: 226, pressed: false)
        let key = events.first { $0.type == .keyDown }!
        XCTAssertEqual(key.getIntegerValueField(.keyboardEventKeycode), 126)
        XCTAssertTrue(key.flags.contains(.maskControl))
    }
    func testEmptySceneCollectionStaysEmptyAfterRestart() {
        model.scenes = []
        let restored = AppModel(defaults: defaults, observeSystem: false, eventPoster: { _ in })
        defer { restored.stopControl() }
        XCTAssertTrue(restored.scenes.isEmpty)
        XCTAssertNil(restored.selectedSceneID)
    }
    func testEveryPhysicalSceneBindingPersistsAndExecutesWithEnableAndGlobalFallback() {
        let id = model.addScene(for: .init(id: "org.example.audit", name: "Audit", url: nil))
        model.settings.volumeKeyMode = .key
        model.settings.ringToggleKey = ""
        for key in RemoteKey.physicalOrder {
            model.settings.globalBindings[key.rawValue] = .init(action: .key, value: "F1")
            model.setSceneBinding(.init(action: .key, value: "F6", modifiers: [.control]), key: key, sceneID: id)
        }
        let restored = AppModel(defaults: defaults, observeSystem: false, accessibilityCheck: { true }, eventPoster: { self.events.append($0) })
        defer { restored.stopControl() }
        restored.currentBundleID = "org.example.audit"
        for key in RemoteKey.physicalOrder {
            events = []
            restored.handleRemotePress(key, pressed: true); restored.handleRemotePress(key, pressed: false)
            XCTAssertEqual(events.map(\.type), [.flagsChanged, .keyDown, .keyUp, .flagsChanged], key.rawValue)
            XCTAssertEqual(events[1].getIntegerValueField(.keyboardEventKeycode), 97, key.rawValue)
            XCTAssertTrue(events[1].flags.contains(.maskControl), key.rawValue)
            var disabled = restored.sceneBinding(for: key, sceneID: id); disabled.enabled = false
            restored.setSceneBinding(disabled, key: key, sceneID: id)
            events = []
            restored.handleRemotePress(key, pressed: true); restored.handleRemotePress(key, pressed: false)
            XCTAssertTrue(events.isEmpty, key.rawValue)
            disabled.enabled = true; restored.setSceneBinding(disabled, key: key, sceneID: id)
        }
        restored.currentBundleID = "org.example.other"
        for key in RemoteKey.physicalOrder {
            events = []
            restored.handleRemotePress(key, pressed: true); restored.handleRemotePress(key, pressed: false)
            XCTAssertEqual(events.map(\.type), [.keyDown, .keyUp], key.rawValue)
            XCTAssertEqual(events[0].getIntegerValueField(.keyboardEventKeycode), 122, key.rawValue)
        }
    }
    func testAllThirteenPhysicalKeysEmitSceneMappingAndReturnToGlobalWhenDisabled() {
        let id = model.addScene(for: .init(id: "org.example.allkeys", name: "All Keys", url: nil))
        model.currentBundleID = "org.example.allkeys"
        model.settings.autoSwitchScenes = true
        model.settings.volumeKeyMode = .key
        model.settings.ringToggleKey = ""
        let inputs: [(RemoteKey, Int)] = [(.voice, 4), (.tv, 0x60), (.menu, 0x40),
            (.power, 0x30), (.mute, 0xE2), (.volumeUp, 0xE9), (.volumeDown, 0xEA),
            (.playPause, 0xB0), (.center, 0x80), (.touchUp, 0x42), (.touchDown, 0x43),
            (.touchLeft, 0x44), (.touchRight, 0x45)]
        for (key, usage) in inputs {
            model.settings.globalBindings[key.rawValue] = .init(action: .key, value: "F6")
            model.setSceneBinding(.init(action: .key, value: "F7"), key: key, sceneID: id)
            events.removeAll()
            model.handleHIDUsage(page: 12, usage: usage, pressed: true)
            model.handleHIDUsage(page: 12, usage: usage, pressed: false)
            XCTAssertEqual(events.map(\.type), [.keyDown, .keyUp], key.rawValue)
            XCTAssertEqual(events.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [98, 98], key.rawValue)
        }
        let index = model.scenes.firstIndex { $0.id == id }!
        model.scenes[index].enabled = false
        for (key, usage) in inputs {
            events.removeAll()
            model.handleHIDUsage(page: 12, usage: usage, pressed: true)
            model.handleHIDUsage(page: 12, usage: usage, pressed: false)
            XCTAssertEqual(events.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [97, 97], key.rawValue)
        }
    }
}
