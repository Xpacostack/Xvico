import Foundation

struct RemoteTouchSample {
    // Native MultitouchSupport coordinates: +X right, +Y toward remote top.
    // Screen-space Y is inverted only when producing pointer movement.
    var x: Double
    var y: Double
    var touching: Bool
    var timestamp = ProcessInfo.processInfo.systemUptime

    static func multitouch(x: Double, y: Double, state: Int32, timestamp: Double) -> Self? {
        guard x.isFinite, y.isFinite, timestamp.isFinite else { return nil }
        return Self(x: min(1, max(0, x)), y: min(1, max(0, y)),
                    touching: state == 3 || state == 4, timestamp: timestamp)
    }
}
enum RemoteGestureOutput: Equatable {
    case pointer(Double, Double)
    case scroll(Int32, Bool)
    case appStep(Int)
    case appEnd
    case taskStep(Int)
}

// Consumes normalized coordinates from the remote's own digitizer interface.
// It never consumes the user's mouse or built-in trackpad.
struct RemoteGestureProcessor {
    private var previous: RemoteTouchSample?
    private var accumulatedAngle = 0.0
    private var switchingApps = false
    private var previousMode: RingAction?
    private var pointerMotion = RemotePointerMotionFilter()
    private var scrollRemainder = 0.0

    mutating func process(_ sample: RemoteTouchSample, settings: XvicoSettings, mode: RingAction) -> [RemoteGestureOutput] {
        guard sample.touching && settings.touchEnabled else {
            let result: [RemoteGestureOutput] = switchingApps ? [.appEnd] : []
            previous = nil; accumulatedAngle = 0; switchingApps = false; previousMode = nil
            pointerMotion.reset(); scrollRemainder = 0
            return result
        }
        guard sample.x.isFinite && sample.y.isFinite && (0...1).contains(sample.x) && (0...1).contains(sample.y) else { return [] }
        var outputs: [RemoteGestureOutput] = []
        if previousMode != mode {
            if switchingApps { outputs.append(.appEnd) }
            switchingApps = false; accumulatedAngle = 0; scrollRemainder = 0
        }
        previousMode = mode
        defer { previous = sample }
        guard let previous else { pointerMotion.seed(sample); return outputs }
        // Compare the normalized distance directly with the stored 33%,
        // rather than doubling the radius into a fraction of the half-width.
        let radius = hypot(sample.x - 0.5, sample.y - 0.5)
        let previousRadius = hypot(previous.x - 0.5, previous.y - 0.5)
        let ringRadius = min(0.48, max(0.22, settings.ringRadius))
        guard settings.ringEnabled && radius >= ringRadius && previousRadius >= ringRadius else {
            if switchingApps { outputs.append(.appEnd); switchingApps = false }
            accumulatedAngle = 0; scrollRemainder = 0
            if let movement = pointerMotion.process(sample, sensitivity: settings.pointerSensitivity) {
                outputs.append(.pointer(movement.x, movement.y))
            }
            return outputs
        }
        pointerMotion.reset()
        var angle = atan2(sample.y - 0.5, sample.x - 0.5) - atan2(previous.y - 0.5, previous.x - 0.5)
        if angle > .pi { angle -= 2 * .pi }
        if angle < -.pi { angle += 2 * .pi }
        // Drop jumps rather than turning a missing hardware frame into many actions.
        guard abs(angle) < .pi / 2 else { accumulatedAngle = 0; return outputs }
        angle *= min(1.8, max(0.6, settings.ringSensitivity))
        if mode == .scroll && settings.wheelStyle == .continuous {
            // Keep sub-pixel rotation from slow frames instead of dropping it.
            // truncate toward zero and cap a emitted frame at +/-120 pixels.
            scrollRemainder += angle * 300
            let wholePixels = scrollRemainder.rounded(.towardZero)
            let pixels = Int32(min(120, max(-120, wholePixels)))
            // Subtract d8 (the full truncation), not capped w20.
            // Retaining overflow produces scrolling after rotation stops.
            scrollRemainder -= wholePixels
            if pixels != 0 { outputs.append(.scroll(pixels, true)) }
        } else {
            accumulatedAngle += angle
            let threshold = mode == .scroll ? 0.16 : mode == .switchApp ? 0.32 : 0.30
            while abs(accumulatedAngle) >= threshold {
                let direction = accumulatedAngle > 0 ? 1 : -1
                accumulatedAngle -= Double(direction) * threshold
                switch mode {
                case .scroll: outputs.append(.scroll(Int32(direction), false))
                case .switchApp: outputs.append(.appStep(direction)); switchingApps = true
                case .codexTasks: outputs.append(.taskStep(direction))
                }
            }
        }
        return outputs
    }
}
