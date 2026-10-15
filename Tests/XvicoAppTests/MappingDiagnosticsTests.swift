import XCTest
import AppKit
@testable import XvicoApp

@MainActor
final class MappingDiagnosticsTests: XCTestCase {
    func testSourcesMatchMergedSceneAndInheritedPressBehaviors() {
        var global = KeyBinding(action: .key, value: "F1", longPressEnabled: true,
                                longPressValue: "F2", doubleClickEnabled: true, doubleClickValue: "F3")
        global.longPressRightModifiers = [.command]
        let globals = [RemoteKey.voice.rawValue: global]
        var scene = XvicoScene.coding(name: "Editor", bundleID: "org.example.editor", color: "blue")
        scene.bindings[RemoteKey.voice.rawValue] = .init(action: .key, value: "F6")
        let result = BindingResolver.resolve(.voice, globals: globals, scene: scene)
        XCTAssertEqual(result.source, .scene)
        XCTAssertEqual(result.holdSource, .global)
        XCTAssertEqual(result.doubleSource, .global)
        XCTAssertEqual(result.binding.value, "F6")
        XCTAssertEqual(result.binding.longPressValue, "F2")
        XCTAssertEqual(result.binding.longPressRightModifiers, [.command])
        XCTAssertEqual(result.binding.doubleClickValue, "F3")
        XCTAssertEqual(BindingResolver.resolve(.mute, globals: globals, scene: scene).source, .initial)
        scene.bindings[RemoteKey.voice.rawValue]?.longPressOverride = .disabled
        let disabled = BindingResolver.resolve(.voice, globals: globals, scene: scene)
        XCTAssertFalse(disabled.binding.longPressEnabled)
        XCTAssertEqual(disabled.holdSource, .scene)
    }

    func testRuntimeAndInspectorAgreeAndSentModifiersAreNotLost() {
        let domain = "Xvico.MappingDiagnostics.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        var events: [CGEvent] = []
        let model = AppModel(defaults: defaults, observeSystem: false,
            accessibilityCheck: { true }, eventPoster: { events.append($0) })
        defer { model.stopControl() }
        model.scenes = [.coding(name: "Editor", bundleID: "org.example.editor", color: "blue")]
        model.scenes[0].bindings[RemoteKey.menu.rawValue] = .init(action: .key, value: "2", modifiers: [.control])
        model.currentBundleID = "org.example.editor"
        model.handleRemotePress(.menu, pressed: true)
        model.handleRemotePress(.menu, pressed: false)
        XCTAssertEqual(model.runtimeResolution(for: .menu).binding, model.runtimeBinding(for: .menu))
        XCTAssertTrue(events.first { $0.type == .keyDown }!.flags.contains(.maskControl))
        XCTAssertEqual(model.inputDiagnostics.lastOutput?.value, "⌃2")
        XCTAssertEqual(model.inputDiagnostics.lastOutput?.sceneName, "Editor")
        XCTAssertEqual(model.inputDiagnostics.lastOutput?.targetBundleID, "org.example.editor")
        XCTAssertTrue(model.lastAction.contains("⌃2"))
        model.perform(.init(action: .key, value: "3", modifiers: [.command]))
        XCTAssertTrue(model.lastAction.contains("⌘3"), "Tap dispatch must not overwrite the modifier-aware diagnostic")
        model.scenes[0].enabled = false
        XCTAssertEqual(model.runtimeResolution(for: .menu).source, .global)
    }

    func testPermissionFailureIsNotReportedAsSentAndTextIsNotLogged() {
        let domain = "Xvico.MappingDenied.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        var count = 0
        let model = AppModel(defaults: defaults, observeSystem: false,
            accessibilityCheck: { false }, eventPoster: { _ in count += 1 })
        defer { model.stopControl() }
        model.settings.autoSwitchScenes = false
        model.settings.globalBindings[RemoteKey.menu.rawValue] = .init(action: .key, value: "F2")
        model.handleRemotePress(.menu, pressed: true)
        model.handleRemotePress(.menu, pressed: false)
        XCTAssertEqual(count, 0)
        XCTAssertEqual(model.inputDiagnostics.lastOutput?.sent, false)
        XCTAssertEqual(KeyBinding(action: .text, value: "private text").diagnosticValue, "")
    }
}
