import Foundation
import AppKit
import SceneKit
import Metal
import AVFoundation
import CoreVideo

struct SceneSpec: Decodable { let id: String; let start: Double; let end: Double; let eyebrow: String; let title: String; let subtitle: String }
struct RemoteKeyframe: Decodable { let time: Double; let x: Double; let y: Double; let width: Double; let yaw: Double; let registration: String?; let pitch: Double?; let roll: Double? }
struct Film: Decodable { let title: String; let width: Int; let height: Int; let fps: Int; let duration: Double; let scenes: [SceneSpec]; let proofTimes: [Double]; let keyTimes: [Double]; let remoteMotion: [RemoteKeyframe] }
let project = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
let promo = project.appendingPathComponent("promo/douyin")
let film = try JSONDecoder().decode(Film.self, from: Data(contentsOf: promo.appendingPathComponent("storyboard.json")))
let W = CGFloat(film.width), H = CGFloat(film.height)
let fm = FileManager.default
try fm.createDirectory(at: promo.appendingPathComponent("dist"), withIntermediateDirectories: true)
try fm.createDirectory(at: promo.appendingPathComponent(".build/keyframes"), withIntermediateDirectories: true)
let args = Array(CommandLine.arguments.dropFirst(2))
let previewOnly = args.contains("--preview")
let scale: CGFloat = args.contains("--draft") ? 0.5 : 1
let outW = Int(W * scale), outH = Int(H * scale)
let output = promo.appendingPathComponent(args.contains("--draft") ? ".build/draft-silent.mp4" : ".build/film-silent.mp4")
let cyan = NSColor(srgbRed: 0.23, green: 0.76, blue: 1, alpha: 1)
let voiceGreen = NSColor(srgbRed: 0.19, green: 0.82, blue: 0.35, alpha: 1)
let mint = NSColor(srgbRed: 0.19, green: 0.78, blue: 0.66, alpha: 1)
let lime = NSColor(srgbRed: 0.65, green: 0.92, blue: 0.35, alpha: 1)
let ink = NSColor(srgbRed: 0.025, green: 0.029, blue: 0.04, alpha: 1)
let muted = NSColor(srgbRed: 0.59, green: 0.67, blue: 0.75, alpha: 1)
let white = NSColor(srgbRed: 0.96, green: 0.98, blue: 1, alpha: 1)
func clamp(_ v: Double, _ a: Double = 0, _ b: Double = 1) -> Double { min(b,max(a,v)) }
func smooth(_ v: Double) -> Double { let x = clamp(v); return x*x*(3-2*x) }
func ease(_ v: Double) -> Double { 1-pow(1-clamp(v),3) }
func image(_ path: String) -> NSImage { guard let i=NSImage(contentsOf:project.appendingPathComponent(path)) else { fatalError("Missing asset: \(path)") }; return i }
let icon = image("Assets/Xvico-v2.png")
let fontName = "PingFangSC-Semibold"
func text(_ s: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat, color: NSColor = white, weight: NSFont.Weight = .semibold, align: NSTextAlignment = .left, tracking: CGFloat = 0) {
    let style = NSMutableParagraphStyle(); style.alignment=align;style.lineSpacing=size*0.14;style.lineBreakMode = .byWordWrapping
    let font = NSFont(name:fontName,size:size) ?? NSFont.systemFont(ofSize:size,weight:weight)
    let attrs: [NSAttributedString.Key:Any] = [.font:font,.foregroundColor:color,.paragraphStyle:style,.kern:tracking]
    NSAttributedString(string:s,attributes:attrs).draw(in:NSRect(x:x,y:y,width:width,height:H-y))
}
func latin(_ s:String,x:CGFloat,y:CGFloat,width:CGFloat,size:CGFloat,color:NSColor=white,weight:NSFont.Weight = .semibold,align:NSTextAlignment = .left) {
    let style=NSMutableParagraphStyle();style.alignment=align
    NSAttributedString(string:s,attributes:[.font:NSFont.systemFont(ofSize:size,weight:weight),.foregroundColor:color,.paragraphStyle:style]).draw(in:NSRect(x:x,y:y,width:width,height:size*1.5))
}
func rect(_ r: CGRect, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil, line: CGFloat = 1) {
    let p=NSBezierPath(roundedRect:r,xRadius:radius,yRadius:radius);fill.setFill();p.fill();if let stroke {stroke.setStroke();p.lineWidth=line;p.stroke()}
}
func line(_ a:CGPoint,_ b:CGPoint,color:NSColor,width:CGFloat=1) {let p=NSBezierPath();p.move(to:a);p.line(to:b);p.lineWidth=width;color.setStroke();p.stroke()}
func glow(_ ctx:CGContext,x:CGFloat,y:CGFloat,radius:CGFloat,color:NSColor,alpha:CGFloat) {
    let c=color.usingColorSpace(.deviceRGB)!;let colors=[c.withAlphaComponent(alpha).cgColor,c.withAlphaComponent(0).cgColor] as CFArray
    let gradient=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors,locations:[0,1])!
    ctx.drawRadialGradient(gradient,startCenter:CGPoint(x:x,y:y),startRadius:0,endCenter:CGPoint(x:x,y:y),endRadius:radius,options:[])
}
func drawImage(_ i:NSImage,_ r:CGRect,alpha:CGFloat=1){i.draw(in:r,from:.zero,operation:.sourceOver,fraction:alpha,respectFlipped:true,hints:[.interpolation:NSImageInterpolation.high])}
func panelImage(_ i:NSImage,_ r:CGRect,ctx:CGContext,radius:CGFloat=20){
    ctx.saveGState();ctx.setShadow(offset:CGSize(width:0,height:18),blur:45,color:NSColor.black.withAlphaComponent(0.45).cgColor);rect(r,radius:radius,fill:NSColor.white.withAlphaComponent(0.9));ctx.restoreGState()
    ctx.saveGState();NSBezierPath(roundedRect:r,xRadius:radius,yRadius:radius).addClip();drawImage(i,r);ctx.restoreGState()
    rect(r,radius:radius,fill:.clear,stroke:white.withAlphaComponent(0.24),line:1.5)
}
func pill(_ label:String,x:CGFloat,y:CGFloat,width:CGFloat,accent:Bool=false){rect(CGRect(x:x,y:y,width:width,height:48),radius:24,fill:accent ? cyan.withAlphaComponent(0.14) : white.withAlphaComponent(0.05),stroke:accent ? cyan.withAlphaComponent(0.45) : white.withAlphaComponent(0.13));text(label,x:x+12,y:y+11,width:width-24,size:20,color:accent ? cyan : muted,align:.center)}

