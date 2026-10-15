import Foundation

final class VoiceFirstFrameGate: @unchecked Sendable {
    private let lock = NSLock()
    private var taken = false
    func take() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !taken else { return false }
        taken = true
        return true
    }
}

/// Monotonic timestamps, published only at stage boundaries, never per buffer.
struct VoiceLatencyMetrics: Equatable {
    var began: Double?
    var released: Double?
    var readyMilliseconds: Double?
    var firstAudioMilliseconds: Double?
    var firstTextMilliseconds: Double?
    var finalMilliseconds: Double?
    var deliveryMilliseconds: Double?

    mutating func begin(at now: Double) { self = Self(); began = now }
    mutating func ready(at now: Double) { readyMilliseconds = elapsed(from: began, to: now) }
    mutating func audio(at now: Double) {
        if firstAudioMilliseconds == nil { firstAudioMilliseconds = elapsed(from: began, to: now) }
    }
    mutating func text(at now: Double) {
        if firstTextMilliseconds == nil { firstTextMilliseconds = elapsed(from: began, to: now) }
    }
    mutating func release(at now: Double) { released = now }
    mutating func final(at now: Double) { finalMilliseconds = elapsed(from: released, to: now) }
    private func elapsed(from start: Double?, to now: Double) -> Double? {
        guard let start, start.isFinite, now.isFinite, now >= start else { return nil }
        return (now - start) * 1000
    }
}
