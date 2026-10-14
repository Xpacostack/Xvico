import AVFoundation
import Darwin
import Foundation

enum RemoteAudioError: Error, LocalizedError {
    case codecMissing, codecSymbolMissing, decoderCreation(Int32), malformedFrame, decode(Int32)
    var errorDescription: String? {
        switch self {
        case .codecMissing: "应用内 Opus 解码器缺失"
        case .codecSymbolMissing: "Opus 解码器接口不完整"
        case .decoderCreation(let code): "无法创建音频解码器（\(code)）"
        case .malformedFrame: "收到的通知不符合已验证的 Siri Remote 音频帧格式"
        case .decode(let code): "遥控器音频帧解码失败（\(code)）"
        }
    }
}

struct RemoteOpusFrame: Equatable {
    let session: UInt16
    let sequence: UInt16
    let packet: Data

    // A2854 report 0xFA: session LE16, sequence LE16, length, Opus, padding.
    // Source: henaxxx/a2854-siri-remote-linux, decode_siri_voice.py. Accept only
    // the observed mono, 20ms, wideband CELT format; never decode arbitrary HID.
    static func parse(_ data: Data, reportID: Int? = nil) throws -> Self {
        var bytes = Array(data)
        if reportID == 0xFA, bytes.count == 101, bytes.first == 0xFA { bytes.removeFirst() }
        if reportID == nil, bytes.count == 101, bytes.first == 0xFA { bytes.removeFirst() }
        guard reportID == nil || reportID == 0xFA,
              bytes.count == 100, bytes[4] > 0,
              Int(bytes[4]) <= bytes.count - 5, bytes[5] == 0xB8 else { throw RemoteAudioError.malformedFrame }
        let end = 5 + Int(bytes[4])
        guard bytes[end...].allSatisfy({ $0 == 0 }) else { throw RemoteAudioError.malformedFrame }
        return Self(session: UInt16(bytes[0]) | UInt16(bytes[1]) << 8,
                    sequence: UInt16(bytes[2]) | UInt16(bytes[3]) << 8,
                    packet: Data(bytes[5..<end]))
    }
}

final class RemoteAudioDecoder {
    private typealias Create = @convention(c) (Int32, Int32, UnsafeMutablePointer<Int32>?) -> OpaquePointer?
    private typealias Destroy = @convention(c) (OpaquePointer?) -> Void
    private typealias Decode = @convention(c) (OpaquePointer?, UnsafePointer<UInt8>?, Int32, UnsafeMutablePointer<Float>?, Int32, Int32) -> Int32
    private typealias Initialize = @convention(c) (OpaquePointer?, Int32, Int32) -> Int32
    private let library: UnsafeMutableRawPointer
    private let decoder: OpaquePointer
    private let decodeFunction: Decode
    private let destroyFunction: Destroy
    private let initializeFunction: Initialize
    let sampleRate: Double = 16_000

    init() throws {
        guard let url = Bundle.module.url(forResource: "libopus.0", withExtension: "dylib", subdirectory: "VoiceRuntime"),
              let library = dlopen(url.path, RTLD_NOW | RTLD_LOCAL) else { throw RemoteAudioError.codecMissing }
        guard let create = dlsym(library, "opus_decoder_create"),
              let destroy = dlsym(library, "opus_decoder_destroy"),
              let decode = dlsym(library, "opus_decode_float"),
              let initialize = dlsym(library, "opus_decoder_init") else {
            dlclose(library); throw RemoteAudioError.codecSymbolMissing
        }
        var error: Int32 = 0
        guard let decoder = unsafeBitCast(create, to: Create.self)(16_000, 1, &error), error == 0 else {
            dlclose(library); throw RemoteAudioError.decoderCreation(error)
        }
        self.library = library; self.decoder = decoder
        decodeFunction = unsafeBitCast(decode, to: Decode.self)
        destroyFunction = unsafeBitCast(destroy, to: Destroy.self)
        initializeFunction = unsafeBitCast(initialize, to: Initialize.self)
    }
    deinit { destroyFunction(decoder); dlclose(library) }

    func reset() { _ = initializeFunction(decoder, 16_000, 1) }
    func decode(_ packet: Data?) throws -> AVAudioPCMBuffer {
        let capacity: Int32 = packet == nil ? 320 : 1920 // 20ms concealment / max 120ms
        var samples = [Float](repeating: 0, count: Int(capacity))
        let count = samples.withUnsafeMutableBufferPointer { output -> Int32 in
            guard let packet else { return decodeFunction(decoder, nil, 0, output.baseAddress, capacity, 0) }
            return packet.withUnsafeBytes { bytes in
                decodeFunction(decoder, bytes.bindMemory(to: UInt8.self).baseAddress,
                               Int32(packet.count), output.baseAddress, capacity, 0)
            }
        }
        guard count > 0, count <= capacity,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
              let output = buffer.floatChannelData else { throw RemoteAudioError.decode(count) }
        buffer.frameLength = AVAudioFrameCount(count)
        for index in 0..<Int(count) { output[0][index] = samples[index] }
        return buffer
    }
}

final class RemoteAudioStream {
    private let decoder: RemoteAudioDecoder
    private var session: UInt16?
    private var sequence: UInt16?
    private(set) var decodedFrames = 0
    private(set) var concealedFrames = 0
    private(set) var duplicateFrames = 0
    init() throws { decoder = try RemoteAudioDecoder() }

    // A capture connection survives multiple holds; its handle is not a speech
    // session ID. Reset sequence history at each physical microphone activation.
    func beginUtterance() {
        decoder.reset(); session = nil; sequence = nil
    }

    func ingest(_ frame: RemoteOpusFrame) throws -> [AVAudioPCMBuffer] {
        var buffers: [AVAudioPCMBuffer] = []
        if session != frame.session {
            decoder.reset(); session = frame.session; sequence = nil
        }
        if let sequence {
            let distance = frame.sequence &- sequence
            if distance == 0 || distance > 0x8000 { duplicateFrames += 1; return [] }
            if distance > 6 { decoder.reset() }
            else if distance > 1 {
                for _ in 1..<Int(distance) { buffers.append(try decoder.decode(nil)); concealedFrames += 1 }
            }
        }
        buffers.append(try decoder.decode(frame.packet))
        sequence = frame.sequence; decodedFrames += 1
        return buffers
    }
}
