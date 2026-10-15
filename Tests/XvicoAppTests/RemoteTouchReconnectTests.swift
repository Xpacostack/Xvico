import XCTest
@testable import XvicoApp

@MainActor
private final class DelayedTouchDriver: RemoteMultitouchMonitoring {
    var onSample: ((RemoteTouchSample) -> Void)?
    var onStatus: ((String) -> Void)?
    var attempts: [UInt32] = []
    var stops = 0
    var available = false
    var outcomes: [Bool] = []
    func start(locationID: UInt32) -> Bool {
        attempts.append(locationID)
        return outcomes.isEmpty ? available : outcomes.removeFirst()
    }
    func stop() { stops += 1 }
}

@MainActor
final class RemoteTouchReconnectTests: XCTestCase {
    private let shortDelays: [UInt64] = [1_000_000, 1_000_000, 1_000_000]
    private func settle(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        while !condition() && ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(condition(), file: file, line: line)
    }

    func testHIDArrivesBeforeMultitouchAndAutomaticallyRecoversWhenReady() async throws {
        let driver = DelayedTouchDriver()
        driver.outcomes = [false, false, true]
        let controller = RemoteTouchReconnectController(driver: driver, retryDelays: shortDelays)
        defer { controller.stop() }
        controller.connect(locationID: 42)
        XCTAssertEqual(driver.attempts, [42])
        try await settle { driver.attempts.count == 3 }
        XCTAssertEqual(driver.attempts, [42, 42, 42])
        try await Task.sleep(nanoseconds: 15_000_000)
        XCTAssertEqual(driver.attempts.count, 3, "A successful binding must not be restarted")
    }

    func testImmediateSuccessDoesNotScheduleIdleRestarts() async throws {
        let driver = DelayedTouchDriver(); driver.available = true
        let controller = RemoteTouchReconnectController(driver: driver, retryDelays: shortDelays)
        defer { controller.stop() }
        controller.connect(locationID: 42)
        try await Task.sleep(nanoseconds: 15_000_000)
        XCTAssertEqual(driver.attempts, [42])
    }

    func testDisconnectCancelsPendingAcquisition() async throws {
        let driver = DelayedTouchDriver()
        let controller = RemoteTouchReconnectController(driver: driver, retryDelays: shortDelays)
        controller.connect(locationID: 42)
        controller.stop()
        driver.available = true
        try await Task.sleep(nanoseconds: 15_000_000)
        XCTAssertEqual(driver.attempts, [42])
        XCTAssertEqual(driver.stops, 2)
    }

    func testReconnectWithNewLocationCancelsOldRetry() async throws {
        let driver = DelayedTouchDriver()
        let controller = RemoteTouchReconnectController(driver: driver, retryDelays: shortDelays)
        defer { controller.stop() }
        controller.connect(locationID: 42)
        driver.available = true
        controller.connect(locationID: 99)
        try await Task.sleep(nanoseconds: 15_000_000)
        XCTAssertEqual(driver.attempts, [42, 99])
    }

    func testReusedLocationStillCreatesFreshAcquisitionAfterDisconnect() async throws {
        let driver = DelayedTouchDriver()
        let controller = RemoteTouchReconnectController(driver: driver, retryDelays: shortDelays)
        defer { controller.stop() }
        controller.connect(locationID: 42)
        controller.stop()
        driver.outcomes = [false, true]
        controller.connect(locationID: 42)
        try await settle { driver.attempts.count == 3 }
        try await Task.sleep(nanoseconds: 15_000_000)
        XCTAssertEqual(driver.attempts, [42, 42, 42])
    }

    func testStartupFailureRemainsRetryableAndAttemptsAreBounded() async throws {
        let driver = DelayedTouchDriver()
        let controller = RemoteTouchReconnectController(driver: driver, retryDelays: shortDelays)
        defer { controller.stop() }
        controller.connect(locationID: 42)
        try await settle { driver.attempts.count == 4 }
        try await Task.sleep(nanoseconds: 15_000_000)
        XCTAssertEqual(driver.attempts.count, 4)
        driver.available = true
        controller.connect(locationID: 42)
        XCTAssertEqual(driver.attempts.count, 5, "Manual recovery remains available after the bounded retry window")
    }

    func testStopDuringBackoffAndLateReconnectDoNotReviveOldDevice() async throws {
        let driver = DelayedTouchDriver()
        let controller = RemoteTouchReconnectController(driver: driver, retryDelays: [1_000_000, 100_000_000, 100_000_000])
        defer { controller.stop() }
        controller.connect(locationID: 42)
        try await settle { driver.attempts.count == 2 }
        controller.stop()
        driver.available = true
        controller.connect(locationID: 99)
        try await Task.sleep(nanoseconds: 15_000_000)
        XCTAssertEqual(driver.attempts, [42, 42, 99])
    }
}

final class RemoteTouchFrameGateTests: XCTestCase {
    func testQueuedFramesCannotCrossStopOrRebindEvenWithReusedDevicePointer() throws {
        let gate = RemoteTouchFrameGate()
        XCTAssertNil(gate.capture(device: 42))
        gate.activate(device: 42)
        let first = try XCTUnwrap(gate.capture(device: 42))
        XCTAssertTrue(gate.accepts(first))
        gate.reset()
        XCTAssertFalse(gate.accepts(first))
        XCTAssertNil(gate.capture(device: 42))
        gate.activate(device: 42)
        let next = try XCTUnwrap(gate.capture(device: 42))
        XCTAssertNotEqual(first, next)
        XCTAssertFalse(gate.accepts(first))
        XCTAssertTrue(gate.accepts(next))
    }

    func testFramesFromOtherDeviceAreRejected() throws {
        let gate = RemoteTouchFrameGate()
        gate.activate(device: 42)
        XCTAssertNil(gate.capture(device: 99))
        XCTAssertNotNil(gate.capture(device: nil))
        let old = try XCTUnwrap(gate.capture(device: 42))
        gate.activate(device: 99)
        XCTAssertNil(gate.capture(device: 42))
        XCTAssertFalse(gate.accepts(old))
        XCTAssertNotNil(gate.capture(device: 99))
    }
}
