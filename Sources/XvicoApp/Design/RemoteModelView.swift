import SwiftUI
import SceneKit

struct RemoteDrawing: NSViewRepresentable {
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        view.setPresentation(selected: selected, width: editorWidth, reduceMotion: reduceMotion)
        view.setAccessibilityHelp(XvicoLocalization.string("左右拖动可完整旋转到背面，松手自动回正；点击实际按键编辑映射", locale: locale))
    }
}

// Use the actual USDZ surface intersection, in model coordinates. A screen-space
// button overlay would drift as soon as the remote turns or the panel opens.
final class RemoteSceneView: SCNView {
    var onSelect: ((RemoteKey) -> Void)?
    private var assetRoot: SCNNode?
    private var surfaceBounds: (min: SCNVector3, max: SCNVector3)?
    private var camera: SCNCamera?
    private var editorOpen = false
    private var editorWidth: CGFloat = 345
    private(set) var focusedKey: RemoteKey?
    private var reduceMotion = false
    private let focusLightNode = SCNNode()
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
        surfaceBounds = model.boundingBox
        // Selection feedback is real illumination, never visible hit geometry.
        focusLightNode.name = "selectionSurfaceLight"
        let focusLight = SCNLight()
        focusLight.type = .omni
        focusLight.color = NSColor(white: 1, alpha: 1)
        focusLight.intensity = 0
        focusLight.attenuationStartDistance = 0
        focusLight.attenuationEndDistance = (model.boundingBox.max.x - model.boundingBox.min.x) * 0.65
        focusLightNode.light = focusLight
        model.addChildNode(focusLightNode)
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
        // Match the actual GPU's sample support rather than assuming 8x MSAA
        // is available on every Apple Silicon / Intel device.
        antialiasingMode = device?.supportsTextureSampleCount(8) == true ? .multisampling8X : .multisampling4X
        // SceneKit's temporal history can resolve a clear drawable to opaque
        // black in SwiftUI. Use high-density MSAA without that history buffer.
        isTemporalAntialiasingEnabled = false
        wantsBestResolutionOpenGLSurface = true
        updateRenderScale()
        autoenablesDefaultLighting = false
        allowsCameraControl = false
        isPlaying = true
        setAccessibilityLabel("Siri Remote 3D model")
        setAccessibilityHelp("左右拖动可完整旋转到背面，松手自动回正；点击实际按键编辑映射")
    }

    override func mouseDown(with event: NSEvent) {
        // A new drag starts from what is currently visible, including halfway
        // through the return animation.
        let visibleAngles = turntable.presentation.eulerAngles
        turntable.removeAction(forKey: "returnToFront")
        turntable.removeAnimation(forKey: "eulerAngles")
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        turntable.eulerAngles = visibleAngles
        SCNTransaction.commit()
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
            returnToFocusedPose()
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - startPoint.x, point.y - startPoint.y) <= 4 else {
            returnToFocusedPose()
            return
        }
        if let key = selectableKey(at: point) { onSelect?(key) }
        returnToFocusedPose()
    }

    // Kept for layout-only callers. Selection, framing and accessibility all
    // use the single presentation entry point in the SwiftUI bridge.
    func setEditorLayout(open: Bool, width: CGFloat) {
        let changed = open != editorOpen || width != editorWidth
        editorOpen = open; editorWidth = width
        updateModelLayout(animated: changed)
    }

    func setPresentation(selected: RemoteKey?, width: CGFloat, reduceMotion: Bool) {
        guard selected != focusedKey || width != editorWidth || reduceMotion != self.reduceMotion else { return }
        let visibleAngles = turntable.presentation.eulerAngles
        turntable.removeAction(forKey: "returnToFront")
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        turntable.eulerAngles = visibleAngles
        SCNTransaction.commit()
        let selectionChanged = selected != focusedKey || reduceMotion != self.reduceMotion
        self.reduceMotion = reduceMotion
        focusedKey = selected
        editorOpen = selected != nil
        editorWidth = width
        if selectionChanged { updateFocusFeedback() }
        updateModelLayout(animated: true)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateModelLayout(animated: false, applyPose: false)
    }

    private var focusAngles: SCNVector3 {
        guard let focusedKey, !reduceMotion else { return SCNVector3(0, Self.restingYaw, 0) }
        // Positive model X is the Siri side. A negative yaw turns it toward
        // the camera; all face keys retain a clear front surface.
        switch focusedKey {
        case .voice, .siriHold: return SCNVector3(-0.06, -0.58, -0.10)
        case .power: return SCNVector3(0.08, -0.22, -0.05)
        case .menu: return SCNVector3(0.02, 0.12, 0.035)
        case .tv: return SCNVector3(0.02, -0.20, -0.035)
        case .playPause: return SCNVector3(-0.035, 0.12, 0.025)
        case .mute: return SCNVector3(-0.065, 0.12, 0.025)
        case .volumeUp: return SCNVector3(-0.025, -0.20, -0.025)
        case .volumeDown: return SCNVector3(-0.065, -0.20, -0.025)
        case .touchUp: return SCNVector3(0.07, Self.restingYaw, 0)
        case .touchDown: return SCNVector3(-0.07, Self.restingYaw, 0)
        case .touchLeft: return SCNVector3(0, 0.12, 0.025)
        case .touchRight: return SCNVector3(0, -0.20, -0.025)
        case .center: return SCNVector3(0, Self.restingYaw, 0)
        default: return SCNVector3(0, Self.restingYaw, 0)
        }
    }

    private func returnToFocusedPose() {
        let target = focusAngles
        if reduceMotion { turntable.eulerAngles = target; return }
        let action = SCNAction.rotateTo(x: target.x, y: target.y, z: target.z, duration: 0.38, usesShortestUnitArc: true)
        action.timingMode = .easeInEaseOut
        turntable.runAction(action, forKey: "returnToFront")
    }

    private func updateModelLayout(animated: Bool, applyPose: Bool = true) {
        guard let camera, bounds.height > 0 else { return }
        // Preserve the original resting size in the larger, stable viewport.
        let restingScale = 7.5 * max(1, bounds.height / 565)
        let scale: Double = reduceMotion ? (editorOpen ? 7.10 : restingScale)
            : focusedKey != nil ? (focusedKey == .voice ? 7.15 : 7.08) : (editorOpen ? 7.10 : restingScale)
        let shift = editorOpen ? (editorWidth + 24) / 2 : 0
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated && !reduceMotion ? 0.46 : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        if camera.orthographicScale != scale { camera.orthographicScale = scale }
        turntable.position.x = shift * CGFloat(scale * 2) / bounds.height
        if applyPose { turntable.eulerAngles = focusAngles }
        SCNTransaction.commit()
    }

    private static let frontAnchors: [(RemoteKey, CGFloat, CGFloat)] = [
        (.power, 0.80, 0.05), (.center, 0.50, 0.21),
        (.touchUp, 0.50, 0.10), (.touchDown, 0.50, 0.32),
        (.touchLeft, 0.10, 0.21), (.touchRight, 0.90, 0.21),
        (.menu, 0.285, 0.377), (.tv, 0.715, 0.377),
        (.playPause, 0.285, 0.487), (.mute, 0.285, 0.596),
        (.volumeUp, 0.715, 0.487), (.volumeDown, 0.715, 0.596)
    ]

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateRenderScale()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateRenderScale()
    }

    override var isOpaque: Bool { false }

    private func updateRenderScale() {
        // Keep the Metal backing sharp, including on 1x external displays.
        // This changes raster density only, not layout or model hit coordinates.
        let renderScale = max(2, window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.contentsScale = renderScale
        layer?.minificationFilter = .trilinear
        layer?.magnificationFilter = .linear
    }

    private func updateFocusFeedback() {
        focusLightNode.removeAction(forKey: "selectionFeedback")
        focusLightNode.light?.intensity = 0
        guard let root = assetRoot, let key = focusedKey, !reduceMotion else { return }
        let b = surfaceBounds ?? root.boundingBox
        let width = b.max.x - b.min.x
        let length = b.max.z - b.min.z
        if key == .voice || key == .siriHold {
            focusLightNode.position = SCNVector3(b.max.x + width * 0.16, (b.min.y + b.max.y) / 2,
                                               b.min.z + length * 0.22)
        } else if let (_, x, y) = Self.frontAnchors.first(where: { $0.0 == key }) {
            focusLightNode.position = SCNVector3(b.min.x + width * x, b.max.y + width * 0.20,
                                               b.min.z + length * y)
        } else { return }
        // One gentle reflection after the turn starts, then back to the exact
        // original lighting. No looping pulse, outline, overlay or geometry.
        let glint = SCNAction.customAction(duration: 0.44) { node, elapsed in
            let envelope = sin(CGFloat.pi * min(1, elapsed / 0.44))
            node.light?.intensity = 16 * envelope * envelope
        }
        focusLightNode.runAction(.sequence([.wait(duration: 0.22), glint, .run { node in
            node.light?.intensity = 0
        }]), forKey: "selectionFeedback")
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
            if let key = Self.key(at: local, bounds: surfaceBounds ?? root.boundingBox),
               key == .voice ? sideNormal.z > 0.05 : frontVisible { return key }
        }
        let b = surfaceBounds ?? root.boundingBox
        var nearest: (key: RemoteKey, distance: CGFloat)?
        for (key, x, y) in Self.frontAnchors where frontVisible {
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
