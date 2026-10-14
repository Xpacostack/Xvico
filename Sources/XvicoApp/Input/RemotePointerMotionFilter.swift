import Foundation

// Native touch Y remains bottom-origin; this is the only screen-Y inversion.
struct RemotePointerMotionFilter {
    private var previous: RemoteTouchSample?
    private var filteredX = 0.0
    private var filteredY = 0.0
    private var warmupFrames = 2

    mutating func reset() { self = Self() }
    mutating func seed(_ sample: RemoteTouchSample) {
        previous = sample; filteredX = 0; filteredY = 0; warmupFrames = 2
    }

    mutating func process(_ sample: RemoteTouchSample, sensitivity: Double) -> (x: Double, y: Double)? {
        guard sample.touching else { reset(); return nil }
        guard let previous else { seed(sample); return nil }
        self.previous = sample
        let elapsed = sample.timestamp - previous.timestamp
        guard elapsed > 0 && elapsed <= 0.12 else { seed(sample); return nil }
        var dx = sample.x - previous.x
        var dy = sample.y - previous.y
        let distance = hypot(dx, dy)
        guard distance >= 0.0015 else { filteredX = 0; filteredY = 0; return nil }
        guard distance <= 0.12 else {
            filteredX = 0; filteredY = 0; warmupFrames = 2; return nil
        }
        if warmupFrames > 0 { warmupFrames -= 1; return nil }
        if distance > 0.065 { dx *= 0.065 / distance; dy *= 0.065 / distance }
        let interval = max(0.008, elapsed)
        let weight = min(0.92, max(0.68, 0.68 + distance / interval * 0.12))
        filteredX = weight * dx + (1 - weight) * filteredX
        filteredY = weight * dy + (1 - weight) * filteredY
        let speed = hypot(filteredX, filteredY) / interval
        let acceleration: Double
        if speed < 0.1 { acceleration = 0.65 }
        else if speed < 0.7 { acceleration = 0.65 + (speed - 0.1) / 0.6 * 0.35 }
        else if speed < 2.2 { acceleration = 1 + (speed - 0.7) / 1.5 * 1.2 }
        else { acceleration = 2.2 }
        let gain = 760 * min(3, max(0.2, sensitivity)) * acceleration
        return (filteredX * gain, -filteredY * gain)
    }
}
