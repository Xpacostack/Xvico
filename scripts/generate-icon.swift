import AppKit
import SceneKit
import Metal
import Foundation

// Render the reused SiriRemote.usdz, with the user's original RGBA X artwork
// as a material. No paths, contours, or colors of the locked symbol are redrawn.
let project = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let output = project.appendingPathComponent("Assets", isDirectory: true)
let modelURL = project.appendingPathComponent("Sources/XvicoApp/Resources/SiriRemote.usdz")
let symbolURL = output.appendingPathComponent("XPaco_X_Symbol_Color_Master_1254.png")
let scene = try SCNScene(url: modelURL)
let model = scene.rootNode.childNodes.first!
let b = model.boundingBox
model.removeFromParentNode()
model.eulerAngles.x = .pi / 2
let pose = SCNNode()
pose.eulerAngles = SCNVector3(0, -0.38, -0.10)
pose.position.x = -0.35
pose.addChildNode(model)
scene.rootNode.addChildNode(pose)
let symbol = SCNPlane(width: 1.65, height: 1.65)
let material = SCNMaterial()
material.lightingModel = .constant
material.diffuse.contents = NSImage(contentsOf: symbolURL)!
material.isDoubleSided = false
material.writesToDepthBuffer = true
symbol.materials = [material]
let logo = SCNNode(geometry: symbol)
logo.eulerAngles.x = -.pi / 2
logo.position = SCNVector3((b.min.x + b.max.x) / 2, b.max.y + 0.006, b.min.z + (b.max.z - b.min.z) * 0.21)
model.addChildNode(logo)
let cameraNode = SCNNode()
let camera = SCNCamera()
camera.fieldOfView = 17
camera.zNear = 0.1; camera.zFar = 100
camera.wantsHDR = true
camera.wantsExposureAdaptation = false
camera.exposureOffset = -0.55
camera.bloomIntensity = 0.05
camera.screenSpaceAmbientOcclusionIntensity = 0.8
cameraNode.camera = camera
cameraNode.position = SCNVector3(0, 3.8, 24)
scene.rootNode.addChildNode(cameraNode)
func light(_ type: SCNLight.LightType, intensity: CGFloat, position: SCNVector3, angle: SCNVector3, temperature: CGFloat) {
    let node=SCNNode(); let light=SCNLight()
    light.type=type; light.intensity=intensity; light.temperature=temperature
    node.light=light; node.position=position; node.eulerAngles=angle
    scene.rootNode.addChildNode(node)
}
light(.ambient, intensity: 240, position: SCNVector3(0,0,0), angle: SCNVector3(0,0,0), temperature: 6500)
light(.directional, intensity: 750, position: SCNVector3(-6,12,15), angle: SCNVector3(-0.45,-0.45,0), temperature: 6100)
light(.directional, intensity: 270, position: SCNVector3(7,8,10), angle: SCNVector3(-0.3,0.65,0), temperature: 7800)
scene.background.contents = NSColor.clear
let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
renderer.scene=scene; renderer.pointOfView=cameraNode
let rendered = renderer.snapshot(atTime: 0, with: CGSize(width: 1024, height: 1024), antialiasingMode: .multisampling4X)
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(calibratedRed: r, green: g, blue: b, alpha: a) }
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 4096, bitsPerPixel: 32)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let tile = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 188, yRadius: 188)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow(); shadow.shadowColor = .black.withAlphaComponent(0.25); shadow.shadowBlurRadius = 18; shadow.shadowOffset = NSSize(width: 0, height: -8); shadow.set()
color(0.96,0.98,1).setFill(); tile.fill()
NSGraphicsContext.restoreGraphicsState()
tile.addClip()
NSGradient(colors:[color(0.99,0.995,1),color(0.88,0.93,0.98)])!.draw(in:tile,angle:-55)
color(0.48,0.75,0.95,0.12).setFill(); NSBezierPath(ovalIn:NSRect(x:130,y:180,width:740,height:700)).fill()
for i in 0..<2 {
    let path=NSBezierPath(); path.appendArc(withCenter:NSPoint(x:750,y:645),radius:CGFloat(86+i*41),startAngle:-8,endAngle:110)
    color(0.2,0.7,0.73,CGFloat(0.17-Double(i)*0.04)).setStroke(); path.lineWidth=5; path.stroke()
}
let wave=NSBezierPath();wave.move(to:NSPoint(x:725,y:356))
for i in 0...68 { let amplitude=34*exp(-pow((Double(i)-30)/22,2)); wave.line(to:NSPoint(x:725+CGFloat(i)*3.8,y:356+CGFloat(sin(Double(i)*0.55)*amplitude))) }
color(0.12,0.68,0.59,0.5).setStroke();wave.lineWidth=3;wave.stroke()
let objectShadow=NSShadow();objectShadow.shadowColor = .black.withAlphaComponent(0.23);objectShadow.shadowBlurRadius=20;objectShadow.shadowOffset=NSSize(width:12,height:-8);objectShadow.set()
rendered.draw(in:NSRect(x:0,y:0,width:1024,height:1024),from:.zero,operation:.sourceOver,fraction:1)
NSGraphicsContext.restoreGraphicsState()
let png=rep.representation(using:.png,properties:[:])!
try png.write(to:output.appendingPathComponent("Xvico-v2.png"))
try png.write(to:output.appendingPathComponent("Xvico.png"))
let master=NSImage(data:png)!
let iconset=output.appendingPathComponent("Xvico.iconset",isDirectory:true)
try FileManager.default.createDirectory(at:iconset,withIntermediateDirectories:true)
for size in [16,32,128,256,512] {
 for scale in [1,2] {
    let pixels=size*scale
    let r=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:pixels*4,bitsPerPixel:32)!
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:r)
    NSGraphicsContext.current?.imageInterpolation = .high
    master.draw(in:NSRect(x:0,y:0,width:pixels,height:pixels),from:.zero,operation:.copy,fraction:1)
    NSGraphicsContext.restoreGraphicsState()
    let suffix=scale==2 ? "@2x" : ""
    try r.representation(using:.png,properties:[:])!.write(to:iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
 }
}
print("Rendered actual USDZ and original X symbol into Xvico-v2.png and iconset")
