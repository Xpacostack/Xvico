import XCTest
@testable import XvicoApp

final class RemoteDirectionTests: XCTestCase {
    private func contact(_ x: Double, _ y: Double, _ timestamp: Double, state: Int32 = 4) -> RemoteTouchSample {
        RemoteTouchSample.multitouch(x: x, y: y, state: state, timestamp: timestamp)!
    }
    private func pointer(dx: Double, dy: Double, sensitivity: Double = 1) -> (Double, Double) {
        var settings = XvicoSettings(); settings.pointerSensitivity = sensitivity
        var processor = RemoteGestureProcessor()
        var total = (0.0, 0.0)
        for frame in 0..<10 {
            let sample = contact(0.5 + Double(frame) * dx, 0.5 + Double(frame) * dy, Double(frame) * 0.01)
            for output in processor.process(sample, settings: settings, mode: .scroll) {
                if case .pointer(let x, let y) = output { total.0 += x; total.1 += y }
            }
        }
        return total
    }
    func testNativeContactDrivesCorrectScreenDirections() {
        // Exercise the hardware-coordinate conversion before the gesture layer.
        XCTAssertGreaterThan(pointer(dx: 0.01, dy: 0).0, 0)
        XCTAssertLessThan(pointer(dx: -0.01, dy: 0).0, 0)
        XCTAssertLessThan(pointer(dx: 0, dy: 0.01).1, 0, "Finger up must move screen pointer up")
        XCTAssertGreaterThan(pointer(dx: 0, dy: -0.01).1, 0)
        XCTAssertGreaterThan(pointer(dx: 0.01, dy: 0).0, 35, "A short central swipe must not be swallowed by ring detection")
        XCTAssertGreaterThan(pointer(dx: 0.01, dy: 0, sensitivity: 2).0, pointer(dx: 0.01, dy: 0).0 * 1.9)
    }
    func testOrdinarySwipeOutsideOldHalfRadiusStillMovesPointer() {
        var settings = XvicoSettings(); settings.ringRadius = 0.33
        var processor = RemoteGestureProcessor()
        var outputs: [RemoteGestureOutput] = []
        for frame in 0..<9 {
            outputs += processor.process(contact(0.73, 0.45 + Double(frame) * 0.01, Double(frame) * 0.01), settings: settings, mode: .scroll)
        }
        XCTAssertTrue(outputs.contains { if case .pointer = $0 { return true }; return false })
        XCTAssertFalse(outputs.contains { if case .scroll = $0 { return true }; return false })
    }
    func testRotationOrientationAgreesAcrossEveryRingMode() {
        for mode in RingAction.allCases {
            for style in WheelStyle.allCases {
                for clockwise in [true, false] {
                    var processor = RemoteGestureProcessor()
                    var settings = XvicoSettings(); settings.wheelStyle = style
                    var directions: [Int] = []
                    for frame in 0..<18 {
                        let angle = Double(frame) * 0.05 * (clockwise ? -1 : 1)
                        let sample = contact(0.5 + 0.4 * cos(angle), 0.5 + 0.4 * sin(angle), Double(frame) * 0.01)
                        for output in processor.process(sample, settings: settings, mode: mode) {
                            switch output {
                            case .scroll(let amount, _): directions.append(Int(amount))
                            case .appStep(let direction), .taskStep(let direction): directions.append(direction)
                            default: XCTFail("Outer-ring motion must not produce pointer output")
                            }
                        }
                    }
                    XCTAssertFalse(directions.isEmpty)
                    XCTAssertTrue(directions.allSatisfy { clockwise ? $0 < 0 : $0 > 0 }, "One coordinate orientation must drive every ring mode")
                }
            }
        }
    }
    func testSlowContinuousRotationAccumulatesSmallFrames() {
        var processor = RemoteGestureProcessor()
        var settings = XvicoSettings(); settings.wheelStyle = .continuous
        var pixels: Int32 = 0
        for frame in 0..<101 {
            let angle = -Double(frame) * 0.001
            for output in processor.process(contact(0.5 + 0.4 * cos(angle), 0.5 + 0.4 * sin(angle), Double(frame) * 0.01), settings: settings, mode: .scroll) {
                if case .scroll(let amount, _) = output { pixels += amount }
            }
        }
        XCTAssertLessThan(pixels, -10, "Slow rotation must not disappear when each frame is less than one pixel")
    }
    func testContactReleaseAndReacquireNeverGenerateJump() {
        var processor = RemoteGestureProcessor()
        let settings = XvicoSettings()
        for frame in 0..<7 { _ = processor.process(contact(0.5 + Double(frame) * 0.01, 0.5, Double(frame) * 0.01), settings: settings, mode: .scroll) }
        for state: Int32 in [0, 1, 2, 5, 6, 7] {
            XCTAssertFalse(contact(0.8, 0.8, 0.08, state: state).touching)
        }
        XCTAssertTrue(processor.process(contact(0.8, 0.8, 0.08, state: 6), settings: settings, mode: .scroll).isEmpty)
        XCTAssertTrue(processor.process(contact(0.3, 0.4, 0.09), settings: settings, mode: .scroll).isEmpty)
    }
    func testFastRingRotationDoesNotLeaveScrollOverflowAfterStopping() {
        for direction in [-1.0, 1.0] {
            var processor = RemoteGestureProcessor()
            var settings = XvicoSettings(); settings.wheelStyle = .continuous
            settings.ringSensitivity = 1
            let initial = contact(0.9, 0.5, 0)
            _ = processor.process(initial, settings: settings, mode: .scroll)
            let angle = 0.8 * direction
            let end = contact(0.5 + 0.4 * cos(angle), 0.5 + 0.4 * sin(angle), 0.01)
            XCTAssertEqual(processor.process(end, settings: settings, mode: .scroll), [.scroll(Int32(120 * direction), true)])
            for _ in 0..<4 {
                XCTAssertTrue(processor.process(end, settings: settings, mode: .scroll).isEmpty,
                              "Discard capped overflow instead of replaying it on stationary frames")
            }
        }
    }
}
