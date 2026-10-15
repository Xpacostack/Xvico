import AppKit
import AVFoundation
import XCTest
@testable import XvicoApp

@MainActor
private final class CaptureStub: RemoteVoiceCapturing {
    struct Session {
        let frame: (RemoteOpusFrame) -> Void
        let status: (String) -> Void
        let ready: () -> Void
        let error: (String) -> Void
    }
    var sessions: [Session] = []
    var stops = 0
    var duringStop: (() -> Void)?
    func start(usePersistentApproval: Bool, onFrame: @escaping (RemoteOpusFrame) -> Void,
               onStatus: @escaping (String) -> Void, onReady: @escaping () -> Void,
               onError: @escaping (String) -> Void) {
        sessions.append(.init(frame: onFrame, status: onStatus, ready: onReady, error: onError))
    }
    func stop() { stops += 1; duringStop?() }
}

@MainActor
private final class InputStub: RemoteInputMonitoring {
    var onUsage: ((Int, Int, Bool) -> Void)?
    var onStatus: ((String) -> Void)?
    var onTouch: ((RemoteTouchSample) -> Void)?
    var onTouchStatus: ((String) -> Void)?
    var onInterception: ((Bool) -> Void)?
    var onDiagnostic: ((String) -> Void)?
    var onInterceptionDetail: ((String?) -> Void)?
    var onInputLost: (() -> Void)?
    var starts: [Bool] = []
    var stops = 0
    func start(interceptButtons: Bool) { starts.append(interceptButtons) }
    func stop() { stops += 1 }
    func setButtonInterception(_ enabled: Bool) {}
    func reidentifyTouch() {}
}

@MainActor
final class VoiceLifecycleTests: XCTestCase {
    private var domain: String!
    private var defaults: UserDefaults!
    private var capture: CaptureStub!
    private var input: InputStub!
    private var remote: RemoteVoiceService!
    private var voice: VoiceService!
    private var model: AppModel!
    private var events: [CGEvent] = []
    private var commands: [Bool] = []
    private var commandResult: Int32 = 0
    private var deliveredAudio = 0
    // Existing synthetic Opus test tone. No microphone or recognizer is opened.
    private var frame: RemoteOpusFrame {
        let hex = "b87b5af3f6a1db150c1207826c0faff5d2103fce0af468da6fd16e3bf113de73f0443360c7f8810314c09fa5e98aaaefdca075aea5e14f2ecfb0a1"
        let data = stride(from: 0, to: hex.count, by: 2).reduce(into: Data()) { data, offset in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            data.append(UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!)
        }
        return .init(session: 1, sequence: 0, packet: data)
    }

    override func setUp() async throws {
        domain = "XvicoVoiceLifecycle.\(UUID())"
        defaults = UserDefaults(suiteName: domain)!
        capture = CaptureStub(); input = InputStub()
        remote = RemoteVoiceService(defaults: defaults,
            microphoneControl: { [weak self] held in
                guard let self else { return 1 }
                self.commands.append(held); return self.commandResult
            }, capture: capture)
        voice = VoiceService(defaults: defaults)
        voice.inputSource = .siriRemote; voice.recognitionMode = .inputMethod
        model = AppModel(defaults: defaults, observeSystem: false, accessibilityCheck: { true },
            eventPoster: { [weak self] in self?.events.append($0) }, inputMonitor: input, remoteVoice: remote)
        model.settings.autoSwitchScenes = false; model.settings.ringToggleKey = ""
        model.controlStopped = { [weak voice] in voice?.stop() }
        model.siriVoiceHandler = { [weak voice, weak model] down in
            guard let voice, let model else { return false }
            return voice.handleRemotePush(down, model: model)
        }
        model.mappedKeyboardHandler = { [weak voice, weak model] binding, down in
            guard let voice, let model else { return }
            voice.handleMappedKeyboard(binding, down: down, model: model)
        }
    }

