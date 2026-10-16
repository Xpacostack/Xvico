import Foundation
import AppKit
import AVFoundation

@main enum Validate {
    static func main() async throws {
        let dir=URL(fileURLWithPath:CommandLine.arguments[1]).appendingPathComponent("promo/update-iteration")
        let cfg=try JSONSerialization.jsonObject(with:Data(contentsOf:dir.appendingPathComponent("storyboard.json"))) as! [String:Any]
        let expectedDuration=cfg["duration"] as! Double;let expectedFrames=Int(expectedDuration*Double(cfg["fps"] as! Int))
        let url=dir.appendingPathComponent("dist/Xvico-ui-features-9x16.mp4")
        let movie=AVURLAsset(url:url)
        let duration=CMTimeGetSeconds(try await movie.load(.duration))
        let video=try await movie.loadTracks(withMediaType:.video).first!
        let audio=try await movie.loadTracks(withMediaType:.audio).first!
        let reader=try AVAssetReader(asset:movie)
        let v=AVAssetReaderTrackOutput(track:video,outputSettings:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA]);v.alwaysCopiesSampleData=false;reader.add(v)
        guard reader.startReading() else {throw reader.error!}
        var frames=0;var last = -1.0;var timestampErrors=0;var first = 0.0
        while let sample=v.copyNextSampleBuffer(){
            let pts=CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
            if frames==0 {first=pts}
            if pts<=last {timestampErrors+=1}
            last=pts;frames+=1
        }
        guard reader.status == .completed else {throw reader.error!}
        let ar=try AVAssetReader(asset:movie)
        let a=AVAssetReaderTrackOutput(track:audio,outputSettings:[AVFormatIDKey:kAudioFormatLinearPCM,AVLinearPCMIsFloatKey:true,AVLinearPCMBitDepthKey:32,AVLinearPCMIsNonInterleaved:false,AVSampleRateKey:48000,AVNumberOfChannelsKey:2]);ar.add(a)
        guard ar.startReading() else {throw ar.error!}
        var samples=0;var energy:Double=0;var peak:Float=0;var nonFinite=0
        while let sample=a.copyNextSampleBuffer(){
            guard let block=CMSampleBufferGetDataBuffer(sample) else {continue}
            var length=0;var total=0;var ptr:UnsafeMutablePointer<Int8>?
            guard CMBlockBufferGetDataPointer(block,atOffset:0,lengthAtOffsetOut:&length,totalLengthOut:&total,dataPointerOut:&ptr)==kCMBlockBufferNoErr else {fatalError("Cannot read audio block")}
            let count=total/MemoryLayout<Float>.size
            ptr!.withMemoryRebound(to:Float.self,capacity:count){values in
                for i in 0..<count {let x=values[i];if !x.isFinite {nonFinite+=1;continue};peak=max(peak,abs(x));energy+=Double(x*x)}
            }
            samples+=count
        }
        guard ar.status == .completed else {throw ar.error!}
        let audioSeconds=Double(samples)/2/48000
        var report=try JSONSerialization.jsonObject(with:Data(contentsOf:dir.appendingPathComponent("dist/verification.json"))) as! [String:Any]
        report["fullDecode"]=["videoFrames":frames,"firstVideoPTS":first,"lastVideoPTS":last,"timestampErrors":timestampErrors,"audioSamplesPerChannel":samples/2,"decodedAudioSeconds":audioSeconds,"decodedAudioPeakDbFS":20*log10(Double(peak)),"decodedAudioRmsDbFS":20*log10(sqrt(energy/Double(samples))),"nonFiniteAudioSamples":nonFinite]
        guard frames==expectedFrames,abs(duration-expectedDuration)<0.05,timestampErrors==0,abs(audioSeconds-expectedDuration)<0.1,peak<1,peak>0.1,nonFinite==0 else {fatalError("Media verification failed")}
        report["verificationPassed"]=true
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:dir.appendingPathComponent("dist/verification.json"))
        // Contact sheet from frames decoded from the final MP4, not pre-encode previews.
        let count=(cfg["keyTimes"] as! [Double]).count;let cols=4,rows=2;let tileW=270,tileH=480;let canvas=NSImage(size:NSSize(width:tileW*cols,height:(tileH+32)*rows))
        canvas.lockFocusFlipped(true);NSColor(srgbRed:0.025,green:0.045,blue:0.085,alpha:1).setFill();NSRect(x:0,y:0,width:tileW*cols,height:(tileH+32)*rows).fill()
        let times=cfg["keyTimes"] as! [Double]
        let scenes=cfg["scenes"] as! [[String:Any]]
        for i in 0..<count {
            let image=NSImage(contentsOf:dir.appendingPathComponent(".build/keyframes/encoded-\(String(format:"%02d",i)).png"))!
            let x=(i%cols)*tileW,y=(i/cols)*(tileH+32)
            image.draw(in:NSRect(x:x,y:y,width:tileW,height:tileH),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
            let label=String(format:"%04.1fs · ",times[i])+(scenes[i]["eyebrow"] as! String)
            NSAttributedString(string:label,attributes:[.font:NSFont.systemFont(ofSize:14,weight:.medium),.foregroundColor:NSColor.white]).draw(at:NSPoint(x:x+14,y:y+tileH+7))
        }

        canvas.unlockFocus()
        try NSBitmapImageRep(data:canvas.tiffRepresentation!)!.representation(using:.png,properties:[:])!.write(to:dir.appendingPathComponent("dist/Xvico-storyboard.png"))
        print("PASS: \(frames) video frames; \(audioSeconds)s decoded stereo audio; monotonic timestamps; no audio clipping.")
    }
}
