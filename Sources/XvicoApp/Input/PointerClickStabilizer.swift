import Foundation

/// Uses the remote sample clock only. A short mechanical-click disturbance
/// must not move the pointer; deliberate motion immediately unlocks dragging.
struct PointerClickStabilizer {
    private var anchor: RemoteTouchSample?
    private var began: Double?
    private var releaseDeadline: Double?
    private var active = false
    private var unlocked = false

    mutating func press(at sample: RemoteTouchSample?) {
        anchor = sample?.touching == true ? sample : nil
        began = anchor?.timestamp
        releaseDeadline = nil
        active = true
        unlocked = false
    }
    mutating func release(at sample: RemoteTouchSample?) {
        active = false
        if !unlocked, let sample, sample.touching { releaseDeadline = sample.timestamp + 0.06 }
        else { reset() }
    }
    mutating func reset() { self = Self() }

    mutating func suppresses(_ sample: RemoteTouchSample) -> Bool {
        guard sample.touching else { reset(); return false }
        guard !unlocked, active || releaseDeadline != nil else { return false }
        if let deadline = releaseDeadline, sample.timestamp >= deadline { reset(); return false }
        if anchor == nil { anchor = sample; began = sample.timestamp }
        guard let anchor, let began else { return false }
        let elapsed = sample.timestamp - began
        guard elapsed >= 0, elapsed <= 0.12,
              hypot(sample.x - anchor.x, sample.y - anchor.y) < 0.018 else {
            unlocked = true
            releaseDeadline = nil
            return false
        }
        return true
    }
}
