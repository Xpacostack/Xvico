import XCTest
import AppKit
@testable import XvicoApp

@MainActor
final class ConfigurationReloadTests: XCTestCase {
    private var domain: String!
    private var defaults: UserDefaults!
    private var directory: URL!
    private var models: [AppModel] = []
    private var events: [CGEvent] = []

    override func setUp() async throws {
        domain = "XvicoReload.\(UUID())"
        defaults = UserDefaults(suiteName: domain)!
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(domain)
    }
    override func tearDown() async throws {
        models.forEach { $0.stopControl() }; models = []
        defaults.removePersistentDomain(forName: domain)
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        events = []
    }
    private func makeModel() -> AppModel {
        let model = AppModel(defaults: defaults, observeSystem: false, accessibilityCheck: { true },
                             eventPoster: { [weak self] in self?.events.append($0) }, configurationDirectory: directory)
        models.append(model)
        return model
    }
    private var file: URL { directory.appendingPathComponent("config.json") }
    private func read() throws -> AppConfiguration { try AppConfiguration.decode(Data(contentsOf: file)) }
    private func externalEdit(_ change: (inout AppConfiguration) -> Void) throws {
        var value = try read(); change(&value)
        try value.encoded().write(to: file, options: .atomic)
    }

    func testFileWinsOverRollbackMirrorsAndRestartPreservesEverything() throws {
        let first = makeModel()
        first.settings.dragAcceleration = 1.9
        first.settings.globalBindings[RemoteKey.menu.rawValue] = .init(action: .key, value: "B")
        first.addScene(name: "Saved", bundleID: "test.saved")
        first.shortcuts.append(.init(name: "Hello", phrase: "hello", action: .text, value: "hello"))
        let expected = try read()
        defaults.set(try JSONEncoder().encode(XvicoSettings()), forKey: "xvibe.settings")
        let restarted = makeModel()
        XCTAssertEqual(restarted.settings, expected.settings)
        XCTAssertEqual(restarted.scenes, expected.scenes)
        XCTAssertEqual(restarted.shortcuts, expected.shortcuts)
        XCTAssertEqual(restarted.selectedSceneID, first.selectedSceneID)
    }

    func testExternalMappingReloadChangesActualRuntimeAndSceneRouting() throws {
        let model = makeModel()
        let scene = model.scenes[0]
        model.currentBundleID = scene.bundleID
        try externalEdit {
            $0.scenes[0].bindings[RemoteKey.menu.rawValue] = .init(action: .key, value: "B", modifiers: [.control])
        }
        model.refreshConfiguration()
        XCTAssertEqual(model.runtimeBinding(for: .menu).value, "B")
        XCTAssertEqual(model.runtimeResolution(for: .menu).source, .scene)
        model.handleRemotePress(.menu, pressed: true); model.handleRemotePress(.menu, pressed: false)
        let down = try XCTUnwrap(events.first { $0.type == .keyDown })
        XCTAssertEqual(down.getIntegerValueField(.keyboardEventKeycode), 11)
        XCTAssertTrue(down.flags.contains(.maskControl))
        XCTAssertEqual(model.configurationState, .synced)
    }

    func testReloadWaitsForCapturedKeyReleaseBeforeChangingBinding() throws {
        let model = makeModel()
        model.settings.autoSwitchScenes = false
        model.settings.ringToggleKey = ""
        model.settings.globalBindings[RemoteKey.menu.rawValue] = .init(action: .key, value: "A")
        model.handleRemotePress(.menu, pressed: true)
        try externalEdit { $0.settings.globalBindings[RemoteKey.menu.rawValue] = .init(action: .key, value: "B") }
        model.refreshConfiguration()
        XCTAssertEqual(model.configurationState, .waitingForRelease)
        XCTAssertEqual(model.runtimeBinding(for: .menu).value, "A")
        model.selectedSceneID = model.scenes.last?.id
        XCTAssertEqual(model.configurationState, .waitingForRelease, "Selecting an editor scene is not a conflicting behavior edit")
        model.handleRemotePress(.menu, pressed: false)
        XCTAssertEqual(events.filter { $0.type == .keyDown || $0.type == .keyUp }.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [0, 0])
        XCTAssertEqual(model.runtimeBinding(for: .menu).value, "B")
        XCTAssertEqual(model.configurationState, .synced)
    }

