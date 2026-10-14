import XCTest
@testable import XvicoApp

final class VoicePresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1000)

    func testOldAudioNeverKeepsIdleOrNewUtteranceInCapturingState() {
        var snapshot = VoiceActivitySnapshot(mode: .inputMethod, channelReady: true, lastAudioAt: now)
        XCTAssertEqual(snapshot.presentation(at: now).stage, .ready)
        snapshot.microphoneRequested = true
        snapshot.lastAudioAt = nil
        XCTAssertEqual(snapshot.presentation(at: now).stage, .awaitingAudio)
        snapshot.lastAudioAt = now
        XCTAssertEqual(snapshot.presentation(at: now).stage, .capturing)
        // A stopped stream must lose its collecting indicator even with the
        // microphone command still active and no new errors from the transport.
        XCTAssertEqual(snapshot.presentation(at: now.addingTimeInterval(2)).stage, .awaitingAudio)
        snapshot.microphoneRequested = false
        XCTAssertEqual(snapshot.presentation(at: now).stage, .ready)
        snapshot.channelReady = false
        XCTAssertEqual(snapshot.presentation(at: now).stage, .idle)
    }

    func testInputMethodCannotClaimXvicoIsRecognizingOrShowOldSpeechFailure() {
        var snapshot = VoiceActivitySnapshot(mode: .inputMethod, channelReady: true,
            microphoneRequested: true, lastAudioAt: now, recognitionListening: true,
            finalizing: true, recognitionStatus: "识别完成", recognitionError: "old speech failure")
        XCTAssertEqual(snapshot.presentation(at: now).stage, .capturing)
        XCTAssertTrue(snapshot.presentation(at: now).detail.contains("输入法"))
        snapshot.channelReady = false
        snapshot.microphoneRequested = false
        snapshot.recognitionStatus = "未检测到可识别的语音"
        XCTAssertEqual(snapshot.presentation(at: now).stage, .idle)
        XCTAssertFalse(snapshot.presentation(at: now).detail.contains("未检测到"))
        snapshot.recognitionStatus = "识别未返回最终文字"
        XCTAssertFalse(snapshot.presentation(at: now).detail.contains("识别未返回"))
    }

    func testRecognitionFinalizationAndNextUtteranceUseCurrentSession() {
        var snapshot = VoiceActivitySnapshot(channelReady: true, microphoneRequested: true,
            lastAudioAt: now, recognitionListening: true)
        XCTAssertEqual(snapshot.presentation(at: now).stage, .recognizing)
        snapshot.microphoneRequested = false
        snapshot.recognitionListening = false
        snapshot.finalizing = true
        XCTAssertEqual(snapshot.presentation(at: now).stage, .finalizing)
        snapshot.finalizing = false
        snapshot.recognitionStatus = "识别完成"
        XCTAssertEqual(snapshot.presentation(at: now).stage, .completed)
        snapshot.microphoneRequested = true
        snapshot.lastAudioAt = nil
        XCTAssertEqual(snapshot.presentation(at: now).stage, .awaitingAudio)
    }

    func testFailuresAreVisibleAndMacModeIgnoresUnrelatedRemoteFailures() {
        var snapshot = VoiceActivitySnapshot(channelReady: true, microphoneRequested: true,
            lastAudioAt: now, microphoneError: "microphone stop failed")
        XCTAssertEqual(snapshot.presentation(at: now).stage, .needsAttention)
        XCTAssertEqual(snapshot.presentation(at: now).detail, "microphone stop failed")
        snapshot.source = .mac
        snapshot.mode = .inputMethod
        XCTAssertEqual(snapshot.presentation(at: now).stage, .ready)
        snapshot.mode = .local
        snapshot.recognitionError = "recognizer unavailable"
        XCTAssertEqual(snapshot.presentation(at: now).stage, .needsAttention)
        XCTAssertEqual(snapshot.presentation(at: now).detail, "recognizer unavailable")
    }

    @MainActor func testMicrophoneCommandsPublishStateAndRetainFailedStopForRetry() {
        var commands: [Bool] = []
        var result: Int32 = 0
        let remote = RemoteVoiceService(microphoneControl: { commands.append($0); return result })
        remote.setMicrophoneHeld(true)
        XCTAssertTrue(remote.microphoneHeld)
        XCTAssertNil(remote.lastAudioAt)
        result = 1
        remote.setMicrophoneHeld(false)
        XCTAssertTrue(remote.microphoneHeld)
        XCTAssertNotNil(remote.microphoneControlError)
        var snapshot = VoiceActivitySnapshot(channelReady: true, microphoneRequested: remote.microphoneHeld,
            microphoneError: remote.microphoneControlError)
        XCTAssertEqual(snapshot.presentation(at: now).stage, .needsAttention)
        result = 0
        remote.stop()
        XCTAssertFalse(remote.microphoneHeld)
        XCTAssertNil(remote.microphoneControlError)
        XCTAssertNil(remote.lastAudioAt)
        snapshot.channelReady = false
        snapshot.microphoneRequested = remote.microphoneHeld
        snapshot.microphoneError = remote.microphoneControlError
        XCTAssertEqual(snapshot.presentation(at: now).stage, .idle)
        XCTAssertEqual(commands, [true, false, false])
    }
}
