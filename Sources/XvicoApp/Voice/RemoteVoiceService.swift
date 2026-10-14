import AVFoundation
import Combine
import Foundation
import XvicoBluetooth

struct InputMethodMicrophoneGate {
    private(set) var active = false
    mutating func trigger() -> Bool { active.toggle(); return active }
    mutating func reset() { active = false }
}

@MainActor
final class RemoteVoiceService: ObservableObject {
    @Published private(set) var status = "尚未连接语音通道"
    @Published private(set) var isConnecting = false
    @Published private(set) var isSubscribed = false
    @Published private(set) var notifications = 0
    @Published private(set) var decodedFrames = 0
    @Published private(set) var unknownFrames = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var microphoneControlStatus = "尚未发送遥控器麦克风控制"
    @Published private(set) var microphoneHeld = false
    @Published private(set) var microphoneControlError: String?
    @Published private(set) var lastAudioAt: Date?
    private var inputMethodGate = InputMethodMicrophoneGate()
    func inputMethodTrigger() {
        setMicrophoneHeld(inputMethodGate.trigger())
    }
    private var transport: CoreBluetoothVoiceTransport?
    private var monitor: DirectVoiceGATTMonitor?
    private var connection: Task<Void, Never>?
    private var generation = UUID()
    private var stream: RemoteAudioStream?
    private var audioHandler: ((AVAudioPCMBuffer) -> Void)?
    private var errorHandler: ((String) -> Void)?
    private let defaults: UserDefaults
    private let microphoneControl: (Bool) -> Int32
    private let capture = RemoteVoiceCapture()

    init(defaults: UserDefaults = .standard,
         microphoneControl: @escaping (Bool) -> Int32 = RemoteMicrophoneControl.setEnabled) {
        self.defaults = defaults
        self.microphoneControl = microphoneControl
    }
    var hasDecodedAudio: Bool { decodedFrames > 0 }
    func setMicrophoneHeld(_ held: Bool) {
        guard held != microphoneHeld else { return }
        if held { stream?.beginUtterance() }
        let result = microphoneControl(held)
        // Keep a failed stop pending so cleanup can retry it.
        if result == 0 {
            microphoneHeld = held
            lastAudioAt = nil
            microphoneControlError = nil
        }
        microphoneControlStatus = result == 0
            ? (held ? "已请求开启遥控器麦克风" : "已请求停止遥控器麦克风")
            : String(format: "遥控器麦克风控制返回 0x%08X", result)
        if result != 0 { microphoneControlError = microphoneControlStatus }
    }

    func startCapture(usePersistentApproval: Bool = true, audio: @escaping (AVAudioPCMBuffer) -> Void,
                      failure: @escaping (String) -> Void) {
        stop(); audioHandler = audio; errorHandler = failure
        notifications = 0; decodedFrames = 0; unknownFrames = 0; errorMessage = nil
        do { stream = try RemoteAudioStream() }
        catch { fail(error.localizedDescription); return }
        isConnecting = true
        let session = generation
        capture.start(usePersistentApproval: usePersistentApproval, onFrame: { [weak self] in self?.receiveFrame($0) },
                      onStatus: { [weak self] status in
                          guard let self, self.generation == session else { return }
                          self.status = status
                      },
                      onReady: { [weak self] in
                          guard let self, self.generation == session else { return }
                          self.isConnecting = false; self.isSubscribed = true
                      },
                      onError: { [weak self] in self?.fail($0) })
    }

