import XCTest
import SceneKit
import AppKit
@testable import XvicoApp

@MainActor
final class RemoteModelInteractionTests: XCTestCase {
    private func makeView() -> RemoteSceneView {
        let view = RemoteSceneView(frame: NSRect(x: 0, y: 0, width: 850, height: 565))
        view.loadModel()
        return view
    }

    private func buttonPoint(_ view: RemoteSceneView, x: CGFloat, y: CGFloat) throws -> NSPoint {
        let turntable = try XCTUnwrap(view.scene?.rootNode.childNode(withName: "remoteTurntable", recursively: false))
        let root = try XCTUnwrap(turntable.childNodes.first)
        let b = root.boundingBox
        let local = SCNVector3(b.min.x + (b.max.x - b.min.x) * x, b.max.y,
                              b.min.z + (b.max.z - b.min.z) * y)
        let screen = view.projectPoint(root.presentation.convertPosition(local, to: nil))
        return NSPoint(x: screen.x, y: screen.y)
    }

    private func render(_ view: RemoteSceneView, name: String) throws {
        let image = view.snapshot()
        if let directory = ProcessInfo.processInfo.environment["XVICO_MODEL_EVIDENCE_DIR"] {
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
        }
    }

    private func event(_ type: NSEvent.EventType, at point: NSPoint) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }

    func testDragCanExposeRearWithoutSelectingHiddenFrontButtons() async throws {
        let view = makeView()
        defer { view.isPlaying = false }
        try render(view, name: "model-front-render")
        let front = try buttonPoint(view, x: 0.5, y: 0.21)
        XCTAssertEqual(view.selectableKey(at: front), .center)
        view.mouseDown(with: try event(.leftMouseDown, at: front))
        view.mouseDragged(with: try event(.leftMouseDragged, at: NSPoint(x: front.x + 267, y: front.y)))
        try render(view, name: "model-back-render")
        let rear = try buttonPoint(view, x: 0.5, y: 0.21)
        XCTAssertNil(view.selectableKey(at: rear), "Back-facing center must not open the front button editor")
        view.mouseUp(with: try event(.leftMouseUp, at: NSPoint(x: front.x + 267, y: front.y)))
        // An offscreen SCNView has no display-link ticks. Drive the shared
        // scene renderer's clock so the real return action can finish.
        let renderer = SCNRenderer(device: view.device, options: nil)
        renderer.scene = view.scene
        renderer.pointOfView = view.pointOfView
        let time = ProcessInfo.processInfo.systemUptime
        renderer.update(atTime: time)
        renderer.update(atTime: time + 0.45)
        try render(view, name: "model-return-render")
        let returned = try buttonPoint(view, x: 0.5, y: 0.21)
        XCTAssertEqual(view.selectableKey(at: returned), .center, "Release must restore front-facing interaction")
    }

    func testButtonsRemainAlignedWhenEditorMovesAndZoomsModel() async throws {
        let view = makeView()
        defer { view.isPlaying = false }
        view.setEditorLayout(open: true, width: 345)
        try await Task.sleep(nanoseconds: 350_000_000)
        try render(view, name: "model-editor-render")
        for (key, x, y) in [(RemoteKey.center, CGFloat(0.5), CGFloat(0.21)),
                            (.menu, 0.285, 0.377), (.tv, 0.715, 0.377)] {
            XCTAssertEqual(view.selectableKey(at: try buttonPoint(view, x: x, y: y)), key)
        }
    }

    func testEveryPhysicalSelectionKeepsItsSurfaceSelectableWithoutVisibleHitGeometry() async throws {
        let view = makeView()
        defer { view.isPlaying = false }
        let turntable = try XCTUnwrap(view.scene?.rootNode.childNode(withName: "remoteTurntable", recursively: false))
        let root = try XCTUnwrap(turntable.childNodes.first)
        let originalBounds = root.boundingBox
        let anchors: [(RemoteKey, CGFloat, CGFloat)] = [
            (.power, 0.80, 0.05), (.center, 0.50, 0.21),
            (.touchUp, 0.50, 0.10), (.touchDown, 0.50, 0.32),
            (.touchLeft, 0.10, 0.21), (.touchRight, 0.90, 0.21),
            (.menu, 0.285, 0.377), (.tv, 0.715, 0.377),
            (.playPause, 0.285, 0.487), (.mute, 0.285, 0.596),
            (.volumeUp, 0.715, 0.487), (.volumeDown, 0.715, 0.596), (.voice, 1, 0.22)
        ]
        for (key, x, y) in anchors {
            view.setPresentation(selected: key, width: 345, reduceMotion: false)
            try await Task.sleep(nanoseconds: 510_000_000)
            let renderer = SCNRenderer(device: view.device, options: nil)
            renderer.scene = view.scene
            renderer.pointOfView = view.pointOfView
            let now = ProcessInfo.processInfo.systemUptime
            renderer.update(atTime: now)
            renderer.update(atTime: now + 0.6)
            try render(view, name: "focus-" + String(RemoteKey.physicalOrder.firstIndex(of: key) ?? 0))
            let p = SCNVector3(originalBounds.min.x + (originalBounds.max.x - originalBounds.min.x) * x,
                               key == .voice ? 0 : originalBounds.max.y,
                               originalBounds.min.z + (originalBounds.max.z - originalBounds.min.z) * y)
            let screen = view.projectPoint(root.presentation.convertPosition(p, to: nil))
            XCTAssertEqual(view.selectableKey(at: NSPoint(x: screen.x, y: screen.y)), key, "Selected key must remain aligned: \(key)")
            XCTAssertGreaterThan(screen.x, 345, "Model must remain clear of the editor")
            XCTAssertGreaterThan(screen.y, 0)
            XCTAssertLessThan(screen.y, view.bounds.height)
            for xCorner in [originalBounds.min.x, originalBounds.max.x] {
                for yCorner in [originalBounds.min.y, originalBounds.max.y] {
                    for zCorner in [originalBounds.min.z, originalBounds.max.z] {
                        let corner = view.projectPoint(root.presentation.convertPosition(SCNVector3(xCorner, yCorner, zCorner), to: nil))
                        XCTAssertGreaterThan(corner.y, 5, "Top/bottom safety margin for \(key)")
                        XCTAssertLessThan(corner.y, view.bounds.height - 5, "Top/bottom safety margin for \(key)")
                        XCTAssertGreaterThan(corner.x, 345, "Clear of editor for \(key)")
                        XCTAssertLessThan(corner.x, view.bounds.width - 5)
                    }
                }
            }
            XCTAssertEqual(view.focusedKey, key)
            XCTAssertNil(root.childNode(withName: "selectedKeyIndicator", recursively: false))
            XCTAssertNil(try XCTUnwrap(root.childNode(withName: "selectionSurfaceLight", recursively: false)).geometry)
        }
        view.setPresentation(selected: nil, width: 345, reduceMotion: false)
        try await Task.sleep(nanoseconds: 510_000_000)
        let renderer = SCNRenderer(device: view.device, options: nil)
        renderer.scene = view.scene
        renderer.pointOfView = view.pointOfView
        let now = ProcessInfo.processInfo.systemUptime
        renderer.update(atTime: now)
        renderer.update(atTime: now + 0.6)
        try render(view, name: "focus-closed")
        XCTAssertNil(view.focusedKey)
        XCTAssertNil(root.childNode(withName: "selectedKeyIndicator", recursively: false))
        XCTAssertEqual(try XCTUnwrap(root.childNode(withName: "selectionSurfaceLight", recursively: false)?.light).intensity, 0)
        XCTAssertEqual(turntable.eulerAngles.y, -0.06, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(view.pointOfView?.camera).orthographicScale, 7.5, accuracy: 0.001)
    }

    func testReducedMotionKeepsFrontPoseAndSelectionDoesNotRestartOnUnchangedUpdate() async throws {
        let view = makeView()
        defer { view.isPlaying = false }
        view.setPresentation(selected: .voice, width: 345, reduceMotion: true)
        let turntable = try XCTUnwrap(view.scene?.rootNode.childNode(withName: "remoteTurntable", recursively: false))
        XCTAssertEqual(turntable.eulerAngles.y, -0.06, accuracy: 0.001)
        XCTAssertEqual(turntable.eulerAngles.z, 0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(view.pointOfView?.camera).orthographicScale, 7.1, accuracy: 0.001)
        let p = try buttonPoint(view, x: 0.5, y: 0.21)
        view.mouseDown(with: try event(.leftMouseDown, at: p))
        view.mouseDragged(with: try event(.leftMouseDragged, at: NSPoint(x: p.x + 120, y: p.y)))
        let draggedYaw = turntable.eulerAngles.y
        view.setPresentation(selected: .voice, width: 345, reduceMotion: true)
        XCTAssertEqual(turntable.eulerAngles.y, draggedYaw, "Unchanged SwiftUI updates must not interrupt a drag")
        view.mouseUp(with: try event(.leftMouseUp, at: NSPoint(x: p.x + 120, y: p.y)))
        XCTAssertEqual(turntable.eulerAngles.y, -0.06, accuracy: 0.001)
    }


    func testRapidSelectionAndClosingDuringReturnDoNotLeaveStalePoseOrIndicators() async throws {
        let view = makeView()
        defer { view.isPlaying = false }
        for key in RemoteKey.physicalOrder + [.voice, .tv, .menu] {
            view.setPresentation(selected: key, width: 345, reduceMotion: false)
        }
        let turntable = try XCTUnwrap(view.scene?.rootNode.childNode(withName: "remoteTurntable", recursively: false))
        let root = try XCTUnwrap(turntable.childNodes.first)
        let p = NSPoint(x: 600, y: 250)
        view.mouseDown(with: try event(.leftMouseDown, at: p))
        view.mouseDragged(with: try event(.leftMouseDragged, at: NSPoint(x: 800, y: 250)))
        view.mouseUp(with: try event(.leftMouseUp, at: NSPoint(x: 800, y: 250)))
        view.setPresentation(selected: nil, width: 345, reduceMotion: true)
        XCTAssertNil(turntable.action(forKey: "returnToFront"))
        XCTAssertNil(view.focusedKey)
        XCTAssertEqual(turntable.eulerAngles.y, -0.06, accuracy: 0.001)
        XCTAssertNil(root.childNode(withName: "selectedKeyIndicator", recursively: false))
        XCTAssertEqual(try XCTUnwrap(root.childNode(withName: "selectionSurfaceLight", recursively: false)?.light).intensity, 0)
        XCTAssertEqual(root.childNodes.filter { $0.name == "selectionSurfaceLight" }.count, 1)
    }


    func testLargerStableViewportPreservesRestSizeAndResizeDoesNotResetDrag() async throws {
        let view = makeView()
        defer { view.isPlaying = false }
        let camera = try XCTUnwrap(view.pointOfView?.camera)
        let originalPixelsPerUnit = view.bounds.height / (camera.orthographicScale * 2)
        view.setFrameSize(NSSize(width: 1008, height: 620))
        XCTAssertEqual(view.bounds.height / (camera.orthographicScale * 2), originalPixelsPerUnit, accuracy: 0.001)
        view.setPresentation(selected: .voice, width: 345, reduceMotion: false)
        let p = NSPoint(x: 700, y: 250)
        view.mouseDown(with: try event(.leftMouseDown, at: p))
        view.mouseDragged(with: try event(.leftMouseDragged, at: NSPoint(x: 820, y: 250)))
        let turntable = try XCTUnwrap(view.scene?.rootNode.childNode(withName: "remoteTurntable", recursively: false))
        let draggedYaw = turntable.eulerAngles.y
        view.setFrameSize(NSSize(width: 1180, height: 620))
        XCTAssertEqual(turntable.eulerAngles.y, draggedYaw, accuracy: 0.001,
                       "Layout callbacks must not interrupt orientation or drag")
    }


    func testRenderingUsesHighResolutionMSAAWithTransparentBacking() throws {
        let view = makeView()
        defer { view.isPlaying = false }
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(view.layer).contentsScale, 2)
        XCTAssertFalse(view.isTemporalAntialiasingEnabled)
        XCTAssertFalse(view.isOpaque)
        XCTAssertFalse(try XCTUnwrap(view.layer).isOpaque)
        XCTAssertTrue(view.wantsBestResolutionOpenGLSurface)
        XCTAssertEqual(view.antialiasingMode, view.device?.supportsTextureSampleCount(8) == true ? .multisampling8X : .multisampling4X)
        let image = view.snapshot()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
        XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)).alphaComponent, 0.01)
        XCTAssertGreaterThanOrEqual(bitmap.pixelsWide, Int(view.bounds.width * 2))
        XCTAssertGreaterThanOrEqual(bitmap.pixelsHigh, Int(view.bounds.height * 2))
        if let directory = ProcessInfo.processInfo.environment["XVICO_MODEL_EVIDENCE_DIR"] {
            let diagnostics: [String: Any] = ["pointWidth": view.bounds.width, "pointHeight": view.bounds.height,
                "pixelWidth": bitmap.pixelsWide, "pixelHeight": bitmap.pixelsHigh,
                "backingScale": view.layer?.contentsScale ?? 0, "temporalAA": view.isTemporalAntialiasingEnabled,
                "sampleCount": view.antialiasingMode == .multisampling8X ? 8 : 4]
            try JSONSerialization.data(withJSONObject: diagnostics, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent("render-diagnostics.json"))
        }
    }

    func testFeedbackEndsAndCancelsOnCloseWithoutChangingModelGeometry() throws {
        let view = makeView()
        defer { view.isPlaying = false }
        let turntable = try XCTUnwrap(view.scene?.rootNode.childNode(withName: "remoteTurntable", recursively: false))
        let root = try XCTUnwrap(turntable.childNodes.first)
        let originalGeometryCount = root.childNodes.filter { $0.geometry != nil }.count
        view.setPresentation(selected: .voice, width: 345, reduceMotion: false)
        let light = try XCTUnwrap(root.childNode(withName: "selectionSurfaceLight", recursively: false))
        XCTAssertNotNil(light.action(forKey: "selectionFeedback"))
        let renderer = SCNRenderer(device: view.device, options: nil)
        renderer.scene = view.scene
        renderer.pointOfView = view.pointOfView
        let time = ProcessInfo.processInfo.systemUptime
        renderer.update(atTime: time)
        renderer.update(atTime: time + 0.50)
        XCTAssertGreaterThan(try XCTUnwrap(light.light).intensity, 0)
        XCTAssertLessThanOrEqual(try XCTUnwrap(light.light).intensity, 16)
        renderer.update(atTime: time + 1.2)
        XCTAssertEqual(try XCTUnwrap(light.light).intensity, 0)
        view.setPresentation(selected: .tv, width: 345, reduceMotion: false)
        XCTAssertNotNil(light.action(forKey: "selectionFeedback"))
        view.setPresentation(selected: nil, width: 345, reduceMotion: false)
        XCTAssertNil(light.action(forKey: "selectionFeedback"))
        XCTAssertEqual(try XCTUnwrap(light.light).intensity, 0)
        XCTAssertEqual(root.childNodes.filter { $0.geometry != nil }.count, originalGeometryCount)
        view.setPresentation(selected: .volumeUp, width: 345, reduceMotion: true)
        XCTAssertNil(light.action(forKey: "selectionFeedback"))
        XCTAssertEqual(try XCTUnwrap(light.light).intensity, 0)
    }

}