    override func tearDown() async throws {
        capture.duringStop = nil
        model.stopControl(); voice.stop(); commandResult = 0; remote.stop()
        model = nil; voice = nil; remote = nil; capture = nil; input = nil
        defaults.removePersistentDomain(forName: domain)
        events = []; commands = []; commandResult = 0; deliveredAudio = 0
    }

    private func startCapture() -> CaptureStub.Session {
        remote.startCapture(audio: { [weak self] _ in self?.deliveredAudio += 1 }, failure: { _ in })
        let session = capture.sessions.last!
        session.ready()
        return session
    }

    func testFailedEnableRetriesEnableOnNextTriggerWithoutExtraClick() {
        commandResult = 1
        remote.inputMethodTrigger()
        XCTAssertFalse(remote.microphoneHeld)
        XCTAssertNotNil(remote.microphoneControlError)
        commandResult = 0
        remote.inputMethodTrigger()
        XCTAssertTrue(remote.microphoneHeld)
        XCTAssertNil(remote.microphoneControlError)
        remote.inputMethodTrigger()
        XCTAssertFalse(remote.microphoneHeld)
        XCTAssertEqual(commands, [true, true, false])
    }

    func testFailedDisableRetriesDisableAndNextTriggerStartsAgain() {
        remote.inputMethodTrigger()
        commandResult = 1
        remote.inputMethodTrigger()
        XCTAssertTrue(remote.microphoneHeld)
        commandResult = 0
        remote.inputMethodTrigger()
        XCTAssertFalse(remote.microphoneHeld)
        remote.inputMethodTrigger()
        XCTAssertTrue(remote.microphoneHeld)
        XCTAssertEqual(commands, [true, false, false, true])
    }

    func testOneHundredUtterancesResetSequenceWithoutRestartingCapture() {
        let session = startCapture()
        for count in 1...100 {
            remote.inputMethodTrigger()
            XCTAssertTrue(remote.microphoneHeld)
            session.frame(frame)
            XCTAssertEqual(remote.decodedFrames, count)
            remote.inputMethodTrigger()
            XCTAssertFalse(remote.microphoneHeld)
            XCTAssertNil(remote.lastAudioAt)
        }
        XCTAssertEqual(capture.sessions.count, 1)
        XCTAssertEqual(deliveredAudio, 100)
        XCTAssertEqual(commands.count, 200)
    }

    func testOldSessionFramesStatusReadyAndFailureCannotAffectNewSession() {
        let old = startCapture()
        let current = startCapture()
        current.status("current")
        old.ready(); old.status("obsolete"); old.frame(frame); old.error("obsolete failure")
        XCTAssertTrue(remote.isSubscribed)
        XCTAssertEqual(remote.status, "current")
        XCTAssertNil(remote.errorMessage)
        XCTAssertEqual(remote.notifications, 0)
        current.frame(frame)
        XCTAssertEqual(deliveredAudio, 1)
        XCTAssertEqual(remote.decodedFrames, 1)
    }

    func testStopInvalidatesCallbacksBeforeTeardownEmitsFailure() {
        let session = startCapture()
        capture.duringStop = { session.error("teardown failure"); session.ready(); session.frame(self.frame) }
        remote.stop()
        XCTAssertFalse(remote.isSubscribed)
        XCTAssertFalse(remote.isConnecting)
        XCTAssertNil(remote.errorMessage)
        XCTAssertEqual(deliveredAudio, 0)
    }

    func testStopInsideAudioHandlerCannotResurrectChannel() {
        remote.startCapture(audio: { [weak remote] _ in remote?.stop() }, failure: { _ in })
        let session = capture.sessions.last!
        session.ready(); session.frame(frame)
        XCTAssertFalse(remote.isSubscribed)
        XCTAssertNil(remote.lastAudioAt)
    }