final class RemoteRender {
    let renderer: SCNRenderer
    let turn = SCNNode()
    let asset: SCNNode
    var cache=[String:NSImage]()
    var cacheOrder=[String]()
    init() throws {
        let scene=try SCNScene(url:project.appendingPathComponent("Sources/XvicoApp/Resources/SiriRemote.usdz"),options:nil)
        guard let model=scene.rootNode.childNodes.first else {fatalError("Empty model")}
        asset=model
        model.removeFromParentNode(); model.eulerAngles=SCNVector3(Float.pi/2,0,0);turn.addChildNode(model);scene.rootNode.addChildNode(turn)
        let camera=SCNNode();camera.camera=SCNCamera();camera.camera!.usesOrthographicProjection=true;camera.camera!.orthographicScale=7.6;camera.camera!.zNear=0.1;camera.camera!.zFar=100;camera.position=SCNVector3(0,0,24);scene.rootNode.addChildNode(camera)
        for (type,intensity,angles) in [(SCNLight.LightType.ambient,CGFloat(350),SCNVector3(0,0,0)),(.directional,CGFloat(600),SCNVector3(-0.25,-0.3,0))] {let n=SCNNode();n.light=SCNLight();n.light!.type=type;n.light!.intensity=intensity;n.eulerAngles=angles;scene.rootNode.addChildNode(n)}
        scene.background.contents=NSColor.clear
        renderer=SCNRenderer(device:MTLCreateSystemDefaultDevice(),options:nil);renderer.scene=scene;renderer.pointOfView=camera
    }
    func anchor(u:CGFloat,v:CGFloat,side:Bool=false,in r:CGRect)->CGPoint {
        let b=asset.boundingBox
        let p=SCNVector3(b.min.x+(b.max.x-b.min.x)*u,side ? 0:b.max.y,b.min.z+(b.max.z-b.min.z)*v)
        let q=renderer.projectPoint(asset.convertPosition(p,to:nil))
        return CGPoint(x:r.minX+q.x/1200*r.width,y:r.minY+(1680-q.y)/1680*r.height)
    }
    func frame(yaw:Double,pitch:Double=0,roll:Double=0)->NSImage {
        let y=Int((yaw*180/Double.pi*8).rounded())
        let x=Int((pitch*180/Double.pi*8).rounded())
        let z=Int((roll*180/Double.pi*8).rounded())
        let index="\(x):\(y):\(z)"
        SCNTransaction.begin();SCNTransaction.disableActions=true
        turn.eulerAngles=SCNVector3(CGFloat(x)*CGFloat.pi/(180*8),CGFloat(y)*CGFloat.pi/(180*8),CGFloat(z)*CGFloat.pi/(180*8))
        SCNTransaction.commit()
        if let i=cache[index]{return i}
        let i=renderer.snapshot(atTime:0,with:CGSize(width:1200,height:1680),antialiasingMode:.multisampling4X)
        if cacheOrder.count>=48 {cache.removeValue(forKey:cacheOrder.removeFirst())}
        cache[index]=i;cacheOrder.append(index);return i
    }
}
let remote=try RemoteRender()
let violet=NSColor(srgbRed:0.48,green:0.35,blue:1,alpha:1)
func opacity(_ ctx:CGContext,_ alpha:Double,_ body:()->Void){guard alpha>0 else{return};ctx.saveGState();ctx.setAlpha(CGFloat(clamp(alpha)));ctx.beginTransparencyLayer(auxiliaryInfo:nil);ctx.setAlpha(1);body();ctx.endTransparencyLayer();ctx.restoreGState()}
func motionEase(_ v:Double)->Double {let p=clamp(v);return p*p*p*(p*(p*6-15)+10)}
func mix(_ a:CGFloat,_ b:CGFloat,_ p:Double)->CGFloat {a+(b-a)*CGFloat(clamp(p))}
func blendRect(_ a:CGRect,_ b:CGRect,_ p:Double)->CGRect {CGRect(x:mix(a.minX,b.minX,p),y:mix(a.minY,b.minY,p),width:mix(a.width,b.width,p),height:mix(a.height,b.height,p))}
func typed(_ s:String,_ p:Double)->String {String(s.prefix(Int(Double(s.count)*clamp(p))))}
struct RemotePose {let rect:CGRect;let yaw:Double;let pitch:Double;let roll:Double}
// Resolve alpha bounds only at authored keyframes; interpolate the full image
// rectangles and orientations together so no per-frame crop can produce a jump.
func alphaBounds(_ k:RemoteKeyframe)->CGRect {
    let rep=NSBitmapImageRep(data:remote.frame(yaw:k.yaw,pitch:k.pitch ?? 0,roll:k.roll ?? 0).tiffRepresentation!)!
    var minX=rep.pixelsWide,minY=rep.pixelsHigh,maxX=0,maxY=0
    for y in stride(from:0,to:rep.pixelsHigh,by:3) {for x in stride(from:0,to:rep.pixelsWide,by:3) {
        if (rep.colorAt(x:x,y:y)?.alphaComponent ?? 0)>0.15 {minX=min(minX,x);minY=min(minY,y);maxX=max(maxX,x);maxY=max(maxY,y)}
    }}
    return CGRect(x:CGFloat(minX)/CGFloat(rep.pixelsWide),y:CGFloat(minY)/CGFloat(rep.pixelsHigh),width:CGFloat(maxX-minX+3)/CGFloat(rep.pixelsWide),height:CGFloat(maxY-minY+3)/CGFloat(rep.pixelsHigh))
}
let poses:[RemotePose]=film.remoteMotion.map {k in
    let b=alphaBounds(k),h=CGFloat(k.width)/b.height,w=h/1.4
    return RemotePose(rect:CGRect(x:CGFloat(k.x)-b.midX*w,y:CGFloat(k.y)-b.midY*h,width:w,height:h),yaw:k.yaw,pitch:k.pitch ?? 0,roll:k.roll ?? 0)
}
func remotePose(_ t:Double)->RemotePose {
    let keys=film.remoteMotion,i=keys.lastIndex(where:{$0.time<=t}) ?? 0,j=min(i+1,keys.count-1)
    let p=keys[j].time>keys[i].time ? motionEase((t-keys[i].time)/(keys[j].time-keys[i].time)):0
    let a=poses[i],b=poses[j]
    return RemotePose(rect:blendRect(a.rect,b.rect,p),yaw:a.yaw+(b.yaw-a.yaw)*p,pitch:a.pitch+(b.pitch-a.pitch)*p,roll:a.roll+(b.roll-a.roll)*p)
}
let sidebar=image("promo/douyin/.build/sidebar.png")
let siri=image("promo/.build/app-plates/siri-focus.png")
let volume=image("promo/.build/app-plates/volume-focus.png")
let preset=image("promo/.build/app-plates/codex-preset-focus.png")
let voice=image("promo/.build/app-plates/voice-input-focus.png")
func glass(_ r:CGRect,_ ctx:CGContext,accent:NSColor=cyan){
    ctx.saveGState();ctx.setShadow(offset:CGSize(width:0,height:22),blur:55,color:accent.withAlphaComponent(0.09).cgColor)
    rect(r,radius:30,fill:NSColor(srgbRed:0.065,green:0.085,blue:0.13,alpha:0.94));ctx.restoreGState()
    let p=NSBezierPath(roundedRect:r,xRadius:30,yRadius:30)
    NSGradient(colors:[white.withAlphaComponent(0.08),white.withAlphaComponent(0.008),accent.withAlphaComponent(0.025)])!.draw(in:p,angle:80)
    rect(r,radius:30,fill:.clear,stroke:white.withAlphaComponent(0.17),line:1.3)
    line(CGPoint(x:r.minX+26,y:r.minY+1),CGPoint(x:r.maxX-26,y:r.minY+1),color:accent.withAlphaComponent(0.45),width:1)
}
func cornerMarks(_ r:CGRect,_ alpha:CGFloat=0.28){
    let l:CGFloat=20
    for (x,y,sx,sy) in [(r.minX,r.minY,1.0,1.0),(r.maxX,r.minY,-1.0,1.0),(r.minX,r.maxY,1.0,-1.0),(r.maxX,r.maxY,-1.0,-1.0)] {
        line(CGPoint(x:x,y:y),CGPoint(x:x+l*sx,y:y),color:cyan.withAlphaComponent(alpha),width:1.5)
        line(CGPoint(x:x,y:y),CGPoint(x:x,y:y+l*sy),color:cyan.withAlphaComponent(alpha),width:1.5)
    }
}
func background(_ ctx:CGContext,_ t:Double){
    NSColor(srgbRed:0.018,green:0.027,blue:0.055,alpha:1).setFill();NSRect(x:0,y:0,width:W,height:H).fill()
    glow(ctx,x:780+80*sin(t*0.13),y:920,radius:850,color:cyan,alpha:0.13)
    glow(ctx,x:140,y:1450,radius:750,color:violet,alpha:0.105)
    // Distant technical field; nothing is painted onto a physical button.
    for i in 0...14 {let x=CGFloat(i)*80-20;line(CGPoint(x:x,y:580),CGPoint(x:x,y:1640),color:cyan.withAlphaComponent(0.035))}
    for i in 0...13 {let y=600+CGFloat(i)*80;line(CGPoint(x:0,y:y),CGPoint(x:W,y:y),color:cyan.withAlphaComponent(0.035))}
    for i in 0..<30 {let q=(Double(i)*0.618033+t*0.014).truncatingRemainder(dividingBy:1);let x=CGFloat((i*173+39)%1020)+30,y=CGFloat(q)*1100+540;rect(CGRect(x:x,y:y,width:2,height:2),radius:1,fill:white.withAlphaComponent(0.18))}
    latin("Xvico",x:82,y:151,width:300,size:32,weight:.bold)
    latin("2026.10 / UPDATE",x:500,y:162,width:430,size:18,color:muted,weight:.medium,align:.right)
    line(CGPoint(x:82,y:217),CGPoint(x:930,y:217),color:white.withAlphaComponent(0.11))
    let progress=CGFloat(clamp(t/film.duration));line(CGPoint(x:82,y:217),CGPoint(x:82+848*progress,y:217),color:cyan.withAlphaComponent(0.65),width:2)
    latin("SIRI REMOTE × MAC",x:82,y:1740,width:500,size:17,color:muted,weight:.medium)
    latin("XPACO",x:740,y:1740,width:190,size:17,color:muted,weight:.medium,align:.right)
}
func heading(_ scene:SceneSpec,_ t:Double,_ ctx:CGContext){
    let a=smooth((t-scene.start)/0.45),offset=CGFloat(1-motionEase((t-scene.start)/0.65))*25
    opacity(ctx,a){latin(scene.eyebrow,x:86,y:263+offset,width:850,size:21,color:cyan,weight:.medium);text(scene.title,x:80,y:316+offset,width:865,size:86,tracking:-2)}
}
func wave(_ t:Double,_ r:CGRect,_ color:NSColor=voiceGreen){
    for i in 0..<52 {let q=Double(i)/51;let h=CGFloat(7+(Double(r.height)-7)*pow(sin(q*Double.pi),1.1)*abs(sin(Double(i)*0.51+t*8.8)));rect(CGRect(x:r.minX+CGFloat(q)*r.width,y:r.midY-h/2,width:5,height:h),radius:2.5,fill:color.withAlphaComponent(CGFloat(0.45+0.5*sin(q*Double.pi))))}
}
func connector(_ a:CGPoint,_ b:CGPoint,_ t:Double,_ ctx:CGContext,_ alpha:Double=1){
    opacity(ctx,alpha){
        let p=NSBezierPath();p.move(to:a);p.curve(to:b,controlPoint1:CGPoint(x:a.x+120,y:a.y+80),controlPoint2:CGPoint(x:b.x+100,y:b.y-130));voiceGreen.withAlphaComponent(0.2).setStroke();p.lineWidth=2;p.stroke()
        for i in 0..<14 {let q=(t*0.34+Double(i)/14).truncatingRemainder(dividingBy:1),u=1-q;let x=u*u*u*a.x+3*u*u*q*(a.x+120)+3*u*q*q*(b.x+100)+q*q*q*b.x,y=u*u*u*a.y+3*u*u*q*(a.y+80)+3*u*q*q*(b.y-130)+q*q*q*b.y;rect(CGRect(x:x-2,y:y-2,width:4,height:4),radius:2,fill:voiceGreen.withAlphaComponent(CGFloat(sin(q*Double.pi))*0.85))}
    }
}
func remoteView(_ pose:RemotePose,_ ctx:CGContext){
    let i=remote.frame(yaw:pose.yaw,pitch:pose.pitch,roll:pose.roll)
    ctx.saveGState();ctx.setShadow(offset:CGSize(width:8,height:22),blur:30,color:NSColor.black.withAlphaComponent(0.4).cgColor);drawImage(i,pose.rect);ctx.restoreGState()
}
let prompt="帮我做一个深色番茄钟网页，\n带开始、暂停和重置按钮。"
func stage(_ s:SceneSpec,_ t:Double,_ ctx:CGContext){
    let u=t-s.start
    heading(s,t,ctx)
    switch s.id {
    case "hero":
        latin("SPEAK. BUILD. ITERATE.",x:86,y:557,width:850,size:22,color:muted,weight:.medium)
        let ellipse=NSBezierPath(ovalIn:CGRect(x:170,y:1580,width:740,height:100));cyan.withAlphaComponent(0.20).setStroke();ellipse.lineWidth=1.5;ellipse.stroke()
        glow(ctx,x:540,y:1610,radius:380,color:cyan,alpha:0.12)
    case "glass":
        let r=CGRect(x:86,y:650+CGFloat(1-motionEase(u/0.75))*35,width:365,height:365*365/172)
        panelImage(sidebar,r,ctx:ctx,radius:30)
        cornerMarks(r.insetBy(dx:-12,dy:-12))
        text("玻璃侧栏 · 轻盈弹层",x:86,y:1490,width:830,size:33,color:muted)
        latin("A LIGHTER WAY TO CONTROL",x:86,y:1550,width:850,size:20,color:cyan,weight:.medium)
    case "focus":
        let change=smooth((t-10.1)/0.6),r=CGRect(x:80,y:665,width:455,height:455*384/347)
        opacity(ctx,1-change){panelImage(siri,r,ctx:ctx,radius:26)}
        opacity(ctx,change){panelImage(volume,CGRect(x:r.minX,y:r.minY,width:r.width,height:r.width*441/347),ctx:ctx,radius:26)}
        text(change<0.5 ? "Siri 键" : "音量键",x:85,y:1320,width:450,size:39,color:white)
        text("旋转 · 放大 · 精准聚焦",x:85,y:1387,width:550,size:28,color:muted)
    case "presets":
        let r=CGRect(x:505,y:785,width:425,height:425*129/299)
        panelImage(preset,r,ctx:ctx,radius:24)
        text("Codex 多任务",x:512,y:1040,width:420,size:37)
        text("外圈转动\n快速切换任务",x:512,y:1114,width:420,size:32,color:muted)
        rect(CGRect(x:512,y:1250,width:380,height:66),radius:18,fill:cyan.withAlphaComponent(0.08),stroke:cyan.withAlphaComponent(0.25))
        latin("⌘ 1   ⌘ 2   ⌘ 3  …",x:530,y:1266,width:350,size:26,color:cyan)
    case "voice":
        let r=CGRect(x:86,y:1435,width:844,height:844*248/688)
        opacity(ctx,1-smooth((u-1.1)/0.7)){panelImage(voice,r,ctx:ctx,radius:24)}
        opacity(ctx,smooth((u-1.0)/0.7)){
            glass(CGRect(x:86,y:1365,width:844,height:222),ctx,accent:voiceGreen)
            latin("VOICE INPUT",x:116,y:1394,width:680,size:20,color:voiceGreen)
            wave(t,CGRect(x:124,y:1450,width:760,height:80))
        }
        text("Siri Remote → 输入法",x:86,y:1640,width:830,size:28,color:muted)
    case "coding":
        let r=CGRect(x:82,y:1055,width:848,height:555)
        glass(r,ctx)
        latin("Codex",x:116,y:1090,width:380,size:34)
        latin("focus-timer",x:570,y:1100,width:320,size:20,color:muted,align:.right)
        line(CGPoint(x:115,y:1157),CGPoint(x:895,y:1157),color:white.withAlphaComponent(0.10))
        rect(CGRect(x:112,y:1188,width:788,height:165),radius:22,fill:white.withAlphaComponent(0.045),stroke:voiceGreen.withAlphaComponent(0.23))
        text(typed(prompt,(t-20.6)/2.3),x:138,y:1217,width:730,size:36)
        if u<2 {wave(t,CGRect(x:130,y:1377,width:740,height:55))}
        opacity(ctx,smooth((u-2)/0.5)){
            text("正在构建页面…",x:118,y:1392,width:730,size:31,color:cyan)
            latin("+ Timer / Controls / Dark theme",x:118,y:1460,width:750,size:24,color:muted)
            for i in 0..<3 {let width=CGFloat(360+(i%2)*200)*CGFloat(smooth((u-2.4-Double(i)*0.25)/0.7));rect(CGRect(x:118,y:1518+CGFloat(i)*22,width:width,height:5),radius:2.5,fill:cyan.withAlphaComponent(0.4-Double(i)*0.09))}
        }
    case "result":
        let r=CGRect(x:470,y:680,width:460,height:895)
        glass(r,ctx,accent:mint)
        latin("FOCUS",x:500,y:728,width:400,size:24,color:mint,align:.center)
        let p=NSBezierPath(ovalIn:CGRect(x:570,y:846,width:260,height:260));mint.withAlphaComponent(0.55).setStroke();p.lineWidth=4;p.stroke()
        latin("25:00",x:490,y:925,width:420,size:70,weight:.light,align:.center)
        for (i,label) in ["开始","暂停","重置"].enumerated(){let x:CGFloat=498+CGFloat(i)*137;rect(CGRect(x:x,y:1170,width:126,height:58),radius:16,fill:i==0 ? mint:white.withAlphaComponent(0.05));text(label,x:x,y:1186,width:126,size:25,color:i==0 ? ink:muted,align:.center)}
        text("今日任务",x:502,y:1310,width:380,size:31)
        for (i,label) in ["完成页面原型","继续下一轮迭代"].enumerated(){let y:CGFloat=1380+CGFloat(i)*58;rect(CGRect(x:502,y:y+8,width:19,height:19),radius:5,fill:mint.withAlphaComponent(0.10),stroke:mint.withAlphaComponent(0.6));text(label,x:542,y:y,width:350,size:26,color:muted)}
        text("「再加一个任务列表」",x:86,y:1620,width:840,size:32,color:voiceGreen)
    default:
        // The remote remains visible beside the brand through the final frame.
        opacity(ctx,smooth(u/0.6)){
            drawImage(icon,CGRect(x:86,y:750,width:150,height:150))
            latin("Xvico",x:80,y:947,width:510,size:116,weight:.bold)
            for (i,word) in ["SPEAK.","BUILD.","ITERATE."].enumerated(){latin(word,x:86,y:1140+CGFloat(i)*86,width:540,size:55,color:cyan,weight:.bold)}
            text("遥控器 × Mac × 你的创造力",x:86,y:1610,width:840,size:31,color:muted)
        }
    }
}
func render(_ t:Double,_ buffer:CVPixelBuffer){
    CVPixelBufferLockBaseAddress(buffer,[]);defer{CVPixelBufferUnlockBaseAddress(buffer,[])}
    let ctx=CGContext(data:CVPixelBufferGetBaseAddress(buffer),width:outW,height:outH,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(buffer),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.scaleBy(x:scale,y:scale);ctx.translateBy(x:0,y:H);ctx.scaleBy(x:1,y:-1)
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:ctx,flipped:true)
    background(ctx,t)
    let i=film.scenes.lastIndex(where:{$0.start<=t}) ?? 0,s=film.scenes[i]
    let enter=s.start==0 ? 1:smooth((t-s.start)/0.3),leave=s.id=="outro" ? 1:1-smooth((t-(s.end-0.25))/0.25)
    opacity(ctx,enter*leave){stage(s,t,ctx)}
    let pose=remotePose(t)
    // Exactly one product draw for every frame. No scene owns its lifecycle.
    remoteView(pose,ctx)
    if t>17.1 && t<23 {
        let a=remote.anchor(u:1,v:0.22,side:true,in:pose.rect)
        let p=motionEase((t-19.8)/1.5)
        let b=CGPoint(x:mix(770,735,p),y:mix(1450,1230,p))
        connector(a,b,t,ctx,smooth((t-17.1)/0.5)*(1-smooth((t-22.6)/0.4)))
    }
    text("交互与编程场景演示",x:86,y:1795,width:844,size:19,color:muted.withAlphaComponent(0.65),align:.center)
    NSGraphicsContext.restoreGraphicsState()
}
func newBuffer()->CVPixelBuffer {var b:CVPixelBuffer?;CVPixelBufferCreate(nil,outW,outH,kCVPixelFormatType_32BGRA,[kCVPixelBufferCGImageCompatibilityKey:true,kCVPixelBufferCGBitmapContextCompatibilityKey:true] as CFDictionary,&b);return b!}
func saveFrame(_ t:Double,_ path:URL){let b=newBuffer();render(t,b);let ci=CIImage(cvPixelBuffer:b);let cg=CIContext().createCGImage(ci,from:ci.extent)!;let rep=NSBitmapImageRep(cgImage:cg);try! rep.representation(using:.png,properties:[:])!.write(to:path)}