    func testReloadWaitsForBothMouseReleaseAndTouchRelease() throws {
        let model = makeModel()
        model.settings.autoSwitchScenes = false; model.settings.ringEnabled = false
        model.settings.globalBindings[RemoteKey.center.rawValue] = .init(action: .click, value: "")
        model.handleTouch(.init(x: 0.5, y: 0.5, touching: true, timestamp: 1))
        model.handleRemotePress(.center, pressed: true)
        try externalEdit { $0.settings.dragAcceleration = 2.2 }
        model.refreshConfiguration()
        XCTAssertEqual(model.configurationState, .waitingForRelease)
        XCTAssertEqual(model.settings.dragAcceleration, 1.6)
        model.handleRemotePress(.center, pressed: false)
        XCTAssertEqual(model.settings.dragAcceleration, 1.6)
        XCTAssertEqual(events.map(\.type), [.leftMouseDown, .leftMouseUp])
        model.handleTouch(.init(x: 0.5, y: 0.5, touching: false, timestamp: 1.1))
        XCTAssertEqual(model.settings.dragAcceleration, 2.2)
        XCTAssertEqual(model.configurationState, .synced)
    }

    func testDisconnectReleasesOwnedMouseAndKeyboardAndUnblocksReload() throws {
        let model = makeModel()
        model.settings.autoSwitchScenes = false
        model.settings.ringToggleKey = ""
        model.settings.globalBindings[RemoteKey.center.rawValue] = .init(action: .click, value: "")
        model.settings.globalBindings[RemoteKey.menu.rawValue] = .init(action: .key, value: "A", modifiers: [.command])
        model.handleTouch(.init(x: 0.5, y: 0.5, touching: true, timestamp: 1))
        model.handleRemotePress(.center, pressed: true)
        model.handleRemotePress(.menu, pressed: true)
        try externalEdit { $0.settings.dragAcceleration = 2.2 }
        model.refreshConfiguration()
        XCTAssertEqual(model.configurationState, .waitingForRelease)
        model.handleRemoteInputLoss()
        XCTAssertFalse(model.isHoldingRemoteButton)
        XCTAssertEqual(events.filter { $0.type == .leftMouseUp }.count, 1)
        XCTAssertEqual(events.filter { $0.type == .keyUp && $0.getIntegerValueField(.keyboardEventKeycode) == 0 }.count, 1)
        XCTAssertEqual(model.settings.dragAcceleration, 2.2)
        XCTAssertEqual(model.configurationState, .synced)
        let count = events.count
        model.handleRemoteInputLoss()
        model.handleRemotePress(.center, pressed: false)
        XCTAssertEqual(events.count, count, "Repeated loss/late releases must not send duplicate mouse-up events")
    }

    func testSpecialVolumeModeAlsoDefersUntilPhysicalRelease() throws {
        let model = makeModel()
        model.settings.volumeKeyMode = .scroll
        model.handleRemotePress(.volumeUp, pressed: true)
        try externalEdit { $0.settings.dragAcceleration = 2.1 }
        model.refreshConfiguration()
        XCTAssertEqual(model.configurationState, .waitingForRelease)
        model.handleRemotePress(.volumeUp, pressed: false)
        XCTAssertEqual(model.configurationState, .synced)
        XCTAssertEqual(model.settings.dragAcceleration, 2.1)
    }

    func testDelayedSingleTapCompletesBeforePendingConfigurationApplies() async throws {
        let model = makeModel()
        model.settings.autoSwitchScenes = false
        model.settings.ringToggleKey = ""
        model.settings.globalBindings[RemoteKey.voice.rawValue] = .init(action: .key, value: "A",
             doubleClickEnabled: true, doubleClickAction: .key, doubleClickValue: "B")
        model.handleRemotePress(.voice, pressed: true)
        model.handleRemotePress(.voice, pressed: false)
        try externalEdit { $0.settings.globalBindings[RemoteKey.voice.rawValue] = .init(action: .key, value: "C") }
        model.refreshConfiguration()
        XCTAssertEqual(model.configurationState, .waitingForRelease)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(events.filter { $0.type == .keyDown }.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [0])
        XCTAssertEqual(model.runtimeBinding(for: .voice).value, "C")
        XCTAssertEqual(model.configurationState, .synced)
    }