    func testFailureStopsMicrophoneAndAllowsExplicitRestart() {
        let session = startCapture()
        remote.inputMethodTrigger()
        session.error("test backend ended")
        XCTAssertFalse(remote.microphoneHeld)
        XCTAssertFalse(remote.isSubscribed)
        XCTAssertEqual(remote.errorMessage, "test backend ended")
        _ = startCapture()
        XCTAssertTrue(remote.isSubscribed)
        XCTAssertNil(remote.errorMessage)
        remote.inputMethodTrigger()
        XCTAssertEqual(commands, [true, false, true])
    }

    func testImmediateStopCancelsQueuedChannelStartup() async {
        voice.startRemoteChannel(model: model)
        voice.stop()
        await Task.yield(); await Task.yield()
        XCTAssertTrue(capture.sessions.isEmpty)
        XCTAssertFalse(remote.isSubscribed)
    }

    func testRapidStartsOnlyLaunchLatestRequest() async throws {
        for _ in 0..<10 { voice.startRemoteChannel(model: model) }
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(capture.sessions.count, 1)
        XCTAssertTrue(remote.isConnecting)
    }

    func testMappedFnTogglesOnlyOnRealKeyDownAndClosesOnDisconnect() {
        _ = startCapture()
        var binding = KeyBinding(action: .key, value: "Fn"); binding.siriMode = "长按模式"
        model.settings.globalBindings[RemoteKey.voice.rawValue] = binding
        model.handleRemotePress(.voice, pressed: true)
        model.handleRemotePress(.voice, pressed: true)
        model.handleRemotePress(.voice, pressed: false)
        XCTAssertEqual(commands, [true])
        XCTAssertTrue(remote.microphoneHeld)
        input.onInputLost?()
        XCTAssertEqual(commands, [true, false])
        XCTAssertFalse(remote.isSubscribed)
        XCTAssertFalse(remote.microphoneHeld)
        XCTAssertNotNil(remote.errorMessage)
        input.onInputLost?()
        XCTAssertNotNil(remote.errorMessage, "Duplicate loss must retain restart guidance")
        model.handleRemotePress(.voice, pressed: false)
        XCTAssertEqual(commands, [true, false])
    }

    func testSleepReleasesMouseAndKeyboardClosesAudioAndWakeOnlyRestartsHID() {
        defaults.set(true, forKey: "xvico.voice.serviceConsent.v1")
        _ = startCapture(); remote.inputMethodTrigger()
        model.settings.globalBindings[RemoteKey.menu.rawValue] = .init(action: .key, value: "A", modifiers: [.command])
        model.settings.globalBindings[RemoteKey.center.rawValue] = .init(action: .click, value: "")
        model.handleRemotePress(.menu, pressed: true); model.handleRemotePress(.center, pressed: true)
        let settings = model.settings
        model.handleSystemSleep(); model.handleSystemSleep()
        XCTAssertTrue(model.systemSleeping)
        XCTAssertTrue(model.running)
        XCTAssertFalse(model.isHoldingRemoteButton)
        XCTAssertFalse(remote.isSubscribed)
        XCTAssertFalse(remote.microphoneHeld)
        XCTAssertNotNil(remote.errorMessage)
        XCTAssertEqual(input.stops, 1)
        XCTAssertEqual(events.filter { $0.type == .keyUp }.count, 1)
        XCTAssertEqual(events.filter { $0.type == .leftMouseUp }.count, 1)
        let count = events.count
        model.handleRemotePress(.menu, pressed: true)
        model.handleTouch(.init(x: 0.9, y: 0.5, touching: true))
        XCTAssertEqual(events.count, count)
        model.handleSystemWake(); model.handleSystemWake()
        XCTAssertEqual(input.starts, [settings.interceptRemoteButtons])
        XCTAssertFalse(model.systemSleeping)
        XCTAssertEqual(capture.sessions.count, 1, "Wake must never restart recording")
        XCTAssertTrue(defaults.bool(forKey: "xvico.voice.serviceConsent.v1"))
        XCTAssertEqual(model.settings, settings)
        model.handleRemotePress(.menu, pressed: false)
        XCTAssertEqual(events.count, count, "Late releases do not target the new stream")
        model.handleRemotePress(.menu, pressed: true); model.handleRemotePress(.menu, pressed: false)
        XCTAssertEqual(events.filter { $0.type == .keyUp }.count, 2)
    }

