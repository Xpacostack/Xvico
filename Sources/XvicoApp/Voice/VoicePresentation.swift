import Foundation

enum VoiceStage: Equatable {
    case idle, starting, ready, awaitingAudio, capturing, recognizing, finalizing, completed, needsAttention
}

struct VoicePresentation: Equatable {
    let stage: VoiceStage
    let title: String
    let detail: String
}

// Presentation uses the current utterance and recent decoded buffers. Lifetime
// frame counts stay in diagnostics and cannot turn an idle microphone green.
struct VoiceActivitySnapshot {
    var source: VoiceInputSource = .siriRemote
    var mode: VoiceRecognitionMode = .local
    var channelConnecting = false
    var channelReady = false
    var microphoneRequested = false
    var lastAudioAt: Date?
    var recognitionStarting = false
    var recognitionListening = false
    var finalizing = false
    var recognitionStatus = ""
    var channelError: String?
    var microphoneError: String?
    var recognitionError: String?
    var inputMethodTriggerKey = "Fn"

    func presentation(at now: Date) -> VoicePresentation {
        let remoteError = source == .siriRemote ? (microphoneError ?? channelError) : nil
        let speechError = mode == .local ? recognitionError : nil
        if let error = remoteError ?? speechError {
            return .init(stage: .needsAttention, title: "需要检查", detail: error)
        }
        if mode == .local && finalizing {
            return .init(stage: .finalizing, title: "正在完成识别", detail: "麦克风已停止收音，正在等待最终文字。")
        }
        if recognitionStarting || (source == .siriRemote && channelConnecting) {
            return .init(stage: .starting, title: "正在启动", detail: source == .siriRemote
                ? "正在准备遥控器音频通道，请稍候。" : "正在准备麦克风与本机识别。")
        }
        if source == .mac {
            if mode == .inputMethod {
                return .init(stage: .ready, title: "输入法模式", detail: "在目标输入框使用输入法的语音快捷键。")
            }
            if recognitionListening {
                return .init(stage: .recognizing, title: "正在识别", detail: "使用 Mac 麦克风与本机语音识别。")
            }
            return inactivePresentation()
        }
        guard channelReady else { return inactivePresentation() }
        if microphoneRequested {
            let receiving = lastAudioAt.map { (0...1.2).contains(now.timeIntervalSince($0)) } ?? false
            guard receiving else {
                return .init(stage: .awaitingAudio, title: "等待麦克风音频", detail: "已请求收音；收到音频后会更新状态。")
            }
            if mode == .local && recognitionListening {
                return .init(stage: .recognizing, title: "正在识别", detail: "正在接收遥控器音频，使用本机语音识别。")
            }
            return .init(stage: .capturing, title: "正在收音", detail: mode == .inputMethod
                ? "音频正提供给输入法，文字由输入法写入。" : "正在接收 Siri Remote 麦克风音频。")
        }
        if mode == .local && recognitionStatus == "识别完成" {
            return .init(stage: .completed, title: "识别完成", detail: "麦克风已关闭，可以继续下一段语音。")
        }
        let detail: String
        if mode == .inputMethod {
            detail = "麦克风已关闭；执行 \(inputMethodTriggerKey) 映射可开始语音输入。"
        } else if recognitionStatus.hasPrefix("未检测到") || recognitionStatus.hasPrefix("识别未返回") {
            detail = recognitionStatus
        } else {
            detail = "麦克风已关闭，等待下一次语音输入。"
        }
        return .init(stage: .ready, title: "已就绪", detail: detail)
    }

    private func inactivePresentation() -> VoicePresentation {
        if mode == .local && recognitionStatus == "识别完成" {
            return .init(stage: .completed, title: "识别完成", detail: "识别文字已保留，可复制或输入到目标应用。")
        }
        let detail = mode == .local && (recognitionStatus.hasPrefix("未检测到") || recognitionStatus.hasPrefix("识别未返回"))
            ? recognitionStatus : source == .siriRemote
                ? "启动后可在目标应用中使用遥控器麦克风。" : "开始后使用 Mac 麦克风识别语音。"
        return .init(stage: .idle, title: "未启动", detail: detail)
    }
}
