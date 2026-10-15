import AppKit
import Foundation

struct RemoteVoiceIPC {
    private var pending = Data()
    mutating func ingest(_ data: Data) throws -> [RemoteOpusFrame] {
        pending.append(data)
        var frames: [RemoteOpusFrame] = []
        while pending.count >= 6 {
            let bytes = Array(pending.prefix(6))
            let length = Int(bytes[0]) | Int(bytes[1]) << 8
            guard (2...95).contains(length) else { pending.removeAll(); throw RemoteAudioError.malformedFrame }
            guard pending.count >= length + 6 else { break }
            // Data.removeFirst may advance startIndex without rebasing it.
            // dropFirst/prefix operate relative to the collection's real start,
            // including the second frame in a single pipe read.
            let packet = Data(pending.dropFirst(6).prefix(length))
            guard packet.first == 0xB8 else { pending.removeAll(); throw RemoteAudioError.malformedFrame }
            frames.append(RemoteOpusFrame(session: UInt16(bytes[2]) | UInt16(bytes[3]) << 8,
                                          sequence: UInt16(bytes[4]) | UInt16(bytes[5]) << 8, packet: packet))
            pending.removeFirst(length + 6)
        }
        return frames
    }
}

@MainActor
protocol RemoteVoiceCapturing: AnyObject {
    func start(usePersistentApproval: Bool,
               onFrame: @escaping (RemoteOpusFrame) -> Void, onStatus: @escaping (String) -> Void,
               onReady: @escaping () -> Void, onError: @escaping (String) -> Void)
    func stop()
}

/// Evaluates startup and post-start health using monotonic time. The ready
/// marker alone is not proof that the backend is still alive.
struct RemoteCaptureHealth {
    enum Action: Equatable { case waiting, running, startReader(String), ended, timedOut }
    let startedAt: Double
    var startupTimeout: Double = 150
    private(set) var readerStarted = false

    mutating func poll(now: Double, backendEnded: Bool, capturePath: String?) -> Action {
        if backendEnded { return .ended }
        if readerStarted { return .running }
        if let path = capturePath, path.hasPrefix("/private/var/tmp/xvibe-voice."), path.hasSuffix("/remote.pklg") {
            readerStarted = true
            return .startReader(path)
        }
        return now - startedAt >= startupTimeout ? .timedOut : .waiting
    }
}

@MainActor
final class RemoteVoiceCapture: RemoteVoiceCapturing {
    private var session: URL?
    private var authorization: Task<Void, Never>?
    private var polling: Task<Void, Never>?
    private var reader: Process?
    private var pipe: Pipe?
    private var parser = RemoteVoiceIPC()
    private var generation = UUID()
    private var serviceConnection: NSXPCConnection?

