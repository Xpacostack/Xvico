import XCTest
import Combine
import CoreImage
@testable import XvicoApp

@MainActor
final class PresentationRegressionTests: XCTestCase {
    func testStationaryTouchAvoidsSystemPermissionQueriesButMotionStillChecksTrust() throws {
        let domain = "XvicoTests.TouchPresentation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        var trustQueries = 0
        var events: [CGEvent] = []
        let model = AppModel(defaults: defaults, observeSystem: false,
                             accessibilityCheck: { trustQueries += 1; return false },
                             eventPoster: { events.append($0) })
        defer { model.stopControl(); defaults.removePersistentDomain(forName: domain) }
        model.settings.ringEnabled = false
        for frame in 0..<120 {
            model.handleTouch(.init(x: 0.5, y: 0.5, touching: true, timestamp: Double(frame) / 120))
        }
        XCTAssertEqual(trustQueries, 0, "A stationary contact emits no event and needs no trust query")
        for frame in 120..<130 {
            model.handleTouch(.init(x: 0.5 + Double(frame - 119) * 0.01, y: 0.5,
                                    touching: true, timestamp: Double(frame) / 120))
        }
        XCTAssertGreaterThan(trustQueries, 0, "Real motion must still check permission before posting")
        XCTAssertTrue(events.isEmpty, "Denied permission must continue blocking pointer events")
    }

    func testContinuousScrollKeepsEveryInputEventWithoutInvalidatingWindow() async throws {
        let domain = "XvicoTests.ScrollPresentation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        var events: [CGEvent] = []
        let model = AppModel(defaults: defaults, observeSystem: false,
                             accessibilityCheck: { true }, eventPoster: { events.append($0) })
        defer { model.stopControl(); UserDefaults.standard.removePersistentDomain(forName: domain) }
        model.settings.autoSwitchScenes = false
        model.settings.ringAction = .scroll
        model.settings.wheelStyle = .continuous
        model.settings.touchEnabled = true
        model.settings.ringEnabled = true
        var windowUpdates = 0
        let observer = model.objectWillChange.sink { windowUpdates += 1 }
        defer { observer.cancel() }
        for frame in 0...120 {
            let angle = -Double(frame) * 0.015
            model.handleTouch(RemoteTouchSample(x: 0.5 + 0.4 * cos(angle),
                                               y: 0.5 + 0.4 * sin(angle), touching: true,
                                               timestamp: Double(frame) / 120))
        }
        XCTAssertEqual(events.filter { $0.type == .scrollWheel }.count, 120,
                       "UI optimization must not drop or defer the actual scroll events")
        XCTAssertEqual(windowUpdates, 0, "Hardware diagnostics must not redraw the whole window during scrolling")
        XCTAssertTrue(model.lastAction.hasPrefix("滚动"))
    }

    func testBundledDeveloperImageIsReadableQRCode() async throws {
        let image = try XCTUnwrap(XvicoArtwork.developerQRCode)
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                              options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let codes = detector.features(in: CIImage(cgImage: cgImage)).compactMap { $0 as? CIQRCodeFeature }
        XCTAssertEqual(codes.count, 1)
        XCTAssertFalse(try XCTUnwrap(codes.first?.messageString).isEmpty)
    }
}
