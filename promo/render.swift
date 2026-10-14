import Foundation
import AppKit
import SceneKit
import Metal
import AVFoundation
import CoreVideo

struct SceneSpec: Decodable { let id: String; let start: Double; let end: Double; let eyebrow: String; let title: String; let subtitle: String }
struct RemoteKeyframe: Decodable { let time: Double; let x: Double; let y: Double; let width: Double; let yaw: Double; let registration: String? }
struct Film: Decodable { let title: String; let width: Int; let height: Int; let fps: Int; let duration: Double; let scenes: [SceneSpec]; let proofTimes: [Double]; let keyTimes: [Double]; let remoteMotion: [RemoteKeyframe] }
let project = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
let promo = project.appendingPathComponent("promo")
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
let cyan = NSColor(srgbRed: 0.23, green: 0.89, blue: 0.91, alpha: 1)
let lime = NSColor(srgbRed: 0.65, green: 0.92, blue: 0.35, alpha: 1)
let ink = NSColor(srgbRed: 0.025, green: 0.045, blue: 0.085, alpha: 1)
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
    var cache=[Int:NSImage]()
    init() throws {
        let scene=try SCNScene(url:project.appendingPathComponent("Sources/XvicoApp/Resources/SiriRemote.usdz"),options:nil)
        guard let model=scene.rootNode.childNodes.first else {fatalError("Empty model")}
        asset=model
        model.removeFromParentNode(); model.eulerAngles=SCNVector3(Float.pi/2,0,0);turn.addChildNode(model);scene.rootNode.addChildNode(turn)
        let camera=SCNNode();camera.camera=SCNCamera();camera.camera!.usesOrthographicProjection=true;camera.camera!.orthographicScale=7.6;camera.camera!.zNear=0.1;camera.camera!.zFar=100;camera.position=SCNVector3(0,0,24);scene.rootNode.addChildNode(camera)
        for (type,intensity,angles) in [(SCNLight.LightType.ambient,CGFloat(400),SCNVector3(0,0,0)),(.directional,CGFloat(800),SCNVector3(-0.25,-0.4,0))] {let n=SCNNode();n.light=SCNLight();n.light!.type=type;n.light!.intensity=intensity;n.eulerAngles=angles;scene.rootNode.addChildNode(n)}
        scene.background.contents=NSColor.clear
        renderer=SCNRenderer(device:MTLCreateSystemDefaultDevice(),options:nil);renderer.scene=scene;renderer.pointOfView=camera
    }
    func anchor(u:CGFloat,v:CGFloat,side:Bool=false,in r:CGRect)->CGPoint {
        let b=asset.boundingBox
        let p=SCNVector3(b.min.x+(b.max.x-b.min.x)*u,side ? 0:b.max.y,b.min.z+(b.max.z-b.min.z)*v)
        let q=renderer.projectPoint(asset.convertPosition(p,to:nil))
        return CGPoint(x:r.minX+(q.x-(side ? 12:0))/600*r.width,y:r.minY+(840-q.y)/840*r.height)
    }
    func frame(yaw:Double)->NSImage {
        let index=Int((yaw*180/Double.pi*8).rounded())
        // Update geometry even on cached frames so projected button anchors follow the current pose.
        SCNTransaction.begin();SCNTransaction.animationDuration=0;turn.eulerAngles.y=CGFloat(index)*CGFloat.pi/(180*8);SCNTransaction.commit()
        if let i=cache[index]{return i}
        let i=renderer.snapshot(atTime:0,with:CGSize(width:600,height:840),antialiasingMode:.multisampling4X)
        if cache.count<250 {cache[index]=i};return i
    }
}
let remote=try RemoteRender()
func background(_ ctx:CGContext,_ t:Double){
    ink.setFill();NSRect(x:0,y:0,width:W,height:H).fill()
    glow(ctx,x:1040+40*sin(t*0.12),y:570,radius:740,color:cyan,alpha:0.055)
    glow(ctx,x:260,y:900,radius:580,color:NSColor(srgbRed:0.24,green:0.16,blue:0.65,alpha:1),alpha:0.065)
    latin("Xpaco",x:76,y:49,width:170,size:20,color:muted,weight:.medium)
    latin("Xvico",x:W-220,y:49,width:144,size:22,color:white,align:.right)
}
let promptOne="帮我做一个深色番茄钟网页，有开始、暂停和重置按钮。"
let promptTwo="改成青绿色，再加一个任务列表。"
func mix(_ a:CGFloat,_ b:CGFloat,_ p:Double)->CGFloat {a+(b-a)*CGFloat(clamp(p))}
func blendRect(_ a:CGRect,_ b:CGRect,_ p:Double)->CGRect {CGRect(x:mix(a.minX,b.minX,p),y:mix(a.minY,b.minY,p),width:mix(a.width,b.width,p),height:mix(a.height,b.height,p))}
struct RemotePose { let rect: CGRect; let yaw: Double }
func motionEase(_ v:Double)->Double {let p=clamp(v);return p*p*p*(p*(p*6-15)+10)}
let appBody=CGRect(x:110,y:150,width:1220,height:1220*1620/2360)
let appMain=image("promo/.build/app-plates/app-mapping-main.png")
let appSiri=image("promo/.build/app-plates/app-siri-mapping.png")
let appScenes=image("promo/assets/app-scenes.png")
let appVoice=image("promo/assets/app-voice.png")
let siriFocus=image("promo/.build/app-plates/siri-focus.png")
let presetFocus=image("promo/.build/app-plates/codex-preset-focus.png")
let voiceFocus=image("promo/.build/app-plates/voice-input-focus.png")
let modelRestBounds: CGRect = {
    let rep=NSBitmapImageRep(data:remote.frame(yaw:-0.06).tiffRepresentation!)!
    var minX=rep.pixelsWide,minY=rep.pixelsHigh,maxX=0,maxY=0
    for y in stride(from:0,to:rep.pixelsHigh,by:2) {for x in stride(from:0,to:rep.pixelsWide,by:2) {
        if (rep.colorAt(x:x,y:y)?.alphaComponent ?? 0)>0.15 {minX=min(minX,x);minY=min(minY,y);maxX=max(maxX,x);maxY=max(maxY,y)}
    }}
    return CGRect(x:minX,y:minY,width:maxX-minX+2,height:maxY-minY+2)
}()
func mappedAppRect(_ raw:CGRect,_ body:CGRect=appBody)->CGRect {
    CGRect(x:body.minX+raw.minX/2360*body.width,y:body.minY+raw.minY/1620*body.height,width:raw.width/2360*body.width,height:raw.height/1620*body.height)
}
func registeredModelPose(_ name:String)->RemotePose {
    let raw=name=="main" ? CGRect(x:1215,y:273,width:270,height:1022):CGRect(x:1575,y:245,width:286,height:1076)
    let target=mappedAppRect(raw)
    let height=target.height/(modelRestBounds.height/840)
    let width=height/1.4
    let r=CGRect(x:target.minX-modelRestBounds.minX/600*width,y:target.minY-modelRestBounds.minY/840*height,width:width,height:height)
    return RemotePose(rect:r,yaw:-0.06)
}
func nativeWindow(_ screenshot:NSImage,_ r:CGRect,_ ctx:CGContext,label:String="Xvico") {
    panelImage(screenshot,r,ctx:ctx,radius:17)
    let chrome=CGRect(x:r.minX,y:r.minY-30,width:r.width,height:32)
    rect(chrome,radius:13,fill:NSColor(srgbRed:0.94,green:0.96,blue:0.98,alpha:1))
    rect(CGRect(x:r.minX,y:r.minY-12,width:r.width,height:15),radius:0,fill:NSColor(srgbRed:0.94,green:0.96,blue:0.98,alpha:1))
    for (i,c) in [NSColor.systemRed,NSColor.systemYellow,NSColor.systemGreen].enumerated(){rect(CGRect(x:r.minX+16+CGFloat(i)*17,y:r.minY-21,width:9,height:9),radius:4.5,fill:c.withAlphaComponent(0.8))}
    latin(label,x:r.minX+90,y:r.minY-25,width:r.width-180,size:16,color:NSColor(srgbRed:0.23,green:0.28,blue:0.34,alpha:1),weight:.medium,align:.center)
}
func pointer(_ p:CGPoint,_ ctx:CGContext,click:Double=0){
    if click>0 && click<1 {let radius=CGFloat(10+click*30);let ring=NSBezierPath(ovalIn:CGRect(x:p.x-radius,y:p.y-radius,width:radius*2,height:radius*2));cyan.withAlphaComponent(CGFloat(1-click)).setStroke();ring.lineWidth=2;ring.stroke()}
    ctx.saveGState();ctx.setShadow(offset:CGSize(width:0,height:2),blur:7,color:NSColor.black.withAlphaComponent(0.55).cgColor)
    let pth=NSBezierPath();pth.move(to:p);pth.line(to:CGPoint(x:p.x+1,y:p.y+26));pth.line(to:CGPoint(x:p.x+9,y:p.y+20));pth.line(to:CGPoint(x:p.x+17,y:p.y+31));pth.line(to:CGPoint(x:p.x+22,y:p.y+28));pth.line(to:CGPoint(x:p.x+15,y:p.y+17));pth.line(to:CGPoint(x:p.x+25,y:p.y+15));pth.close();white.setFill();pth.fill();NSColor.black.withAlphaComponent(0.6).setStroke();pth.lineWidth=1;pth.stroke();ctx.restoreGState()
}
func applicationOpening(_ t:Double,_ ctx:CGContext){
    let alpha=smooth((t-3.0)/0.65)*(1-smooth((t-7.8)/0.75))
    let dialog=smooth((t-5.45)/0.6)
    opacity(ctx,alpha){nativeWindow(appMain,appBody,ctx);opacity(ctx,dialog){nativeWindow(appSiri,appBody,ctx)}}
    if t>4.65 && t<5.95 {
        let target=remote.anchor(u:1,v:0.22,side:true,in:remotePose(t).rect)
        let q=motionEase((t-4.65)/0.65)
        pointer(CGPoint(x:mix(1130,target.x,q),y:mix(650,target.y,q)),ctx,click:(t-5.35)/0.55)
    }
}
func detachedSiriCard(_ t:Double,_ ctx:CGContext){
    guard t>=7.75 && t<14 else{return}
    let source=mappedAppRect(CGRect(x:563,y:169,width:691,height:706))
    let target=CGRect(x:178,y:330,width:510,height:510*706/691)
    let r=blendRect(source,target,motionEase((t-7.75)/2.45))
    let a=smooth((t-7.75)/0.7)*(1-smooth((t-13.6)/0.4))
    opacity(ctx,a){panelImage(siriFocus,r,ctx:ctx,radius:25)}
}
func presetApplication(_ t:Double,_ ctx:CGContext){
    let r=CGRect(x:550,y:300,width:810,height:810*1620/2360)
    let a=smooth((t-14.65)/0.7)*(1-smooth((t-16.7)/1.1))
    opacity(ctx,a){nativeWindow(appScenes,r,ctx,label:"Xvico · 预设场景")}
    let from=mappedAppRect(CGRect(x:1684,y:728,width:634,height:167),r)
    let focusRect=blendRect(from,CGRect(x:720,y:470,width:600,height:600*167/634),motionEase((t-16.7)/1.3))
    opacity(ctx,smooth((t-16.7)/0.65)){panelImage(presetFocus,focusRect,ctx:ctx,radius:23);rect(focusRect,radius:23,fill:cyan.withAlphaComponent(0.015),stroke:cyan.withAlphaComponent(0.4),line:1.5)}
}
func voiceApplication(_ t:Double,_ ctx:CGContext){
    let r=CGRect(x:560,y:310,width:800,height:800*1620/2360)
    opacity(ctx,smooth((t-24.1)/0.35)*(1-smooth((t-24.7)/0.7))){nativeWindow(appVoice,r,ctx,label:"Xvico · 语音设置")}
    let from=mappedAppRect(CGRect(x:631,y:150,width:1440,height:340),r)
    let focusRect=blendRect(from,CGRect(x:710,y:350,width:650,height:650*340/1440),motionEase((t-24.7)/0.8))
    opacity(ctx,smooth((t-24.7)/0.5)*(1-smooth((t-25.35)/0.4))){
        panelImage(voiceFocus,focusRect,ctx:ctx,radius:22)
        if t>24.9 {let selected=CGRect(x:focusRect.minX+843/1440*focusRect.width,y:focusRect.minY+105/340*focusRect.height,width:555/1440*focusRect.width,height:90/340*focusRect.height);rect(selected,radius:14,fill:cyan.withAlphaComponent(0.035),stroke:cyan.withAlphaComponent(0.7),line:2)}
    }
}
func remotePose(_ t:Double)->RemotePose {
    let keys=film.remoteMotion
    let index=keys.lastIndex(where:{$0.time<=t}) ?? 0
    let a=keys[index], b=keys[min(index+1,keys.count-1)]
    let p=b.time>a.time ? motionEase((t-a.time)/(b.time-a.time)):0
    func pose(_ k:RemoteKeyframe)->RemotePose {if let registration=k.registration {return registeredModelPose(registration)};return RemotePose(rect:CGRect(x:k.x,y:k.y,width:k.width,height:k.width*1.4),yaw:k.yaw)}
    let start=pose(a), end=pose(b)
    return RemotePose(rect:blendRect(start.rect,end.rect,p),yaw:start.yaw+(end.yaw-start.yaw)*p)
}
func activeRemoteKey(_ t:Double)->String? {
    if t>5.35 && t<7.8 || t>10.7 && t<13.6 || t>24.9 && t<31.4 || t>35.1 && t<37.3 {return "voice"}
    return nil
}
func ringEffect(_ t:Double,_ r:CGRect){
    guard t>=19.8 && t<23.6 else{return}
    let center=remote.anchor(u:0.5,v:0.21,in:r), edge=remote.anchor(u:0.94,v:0.21,in:r)
    let radius=abs(edge.x-center.x)*0.87
    let alpha=smooth((t-19.8)/0.3)*(1-smooth((t-23.3)/0.3))
    let angle=(t-19)*3
    for i in 0..<28 {let a=angle-Double(i)*0.035;let p=CGPoint(x:center.x+cos(a)*radius,y:center.y+sin(a)*radius);rect(CGRect(x:p.x-3,y:p.y-3,width:6,height:6),radius:3,fill:cyan.withAlphaComponent(CGFloat(alpha*(1-Double(i)/28))*0.9))}
}
func typed(_ s:String,_ p:Double)->String {String(s.prefix(Int(Double(s.count)*clamp(p))))}
func opacity(_ ctx:CGContext,_ alpha:Double,_ body:()->Void){guard alpha>0 else{return};ctx.saveGState();ctx.setAlpha(CGFloat(clamp(alpha)));ctx.beginTransparencyLayer(auxiliaryInfo:nil);ctx.setAlpha(1);body();ctx.endTransparencyLayer();ctx.restoreGState()}
func wave(_ t:Double,_ r:CGRect,_ alpha:Double=1){
    for i in 0..<45 {let p=Double(i)/44;let h=CGFloat(6+(Double(r.height)-6)*pow(sin(p*Double.pi),1.4)*abs(sin(Double(i)*0.62+t*7)));rect(CGRect(x:r.minX+CGFloat(p)*r.width,y:r.midY-h/2,width:4,height:h),radius:2,fill:cyan.withAlphaComponent(CGFloat(alpha)*(0.45+0.5*CGFloat(sin(p*Double.pi)))))}
}
func title(_ s:String,_ sub:String="",alpha:Double=1){let ctx=NSGraphicsContext.current!.cgContext;opacity(ctx,alpha){text(s,x:80,y:114,width:1280,size:61,align:.center);if !sub.isEmpty{text(sub,x:80,y:211,width:1280,size:24,color:muted,align:.center)}}}
func pulse(_ p:CGPoint,_ t:Double,_ ctx:CGContext,scale:CGFloat=1){let q=t.truncatingRemainder(dividingBy:1.2)/1.2;glow(ctx,x:p.x,y:p.y,radius:66*scale,color:cyan,alpha:0.22);let ring=NSBezierPath(ovalIn:CGRect(x:p.x-CGFloat(12+q*26)*scale,y:p.y-CGFloat(12+q*26)*scale,width:CGFloat(24+q*52)*scale,height:CGFloat(24+q*52)*scale));cyan.withAlphaComponent(CGFloat(1-q)*0.7).setStroke();ring.lineWidth=2;ring.stroke()}
func remoteView(_ r:CGRect,_ yaw:Double,_ ctx:CGContext,active:String?=nil,time:Double=0)->CGPoint{
    let img=remote.frame(yaw:yaw)
    ctx.saveGState();ctx.setShadow(offset:CGSize(width:6,height:-12),blur:24,color:NSColor.black.withAlphaComponent(0.17).cgColor);drawImage(img,r);ctx.restoreGState()
    let siri=remote.anchor(u:1,v:0.22,side:true,in:r)
    if let active {
        let p=active=="voice" ? siri:remote.anchor(u:active=="mute" ? 0.285:0.50,v:active=="mute" ? 0.596:0.21,in:r)
        pulse(p,time,ctx,scale:r.height/800)
        if active=="voice" {let a=remote.anchor(u:1,v:0.16,side:true,in:r),b=remote.anchor(u:1,v:0.28,side:true,in:r);line(a,b,color:cyan,width:5)}
    }
    return siri
}
func wire(_ a:CGPoint,_ b:CGPoint,_ t:Double,_ ctx:CGContext,alpha:Double=1){
    opacity(ctx,alpha){let p=NSBezierPath();p.move(to:a);p.curve(to:b,controlPoint1:CGPoint(x:a.x+160,y:a.y),controlPoint2:CGPoint(x:b.x-160,y:b.y));cyan.withAlphaComponent(0.17).setStroke();p.lineWidth=1.5;p.stroke();for i in 0..<18 {let q=(t*0.28+Double(i)/18).truncatingRemainder(dividingBy:1);let x=pow(1-q,3)*a.x+3*pow(1-q,2)*q*(a.x+160)+3*(1-q)*q*q*(b.x-160)+q*q*q*b.x;let y=pow(1-q,3)*a.y+3*pow(1-q,2)*q*a.y+3*(1-q)*q*q*b.y+q*q*q*b.y;rect(CGRect(x:x,y:y-2,width:5,height:4),radius:2,fill:cyan.withAlphaComponent(CGFloat(sin(q*Double.pi))*0.8))}}
}
func flatCard(_ r:CGRect,_ ctx:CGContext){ctx.saveGState();ctx.setShadow(offset:CGSize(width:0,height:18),blur:50,color:NSColor.black.withAlphaComponent(0.35).cgColor);rect(r,radius:27,fill:NSColor(srgbRed:0.065,green:0.085,blue:0.11,alpha:1),stroke:white.withAlphaComponent(0.13));ctx.restoreGState()}
func settingRow(_ label:String,_ value:String,_ y:CGFloat,_ selected:Bool,_ x:CGFloat=785,_ w:CGFloat=440){rect(CGRect(x:x,y:y,width:w,height:72),radius:17,fill:selected ? cyan.withAlphaComponent(0.10):white.withAlphaComponent(0.025),stroke:selected ? cyan.withAlphaComponent(0.45):.clear);text(label,x:x+22,y:y+22,width:125,size:23,color:muted);text(value,x:x+143,y:y+22,width:w-165,size:23,color:selected ? cyan:white,align:.right)}
func brandCodex(_ t:Double,_ ctx:CGContext){
    let morph=smooth((t-26.2)/1.1)
    let r=blendRect(CGRect(x:230,y:600,width:980,height:180),CGRect(x:200,y:360,width:1115,height:620),morph)
    flatCard(r,ctx)
    opacity(ctx,morph){latin("Codex",x:r.minX+30,y:r.minY+24,width:210,size:28);latin("focus-timer",x:r.maxX-240,y:r.minY+32,width:205,size:17,color:muted,align:.right);line(CGPoint(x:r.minX+28,y:r.minY+79),CGPoint(x:r.maxX-28,y:r.minY+79),color:white.withAlphaComponent(0.07))}
    let sent=smooth((t-26.5)/0.9)
    let input=CGRect(x:r.minX+30,y:r.maxY-172,width:r.width-60,height:142)
    let bubble=blendRect(input,CGRect(x:r.minX+30,y:r.minY+110,width:r.width-60,height:113),sent)
    rect(bubble,radius:18,fill:white.withAlphaComponent(0.045),stroke:cyan.withAlphaComponent(CGFloat(1-sent)*0.30))
    text(typed(promptOne,(t-23.9)/2.5),x:bubble.minX+24,y:bubble.minY+28,width:bubble.width-88,size:31)
    if t<26.5 {wave(t,CGRect(x:bubble.minX+24,y:bubble.minY-42,width:bubble.width-90,height:29),0.8)}
    if t>=27.4 {opacity(ctx,smooth((t-27.4)/0.5)){latin("Codex",x:r.minX+38,y:r.minY+270,width:180,size:23,color:cyan);text("正在构建你的第一个页面…",x:r.minX+38,y:r.minY+318,width:r.width-80,size:29,color:muted);for (i,code) in ["+ <Timer duration={25 * 60} />","+ <Controls start pause reset />"].enumerated() {let a=smooth((t-27.6-Double(i)*0.25)/0.4);opacity(ctx,a){latin(code,x:r.minX+38,y:r.minY+382+CGFloat(i)*42,width:r.width-76,size:25,color:cyan)}}}}
}
func productPage(_ r:CGRect,_ revised:Double,_ ctx:CGContext){
    flatCard(r,ctx);let purple=NSColor(srgbRed:0.62,green:0.51,blue:0.97,alpha:1);let accent=purple.blended(withFraction:CGFloat(revised),of:cyan)!
    latin("FOCUS",x:r.minX+30,y:r.minY+32,width:r.width-60,size:18,color:accent,align:.center)
    let radius=min(r.width*0.25,110);let center=CGPoint(x:r.midX,y:r.minY+215);let p=NSBezierPath(ovalIn:CGRect(x:center.x-radius,y:center.y-radius,width:radius*2,height:radius*2));accent.withAlphaComponent(0.3).setStroke();p.lineWidth=4;p.stroke()
    latin("25:00",x:r.minX+30,y:center.y-40,width:r.width-60,size:65,color:white,weight:.light,align:.center)
    for (i,label) in ["开始","暂停","重置"].enumerated(){let w=(r.width-88)/3;let b=CGRect(x:r.minX+30+CGFloat(i)*(w+14),y:r.minY+355,width:w,height:50);rect(b,radius:14,fill:i==0 ? accent:white.withAlphaComponent(0.05));text(label,x:b.minX,y:b.minY+13,width:w,size:21,color:i==0 ? ink:muted,align:.center)}
    if revised>0 {opacity(ctx,revised){text("今日任务",x:r.minX+34,y:r.minY+448,width:r.width-68,size:24);for (i,label) in ["完成页面原型","继续下一轮迭代"].enumerated(){let y=r.minY+504+CGFloat(i)*43;rect(CGRect(x:r.minX+35,y:y+4,width:16,height:16),radius:4,fill:cyan.withAlphaComponent(0.08),stroke:cyan.withAlphaComponent(0.5));text(label,x:r.minX+67,y:y,width:r.width-100,size:21,color:muted)}}}
}
func content(_ s:SceneSpec,_ t:Double,_ ctx:CGContext){
    let u=t-s.start
    switch s.id {
    case "hero":
        opacity(ctx,ease(u/0.7)){latin("Xvico",x:115,y:310+CGFloat(1-ease(u/1.0))*50,width:1000,size:150,weight:.bold);text("用声音，开启创造。",x:124,y:520,width:1000,size:49);latin("SIRI REMOTE × VIBE CODING",x:128,y:626,width:1000,size:22,color:cyan,weight:.medium)}
    case "application":
        applicationOpening(t,ctx)
    case "mapping":
        title("每个按键，都听你的。")
    case "scenes":
        title("切换应用，切换手感。")
        presetApplication(t,ctx)
    case "touch":
        title("轻轻一转，流畅向前。")
        let r2=CGRect(x:740,y:320,width:520,height:480);flatCard(r2,ctx)
        latin("你的工作流",x:r2.minX+32,y:r2.minY+31,width:450,size:29)
        ctx.saveGState();ctx.clip(to:CGRect(x:r2.minX+30,y:r2.minY+100,width:450,height:335));for i in 0..<12 {let y=r2.minY+115+CGFloat(i)*66-CGFloat(u*83);rect(CGRect(x:r2.minX+32,y:y,width:CGFloat(310+(i%3)*36),height:12),radius:6,fill:white.withAlphaComponent(i%3==0 ? 0.20:0.075));rect(CGRect(x:r2.minX+32,y:y+27,width:CGFloat(240+(i%2)*45),height:7),radius:4,fill:white.withAlphaComponent(0.045))};ctx.restoreGState();rect(CGRect(x:r2.maxX-17,y:r2.minY+110+CGFloat(u*38),width:4,height:73),radius:2,fill:cyan.withAlphaComponent(0.7))
        if u>2.6 {let q=smooth((u-2.6)/0.9);let point=CGPoint(x:mix(1130,948,q),y:mix(685,558,q));let pointer=NSBezierPath();pointer.move(to:point);pointer.line(to:CGPoint(x:point.x+1,y:point.y+27));pointer.line(to:CGPoint(x:point.x+20,y:point.y+17));pointer.close();white.setFill();pointer.fill();if u>3.7 && u<4.3 {pulse(point,u-3.7,ctx,scale:0.7)}}
        text("外圈滚动  ·  触控指针",x:740,y:850,width:520,size:26,color:muted,align:.center)
    case "voice":
        let demoTime=t-5
        voiceApplication(t,ctx)
        title(demoTime<23.5 ? "按住，想法开始流动。":"想法，落进 Coding 输入框。",alpha:1-smooth((demoTime-27.4)/1.0))
        let r=remotePose(t).rect
        if demoTime>=23.9 {opacity(ctx,smooth((demoTime-23.9)/0.4)){brandCodex(demoTime,ctx)}}
        let held=demoTime>19.9 && demoTime<26.4
        let p=remote.anchor(u:1,v:0.22,side:true,in:r)
        if demoTime>=20.8 && demoTime<21.7 {opacity(ctx,smooth((demoTime-19.9)/0.4)){text("按住 Siri",x:p.x+55,y:p.y-21,width:320,size:27,color:cyan);wave(demoTime,CGRect(x:p.x+55,y:p.y+44,width:360,height:78))}}
        if demoTime>=21.7 && demoTime<24.1 {let a=smooth((demoTime-21.7)/0.5)*(1-smooth((demoTime-23.7)/0.4));opacity(ctx,a){let q=smooth((demoTime-21.7)/2.2);var waveRect=blendRect(CGRect(x:p.x+48,y:p.y+35,width:350,height:80),CGRect(x:284,y:566,width:906,height:40),q);waveRect.origin.x=max(waveRect.minX,p.x+32);waveRect.size.width=min(waveRect.width,1260-waveRect.minX);wave(demoTime,waveRect)}}
        if demoTime>=23.9 && held {wire(p,CGPoint(x:260,y:608),demoTime,ctx,alpha:0.7)}
    case "iterate":
        let demoTime=t-5
        title("说出下一步，继续创造。")
        let revised=smooth((demoTime-32.3)/1.0)
        let reveal=ease(u/0.8)
        let pageRect=CGRect(x:mix(500,815,reveal),y:320,width:500,height:645)
        opacity(ctx,reveal){productPage(pageRect,revised,ctx)}
        opacity(ctx,ease((u-0.4)/0.7)){latin("Codex",x:340,y:384,width:390,size:28);let phrases=demoTime<30.0 ? "第一个页面，已就绪。":typed(promptTwo,(demoTime-30.0)/2.2);text(phrases,x:340,y:456,width:390,size:33);if demoTime>=30 && demoTime<32.3 {wave(demoTime,CGRect(x:340,y:643,width:360,height:53))};if revised>0 {opacity(ctx,revised){text("✓  主题与任务列表已更新",x:340,y:690,width:390,size:24,color:cyan)}}}
    default:
        let e=ease(u/0.9);glow(ctx,x:720,y:485,radius:430,color:cyan,alpha:0.10)
        opacity(ctx,smooth((u-0.35)/0.75)){drawImage(icon,CGRect(x:640,y:205+CGFloat(1-e)*25,width:160,height:160))}
        opacity(ctx,smooth((u-0.25)/0.6)){latin("Xvico",x:90,y:430,width:1260,size:145,weight:.bold,align:.center)}
        opacity(ctx,smooth((u-0.8)/0.7)){text("拿起遥控器，说出下一步。",x:90,y:645,width:1260,size:47,align:.center)}
        latin("SPEAK. BUILD. ITERATE.",x:90,y:765,width:1260,size:24,color:cyan,weight:.medium,align:.center)
    }
}
func render(_ t:Double,_ buffer:CVPixelBuffer){
    CVPixelBufferLockBaseAddress(buffer,[]);defer{CVPixelBufferUnlockBaseAddress(buffer,[])}
    let ctx=CGContext(data:CVPixelBufferGetBaseAddress(buffer),width:outW,height:outH,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(buffer),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.scaleBy(x:scale,y:scale);ctx.translateBy(x:0,y:H);ctx.scaleBy(x:1,y:-1)
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:ctx,flipped:true)
    background(ctx,t)
    let current=film.scenes.lastIndex(where:{$0.start<=t}) ?? 0
    // One persistent product layer: scene content never creates or removes the remote.
    let pose=remotePose(t)
    _=remote.frame(yaw:pose.yaw)
    let scene=film.scenes[current]
    let enter=scene.start==0 ? 1:smooth((t-scene.start-0.08)/0.60)
    let leave=scene.id=="outro" ? 1:1-smooth((t-(scene.end-0.4))/0.4)
    opacity(ctx,enter*leave){content(scene,t,ctx)}
    detachedSiriCard(t,ctx)
    let outroStart=film.scenes.last!.start
    if t<outroStart+0.85 {
        opacity(ctx,1-smooth((t-(outroStart+0.05))/0.8)){
            _=remoteView(pose.rect,pose.yaw,ctx,active:activeRemoteKey(t),time:t)
            ringEffect(t,pose.rect)
        }
    }
    if t>=3 && t<film.scenes.last!.start {text("交互与编程场景演示",x:80,y:1029,width:1280,size:15,color:muted.withAlphaComponent(0.65),align:.center)}
    let black=CGFloat(1-smooth(t/0.35)+smooth((t-(film.duration-0.6))/0.6))
    if black>0 {NSColor.black.withAlphaComponent(min(1,black)).setFill();NSRect(x:0,y:0,width:W,height:H).fill()}
    NSGraphicsContext.restoreGraphicsState()
}
func newBuffer()->CVPixelBuffer {var b:CVPixelBuffer?;CVPixelBufferCreate(nil,outW,outH,kCVPixelFormatType_32BGRA,[kCVPixelBufferCGImageCompatibilityKey:true,kCVPixelBufferCGBitmapContextCompatibilityKey:true] as CFDictionary,&b);return b!}
func saveFrame(_ t:Double,_ path:URL){let b=newBuffer();render(t,b);let ci=CIImage(cvPixelBuffer:b);let cg=CIContext().createCGImage(ci,from:ci.extent)!;let rep=NSBitmapImageRep(cgImage:cg);try! rep.representation(using:.png,properties:[:])!.write(to:path)}
if args.contains("--verify-motion") {
    var maxStep:Double=0, maxScale:Double=0, maxYaw:Double=0
    var previous=remotePose(0)
    for f in 1...Int((film.scenes.last!.start+0.8)*Double(film.fps)) {
        let pose=remotePose(Double(f)/Double(film.fps))
        maxStep=max(maxStep,hypot(Double(pose.rect.midX-previous.rect.midX),Double(pose.rect.midY-previous.rect.midY)))
        maxScale=max(maxScale,abs(Double(pose.rect.width-previous.rect.width)))
        maxYaw=max(maxYaw,abs(pose.yaw-previous.yaw))
        precondition(pose.rect.width>0 && pose.rect.intersects(CGRect(x:0,y:0,width:W,height:H)))
        previous=pose
    }
    precondition(maxStep<22 && maxScale<10 && maxYaw<0.04,"Product motion has a discontinuity")
    let report:[String:Any]=["passed":true,"maxCenterPixelsPerFrame":maxStep,"maxWidthPixelsPerFrame":maxScale,"maxYawRadiansPerFrame":maxYaw,"fps":film.fps,"persistentRemoteThroughSeconds":film.scenes.last!.start+0.05,"remoteDrawLayersPerFrame":1,"curve":"quintic, zero velocity and acceleration at keyframes"]
    let data=try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
    try data.write(to:promo.appendingPathComponent("dist/motion-verification.json"));print(String(data:data,encoding:.utf8)!);exit(0)
}
let sampleTimes = film.keyTimes
if previewOnly {
    for (i,t) in sampleTimes.enumerated(){saveFrame(t,promo.appendingPathComponent(".build/keyframes/\(i)-\(film.scenes[i].id).png"));print("PREVIEW \(i) \(t)")}
    for (i,t) in film.proofTimes.enumerated(){saveFrame(t,promo.appendingPathComponent(".build/keyframes/proof-\(String(format:"%02d",i)).png"))}
    saveFrame(6.8,promo.appendingPathComponent("dist/Xvico-cover.png"));exit(0)
}
try? fm.removeItem(at:output)
let writer=try AVAssetWriter(outputURL:output,fileType:.mp4)
let settings:[String:Any]=[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:outW,AVVideoHeightKey:outH,AVVideoCompressionPropertiesKey:[AVVideoAverageBitRateKey:Int(8_000_000*scale*scale),AVVideoProfileLevelKey:AVVideoProfileLevelH264HighAutoLevel,AVVideoExpectedSourceFrameRateKey:film.fps,AVVideoMaxKeyFrameIntervalKey:film.fps*2]]
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
