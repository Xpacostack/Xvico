import XCTest
import AppKit
@testable import XvicoApp

@MainActor
final class MappingBehaviorTests: XCTestCase {
    func testCompleteKeyboardVocabularyIsAvailable() {
        XCTAssertEqual(KeyboardOutput.all.count, 122)
        XCTAssertEqual(Set(KeyboardOutput.all.map(\.name)).count, 122)
        XCTAssertEqual(KeyboardOutput.named("Up Arrow")?.keyCode, 126)
        XCTAssertEqual(KeyboardOutput.named("Mute")?.systemCode, 7)
        XCTAssertEqual(KeyboardOutput.named("Right Control")?.keyCode, 62)
    }
    func testAllPhysicalKeysUseAssignedActionAndMuteCanRunMissionControl() throws {
        let name = "XvicoMigrationTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var events: [CGEvent] = []
        let model = AppModel(defaults: defaults, observeSystem: false, accessibilityCheck: { true }, eventPoster: { events.append($0) })
        defer { model.stopControl() }
        model.settings.autoSwitchScenes = false; model.settings.volumeKeyMode = .key
        let physical: [(Int, Int, RemoteKey)] = [
            (0x0C, 0x04, .voice), (0x0C, 0x60, .tv), (0x01, 0x86, .menu),
            (0x0C, 0x30, .power), (0x0C, 0xE2, .mute), (0x0C, 0xE9, .volumeUp),
            (0x0C, 0xEA, .volumeDown), (0x0C, 0xCD, .playPause), (0x0C, 0x80, .center),
            (0x0C, 0x42, .touchUp), (0x0C, 0x43, .touchDown), (0x0C, 0x44, .touchLeft), (0x0C, 0x45, .touchRight),
        ]
        for (page, usage, key) in physical {
            events = []
            model.settings.globalBindings[key.rawValue] = KeyBinding(action: .key, value: "Up Arrow", modifiers: [.control])
            model.handleHIDUsage(page: page, usage: usage, pressed: true)
            model.handleHIDUsage(page: page, usage: usage, pressed: false)
            XCTAssertEqual(events.map(\.type), [.flagsChanged, .keyDown, .keyUp, .flagsChanged], key.rawValue)
            XCTAssertEqual(events[1].getIntegerValueField(.keyboardEventKeycode), 126)
            XCTAssertTrue(events[1].flags.contains(.maskControl))
            XCTAssertFalse(events.last!.flags.contains(.maskControl))
            XCTAssertFalse(events.contains(where: { $0.type.rawValue == 14 }), "Custom key must not emit original media action")
        }
    }
    func testHardwareEditorUsesTheSceneThatActuallyExecutes() {
        let name = "XvicoScopeTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var events: [CGEvent] = []
        let model = AppModel(defaults: defaults, observeSystem: false, accessibilityCheck: { true }, eventPoster: { events.append($0) })
        defer { model.stopControl() }
        let index = model.scenes.firstIndex { $0.bundleID == "com.openai.codex" }!
        model.scenes[index].bindings[RemoteKey.mute.rawValue] = KeyBinding(action: .key, value: "Up Arrow", modifiers: [.control])
        model.currentBundleID = "com.openai.codex"
        model.selectSceneForMapping(nil)
        model.handleHIDUsage(page: 0x0C, usage: 0xE2, pressed: true)
        XCTAssertFalse(model.editingGlobalMapping)
        XCTAssertEqual(model.selectedSceneID, model.scenes[index].id)
        XCTAssertEqual(model.binding(for: .mute), model.runtimeBinding(for: .mute))
        model.handleHIDUsage(page: 0x0C, usage: 0xE2, pressed: false)
        XCTAssertEqual(events.first { $0.type == .keyDown }?.getIntegerValueField(.keyboardEventKeycode), 126)
    }
    func testScenePressOverridesResolveAtExecutionAndInEditor() {
        let name = "XvicoPressScopeTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let model = AppModel(defaults: defaults, observeSystem: false, eventPoster: { _ in })
        defer { model.stopControl() }
        let index = model.scenes.firstIndex { $0.bundleID == "com.openai.codex" }!
        model.currentBundleID = "com.openai.codex"
        var global = model.settings.globalBindings[RemoteKey.voice.rawValue]!
        global.longPressEnabled = true; global.longPressValue = "F6"; global.holdNoOutput = true
        global.doubleClickEnabled = true; global.doubleClickValue = "Return"
        model.settings.globalBindings[RemoteKey.voice.rawValue] = global
        var scene = model.sceneBinding(for: .voice, sceneID: model.scenes[index].id)
        scene.longPressOverride = .inherit; scene.doubleClickOverride = .inherit
        model.scenes[index].bindings[RemoteKey.voice.rawValue] = scene
        model.selectSceneForMapping(model.scenes[index])
        XCTAssertEqual(model.runtimeBinding(for: .voice).longPressValue, "F6")
        XCTAssertTrue(model.runtimeBinding(for: .voice).holdNoOutput)
        XCTAssertEqual(model.binding(for: .voice), model.runtimeBinding(for: .voice))
        scene.longPressOverride = .disabled; scene.doubleClickOverride = .disabled
        model.scenes[index].bindings[RemoteKey.voice.rawValue] = scene
        XCTAssertFalse(model.runtimeBinding(for: .voice).longPressEnabled)
        XCTAssertFalse(model.runtimeBinding(for: .voice).doubleClickEnabled)
        scene.longPressOverride = .custom; scene.doubleClickOverride = .custom
        scene.longPressEnabled = true; scene.longPressValue = "F7"
        scene.doubleClickEnabled = true; scene.doubleClickValue = "Space"
        model.scenes[index].bindings[RemoteKey.voice.rawValue] = scene
        XCTAssertEqual(model.runtimeBinding(for: .voice).longPressValue, "F7")
        XCTAssertEqual(model.runtimeBinding(for: .voice).doubleClickValue, "Space")
    }
    func testPhysicalMouseBindingStaysDownForDraggingAndReleasesOnStop() {
        let name = "XvicoMouseHoldTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var events: [CGEvent] = []
        let model = AppModel(defaults: defaults, observeSystem: false, accessibilityCheck: { true }, eventPoster: { events.append($0) })
        defer { model.stopControl() }
        model.settings.autoSwitchScenes = false
        model.settings.globalBindings[RemoteKey.center.rawValue] = KeyBinding(action: .click, value: "", mouseButton: .right)
        model.handleHIDUsage(page: 0x0C, usage: 0x80, pressed: true)
        XCTAssertEqual(events.map(\.type), [.rightMouseDown])
        for frame in 0..<8 {
            model.handleTouch(.init(x: 0.5 + Double(frame) * 0.01, y: 0.5, touching: true, timestamp: Double(frame) * 0.01))
        }
        XCTAssertTrue(events.contains(where: { $0.type == .rightMouseDragged }))
        XCTAssertFalse(events.contains(where: { $0.type == .rightMouseUp }))
        model.handleHIDUsage(page: 0x0C, usage: 0x80, pressed: false)
        XCTAssertEqual(events.last?.type, .rightMouseUp)
        model.handleHIDUsage(page: 0x0C, usage: 0x80, pressed: true)
        model.stopControl()
        XCTAssertEqual(events.last?.type, .rightMouseUp)
    }
}
