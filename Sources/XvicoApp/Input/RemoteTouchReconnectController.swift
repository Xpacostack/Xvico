import Foundation

@MainActor
protocol RemoteMultitouchMonitoring: AnyObject {
    var onSample: ((RemoteTouchSample) -> Void)? { get set }
    var onStatus: ((String) -> Void)? { get set }
    @discardableResult func start(locationID: UInt32) -> Bool
    func stop()
}

/// HID matching may precede the corresponding MultitouchSupport device.
/// Retry only during connection acquisition; never restart a healthy idle
/// trackpad because the user has not touched it.
@MainActor
final class RemoteTouchReconnectController {
    private let driver: any RemoteMultitouchMonitoring
    private let retryDelays: [UInt64]
    private var acquisition: Task<Void, Never>?
    private var generation = UUID()

    init(driver: any RemoteMultitouchMonitoring,
         retryDelays: [UInt64] = [250_000_000, 500_000_000, 1_000_000_000,
                                  2_000_000_000, 3_000_000_000, 5_000_000_000]) {
        self.driver = driver
        self.retryDelays = retryDelays
    }

    func connect(locationID: UInt32) {
        stop()
        let session = generation
        if driver.start(locationID: locationID) { return }
        let delays = retryDelays
        acquisition = Task { [weak self] in
            for delay in delays {
                do { try await Task.sleep(nanoseconds: delay) } catch { return }
                guard !Task.isCancelled, let self, self.generation == session else { return }
                if self.driver.start(locationID: locationID) {
                    self.acquisition = nil
                    return
                }
            }
            guard let self, self.generation == session else { return }
            self.acquisition = nil
        }
    }

    func stop() {
        generation = UUID()
        acquisition?.cancel(); acquisition = nil
        driver.stop()
    }
}
