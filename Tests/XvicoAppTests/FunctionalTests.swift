import XCTest
import AppKit
@testable import XvicoApp

@MainActor
final class FunctionalTests: XCTestCase {
    private var domains: [String] = []
    private var models: [AppModel] = []
    private var events: [CGEvent] = []
    private var microphones: [Int] = []
    private func makeModel(authorized: Bool = true) -> (AppModel, UserDefaults) {
        let name = "XvicoTests.\(UUID().uuidString)"
        domains.append(name)
        let defaults = UserDefaults(suiteName: name)!
        let model = AppModel(defaults: defaults, observeSystem: false, accessibilityCheck: { authorized }, eventPoster: { [weak self] in self?.events.append($0) }, microphoneSwitcher: { [weak self] direction in self?.microphones.append(direction); return "Test microphone" })
        models.append(model)
        return (model, defaults)
    }
    override func tearDown() {
        MainActor.assumeIsolated {
            for model in models { model.stopControl() }
            for domain in domains { UserDefaults.standard.removePersistentDomain(forName: domain) }
            models = []; domains = []; events = []; microphones = []
        }
        super.tearDown()
    }
    private var keyboardDowns: [Int64] { events.filter { $0.type == .keyDown }.map { $0.getIntegerValueField(.keyboardEventKeycode) } }

