import AppKit
import Combine

@MainActor
final class MappingIdleDismissal: ObservableObject {
    private let timeout: TimeInterval
    private var pending: Task<Void, Never>?
    private var eventMonitor: Any?
    private var dismiss: (() -> Void)?
    private var isInteracting: (() -> Bool)?

    init(timeout: TimeInterval = 10) { self.timeout = timeout }

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
        pending?.cancel()
        let delay = UInt64(max(0, timeout) * 1_000_000_000)
        pending = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: delay) } catch { return }
            guard !Task.isCancelled, let self else { return }
            // Finish a held drag or modal app picker before starting another
            // idle interval; never tear down a control under an active press.
            if NSEvent.pressedMouseButtons != 0 || NSApp?.modalWindow != nil || self.isInteracting?() == true {
                self.recordActivity()
                return
            }
            let onDismiss = self.dismiss
            self.stop()
            onDismiss?()
        }
    }

    func stop() {
        pending?.cancel(); pending = nil
        dismiss = nil
        isInteracting = nil
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
    }

    deinit {
        pending?.cancel()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }
}
