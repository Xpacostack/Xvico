import SwiftUI
import SceneKit

struct RemoteDrawing: NSViewRepresentable {
    @Environment(\.locale) private var locale
    let selected: RemoteKey?
    var editorWidth: CGFloat = 345
    let onSelect: (RemoteKey) -> Void

    func makeNSView(context: Context) -> RemoteSceneView {
        let view = RemoteSceneView()
        view.onSelect = onSelect
        view.loadModel()
        return view
    }
    func updateNSView(_ view: RemoteSceneView, context: Context) {
        view.onSelect = onSelect
        view.setEditorLayout(open: selected != nil, width: editorWidth)
        view.setAccessibilityHelp(XvicoLocalization.string("左右拖动可完整旋转到背面，松手自动回正；点击实际按键编辑映射", locale: locale))
    }
}

// Use the actual USDZ surface intersection, in model coordinates. A screen-space
// button overlay would drift as soon as the remote turns or the panel opens.
final class RemoteSceneView: SCNView {
    var onSelect: ((RemoteKey) -> Void)?
    private var assetRoot: SCNNode?
    private var camera: SCNCamera?
    private var editorOpen = false
    private var editorWidth: CGFloat = 345
    private let turntable = SCNNode()
    private var startPoint = NSPoint.zero
    private var startYaw: CGFloat = -0.06
    private var dragged = false
    private static let restingYaw: CGFloat = -0.06

