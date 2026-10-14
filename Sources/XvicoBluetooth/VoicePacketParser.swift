import Foundation

public struct VoicePacketParser: Sendable {
    public let layout: VoicePacketLayout

    public init(layout: VoicePacketLayout = .unclassified) {
        self.layout = layout
    }

    public func parse(_ data: Data, receivedAt: Date = Date()) throws -> VoicePacket {
        let bytes = Array(data)
        guard layout.typeByteOffset >= 0, bytes.count > layout.typeByteOffset else {
            throw VoiceMonitorError.malformedPacket("packet has no type byte")
        }
        guard layout.payloadOffset >= 0, bytes.count >= layout.payloadOffset else {
            throw VoiceMonitorError.malformedPacket("payload offset exceeds packet length")
        }

        let type = bytes[layout.typeByteOffset]
        let kind: VoicePacketKind
        if layout.primaryTypeValues.contains(type) {
            kind = .primaryAudio
        } else if layout.continuationTypeValues.contains(type) {
            kind = .continuationAudio
        } else if layout.metadataTypeValues.contains(type) {
            kind = .metadata
        } else {
            kind = .unknown
        }

        var sequence: UInt16?
        if let offset = layout.sequenceByteOffset, offset >= 0, offset <= bytes.count - 2 {
            sequence = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
        } else {
            sequence = nil
        }

        let payload = Data(data.dropFirst(layout.payloadOffset))
        return VoicePacket(kind: kind, sequence: sequence, payload: payload, raw: data, receivedAt: receivedAt)
    }
}
