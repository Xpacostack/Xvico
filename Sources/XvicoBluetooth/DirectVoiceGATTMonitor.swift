import Foundation

public actor DirectVoiceGATTMonitor {
    public private(set) var state: VoiceMonitorState = .idle
    public private(set) var statistics = VoiceMonitorStatistics()

    private let transport: VoiceGATTTransport
    private let parser: VoicePacketParser
    private var remoteID: UUID?
    private var characteristic: GATTCharacteristicRef?

    public init(transport: VoiceGATTTransport, parser: VoicePacketParser = VoicePacketParser()) {
        self.transport = transport
        self.parser = parser
    }

    public func start() async throws {
        state = .scanning
        do {
            let remote = try await transport.scanForVoiceRemote()
            remoteID = remote
            state = .connecting
            try await transport.connect(to: remote)
            state = .discovering
            let voiceCharacteristic = try await transport.discoverVoiceCharacteristic()
            guard voiceCharacteristic.uuid == VoiceGATTConstants.notificationUUID else {
                throw VoiceMonitorError.characteristicNotFound
            }
            characteristic = voiceCharacteristic
            state = .subscribing
            try await transport.setNotify(true, on: voiceCharacteristic)
            state = .ready
        } catch let error as VoiceMonitorError {
            state = .failed(String(describing: error))
            throw error
        } catch {
            state = .failed(error.localizedDescription)
            throw VoiceMonitorError.transport(error.localizedDescription)
        }
    }

    public func enableVoice() async throws {
        guard let characteristic else { throw VoiceMonitorError.characteristicNotFound }
        guard characteristic.supportsWriteWithoutResponse else {
            throw VoiceMonitorError.enableCommandFailed("characteristic does not support writeWithoutResponse")
        }
        state = .enabling
        do {
            // The sample logs an AF command and uses writeWithoutResponse.
            try await transport.write(VoiceGATTConstants.enableCommand, to: characteristic, withResponse: false)
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
            throw VoiceMonitorError.enableCommandFailed(error.localizedDescription)
        }
    }

    public func handleNotification(_ data: Data, receivedAt: Date = Date()) throws -> VoicePacket {
        do {
            let packet = try parser.parse(data, receivedAt: receivedAt)
            statistics.record(packet)
            if state == .ready { state = .streaming }
            return packet
        } catch {
            statistics.recordFailure()
            throw error
        }
    }

    public func stop() {
        state = .stopping
        transport.disconnect()
        remoteID = nil
        characteristic = nil
        state = .idle
    }
}