    func loadModel() {
        guard let url = Bundle.module.url(forResource: "SiriRemote", withExtension: "usdz"),
              let scene = try? SCNScene(url: url, options: nil),
              let model = scene.rootNode.childNodes.first else { return }
        model.removeFromParentNode()
        model.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        turntable.name = "remoteTurntable"
        turntable.addChildNode(model)
        turntable.eulerAngles.y = startYaw
        scene.rootNode.addChildNode(turntable)
        assetRoot = model
        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = 7.5
        camera.zNear = 0.1
        camera.zFar = 100
        self.camera = camera
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 24)
        scene.rootNode.addChildNode(cameraNode)
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 350
        scene.rootNode.addChildNode(ambient)
        let light = SCNNode()
        light.light = SCNLight()
        light.light?.type = .directional
        light.light?.intensity = 600
        light.eulerAngles = SCNVector3(-0.25, -0.3, 0)
        scene.rootNode.addChildNode(light)
        backgroundColor = .clear
        scene.background.contents = NSColor.clear
        self.scene = scene
        pointOfView = cameraNode
        antialiasingMode = .multisampling4X
        autoenablesDefaultLighting = false
        allowsCameraControl = false
        isPlaying = true
        setAccessibilityLabel("Siri Remote 3D model")
        setAccessibilityHelp("左右拖动可完整旋转到背面，松手自动回正；点击实际按键编辑映射")
    }

    override func mouseDown(with event: NSEvent) {
        // A new drag starts from what is currently visible, including halfway
        // through the return animation.
        let visibleYaw = turntable.presentation.eulerAngles.y
        turntable.removeAction(forKey: "returnToFront")
        turntable.eulerAngles.y = visibleYaw
        startPoint = convert(event.locationInWindow, from: nil)
        startYaw = turntable.eulerAngles.y
        dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let distance = hypot(point.x - startPoint.x, point.y - startPoint.y)
        guard distance > 4 || dragged else { return }
        dragged = true
        let yaw = startYaw + (point.x - startPoint.x) * 0.012
        turntable.eulerAngles.y = yaw.truncatingRemainder(dividingBy: .pi * 2)
    }
    override func mouseUp(with event: NSEvent) {
        if dragged {
            let action = SCNAction.rotateTo(x: 0, y: Self.restingYaw, z: 0, duration: 0.32, usesShortestUnitArc: true)
            action.timingMode = .easeOut
            turntable.runAction(action, forKey: "returnToFront")
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - startPoint.x, point.y - startPoint.y) <= 4 else { return }
        if let key = selectableKey(at: point) { onSelect?(key) }
    }

    func setEditorLayout(open: Bool, width: CGFloat) {
        let changed = open != editorOpen || width != editorWidth
        editorOpen = open; editorWidth = width
        updateModelLayout(animated: changed)
    }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateModelLayout(animated: false)
    }
    private func updateModelLayout(animated: Bool) {
        guard let camera, bounds.height > 0 else { return }
        let scale = editorOpen ? 7.10 : 7.50
        let shift = editorOpen ? (editorWidth + 24) / 2 : 0
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.30 : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        camera.orthographicScale = scale
        turntable.position.x = shift * CGFloat(scale * 2) / bounds.height
        SCNTransaction.commit()
    }

    // Expanded hit targets are projected from the actual model, rather than
    // fixed overlays. They follow yaw, camera zoom, and editor movement.
    func selectableKey(at point: NSPoint) -> RemoteKey? {
        guard let root = assetRoot else { return nil }
        let frontNormal = root.presentation.convertVector(SCNVector3(0, 1, 0), to: nil)
        let sideNormal = root.presentation.convertVector(SCNVector3(1, 0, 0), to: nil)
        let frontVisible = frontNormal.z > 0.08
        if let hit = hitTest(point, options: [.rootNode: root, .searchMode: SCNHitTestSearchMode.closest.rawValue]).first {
            let local = root.presentation.convertPosition(hit.worldCoordinates, from: nil)
            if let key = Self.key(at: local, bounds: root.boundingBox),
               key == .voice ? sideNormal.z > 0.05 : frontVisible { return key }
        }
        let b = root.boundingBox
        let anchors: [(RemoteKey, CGFloat, CGFloat)] = [
            (.power, 0.80, 0.05), (.center, 0.50, 0.21),
            (.touchUp, 0.50, 0.10), (.touchDown, 0.50, 0.32),
            (.touchLeft, 0.10, 0.21), (.touchRight, 0.90, 0.21),
            (.menu, 0.285, 0.377), (.tv, 0.715, 0.377),
            (.playPause, 0.285, 0.487), (.mute, 0.285, 0.596),
            (.volumeUp, 0.715, 0.487), (.volumeDown, 0.715, 0.596)
        ]
        var nearest: (key: RemoteKey, distance: CGFloat)?
        for (key, x, y) in anchors where frontVisible {
            let p = SCNVector3(b.min.x + (b.max.x - b.min.x) * x, b.max.y,
                              b.min.z + (b.max.z - b.min.z) * y)
            let projected = projectPoint(root.presentation.convertPosition(p, to: nil))
            let d = hypot(point.x - projected.x, point.y - projected.y)
            if d <= 22 && (nearest == nil || d < nearest!.distance) { nearest = (key, d) }
        }
        if sideNormal.z >= -0.10 {
            func sidePoint(_ y: CGFloat) -> NSPoint {
                let p = SCNVector3(b.max.x, 0, b.min.z + (b.max.z - b.min.z) * y)
                let projected = projectPoint(root.presentation.convertPosition(p, to: nil))
                return NSPoint(x: projected.x, y: projected.y)
            }
            let d = Self.distance(point, toSegmentFrom: sidePoint(0.16), to: sidePoint(0.28))
            if d <= 14 && (nearest == nil || d < nearest!.distance) { nearest = (.voice, d) }
        }
        return nearest?.key
    }
    static func distance(_ p: NSPoint, toSegmentFrom a: NSPoint, to b: NSPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let length2 = dx * dx + dy * dy
        let t = length2 > 0 ? min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / length2)) : 0
        return hypot(p.x - a.x - t * dx, p.y - a.y - t * dy)
    }

    static func key(at p: SCNVector3, bounds: (min: SCNVector3, max: SCNVector3)) -> RemoteKey? {
        let width = bounds.max.x - bounds.min.x
        let height = bounds.max.z - bounds.min.z
        let x = (p.x - bounds.min.x) / width
        let y = (p.z - bounds.min.z) / height
        // The Siri key is a separate side surface in this model.
        if x > 0.975 && y > 0.14 && y < 0.30 { return .voice }
        guard p.y > 0.05 else { return nil }
        func circle(_ cx: CGFloat, _ cy: CGFloat, _ radius: CGFloat) -> Bool {
            hypot(x - cx, (y - cy) * height / width) < radius
        }
        if circle(0.80, 0.05, 0.105) { return .power }
        if circle(0.50, 0.21, 0.455) {
            if circle(0.50, 0.21, 0.24) { return .center }
            let dx = x - 0.50
            let dy = (y - 0.21) * height / width
            if abs(dx) > abs(dy) { return dx < 0 ? .touchLeft : .touchRight }
            return dy < 0 ? .touchUp : .touchDown
        }
        if circle(0.285, 0.377, 0.19) { return .menu }
        if circle(0.715, 0.377, 0.19) { return .tv }
        if circle(0.285, 0.487, 0.19) { return .playPause }
        if circle(0.285, 0.596, 0.19) { return .mute }
        if x > 0.53 && x < 0.90 && y > 0.44 && y < 0.644 {
            return y < 0.543 ? .volumeUp : .volumeDown
        }
        return nil
    }
}
