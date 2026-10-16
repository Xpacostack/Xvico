import AppKit
import Foundation
import AVFoundation
import CoreVideo

@main enum Finish {
    static func main() async throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1]);let dir=root.appendingPathComponent("promo/update-iteration")
        let cfg=try JSONSerialization.jsonObject(with:Data(contentsOf:dir.appendingPathComponent("storyboard.json"))) as! [String:Any]
        let source=AVURLAsset(url:dir.appendingPathComponent(".build/film-silent.mp4"))
        let sound=AVURLAsset(url:dir.appendingPathComponent(".build/soundtrack.wav"))
        let composition=AVMutableComposition()
        let video=try await source.loadTracks(withMediaType:.video).first!
        let audio=try await sound.loadTracks(withMediaType:.audio).first!
        let duration=try await source.load(.duration)
        let vt=composition.addMutableTrack(withMediaType:.video,preferredTrackID:kCMPersistentTrackID_Invalid)!
        let at=composition.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid)!
        try vt.insertTimeRange(CMTimeRange(start:.zero,duration:duration),of:video,at:.zero)
        try at.insertTimeRange(CMTimeRange(start:.zero,duration:duration),of:audio,at:.zero)
        let path=dir.appendingPathComponent("dist/Xvico-ui-features-9x16.mp4");try? FileManager.default.removeItem(at:path)
        let exporter=AVAssetExportSession(asset:composition,presetName:AVAssetExportPresetHighestQuality)!
        exporter.outputURL=path;exporter.outputFileType = .mp4;exporter.shouldOptimizeForNetworkUse=true
        await exporter.export()
        guard exporter.status == .completed else {throw exporter.error ?? NSError(domain:"Promo",code:1)}
        let movie=AVURLAsset(url:path)
        let tracks=try await movie.load(.tracks)
        var report:[String:Any]=["duration":CMTimeGetSeconds(try await movie.load(.duration)),"fileBytes":try path.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0,"tracks":tracks.count]
        var media=[[String:Any]]()
        for track in tracks {
            let desc=try await track.load(.formatDescriptions)
            let codec=desc.first.map { CMFormatDescriptionGetMediaSubType($0) } ?? 0
            let chars=[UInt8((codec>>24)&255),UInt8((codec>>16)&255),UInt8((codec>>8)&255),UInt8(codec&255)]
            media.append(["type":track.mediaType.rawValue,"codec":String(bytes:chars,encoding:.ascii) ?? "unknown","fps":try await track.load(.nominalFrameRate),"width":try await track.load(.naturalSize).width,"height":try await track.load(.naturalSize).height])
        }
        report["media"]=media
        let gen=AVAssetImageGenerator(asset:movie);gen.appliesPreferredTrackTransform=true;gen.requestedTimeToleranceBefore = .zero;gen.requestedTimeToleranceAfter = .zero
        let times=(cfg["keyTimes"] as! [Double]) + (cfg["proofTimes"] as! [Double]) + [0.0,0.3,(cfg["duration"] as! Double)-0.1]
        var frames=[[String:Any]]()
        for (i,t) in times.enumerated(){
            let (cg,actual)=try await gen.image(at:CMTime(seconds:t,preferredTimescale:600))
            let rep=NSBitmapImageRep(cgImage:cg)
            try rep.representation(using:.png,properties:[:])!.write(to:dir.appendingPathComponent(".build/keyframes/encoded-\(String(format:"%02d",i)).png"))
            frames.append(["requested":t,"actual":CMTimeGetSeconds(actual),"width":cg.width,"height":cg.height])
        }
        report["decodedFrames"]=frames
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:dir.appendingPathComponent("dist/verification.json"))
        print(String(data:try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]),encoding:.utf8)!)
    }
}
