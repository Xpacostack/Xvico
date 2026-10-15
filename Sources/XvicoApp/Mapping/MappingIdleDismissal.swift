import AppKit
import Combine

@MainActor
final class MappingIdleDismissal: ObservableObject {
    private let timeout: TimeInterval
    typealias Scheduler = (TimeInterval, @escaping () -> Void) -> () -> Void
    private let now: () -> TimeInterval
    private let schedule: Scheduler
    private let systemInteracting: @MainActor () -> Bool
    private var cancelPending: (() -> Void)?
    private var deadline = 0.0
    private var eventMonitor: Any?
    private var dismiss: (() -> Void)?
    private var isInteracting: (() -> Bool)?

    init(timeout: TimeInterval = 10,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         schedule: @escaping Scheduler = { delay, fire in
             let task = Task {
                 do { try await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000)) }
                 catch { return }
                 guard !Task.isCancelled else { return }
                 fire()
             }
             return { task.cancel() }
         },
         systemInteracting: @escaping @MainActor () -> Bool = {
             let pressed = NSEvent.pressedMouseButtons != 0
             let modal = NSApp?.modalWindow != nil
             return pressed || modal
         }) {
        self.timeout = timeout; self.now = now; self.schedule = schedule
        self.systemInteracting = systemInteracting
    }

    func begin(isInteracting: @escaping () -> Bool = { false }, onDismiss: @escaping () -> Void) {
        dismiss = onDismiss
        self.isInteracting = isInteracting
        if eventMonitor == nil {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [
                .leftMouseDown, .leftMouseUp, .leftMouseDragged,
                .rightMouseDown, .rightMouseUp, .rightMouseDragged,
                .otherMouseDown, .otherMouseUp, .otherMouseDragged,
                .mouseMoved, .scrollWheel, .keyDown, .keyUp, .flagsChanged
            ]) { [weak self] event in
                self?.recordActivity()
                return event
            }
        }
        recordActivity()
    }

    func recordActivity() {
        guard dismiss != nil else { return }
        deadline = now() + timeout
        // High-rate touch/mouse frames only update a timestamp. Keep one
        // scheduled wakeup instead of creating and cancelling a Task per frame.
        if cancelPending == nil { arm(after: timeout) }
    }

    private func arm(after delay: TimeInterval) {
        cancelPending = schedule(delay) { [weak self] in
            guard let self, self.dismiss != nil else { return }
            self.cancelPending = nil
            let remaining = self.deadline - self.now()
            if remaining > 0 { self.arm(after: remaining); return }
            // Finish a held drag or modal app picker before starting another
            // idle interval; never tear down a control under an active press.
            if self.systemInteracting() || self.isInteracting?() == true {
                self.recordActivity()
                return
            }
            let onDismiss = self.dismiss
            self.stop()
            onDismiss?()
        }
    }

    func stop() {
        cancelPending?(); cancelPending = nil
        dismiss = nil
        isInteracting = nil
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
    }

    deinit {
        cancelPending?()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }
}
