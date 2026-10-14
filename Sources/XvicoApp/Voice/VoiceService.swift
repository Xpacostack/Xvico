import AVFoundation
import Combine
import Speech

enum VoiceInputSource: String, CaseIterable, Identifiable {
    case mac = "Mac 麦克风", siriRemote = "Siri Remote 麦克风"
    var id: String { rawValue }
}

enum VoiceRecognitionMode: String, CaseIterable, Identifiable {
    case local = "Xvico 本机识别", inputMethod = "输入法语音输入"
    var id: String { rawValue }
    static func restored(from value: String?) -> Self {
        let current = value?.replacingOccurrences(of: "Xvibe", with: "Xvico")
            .replacingOccurrences(of: "Xpavi", with: "Xvico")
        return current.flatMap(Self.init(rawValue:)) ?? .local
    }
}

@MainActor
final class VoiceService: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var isStarting = false
    @Published private(set) var isFinalizing = false
    @Published private(set) var transcript = ""
    @Published private(set) var status = "语音已开放 · 等待开始"
    @Published private(set) var errorMessage: String?
    @Published var inputSource: VoiceInputSource = VoiceInputSource(rawValue: UserDefaults.standard.string(forKey: "xvibe.voice.inputSource") ?? "") ?? .mac {
        didSet { UserDefaults.standard.set(inputSource.rawValue, forKey: "xvibe.voice.inputSource") }
    }
    @Published var remotePushToTalk = UserDefaults.standard.bool(forKey: "xvibe.voice.pushToTalk") {
        didSet { UserDefaults.standard.set(remotePushToTalk, forKey: "xvibe.voice.pushToTalk") }
    }
    @Published var recognitionMode = VoiceRecognitionMode.restored(from: UserDefaults.standard.string(forKey: "xvibe.voice.recognitionMode")) {
        didSet { UserDefaults.standard.set(recognitionMode.rawValue, forKey: "xvibe.voice.recognitionMode") }
    }
    @Published var inputMethodTriggerKey = UserDefaults.standard.string(forKey: "xvibe.voice.inputMethodTriggerKey") ?? "Fn" {
        didSet { UserDefaults.standard.set(inputMethodTriggerKey, forKey: "xvibe.voice.inputMethodTriggerKey") }
    }
    func handleMappedKeyboard(_ binding: KeyBinding, down: Bool, model: AppModel) {
        guard down, recognitionMode == .inputMethod, inputSource == .siriRemote,
              model.remoteVoice.isSubscribed,
              binding.normalizedKeyboard.value == inputMethodTriggerKey,
              binding.modifiers.isEmpty else { return }
        model.remoteVoice.inputMethodTrigger()
    }
    private var finishing: Task<Void, Never>?
    private var finalTranscriptHandler: ((String) -> Void)?
    private var pushStartup: Task<Void, Never>?
    private var pushHeld = false
    private var releaseMicrophone: (() -> Void)?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var startup: Task<Void, Never>?
    private var tapInstalled = false
    private var generation = UUID()
    private var remoteStop: (() -> Void)?
    private var recognizer: SFSpeechRecognizer? { SFSpeechRecognizer() }
    static var microphonePermissionLabel: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return "已授权"
        case .denied: return "系统已拒绝"
        case .restricted: return "系统限制"
        case .notDetermined: return "尚未请求授权"
        @unknown default: return "未知状态"
        }
    }
    static var speechPermissionLabel: String {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return "已授权"
        case .denied: return "系统已拒绝"
        case .restricted: return "系统限制"
        case .notDetermined: return "尚未请求授权"
        @unknown default: return "未知状态"
        }
    }
    var readiness: String {
        if recognitionMode == .inputMethod { return "由输入法识别" }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              inputSource == .siriRemote || AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return "等待系统授权" }
        return recognizer?.supportsOnDeviceRecognition == true ? "本机模型可用" : "本机模型不可用"
    }

    @discardableResult
    func requestMicrophonePermission() async -> Bool {
        let state = AVCaptureDevice.authorizationStatus(for: .audio)
        if state == .authorized { return true }
        guard state == .notDetermined else { return false }
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { continuation.resume(returning: $0) }
        }
    }
    @discardableResult
    func requestSpeechPermission() async -> Bool {
        let state = SFSpeechRecognizer.authorizationStatus()
        if state == .authorized { return true }
        guard state == .notDetermined else { return false }
        let result = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        return result == .authorized
    }

    func toggle() {
        if isListening || isStarting { stop(); return }
        startup = Task { await start(source: .mac) }
    }

    func startRemote(stop: @escaping () -> Void = {}) async {
        remoteStop = stop
        await start(source: .siriRemote)
    }
    func appendRemoteAudio(_ buffer: AVAudioPCMBuffer) {
        guard isListening, inputSource == .siriRemote else { return }
        request?.append(buffer); status = "正在本机识别 Siri Remote 音频"
    }
    func remoteFailed(_ detail: String) {
        guard inputSource == .siriRemote else { return }
        stop(); status = "Siri Remote 麦克风尚不可用"; errorMessage = detail
    }
    // The audio channel is prepared once; each hardware hold creates a fresh
    // recognizer request, and release ends audio without cancelling finalization.
    func handleRemotePush(_ pressed: Bool, model: AppModel) -> Bool {
        guard inputSource == .siriRemote || !pressed && pushHeld else { return false }
        if recognitionMode == .inputMethod { return false }
        if !remotePushToTalk && model.remoteVoice.isSubscribed && inputSource == .siriRemote && isListening {
            model.remoteVoice.setMicrophoneHeld(pressed)
        }
        guard remotePushToTalk || !pressed && pushHeld else { return false }
        if pressed {
            guard !isFinalizing else { model.show("请等待上一段语音完成转写"); return true }
            guard !pushHeld else { return true }
            guard model.remoteVoice.isSubscribed else {
                model.show("请先在语音设置连接 Siri Remote 麦克风")
                return true
            }
            stop()
            pushHeld = true
            let target = model.currentBundleID
            pushStartup = Task { [weak self, weak model] in
                guard let self else { return }
                await self.startRemote()
                guard !Task.isCancelled, self.pushHeld, self.isListening else { return }
                self.finalTranscriptHandler = { [weak model] text in model?.insertVoiceText(text, targetBundleID: target) }
                self.releaseMicrophone = { [weak model] in model?.remoteVoice.setMicrophoneHeld(false) }
                model?.remoteVoice.setMicrophoneHeld(true)
            }
        } else {
            releaseMicrophone?(); releaseMicrophone = nil
            pushHeld = false
            pushStartup?.cancel(); pushStartup = nil
            if isStarting { stop(); status = "按住时间太短，请等待识别开始后说话" }
            else { finishRemote() }
        }
        return true
    }
    func finishRemote() {
        guard isListening, inputSource == .siriRemote else { return }
        isListening = false
        isFinalizing = true
        request?.endAudio()
        status = "正在完成转写"
        let session = generation
        finishing?.cancel()
        finishing = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
            guard let self, self.generation == session else { return }
            self.stop()
            self.status = "识别未返回最终结果；已保留文本供手动输入"
        }
    }
    private func start(source: VoiceInputSource) async {
        guard !isListening && !isStarting else { return }
        inputSource = source
        isStarting = true
        defer { isStarting = false }
        let session = UUID()
        generation = session
        errorMessage = nil
        let audioAllowed = source == .siriRemote ? true : await requestMicrophonePermission()
        guard !Task.isCancelled, generation == session else { return }
        guard audioAllowed else {
            status = "需要在系统设置中允许麦克风"
            errorMessage = status
            return
        }
        let speechAllowed = await requestSpeechPermission()
        guard !Task.isCancelled, generation == session else { return }
        guard speechAllowed else {
            status = "需要在系统设置中允许语音识别"
            errorMessage = status
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            status = "当前系统语音识别暂不可用"
            errorMessage = status
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            status = "当前系统或语言不支持本机离线识别"
            errorMessage = "Xvico 不会将语音发送到在线识别服务。请更换受支持的识别语言或更新本机语音资源。"
            return
        }

        if source == .mac {
            let input = engine.inputNode
            guard input.outputFormat(forBus: 0).sampleRate > 0, input.outputFormat(forBus: 0).channelCount > 0 else {
                status = "没有可用的 Mac 麦克风输入"; errorMessage = status; return
            }
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        self.request = request
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.generation == session else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        let handler = self.finalTranscriptHandler
                        let text = self.transcript
                        self.stop(); self.status = "识别完成"
                        if !text.isEmpty { handler?(text) }
                        return
                    }
                }
                if let error {
                    self.stop()
                    if Self.isNoSpeech(error) {
                        self.status = source == .siriRemote ? "未检测到语音，请按住 Siri 后再说话" : "未检测到语音，请靠近所选麦克风再试"
                        self.errorMessage = nil
                    } else {
                        self.status = "语音识别遇到问题"
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
        }
        if source == .mac {
            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                request.append(buffer)
            }
            tapInstalled = true
        }
        do {
            if source == .mac { engine.prepare(); try engine.start() }
            isListening = true
            status = source == .siriRemote ? "等待 Siri Remote 音频（未使用 Mac 麦克风）" : "正在本机识别 Mac 麦克风"
            transcript = ""
        } catch {
            status = "无法启动麦克风"
            errorMessage = error.localizedDescription
            stop()
        }
    }

    static func isNoSpeech(_ error: Error) -> Bool {
        let error = error as NSError
        return (error.domain == "kAFAssistantErrorDomain" && error.code == 1110)
            || error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "no speech detected"
    }

    func stop() {
        releaseMicrophone?(); releaseMicrophone = nil
        isFinalizing = false
        pushStartup?.cancel(); pushStartup = nil; pushHeld = false
        finishing?.cancel(); finishing = nil; finalTranscriptHandler = nil
        let remoteStop = remoteStop; self.remoteStop = nil
        startup?.cancel(); startup = nil; generation = UUID(); isStarting = false
        if engine.isRunning { engine.stop() }
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isListening = false
        if status.hasPrefix("正在") { status = "语音已开放 · 等待开始" }
        remoteStop?()
    }
}
