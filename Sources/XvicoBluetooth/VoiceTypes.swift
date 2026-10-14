import Foundation

public enum VoiceGATTConstants {
    // Values observed in the sample. Keep protocol values isolated from app policy.
    public static let serviceUUID = UUID(uuidString: "8341F2B4-C013-4F04-8197-C4CDB42E26DC")!
    public static let notificationUUID = UUID(uuidString: "30E69638-3752-4FEB-A3AA-3226BCD05ACE")!
    public static let enableCommand = Data([0xAF])
}

public struct GATTCharacteristicRef: Hashable, Sendable {
    public let uuid: UUID
    public let supportsNotify: Bool
    public let supportsWriteWithoutResponse: Bool

    public init(uuid: UUID, supportsNotify: Bool, supportsWriteWithoutResponse: Bool) {
        self.uuid = uuid
        self.supportsNotify = supportsNotify
        self.supportsWriteWithoutResponse = supportsWriteWithoutResponse
    }
}

public enum VoiceMonitorState: Equatable, Sendable {
    case idle
    case scanning
    case connecting
    case discovering
    case subscribing
    case enabling
    case ready
    case streaming
    case stopping
    case failed(String)
}

public enum VoiceMonitorError: Error, Equatable, Sendable {
    case bluetoothUnavailable
    case remoteNotFound
    case serviceNotFound
    case characteristicNotFound
    case notificationSubscriptionFailed(String)
    case enableCommandFailed(String)
    case malformedPacket(String)
    case transport(String)
}

public enum VoicePacketKind: Equatable, Sendable {
    case primaryAudio
    case continuationAudio
    case metadata
    case unknown
}

public struct VoicePacket: Sendable, Equatable {
    public let kind: VoicePacketKind
    public let sequence: UInt16?
    public let payload: Data
    public let raw: Data
    public let receivedAt: Date

    public init(kind: VoicePacketKind, sequence: UInt16?, payload: Data, raw: Data, receivedAt: Date = Date()) {
        self.kind = kind
        self.sequence = sequence
        self.payload = payload
        self.raw = raw
        self.receivedAt = receivedAt
    }
}

public struct VoiceMonitorStatistics: Sendable, Equatable {
    public private(set) var primaryAudioFrames = 0
    public private(set) var continuationFrames = 0
    public private(set) var metadataFrames = 0
    public private(set) var failedPackets = 0

    public init() {}

    mutating func record(_ packet: VoicePacket) {
        switch packet.kind {
        case .primaryAudio: primaryAudioFrames += 1
        case .continuationAudio: continuationFrames += 1
        case .metadata: metadataFrames += 1
        case .unknown: break
        }
    }

    mutating func recordFailure() {
        failedPackets += 1
    }
}

public struct VoicePacketLayout: Sendable, Equatable {
    public let typeByteOffset: Int
    public let sequenceByteOffset: Int?
    public let payloadOffset: Int
    public let primaryTypeValues: Set<UInt8>
    public let continuationTypeValues: Set<UInt8>
    public let metadataTypeValues: Set<UInt8>

    public init(
        typeByteOffset: Int,
        sequenceByteOffset: Int?,
        payloadOffset: Int,
        primaryTypeValues: Set<UInt8>,
        continuationTypeValues: Set<UInt8>,
        metadataTypeValues: Set<UInt8>
    ) {
        self.typeByteOffset = typeByteOffset
        self.sequenceByteOffset = sequenceByteOffset
        self.payloadOffset = payloadOffset
        self.primaryTypeValues = primaryTypeValues
        self.continuationTypeValues = continuationTypeValues
        self.metadataTypeValues = metadataTypeValues
    }

    public static let unclassified = VoicePacketLayout(
        typeByteOffset: 0,
        sequenceByteOffset: nil,
        payloadOffset: 0,
        primaryTypeValues: [],
        continuationTypeValues: [],
        metadataTypeValues: []
    )
}

public protocol VoiceGATTTransport: AnyObject {
    func scanForVoiceRemote() async throws -> UUID
    func connect(to remoteID: UUID) async throws
    func discoverVoiceCharacteristic() async throws -> GATTCharacteristicRef
    func setNotify(_ enabled: Bool, on characteristic: GATTCharacteristicRef) async throws
    func write(_ data: Data, to characteristic: GATTCharacteristicRef, withResponse: Bool) async throws
    func disconnect()
}
