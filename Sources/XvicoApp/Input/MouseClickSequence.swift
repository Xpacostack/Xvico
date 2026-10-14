import Foundation

// and 8-point radius; a completed pair resets instead of counting triples.
struct MouseClickSequence {
    private var previous: (time: Double, point: CGPoint)?
    mutating func click(at point: CGPoint, time: Double, interval: Double) -> Int64 {
        if let previous {
            let elapsed = time - previous.time
            if elapsed >= 0 && elapsed <= max(0, interval)
                && hypot(point.x - previous.point.x, point.y - previous.point.y) <= 8 {
                self.previous = nil
                return 2
            }
        }
        previous = (time, point)
        return 1
    }
}
