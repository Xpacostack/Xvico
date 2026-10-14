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
}