    func testPowerSuppressionRequiresRealButtonPresenceAndSuccessfulSeize() async {
        var state = RemotePowerSuppression()
        XCTAssertFalse(state.active)
        state.buttonManagerOpenWasSeized = true
        XCTAssertFalse(state.active, "Opening with no connected remote is not suppression")
        state.buttonInterfacePresent = true
        XCTAssertTrue(state.active)
        state.buttonManagerOpenWasSeized = false
        XCTAssertFalse(state.active, "Fallback to nonexclusive listening must not report success")
    }
    func testHIDMatchingKeepsRemoteButtonsAndTouchIndependent() async {
        XCTAssertEqual(RemoteHIDInterface.identify(vendor: 0x4c, product: 0x315, page: 0x0c, usage: 1), .buttons)
        XCTAssertEqual(RemoteHIDInterface.identify(vendor: 0x4c, product: 0x315, page: 0x0d, usage: 1), .touch)
        XCTAssertNil(RemoteHIDInterface.identify(vendor: 0x4c, product: 0x315, page: 1, usage: 2))
        XCTAssertNil(RemoteHIDInterface.identify(vendor: 0x4c, product: 0x0265, page: 0x0c, usage: 1))
        XCTAssertNil(RemoteHIDInterface.identify(vendor: 0xffff, product: 0x315, page: 0x0c, usage: 1))
        XCTAssertNil(RemoteHIDInterface.identify(vendor: 0x4c, product: 0x315, page: 0x0c, usage: 2))
    }
    func testPowerPreferenceMigrationAndControlStateAreIndependentFromConnection() async throws {
        let settings = try JSONDecoder().decode(XvicoSettings.self, from: Data(#"{"blockPowerActions":false}"#.utf8))
        XCTAssertFalse(settings.interceptRemoteButtons)
        let (model, _) = makeModel()
        XCTAssertFalse(model.remoteConnected)
        XCTAssertEqual(model.controlStatusLabel, "控制已启用")
        XCTAssertFalse(model.powerIntercepted)
        model.stopControl()
        XCTAssertEqual(model.controlStatusLabel, "控制已停止")
    }
    func testCustomNextSceneActionChangesRuntimeMapping() async {
        let (model, _) = makeModel()
        model.currentBundleID = "unmatched.app"
        model.scenes[0].bindings[RemoteKey.menu.rawValue] = KeyBinding(action: .key, value: "B")
        model.perform(KeyBinding(action: .nextScene, value: ""))
        XCTAssertEqual(model.activeScene?.id, model.scenes[0].id)
        XCTAssertEqual(model.runtimeBinding(for: .menu).value, "B")
        model.perform(KeyBinding(action: .nextScene, value: ""))
        XCTAssertEqual(model.activeScene?.id, model.scenes[1].id)
    }
    func testLegacyAndAllGlobalFieldsRoundtrip() async throws {
        let legacy = try JSONDecoder().decode(XvicoSettings.self, from: Data(#"{"touchEnabled":false,"scrollSensitivity":1.5}"#.utf8))
        XCTAssertFalse(legacy.touchEnabled)
        XCTAssertEqual(legacy.scrollSensitivity, 1.5)
        XCTAssertEqual(legacy.ringSensitivity, 1.08)
        XCTAssertEqual(legacy.ringRadius, 0.33)
        var settings = legacy
        settings.pointerSensitivity = 2.1; settings.ringAction = .switchApp; settings.ringToggleKey = ""
        settings.volumeKeyMode = .scroll; settings.volumeScrollStep = 123; settings.wheelStyle = .stepped
        settings.showDockIcon = false; settings.showMenuBarIcon = true; settings.keepRunningWhenClosed = false
        settings.interfaceLanguage = .japanese
        settings.globalBindings[RemoteKey.center.rawValue]?.textValue = "Example"
        XCTAssertEqual(try JSONDecoder().decode(XvicoSettings.self, from: JSONEncoder().encode(settings)), settings)
    }
    func testRestartPreservesSettingsShortcutsAndSelectedScene() async throws {
        let (model, defaults) = makeModel()
        model.addScene(name: "Persistent", bundleID: "org.example.app")
        let selected = model.selectedSceneID
        model.settings.volumeKeyMode = .scroll; model.settings.volumeScrollStep = 127
        model.settings.ringRadius = 0.47; model.settings.pointerSensitivity = 1.7
        model.shortcuts.append(UserShortcut(name: "Example", phrase: "example", action: .text, value: "Data"))
        let restored = AppModel(defaults: defaults, observeSystem: false, eventPoster: { _ in })
        models.append(restored)
        XCTAssertEqual(restored.settings, model.settings)
        XCTAssertEqual(restored.shortcuts, model.shortcuts)
        XCTAssertEqual(restored.selectedSceneID, selected)
        XCTAssertEqual(restored.scenes, model.scenes)
    }
    func testDefaultAndAppSceneAreSeparate() async throws {
        let (model, _) = makeModel()
        model.updateBinding(KeyBinding(action: .key, value: "A"), for: .menu)
        let scene = model.scenes[0]
        model.selectSceneForMapping(scene)
        model.updateBinding(KeyBinding(action: .key, value: "B"), for: .menu)
        model.currentBundleID = "org.example.unmatched"
        XCTAssertEqual(model.runtimeBinding(for: .menu).value, "A")
        model.currentBundleID = scene.bundleID
        XCTAssertEqual(model.runtimeBinding(for: .menu).value, "B")
        model.settings.autoSwitchScenes = false
        XCTAssertEqual(model.runtimeBinding(for: .menu).value, "A")
        model.selectSceneForMapping(nil)
        XCTAssertEqual(model.binding(for: .menu).value, "A")
    }
    func testBuiltInPresetMappingsMatchExpectedActions() async throws {
        let all = ScenePreset.all
        XCTAssertEqual(all.count, 6)
        let video = all.first { $0.id == "video" }!
        XCTAssertEqual(video.bindings[RemoteKey.center.rawValue]?.value, "Return")
        let zoom = all.first { $0.id == "zoom" }!
        XCTAssertEqual(zoom.bindings[RemoteKey.mute.rawValue]?.value, "A")
        XCTAssertEqual(zoom.bindings[RemoteKey.mute.rawValue]?.modifiers, [.command, .shift])
        XCTAssertEqual(all.first { $0.id == "reading" }?.bindings[RemoteKey.touchDown.rawValue]?.value, "Page Down")
        XCTAssertEqual(all.first { $0.id == "music" }?.bindings[RemoteKey.touchRight.rawValue]?.value, "Next Track")
        let (model, _) = makeModel()
        let count = model.scenes.count
        model.applyPreset(zoom, bundleID: model.scenes[0].bundleID)
        XCTAssertEqual(model.scenes.count, count)
        XCTAssertEqual(model.selectedScene?.bindings, zoom.bindings)
    }
    func testFileExportImportAndInvalidFileAtomicity() async throws {
        let (model, _) = makeModel()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("scene.json")
        let first = model.scenes[0]
        try model.exportScenes(to: file, scene: first)
        XCTAssertEqual(try JSONDecoder().decode([XvicoScene].self, from: Data(contentsOf: file)), [first])
        XCTAssertEqual(try model.importScenes(from: file), 1)
        XCTAssertNotEqual(model.scenes.last?.id, first.id)
        let before = model.scenes
        try Data("invalid json".utf8).write(to: file)
        XCTAssertThrowsError(try model.importScenes(from: file))
        XCTAssertEqual(model.scenes, before)
    }
    func testShortcutGlyphParsingAndActualEventFlags() async throws {
        let (model, _) = makeModel()
        model.perform(KeyBinding(action: .key, value: "⌘⇧R"))
        XCTAssertEqual(keyboardDowns, [15])
        XCTAssertTrue(events.first { $0.type == .keyDown }!.flags.contains([.maskCommand, .maskShift]))
        XCTAssertFalse(events.last!.flags.contains([.maskCommand, .maskShift]))
        XCTAssertEqual(KeyBinding(action: .key, value: "⌘+").normalizedKeyboard.modifiers, [.command, .shift])
    }
    func testGlobalPresetRestoresAllDeviceConfiguration() async throws {
        let (model, _) = makeModel()
        model.settings.ringAction = .switchApp; model.settings.volumeKeyMode = .scroll
        model.settings.volumeScrollStep = 111; model.settings.pointerSensitivity = 1.8
        model.settings.globalBindings[RemoteKey.menu.rawValue] = KeyBinding(action: .key, value: "F8")
        let expected = model.settings
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try model.exportGlobalPreset(to: file)
        model.settings = XvicoSettings()
        try model.importGlobalPreset(from: file)
        XCTAssertEqual(model.settings, expected)
        XCTAssertEqual(model.runtimeBinding(for: .menu).value, "F8")
    }
    func testPermissionDenialAndDisabledBindingEmitNothing() async throws {
        let (model, _) = makeModel(authorized: false)
        model.perform(KeyBinding(action: .key, value: "A"))
        XCTAssertTrue(events.isEmpty)
        XCTAssertTrue(model.toast?.contains("辅助功能") == true)
        model.perform(KeyBinding(action: .key, value: "A", enabled: false))
        XCTAssertTrue(events.isEmpty)
        model.perform(KeyBinding(action: .key, value: "Unknown"))
        XCTAssertTrue(model.toast?.contains("未识别") == true)
    }
    func testMouseAndTextReturnOutputWithoutPostingToDesktop() async throws {
        let (model, _) = makeModel()
        model.perform(KeyBinding(action: .click, value: "", mouseButton: .right))
        XCTAssertEqual(events.map(\.type), [.rightMouseDown, .rightMouseUp])
        events = []
        var binding = KeyBinding(action: .textAndReturn, value: "Hello")
        binding.value = "F12"
        model.perform(binding)
        XCTAssertEqual(keyboardDowns.suffix(1), [36])
        var length = 0; var characters = [UniChar](repeating: 0, count: 64)
        events[0].keyboardGetUnicodeString(maxStringLength: 64, actualStringLength: &length, unicodeString: &characters)
        XCTAssertEqual(String(utf16CodeUnits: characters, count: length), "Hello")
    }
    func testVolumeModesOverrideDisabledMechanicalBindings() async throws {
        let (model, _) = makeModel()
        model.settings.volumeKeyMode = .microphone
        model.handleRemotePress(.volumeUp, pressed: true); model.handleRemotePress(.volumeUp, pressed: false)
        model.handleRemotePress(.volumeDown, pressed: true); model.handleRemotePress(.volumeDown, pressed: false)
        XCTAssertEqual(microphones, [-1, 1]); XCTAssertTrue(events.isEmpty)
        model.settings.volumeKeyMode = .scroll; model.settings.volumeScrollStep = 80
        model.handleRemotePress(.volumeDown, pressed: true); model.handleRemotePress(.volumeDown, pressed: false)
        XCTAssertEqual(events.count, 1); XCTAssertEqual(events[0].type, .scrollWheel)
        events = []; model.settings.volumeKeyMode = .key
        model.settings.globalBindings[RemoteKey.volumeUp.rawValue] = KeyBinding(action: .key, value: "F5")
        model.handleRemotePress(.volumeUp, pressed: true); model.handleRemotePress(.volumeUp, pressed: false)
        XCTAssertEqual(keyboardDowns, [96])
    }
    func testRingTogglePreservesFirstClickAndConsumesSecond() async throws {
        let (model, _) = makeModel()
        model.handleRemotePress(.touchRight, pressed: true); model.handleRemotePress(.touchRight, pressed: false)
        XCTAssertEqual(keyboardDowns, [124])
        model.handleRemotePress(.touchRight, pressed: true); model.handleRemotePress(.touchRight, pressed: false)
        XCTAssertEqual(keyboardDowns, [124]); XCTAssertEqual(model.settings.ringAction, .switchApp)
    }
    func testSiriDoubleTapCancelsSingleOutput() async throws {
        let (model, _) = makeModel()
        model.handleRemotePress(.voice, pressed: true); model.handleRemotePress(.voice, pressed: false)
        model.handleRemotePress(.voice, pressed: true); model.handleRemotePress(.voice, pressed: false)
        try await Task.sleep(nanoseconds: 260_000_000)
        XCTAssertEqual(keyboardDowns, [36])
        XCTAssertFalse(events.contains { $0.getIntegerValueField(.keyboardEventKeycode) == 63 })
    }
    func testHeldKeyReleasesOriginalBindingAfterSceneChange() async throws {
        let (model, _) = makeModel()
        var binding = RemoteKey.voice.referenceBinding
        binding.doubleClickEnabled = false; binding.holdNoOutput = false; binding.longPressValue = "F1"
        model.settings.globalBindings[RemoteKey.voice.rawValue] = binding
        model.handleRemotePress(.voice, pressed: true)
        try await Task.sleep(nanoseconds: 400_000_000)
        binding.longPressValue = "F2"; model.settings.globalBindings[RemoteKey.voice.rawValue] = binding
        model.handleRemotePress(.voice, pressed: false)
        XCTAssertEqual(events.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [122, 122])
        XCTAssertEqual(events.map(\.type), [.keyDown, .keyUp])
    }
    func testStopCancelsPendingTapAndReleasesHeldFn() async throws {
        let (model, _) = makeModel()
        model.handleRemotePress(.voice, pressed: true); model.handleRemotePress(.voice, pressed: false)
        model.stopControl()
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertTrue(events.isEmpty)
        model.running = true
        var binding = RemoteKey.voice.referenceBinding; binding.siriMode = "长按模式"
        model.settings.globalBindings[RemoteKey.voice.rawValue] = binding
        model.handleRemotePress(.voice, pressed: true); model.stopControl()
        XCTAssertEqual(events.map(\.type), [.flagsChanged, .flagsChanged])
        XCTAssertTrue(events[0].flags.contains(.maskSecondaryFn))
        XCTAssertFalse(events[1].flags.contains(.maskSecondaryFn))
    }
    func testTouchDisableKeepsMechanicalKeysAndRingModesDiffer() async throws {
        var settings = XvicoSettings(); settings.touchEnabled = false
        var processor = RemoteGestureProcessor()
        XCTAssertTrue(processor.process(.init(x: 0.9, y: 0.5, touching: true), settings: settings, mode: .scroll).isEmpty)
        settings.touchEnabled = true
        _ = processor.process(.init(x: 0.9, y: 0.5, touching: true), settings: settings, mode: .scroll)
        let scroll = processor.process(.init(x: 0.85, y: 0.7, touching: true), settings: settings, mode: .scroll)
        XCTAssertTrue(scroll.contains { if case .scroll(_, true) = $0 { return true }; return false })
        let (model, _) = makeModel()
        model.settings.touchEnabled = false
        model.handleRemotePress(.touchUp, pressed: true); model.handleRemotePress(.touchUp, pressed: false)
        XCTAssertEqual(keyboardDowns, [126])
        events = []; model.settings.touchEnabled = true; model.settings.ringAction = .switchApp
        model.handleTouch(.init(x: 0.9, y: 0.5, touching: true)); model.handleTouch(.init(x: 0.85, y: 0.7, touching: true))
        XCTAssertTrue(keyboardDowns.contains(48))
        model.handleTouch(.init(x: 0.85, y: 0.7, touching: false))
        XCTAssertEqual(events.last?.type, .flagsChanged)
        XCTAssertFalse(events.last!.flags.contains(.maskCommand))
    }
    func testStandardHIDVocabularyAndUnrelatedDeviceRejection() async throws {
        XCTAssertEqual(RemoteInputMonitor.standardKey(page: 0x0C, usage: 0x60), .tv)
        XCTAssertEqual(RemoteInputMonitor.standardKey(page: 0x0C, usage: 0x04), .voice)
        XCTAssertEqual(RemoteInputMonitor.standardKey(page: 0x0C, usage: 0x80), .center)
        XCTAssertEqual(RemoteInputMonitor.standardKey(page: 0x01, usage: 0x86), .menu)
        XCTAssertEqual(RemoteInputMonitor.standardKey(page: 0x0C, usage: 0xCF), .voice)
        XCTAssertEqual(RemoteInputMonitor.standardKey(page: 0x0C, usage: 0x223), .tv)
        XCTAssertEqual(RemoteInputMonitor.standardKey(page: 0x0C, usage: 0x42), .touchUp)
        XCTAssertNil(RemoteInputMonitor.standardKey(page: 0x07, usage: 0x30))
        XCTAssertNil(RemoteInputMonitor.standardKey(page: 0x0C, usage: 0xFFFF))
    }
    func testPhysicalButtonReportSelectsMatchingEditorAndConfiguredAction() async {
        let (model, _) = makeModel()
        model.settings.autoSwitchScenes = false
        let physicalKeys: [(Int, Int, RemoteKey, String, Int64)] = [
            (0x0C, 0x04, .voice, "A", 0),
            (0x01, 0x86, .menu, "B", 11),
            (0x0C, 0x60, .tv, "C", 8),
            (0x0C, 0x80, .center, "D", 2),
        ]
        for (page, usage, key, letter, code) in physicalKeys {
            events = []
            model.settings.globalBindings[key.rawValue] = KeyBinding(action: .key, value: letter)
            model.handleHIDUsage(page: page, usage: usage, pressed: true)
            XCTAssertEqual(model.selectedKey, key)
            model.selectedKey = nil
            model.handleHIDUsage(page: page, usage: usage, pressed: false)
            XCTAssertNil(model.selectedKey, "Releasing a key must not reopen its editor")
            XCTAssertEqual(keyboardDowns, [code], "Physical report must use this key's configured action")
            XCTAssertEqual(events.last?.type, .keyUp)
            XCTAssertEqual(events.last?.getIntegerValueField(.keyboardEventKeycode), code)
        }
    }
    func testDuplicateAndUnpairedReleasesDoNotSwitchRingMode() async {
        let (model, _) = makeModel()
        model.currentBundleID = "unmatched.app"
        model.settings.ringAction = .scroll
        // Unchanged releases in packed reports are not a first click.
        model.handleRemotePress(.touchRight, pressed: false)
        model.handleRemotePress(.touchRight, pressed: false)
        model.handleRemotePress(.touchRight, pressed: true)
        model.handleRemotePress(.touchRight, pressed: true)
        XCTAssertEqual(model.effectiveRingAction, .scroll)
        model.handleRemotePress(.touchRight, pressed: false)
        model.handleRemotePress(.touchRight, pressed: false)
        XCTAssertEqual(model.effectiveRingAction, .scroll)
        model.handleRemotePress(.touchRight, pressed: true)
        XCTAssertEqual(model.effectiveRingAction, .switchApp, "Two real presses still perform the configured mode toggle")
    }
    func testPackedButtonReportsEmitOnlyChangedValues() async {
        var filter = RemoteButtonValueFilter()
        XCTAssertFalse(filter.changed(deviceID: 1, page: 0x0C, usage: 0x45, value: 0))
        XCTAssertTrue(filter.changed(deviceID: 1, page: 0x0C, usage: 0x45, value: 1))
        XCTAssertFalse(filter.changed(deviceID: 1, page: 0x0C, usage: 0x45, value: 1))
        XCTAssertFalse(filter.changed(deviceID: 1, page: 0x0C, usage: 0x60, value: 0))
        XCTAssertTrue(filter.changed(deviceID: 1, page: 0x0C, usage: 0x45, value: 0))
        XCTAssertFalse(filter.changed(deviceID: 1, page: 0x0C, usage: 0x45, value: 0))
        XCTAssertTrue(filter.changed(deviceID: 2, page: 0x0C, usage: 0x45, value: 1))
        filter.remove(deviceID: 2)
        XCTAssertTrue(filter.changed(deviceID: 2, page: 0x0C, usage: 0x45, value: 1))
    }
    func testChatGPTRingScrollUsesSceneChoiceAndPersistsIt() async {
        let (model, defaults) = makeModel()
        let index = model.scenes.firstIndex { $0.bundleID == "com.openai.codex" }!
        model.currentApp = "ChatGPT"; model.currentBundleID = "com.openai.codex"
        model.scenes[index].ringAction = .scroll
        XCTAssertEqual(model.effectiveRingAction, .scroll)
        for frame in 0..<16 {
            let angle = -Double(frame) * 0.05
            model.handleTouch(.init(x: 0.5 + 0.4 * cos(angle), y: 0.5 + 0.4 * sin(angle), touching: true, timestamp: Double(frame) * 0.01))
        }
        let scroll = events.filter { $0.type == .scrollWheel }
        XCTAssertGreaterThan(scroll.count, 5)
        XCTAssertTrue(keyboardDowns.isEmpty, "Scroll mode must not emit Codex task shortcuts")
        XCTAssertTrue(scroll.allSatisfy { $0.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) < 0 })
        XCTAssertTrue(scroll.allSatisfy { $0.getIntegerValueField(.scrollWheelEventDeltaAxis2) == 0 })
        let restored = AppModel(defaults: defaults, observeSystem: false, eventPoster: { _ in })
        models.append(restored)
        restored.currentBundleID = "com.openai.codex"
        XCTAssertEqual(restored.effectiveRingAction, .scroll)
    }
    func testVoiceStopBeforeStartIsSafe() async throws {
        let voice = VoiceService()
        voice.stop(); voice.stop()
        XCTAssertFalse(voice.isListening); XCTAssertFalse(voice.isStarting)
    }
}