if args.contains("--verify-motion") {
    var maxStep=0.0,maxScale=0.0,maxAngle=0.0
    var previous=remotePose(0)
    for f in 1..<Int(film.duration*Double(film.fps)) {
        let pose=remotePose(Double(f)/Double(film.fps))
        maxStep=max(maxStep,hypot(Double(pose.rect.midX-previous.rect.midX),Double(pose.rect.midY-previous.rect.midY)))
        maxScale=max(maxScale,abs(Double(pose.rect.width-previous.rect.width)))
        maxAngle=max(maxAngle,max(abs(pose.yaw-previous.yaw),max(abs(pose.pitch-previous.pitch),abs(pose.roll-previous.roll))))
        precondition(pose.rect.width>0 && pose.rect.intersects(CGRect(x:0,y:0,width:W,height:H)))
        previous=pose
    }
    precondition(maxStep<22 && maxScale<10 && maxAngle<0.04,"Unexpected product motion discontinuity")
    var bounds=[[String:Any]]()
    for t in film.keyTimes+film.proofTimes+[0,film.duration-1/Double(film.fps)] {
        let p=remotePose(t),k=RemoteKeyframe(time:t,x:0,y:0,width:1,yaw:p.yaw,registration:nil,pitch:p.pitch,roll:p.roll)
        let b=alphaBounds(k),visible=CGRect(x:p.rect.minX+b.minX*p.rect.width,y:p.rect.minY+b.minY*p.rect.height,width:b.width*p.rect.width,height:b.height*p.rect.height)
        precondition(visible.minX>=35 && visible.maxX<=1010 && visible.minY>=570 && visible.maxY<=1695,"Visible remote clipped or overlaps main heading: \(t) \(visible)")
        bounds.append(["time":t,"x":visible.minX,"y":visible.minY,"width":visible.width,"height":visible.height])
    }
    let report:[String:Any]=["passed":true,"maxImageCenterPixelsPerFrame":maxStep,"maxImageWidthPixelsPerFrame":maxScale,"maxAngleRadiansPerFrame":maxAngle,"persistentRemoteThroughSeconds":film.duration,"remoteDrawLayersPerFrame":1,"curve":"quintic; one continuous image rect and orientation track; no per-scene lifecycle","sampledVisibleBounds":bounds]
    let data=try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]);try data.write(to:promo.appendingPathComponent("dist/motion-verification.json"));print("MOTION_OK step=\(maxStep) scale=\(maxScale) angle=\(maxAngle)");exit(0)
}
if previewOnly {
    for (i,t) in film.keyTimes.enumerated() {saveFrame(t,promo.appendingPathComponent(".build/keyframes/\(i)-\(film.scenes[i].id).png"));print("PREVIEW \(i) \(t)")}
    for (i,t) in film.proofTimes.enumerated() {saveFrame(t,promo.appendingPathComponent(".build/keyframes/proof-\(String(format:"%02d",i)).png"))}
    saveFrame(1.7,promo.appendingPathComponent("dist/Xvico-cover-9x16.png"));exit(0)
}
try? fm.removeItem(at:output)
let writer=try AVAssetWriter(outputURL:output,fileType:.mp4)
let settings:[String:Any]=[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:outW,AVVideoHeightKey:outH,AVVideoCompressionPropertiesKey:[AVVideoAverageBitRateKey:Int(12_000_000*scale*scale),AVVideoProfileLevelKey:AVVideoProfileLevelH264HighAutoLevel,AVVideoExpectedSourceFrameRateKey:film.fps,AVVideoMaxKeyFrameIntervalKey:film.fps*2]]
let input=AVAssetWriterInput(mediaType:.video,outputSettings:settings);input.expectsMediaDataInRealTime=false
let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,kCVPixelBufferWidthKey as String:outW,kCVPixelBufferHeightKey as String:outH])
writer.add(input);guard writer.startWriting() else {fatalError("Writer start: \(String(describing:writer.error))")};writer.startSession(atSourceTime:.zero)
let frames=Int(film.duration*Double(film.fps))
for f in 0..<frames {
    autoreleasepool {
        while !input.isReadyForMoreMediaData {Thread.sleep(forTimeInterval:0.002)}
        var b:CVPixelBuffer?;CVPixelBufferPoolCreatePixelBuffer(nil,adaptor.pixelBufferPool!,&b)
        render(Double(f)/Double(film.fps),b!)
        guard adaptor.append(b!,withPresentationTime:CMTime(value:Int64(f),timescale:Int32(film.fps))) else {fatalError("Append: \(String(describing:writer.error))")}
    }
    if f%90==0 {print("RENDER \(f)/\(frames)");fflush(stdout)}
}
input.markAsFinished();let done=DispatchSemaphore(value:0);writer.finishWriting{done.signal()};done.wait()
guard writer.status == .completed else {fatalError("Finish: \(String(describing:writer.error))")}
print("VIDEO_OK \(output.path)")
