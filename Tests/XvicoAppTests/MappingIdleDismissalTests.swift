import XCTest
import Combine
@testable import XvicoApp

@MainActor
final class MappingIdleDismissalTests: XCTestCase {
    func testIdleEditorClosesOnceAndIgnoresLaterActivity() async throws {
        let timer = MappingIdleDismissal(timeout: 0.08)
        defer { timer.stop() }
        let closed = expectation(description: "Idle editor closes")
        var dismissals = 0
        timer.begin { dismissals += 1; closed.fulfill() }
        await fulfillment(of: [closed], timeout: 1)
        timer.recordActivity()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(dismissals, 1, "A dismissed editor must not keep a monitor or fire again")
    }

    func testOperationRestartsFullIdleInterval() async throws {
        let timer = MappingIdleDismissal(timeout: 0.24)
        defer { timer.stop() }
        let closed = expectation(description: "Closes after the latest operation")
        var dismissals = 0
        timer.begin { dismissals += 1; closed.fulfill() }
        try await Task.sleep(nanoseconds: 130_000_000)
        timer.recordActivity()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(dismissals, 0, "The original deadline must not close an editor being used")
        await fulfillment(of: [closed], timeout: 1)
    }

    func testClosingAndReopeningDiscardsPreviousDeadline() async throws {
        let timer = MappingIdleDismissal(timeout: 0.12)
        defer { timer.stop() }
        timer.begin { XCTFail("A closed editor fired its old timeout") }
        try await Task.sleep(nanoseconds: 50_000_000)
        timer.stop()
        try await Task.sleep(nanoseconds: 150_000_000)
        let closed = expectation(description: "Reopened editor has its own timeout")
        timer.begin { closed.fulfill() }
        await fulfillment(of: [closed], timeout: 1)
    }

    func testRemotePressAndTouchProtectActiveEditorIncludingConsumedSiri() async throws {
        let domain = "XvicoTests.MappingIdle.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        let model = AppModel(defaults: defaults, observeSystem: false,
                             accessibilityCheck: { false }, eventPoster: { _ in })
        let timer = MappingIdleDismissal(timeout: 0.12)
        defer { timer.stop(); model.stopControl(); defaults.removePersistentDomain(forName: domain) }
        let closed = expectation(description: "Closes after remote operation ends")
        var dismissals = 0
        var operations = 0
        let monitor = model.mappingInteraction.sink { _ in operations += 1; timer.recordActivity() }
        defer { monitor.cancel() }
        model.siriVoiceHandler = { _ in true }
        timer.begin(isInteracting: { model.isHoldingRemoteButton }) { dismissals += 1; closed.fulfill() }
        model.handleRemotePress(.voice, pressed: true)
        try await Task.sleep(nanoseconds: 180_000_000)
        XCTAssertEqual(dismissals, 0, "Holding Siri must not close the active editor")
        model.handleRemotePress(.voice, pressed: false)
        model.handleTouch(RemoteTouchSample(x: 0.5, y: 0.5, touching: true, timestamp: 1))
        XCTAssertEqual(operations, 3, "Press, release and touch must all count even when Siri is consumed")
        await fulfillment(of: [closed], timeout: 1)
        XCTAssertEqual(dismissals, 1)
    }
}