    func start(audio: @escaping (AVAudioPCMBuffer) -> Void = { _ in },
               failure: @escaping (String) -> Void = { _ in }) {
        stop()
        let session = UUID(); generation = session
        audioHandler = audio; errorHandler = failure
        notifications = 0; decodedFrames = 0; unknownFrames = 0; errorMessage = nil
        do { stream = try RemoteAudioStream() }
        catch { fail(error.localizedDescription); return }
        isConnecting = true; status = "正在查找已连接的 Siri Remote"
        let saved = defaults.string(forKey: "xvibe.voice.remoteID")
        let transport = CoreBluetoothVoiceTransport(preferredRemoteID: saved.flatMap(UUID.init(uuidString:)))
        let monitor = DirectVoiceGATTMonitor(transport: transport)
        self.transport = transport; self.monitor = monitor
        // Register before subscription / AF: initial notifications cannot be lost.
        transport.onNotification = { [weak self] data in
            Task { @MainActor [weak self] in
                guard let self, self.generation == session else { return }
                self.receive(data)
            }
        }
        transport.onDiagnostic = { [weak self] detail in
            Task { @MainActor [weak self] in
                guard let self, self.generation == session, !self.hasDecodedAudio else { return }
                self.status = detail
            }
        }
        transport.onDisconnect = { [weak self] detail in
            Task { @MainActor [weak self] in
                guard let self, self.generation == session else { return }
                self.fail(detail)
            }
        }
        connection = Task { [weak self] in
            do {
                try await monitor.start()
                try Task.checkCancellation()
                guard let self, self.generation == session else { return }
                try await monitor.enableVoice()
                try Task.checkCancellation()
                guard self.generation == session else { return }
                self.isConnecting = false; self.isSubscribed = true
                if !self.hasDecodedAudio { self.status = "已订阅语音通知，等待实际音频；按住 Siri 键说话" }
            } catch {
                guard let self, self.generation == session, !Task.isCancelled else { return }
                self.fail(Self.describe(error))
            }
        }
    }

    // Pure data path; tests use known codec frames and do not record speech.
    func receive(_ data: Data) {
        notifications += 1
        do {
            let frame = try RemoteOpusFrame.parse(data)
            try decode(frame)
        } catch RemoteAudioError.malformedFrame {
            unknownFrames += 1
            status = "收到 \(notifications) 个语音通知，格式尚未确认（已解码 \(decodedFrames) 帧）"
        } catch { fail(error.localizedDescription) }
    }
    private func receiveFrame(_ frame: RemoteOpusFrame) {
        notifications += 1
        do { try decode(frame) } catch { fail(error.localizedDescription) }
    }
    private func decode(_ frame: RemoteOpusFrame) throws {
        guard let stream else { return }
        let buffers = try stream.ingest(frame)
        for buffer in buffers { audioHandler?(buffer) }
        decodedFrames = stream.decodedFrames
        if !buffers.isEmpty {
            lastAudioAt = Date()
            isConnecting = false; isSubscribed = true
            status = "正在接收 Siri Remote 麦克风音频"
        }
    }
    func stop() {
        inputMethodGate.reset()
        setMicrophoneHeld(false)
        capture.stop()
        generation = UUID(); connection?.cancel(); connection = nil
        transport?.disconnect(); transport = nil; monitor = nil
        stream = nil; audioHandler = nil; errorHandler = nil
        lastAudioAt = nil
        isConnecting = false; isSubscribed = false
        status = "语音通道已停止"
    }
    private func fail(_ message: String) {
        let handler = errorHandler
        stop()
        handler?(message)
        errorMessage = message; status = "遥控器麦克风尚不可用"
    }
    private static func describe(_ error: Error) -> String {
        guard let error = error as? VoiceMonitorError else { return error.localizedDescription }
        switch error {
        case .serviceNotFound: return "macOS 未向应用公开遥控器语音服务。按键与触控仍可用；语音需要额外的音频采集后端。"
        case .remoteNotFound: return "未找到可连接的 Siri Remote 语音接口"
        case .bluetoothUnavailable: return "蓝牙未开启或 Xvico 尚未获得蓝牙授权"
        case .characteristicNotFound: return "遥控器语音特征不可见，不能将按键连接当成麦克风已启用"
        case .notificationSubscriptionFailed(let value), .enableCommandFailed(let value), .malformedPacket(let value), .transport(let value): return value
        }
    }
}
