import XCTest
import ApplicationServices
@testable import XvicoApp

final class VoiceDeliveryTests: XCTestCase {
    func testFocusGuardRejectsAppFieldCaretAndContentChanges() {
        let original = VoiceFocusEvidence(pid: 100, elementIdentity: 1, contentHash: 7,
            selectionLocation: 3, selectionLength: 2, secure: false, editable: true)
        XCTAssertNil(VoiceInsertionPolicy.validate(original, current: original))
        var changed = original; changed.pid = 200
        XCTAssertEqual(VoiceInsertionPolicy.validate(original, current: changed), .focusChanged)
        changed = original; changed.elementIdentity = 2
        XCTAssertEqual(VoiceInsertionPolicy.validate(original, current: changed), .focusChanged)
        changed = original; changed.selectionLocation = 4
        XCTAssertEqual(VoiceInsertionPolicy.validate(original, current: changed), .focusChanged)
        changed = original; changed.contentHash = 8
        XCTAssertEqual(VoiceInsertionPolicy.validate(original, current: changed), .focusChanged)
        changed = original; changed.secure = true
        XCTAssertEqual(VoiceInsertionPolicy.validate(original, current: changed), .secureField)
        changed = original; changed.editable = false
        XCTAssertEqual(VoiceInsertionPolicy.validate(original, current: changed), .unavailable)
        XCTAssertEqual(VoiceInsertionPolicy.validate(original, current: nil), .unavailable)
    }
    func testLatencyMeasuresFirstOnlyAndDoesNotInventUnobservableStages() {
        var metrics = VoiceLatencyMetrics()
        metrics.begin(at: 10)
        metrics.ready(at: 10.2); metrics.audio(at: 10.3); metrics.audio(at: 10.9)
        metrics.text(at: 10.6); metrics.text(at: 11)
        metrics.release(at: 12); metrics.final(at: 12.4)
        XCTAssertEqual(metrics.readyMilliseconds!, 200, accuracy: 0.001)
        XCTAssertEqual(metrics.firstAudioMilliseconds!, 300, accuracy: 0.001)
        XCTAssertEqual(metrics.firstTextMilliseconds!, 600, accuracy: 0.001)
        XCTAssertEqual(metrics.finalMilliseconds!, 400, accuracy: 0.001)
        XCTAssertNil(metrics.deliveryMilliseconds)
        metrics.begin(at: 20)
        XCTAssertNil(metrics.firstAudioMilliseconds); XCTAssertNil(metrics.firstTextMilliseconds)
        metrics.final(at: 21)
        XCTAssertNil(metrics.finalMilliseconds, "A missing release has no measured release-to-final time")
        metrics.ready(at: 19)
        XCTAssertNil(metrics.readyMilliseconds)
    }
    func testAudioCallbackGateSchedulesOnlyOneFirstFrameUpdate() {
        let gate = VoiceFirstFrameGate()
        XCTAssertTrue(gate.take())
        for _ in 0..<1000 { XCTAssertFalse(gate.take()) }
    }

    @MainActor
    func testRejectedDeliveryDoesNotFallBackToGlobalKeyboardOrClipboard() async {
        let domain = "Xvico.VoiceDelivery.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let delivery = RejectingDelivery()
        var events = 0
        let model = AppModel(defaults: defaults, observeSystem: false, eventPoster: { _ in events += 1 },
                             voiceTextDelivery: delivery)
        defer { model.stopControl() }
        model.currentBundleID = "org.example.editor"
        let target = await model.captureVoiceTarget()
        XCTAssertEqual(delivery.capturedBundleID, "org.example.editor")
        let result = await model.deliverVoiceText("test utterance", to: target)
        XCTAssertEqual(result, .focusChanged)
        XCTAssertEqual(model.toast, VoiceDeliveryResult.focusChanged.message)
        XCTAssertEqual(events, 0, "A rejected native write must not send text to the new focus")
    }
}

@MainActor
private final class RejectingDelivery: VoiceTextDelivering {
    var capturedBundleID: String?
    func capture(expectedBundleID: String) async -> VoiceTextTarget? {
        capturedBundleID = expectedBundleID
        return nil
    }
    func insert(_ text: String, into target: VoiceTextTarget?) async -> VoiceDeliveryResult { .focusChanged }
}