    func testStopWhileAsleepDoesNotResumeControlAtWake() {
        model.handleSystemSleep(); model.stopControl(); model.handleSystemWake()
        XCTAssertFalse(model.running)
        XCTAssertTrue(input.starts.isEmpty)
        XCTAssertTrue(capture.sessions.isEmpty)
    }

    func testSleepCancelsQueuedCaptureAndExplicitStartIsRequiredAfterWake() async throws {
        voice.startRemoteChannel(model: model)
        model.handleSystemSleep(); model.handleSystemWake()
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertTrue(capture.sessions.isEmpty)
        voice.startRemoteChannel(model: model)
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(capture.sessions.count, 1)
    }

    func testVoicePreferencesSurviveServiceRestartWithoutStartingCapture() {
        voice.inputMethodTriggerKey = "F6"
        let restored = VoiceService(defaults: defaults)
        XCTAssertEqual(restored.inputSource, .siriRemote)
        XCTAssertEqual(restored.recognitionMode, .inputMethod)
        XCTAssertEqual(restored.inputMethodTriggerKey, "F6")
        XCTAssertFalse(restored.isStarting)
        XCTAssertFalse(restored.isListening)
        XCTAssertTrue(capture.sessions.isEmpty)
    }

    func testInterruptionReasonSurvivesRecognitionCallingStopAgain() {
        _ = startCapture()
        remote.interrupt("test interruption", cancellingRecognition: { self.remote.stop() })
        XCTAssertEqual(remote.errorMessage, "test interruption")
        XCTAssertFalse(remote.isSubscribed)
    }
}

final class RemoteCaptureHealthTests: XCTestCase {
    private let path = "/private/var/tmp/xvibe-voice.test/remote.pklg"
    func testStartupWaitsForValidReadyPathThenStartsReaderOnlyOnce() {
        var health = RemoteCaptureHealth(startedAt: 10)
        XCTAssertEqual(health.poll(now: 10.2, backendEnded: false, capturePath: nil), .waiting)
        XCTAssertEqual(health.poll(now: 10.3, backendEnded: false, capturePath: "/tmp/invalid"), .waiting)
        XCTAssertEqual(health.poll(now: 10.4, backendEnded: false, capturePath: path), .startReader(path))
        XCTAssertEqual(health.poll(now: 11, backendEnded: false, capturePath: path), .running)
        XCTAssertEqual(health.poll(now: 4000, backendEnded: false, capturePath: nil), .running)
    }
    func testBackendEndIsDetectedAfterReadyEvenIfReadyFileRemains() {
        var health = RemoteCaptureHealth(startedAt: 0)
        _ = health.poll(now: 1, backendEnded: false, capturePath: path)
        XCTAssertEqual(health.poll(now: 2, backendEnded: true, capturePath: path), .ended)
    }
    func testBackendEndTakesPriorityDuringStartup() {
        var health = RemoteCaptureHealth(startedAt: 0)
        XCTAssertEqual(health.poll(now: 1, backendEnded: true, capturePath: path), .ended)
    }
    func testMissingReadyTimesOutAtMonotonicDeadline() {
        var health = RemoteCaptureHealth(startedAt: 10)
        XCTAssertEqual(health.poll(now: 159.9, backendEnded: false, capturePath: nil), .waiting)
        XCTAssertEqual(health.poll(now: 160, backendEnded: false, capturePath: nil), .timedOut)
    }
}
