import XCTest
import AppKit
@testable import XvicoApp

@MainActor
final class VoiceRoutingTests: XCTestCase {
    func testVoiceHoldConsumesOnlySiriAndDisablingReturnsToStoredMapping() {
        let domain = "XvicoVoiceRouting.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        var events: [CGEvent] = []
        var holds: [Bool] = []
        let model = AppModel(defaults: defaults, observeSystem: false, accessibilityCheck: { true }, eventPoster: { events.append($0) })
        defer { model.stopControl() }
        model.settings.autoSwitchScenes = false
        model.settings.globalBindings[RemoteKey.voice.rawValue] = .init(action: .key, value: "F6")
        model.settings.globalBindings[RemoteKey.menu.rawValue] = .init(action: .key, value: "F1")
        model.siriVoiceHandler = { holds.append($0); return true }
        model.handleHIDUsage(page: 12, usage: 4, pressed: true)
        model.handleHIDUsage(page: 12, usage: 4, pressed: true)
        model.handleHIDUsage(page: 12, usage: 4, pressed: false)
        XCTAssertEqual(holds, [true, false]); XCTAssertTrue(events.isEmpty)
        model.handleHIDUsage(page: 1, usage: 134, pressed: true)
        model.handleHIDUsage(page: 1, usage: 134, pressed: false)
        XCTAssertEqual(events.map(\.type), [.keyDown, .keyUp])
        events = []
        model.siriVoiceHandler = { _ in false }
        model.handleHIDUsage(page: 12, usage: 4, pressed: true)
        model.handleHIDUsage(page: 12, usage: 4, pressed: false)
        XCTAssertEqual(events.map(\.type), [.keyDown, .keyUp])
        XCTAssertEqual(events[0].getIntegerValueField(.keyboardEventKeycode), 97)
    }
    func testStoppingControlCancelsVoiceWorkflowAndLateReleaseDoesNotExecuteKey() {
        let domain = "XvicoVoiceStop.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        var stopped = 0
        var events: [CGEvent] = []
        let model = AppModel(defaults: defaults, observeSystem: false, accessibilityCheck: { true }, eventPoster: { events.append($0) })
        model.siriVoiceHandler = { _ in true }
        model.controlStopped = { stopped += 1 }
        model.handleRemotePress(.voice, pressed: true)
        model.stopControl()
        model.handleRemotePress(.voice, pressed: false)
        XCTAssertEqual(stopped, 1); XCTAssertTrue(events.isEmpty)
    }
    func testMacInputDoesNotConsumeSiriWhenRemotePushPreferenceIsEnabled() {
        let domain = "XvicoMacVoiceRouting.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let model = AppModel(defaults: defaults, observeSystem: false, eventPoster: { _ in })
        defer { model.stopControl() }
        let sourceKey = "xvibe.voice.inputSource", pushKey = "xvibe.voice.pushToTalk"
        let source = UserDefaults.standard.object(forKey: sourceKey)
        let push = UserDefaults.standard.object(forKey: pushKey)
        defer {
            UserDefaults.standard.set(source, forKey: sourceKey)
            UserDefaults.standard.set(push, forKey: pushKey)
        }
        let voice = VoiceService()
        voice.inputSource = .mac; voice.remotePushToTalk = true
        XCTAssertFalse(voice.handleRemotePush(true, model: model))
        XCTAssertFalse(voice.handleRemotePush(false, model: model))
        XCTAssertFalse(voice.isStarting)
    }
    func testNoSpeechIsNotConfusedWithPermissionOrServiceFailure() {
        XCTAssertTrue(VoiceService.isNoSpeech(NSError(domain: "kAFAssistantErrorDomain", code: 1110)))
        XCTAssertTrue(VoiceService.isNoSpeech(NSError(domain: "Speech", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "No speech detected"])))
        XCTAssertFalse(VoiceService.isNoSpeech(NSError(domain: "Speech", code: 1110,
            userInfo: [NSLocalizedDescriptionKey: "Permission denied"])))
        XCTAssertFalse(VoiceService.isNoSpeech(NSError(domain: "kAFAssistantErrorDomain", code: 1101)))
    }
    func testUnconsumedSiriGetsPairedReleaseAndReleasesCapturedMappingAfterAppSwitch() {
        let domain = "XvicoVoicePassthrough.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        var events: [CGEvent] = []; var holds: [Bool] = []
        let model = AppModel(defaults: defaults, observeSystem: false,
            accessibilityCheck: { true }, eventPoster: { events.append($0) })
        defer { model.stopControl() }
        model.settings.globalBindings[RemoteKey.voice.rawValue] = .init(action: .key, value: "F6")
        model.siriVoiceHandler = { holds.append($0); return false }
        model.handleRemotePress(.voice, pressed: true)
        model.currentBundleID = "org.example.changed"
        model.settings.globalBindings[RemoteKey.voice.rawValue] = .init(action: .key, value: "F7")
        model.handleRemotePress(.voice, pressed: false)
        XCTAssertEqual(holds, [true, false])
        XCTAssertEqual(events.map(\.type), [.keyDown, .keyUp])
        XCTAssertEqual(events.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [97, 97])
    }
    func testInputMethodModeDoesNotStartLocalRecognitionOrConsumeConfiguredShortcut() {
        let domain = "XvicoInputMethod.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let keys = ["xvibe.voice.inputSource", "xvibe.voice.pushToTalk", "xvibe.voice.recognitionMode"]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { UserDefaults.standard.set(value, forKey: key) } }
        var events: [CGEvent] = []
        let model = AppModel(defaults: defaults, observeSystem: false,
            accessibilityCheck: { true }, eventPoster: { events.append($0) })
        defer { model.stopControl() }
        let voice = VoiceService()
        voice.inputSource = .siriRemote; voice.recognitionMode = .inputMethod; voice.remotePushToTalk = true
        model.settings.autoSwitchScenes = false
        var binding = KeyBinding(action: .key, value: "Fn")
        binding.siriMode = "长按模式"
        model.settings.globalBindings[RemoteKey.voice.rawValue] = binding
        model.siriVoiceHandler = { voice.handleRemotePush($0, model: model) }
        for _ in 0..<3 {
            model.handleRemotePress(.voice, pressed: true)
            model.handleRemotePress(.voice, pressed: false)
        }
        XCTAssertFalse(voice.isStarting); XCTAssertFalse(voice.isListening); XCTAssertFalse(voice.isFinalizing)
        XCTAssertTrue(voice.transcript.isEmpty)
        XCTAssertEqual(events.count, 6)
        XCTAssertTrue(events.allSatisfy { $0.type == .flagsChanged })
        XCTAssertEqual(voice.readiness, "由输入法识别")
    }
    func testMicrophoneGateOnlyTogglesOnActualTriggerAndResetClosesIt() {
        var commands: [Bool] = []
        let remote = RemoteVoiceService(microphoneControl: { commands.append($0); return 0 })
        XCTAssertFalse(remote.microphoneHeld)
        remote.inputMethodTrigger(); XCTAssertTrue(remote.microphoneHeld)
        remote.inputMethodTrigger(); XCTAssertFalse(remote.microphoneHeld)
        remote.inputMethodTrigger(); XCTAssertTrue(remote.microphoneHeld)
        remote.stop(); XCTAssertFalse(remote.microphoneHeld)
        XCTAssertEqual(commands, [true, false, true, false])
    }
    func testMappedKeyboardObserverSeesActualConfiguredSingleAndDoubleActions() async throws {
        let domain = "XvicoMappedOutput.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let model = AppModel(defaults: defaults, observeSystem: false,
            accessibilityCheck: { true }, eventPoster: { _ in })
        defer { model.stopControl() }
        var outputs: [(String, Bool)] = []
        model.mappedKeyboardHandler = { outputs.append(($0.value, $1)) }
        model.settings.autoSwitchScenes = false
        var binding = KeyBinding(action: .key, value: "Fn")
        binding.siriMode = "分段模式"; binding.doubleClickEnabled = true
        binding.doubleClickValue = "F6"
        model.settings.globalBindings[RemoteKey.voice.rawValue] = binding
        model.handleRemotePress(.voice, pressed: true); model.handleRemotePress(.voice, pressed: false)
        model.handleRemotePress(.voice, pressed: true); model.handleRemotePress(.voice, pressed: false)
        XCTAssertEqual(outputs.map { $0.0 }, ["F6", "F6"])
        XCTAssertEqual(outputs.map { $0.1 }, [true, false])
        outputs.removeAll()
        binding.siriMode = "长按模式"
        model.settings.globalBindings[RemoteKey.voice.rawValue] = binding
        model.handleRemotePress(.voice, pressed: true); model.handleRemotePress(.voice, pressed: false)
        XCTAssertEqual(outputs.map { $0.0 }, ["Fn", "Fn"])
        XCTAssertEqual(outputs.map { $0.1 }, [true, false])
    }
}