    func testConcurrentGUIEditKeepsExternalAndUnsavedVersionsUntilExplicitChoice() throws {
        let model = makeModel()
        try externalEdit { $0.settings.dragAcceleration = 2.2 }
        model.settings.pointerSensitivity = 1.8
        XCTAssertEqual(model.configurationState, .conflict)
        XCTAssertEqual(try read().settings.dragAcceleration, 2.2)
        let unsaved = try AppConfiguration.decode(Data(contentsOf: directory.appendingPathComponent("config.unsaved.json")))
        XCTAssertEqual(unsaved.settings.pointerSensitivity, 1.8)
        model.refreshConfiguration()
        XCTAssertEqual(model.settings.dragAcceleration, 1.6, "Conflict must not silently discard the local edit")
        model.useFileConfiguration()
        XCTAssertEqual(model.settings.dragAcceleration, 2.2)
        XCTAssertEqual(model.settings.pointerSensitivity, 1)
        XCTAssertEqual(model.configurationState, .synced)
    }

    func testExplicitGUIChoiceArchivesExternalBeforeReplacing() throws {
        let model = makeModel()
        try externalEdit { $0.settings.dragAcceleration = 2.2 }
        let external = try Data(contentsOf: file)
        model.settings.pointerSensitivity = 1.8
        model.saveCurrentConfiguration()
        XCTAssertEqual(try read().settings.pointerSensitivity, 1.8)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("config.external-backup.json")), external)
        XCTAssertEqual(model.configurationState, .synced)
    }

    func testUnsavedGUIEditRemainsRecoverableAfterRestartAndChoosingFile() throws {
        let model = makeModel()
        try externalEdit { $0.settings.dragAcceleration = 2.2 }
        model.settings.pointerSensitivity = 1.8
        XCTAssertTrue(model.hasRecoverableConfiguration)
        model.useFileConfiguration()
        XCTAssertTrue(model.hasRecoverableConfiguration)
        let restarted = makeModel()
        XCTAssertTrue(restarted.hasRecoverableConfiguration)
        XCTAssertEqual(restarted.settings.dragAcceleration, 2.2)
        let externalBytes = try Data(contentsOf: file)
        restarted.recoverUnsavedConfiguration()
        XCTAssertEqual(restarted.settings.pointerSensitivity, 1.8)
        XCTAssertEqual(restarted.settings.dragAcceleration, 1.6)
        XCTAssertFalse(restarted.hasRecoverableConfiguration)
        XCTAssertEqual(try read().settings, restarted.settings)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("config.external-backup.json")), externalBytes)
    }

    func testBadExternalEditKeepsRuntimeAndRepairAutomaticallyApplies() throws {
        let model = makeModel()
        let original = try read()
        let invalid = Data("broken json".utf8)
        try invalid.write(to: file, options: .atomic)
        model.refreshConfiguration()
        XCTAssertEqual(model.configurationState, .invalid)
        XCTAssertEqual(model.settings, original.settings)
        let restarted = makeModel()
        XCTAssertEqual(restarted.settings, original.settings)
        XCTAssertEqual(restarted.configurationState, .invalid)
        XCTAssertEqual(try Data(contentsOf: file), invalid)
        var fixed = original; fixed.settings.dragAcceleration = 2
        try fixed.encoded().write(to: file, options: .atomic)
        model.refreshConfiguration()
        XCTAssertEqual(model.settings.dragAcceleration, 2)
        XCTAssertEqual(model.configurationState, .synced)
    }

    func testIdlePollingDoesNotInvalidateUIAndVoiceConsentStaysOutsideDocument() throws {
        defaults.set(true, forKey: "xvico.voice.serviceConsent.v1")
        defaults.set("Fn", forKey: "xvibe.voice.inputMethodTriggerKey")
        let model = makeModel()
        var changes = 0
        let observer = model.objectWillChange.sink { changes += 1 }
        defer { observer.cancel() }
        for _ in 0..<20 { model.refreshConfiguration() }
        XCTAssertEqual(changes, 0)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        XCTAssertNil(json["serviceConsent"])
        try externalEdit { $0.settings.pointerSensitivity = 1.3 }
        model.refreshConfiguration()
        XCTAssertTrue(defaults.bool(forKey: "xvico.voice.serviceConsent.v1"))
        XCTAssertEqual(defaults.string(forKey: "xvibe.voice.inputMethodTriggerKey"), "Fn")
    }
}