    func start(usePersistentApproval: Bool = true,
               onFrame: @escaping (RemoteOpusFrame) -> Void, onStatus: @escaping (String) -> Void,
               onReady: @escaping () -> Void,
               onError: @escaping (String) -> Void) {
        stop()
        let token = UUID(); generation = token
        let resources = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources")
        let helper = resources.appendingPathComponent("VoiceTools/XvibeVoiceCapture")
        let backendHelper = resources.appendingPathComponent("AudioBackend/XvibeBackendHelper")
        let installedBackend = FileManager.default.isExecutableFile(atPath: "/Library/Application Support/Xvibe/AudioBackend/XvibeBackendRunner")
        let readerURL = resources.appendingPathComponent("VoiceTools/XvibeFrameReader")
        guard FileManager.default.isExecutableFile(atPath: helper.path), FileManager.default.isExecutableFile(atPath: readerURL.path) else {
            onError("语音采集工具尚未打包"); return
        }
        guard let runtime = VoiceRuntimeLocation.resolve(app: Bundle.main.bundleURL, home: FileManager.default.homeDirectoryForCurrentUser) else {
            onError("请先在语音设置中导入官方 Apple 运行时"); return
        }
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/Xvibe/VoiceSessions/\(UUID().uuidString)")
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        catch { onError(error.localizedDescription); return }
        session = directory
        let persistent = usePersistentApproval && VoiceBackendAuthorization.isReady()
        let arguments = installedBackend
            ? [backendHelper.path, "session", directory.path, String(getuid()), String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundleURL.path, "compat"]
            : [helper.path, runtime.path, directory.path, String(getuid()), String(ProcessInfo.processInfo.processIdentifier), "--compat-diagnostics"]
        let command = arguments
            .map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
        let literal = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(literal)\" with administrator privileges"
        if persistent {
            guard connectService(directory: directory, token: token, onError: onError) else { return }
            onStatus("正在启动已授权语音后台")
        } else {
            onStatus("等待系统管理员批准本次临时语音采集")
            authorization = Task {
                let error = await Task.detached(priority: .userInitiated) { () -> String? in
                    var details: NSDictionary?
                    guard let appleScript = NSAppleScript(source: script) else { return "无法创建系统管理员批准请求" }
                    appleScript.executeAndReturnError(&details)
                    return details?[NSAppleScript.errorMessage] as? String
                }.value
                guard self.generation == token else { return }
                if let error { self.stop(); onError(error) }
                else { self.stop(); onError("临时语音采集已结束；请重新开始语音输入") }
            }
        }
        polling = Task { [weak self] in
            var health = RemoteCaptureHealth(startedAt: ProcessInfo.processInfo.systemUptime)
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: health.readerStarted ? 1_000_000_000 : 250_000_000) }
                catch { return }
                guard !Task.isCancelled, let self, self.generation == token else { return }
                let ended = FileManager.default.fileExists(atPath: directory.appendingPathComponent("backend-ended").path)
                let data = health.readerStarted ? nil : try? Data(contentsOf: directory.appendingPathComponent("ready.json"))
                let value = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] }
                switch health.poll(now: ProcessInfo.processInfo.systemUptime, backendEnded: ended, capturePath: value?["capture"]) {
                case .waiting, .running: break
                case .ended:
                    self.stop(); onError("语音后台提前结束，请检查蓝牙连接和后台授权"); return
                case .timedOut:
                    self.stop(); onError(persistent ? "已授权语音后台启动超时，请检查状态或重新安装后台" : "语音采集尚未启动；取消或未完成管理员批准"); return
                case .startReader(let path):
                    guard self.runReader(readerURL, trace: path, token: token, onFrame: onFrame, onError: onError) else { return }
                    onReady()
                    guard self.generation == token else { return }
                    onStatus("等待 Siri Remote 音频；临时采集最多持续一小时")
                }
            }
        }
    }
    private func connectService(directory: URL, token: UUID, onError: @escaping (String) -> Void) -> Bool {
        guard let fingerprint = Bundle.main.object(forInfoDictionaryKey: "XvicoVoiceServiceSigningIdentity") as? String,
              let requirement = VoiceHelperContract.requirement(identifier: VoiceHelperContract.label, fingerprint: fingerprint) else {
            stop(); onError("语音后台签名信息缺失，请重新构建应用"); return false
        }
        let connection = NSXPCConnection(machServiceName: VoiceHelperContract.label, options: .privileged)
        connection.setCodeSigningRequirement(requirement)
        connection.remoteObjectInterface = NSXPCInterface(with: VoiceHelperProtocol.self)
        let failed: (String) -> Void = { [weak self] message in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.stop(); onError(message)
            }
        }
        connection.invalidationHandler = { failed("已授权语音后台连接已断开，请检查后台状态") }
        connection.interruptionHandler = { failed("已授权语音后台连接中断，请重新启动") }
        serviceConnection = connection; connection.resume()
        guard let endpoint = connection.remoteObjectProxyWithErrorHandler({ _ in
            failed("无法连接已授权语音后台，请检查状态或重新安装后台")
        }) as? VoiceHelperProtocol else {
            stop(); onError("无法创建语音后台连接"); return false
        }
        endpoint.startSession(directory.lastPathComponent) { message in if let message { failed(message) } }
        return true
    }
    private func runReader(_ executable: URL, trace: String, token: UUID,
                           onFrame: @escaping (RemoteOpusFrame) -> Void, onError: @escaping (String) -> Void) -> Bool {
        let process = Process(); let output = Pipe()
        process.executableURL = executable; process.arguments = [trace]; process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] ended in
            let status = ended.terminationStatus
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.stop()
                onError("语音帧读取已停止（状态 \(status)），请重新开始语音输入")
            }
        }
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                do {
                    for frame in try self.parser.ingest(data) {
                        guard self.generation == token else { return }
                        onFrame(frame)
                    }
                }
                catch { self.stop(); onError(error.localizedDescription) }
            }
        }
        do { try process.run(); reader = process; pipe = output; return true }
        catch { stop(); onError(error.localizedDescription); return false }
    }
    func stop() {
        generation = UUID(); polling?.cancel(); polling = nil
        serviceConnection?.invalidate(); serviceConnection = nil
        pipe?.fileHandleForReading.readabilityHandler = nil
        if reader?.isRunning == true { reader?.terminate() }
        reader = nil; pipe = nil; parser = RemoteVoiceIPC()
        if let session { try? Data().write(to: session.appendingPathComponent("stop"), options: .atomic) }
        session = nil
        authorization?.cancel(); authorization = nil
    }
}
