import XCTest
import Combine
@testable import XvicoApp

@MainActor
private final class IdleTestClock {
    var now = 0.0
    var scheduledCount = 0
    private var jobs: [UUID: (Double, () -> Void)] = [:]
    func schedule(_ delay: TimeInterval, _ fire: @escaping () -> Void) -> () -> Void {
        scheduledCount += 1
        let id = UUID(); jobs[id] = (now + delay, fire)
        return { [weak self] in self?.jobs.removeValue(forKey: id) }
    }
    func advance(_ interval: Double) {
        now += interval
        let due = jobs.filter { $0.value.0 <= now }
        for (id, job) in due {
            jobs.removeValue(forKey: id); job.1()
        }
    }
    func timer(_ timeout: Double = 10) -> MappingIdleDismissal {
        MappingIdleDismissal(timeout: timeout, now: { self.now }, schedule: schedule)
    }
}

@MainActor
final class MappingIdleDismissalTests: XCTestCase {
    func testIdleEditorClosesOnceAndIgnoresLaterActivity() {
        let clock = IdleTestClock(); let timer = clock.timer()
        defer { timer.stop() }
        var dismissals = 0
        timer.begin { dismissals += 1 }
        clock.advance(9.9); XCTAssertEqual(dismissals, 0)
        clock.advance(0.2); XCTAssertEqual(dismissals, 1)
        timer.recordActivity(); clock.advance(20)
        XCTAssertEqual(dismissals, 1)
    }

    func testOperationRestartsFullIdleIntervalWithoutSchedulingPerFrame() {
        let clock = IdleTestClock(); let timer = clock.timer()
        defer { timer.stop() }
        var dismissals = 0
        timer.begin { dismissals += 1 }
        for _ in 0..<600 { clock.advance(0.01); timer.recordActivity() }
        XCTAssertEqual(clock.scheduledCount, 1, "High-rate activity must not allocate a timer per frame")
        clock.advance(4.1)
        XCTAssertEqual(dismissals, 0, "The original deadline must not close an editor being used")
        clock.advance(5.8); XCTAssertEqual(dismissals, 0)
        clock.advance(0.2); XCTAssertEqual(dismissals, 1)
    }

    func testClosingAndReopeningDiscardsPreviousDeadline() {
        let clock = IdleTestClock(); let timer = clock.timer()
        defer { timer.stop() }
        timer.begin { XCTFail("A closed editor fired its old timeout") }
        clock.advance(5); timer.stop(); clock.advance(20)
        var dismissals = 0
        timer.begin { dismissals += 1 }
        clock.advance(9.9); XCTAssertEqual(dismissals, 0)
        clock.advance(0.2); XCTAssertEqual(dismissals, 1)
    }

    func testRemotePressAndTouchProtectActiveEditorIncludingConsumedSiri() throws {
        let domain = "XvicoTests.MappingIdle.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        let model = AppModel(defaults: defaults, observeSystem: false,
                             accessibilityCheck: { false }, eventPoster: { _ in })
        let clock = IdleTestClock(); let timer = clock.timer()
        defer { timer.stop(); model.stopControl(); defaults.removePersistentDomain(forName: domain) }
        var dismissals = 0; var operations = 0
        let monitor = model.mappingInteraction.sink { _ in operations += 1; timer.recordActivity() }
        defer { monitor.cancel() }
        model.siriVoiceHandler = { _ in true }
        timer.begin(isInteracting: { model.isHoldingRemoteButton }) { dismissals += 1 }
        model.handleRemotePress(.voice, pressed: true)
        clock.advance(11)
        XCTAssertEqual(dismissals, 0, "Holding Siri must not close the active editor")
        model.handleRemotePress(.voice, pressed: false)
        model.handleTouch(RemoteTouchSample(x: 0.5, y: 0.5, touching: true, timestamp: 1))
        XCTAssertEqual(operations, 3)
        clock.advance(9.9); XCTAssertEqual(dismissals, 0)
        clock.advance(0.2); XCTAssertEqual(dismissals, 1)
    }

    func testProductionSchedulerActuallyFires() async {
        let timer = MappingIdleDismissal(timeout: 0.02)
        defer { timer.stop() }
        let closed = expectation(description: "Real scheduler fires")
        timer.begin { closed.fulfill() }
        await fulfillment(of: [closed], timeout: 3)
    }
}
