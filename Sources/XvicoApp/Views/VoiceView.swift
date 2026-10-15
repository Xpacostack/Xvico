import SwiftUI
import AppKit

struct VoiceView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var voice: VoiceService
    @EnvironmentObject private var remoteVoice: RemoteVoiceService
    @State private var showingVoiceCommands = false
    @State private var captureApproval = false
    @StateObject private var backend = AudioBackendManager()
    @StateObject private var authorization = VoiceBackendAuthorization()
    @StateObject private var runtime = AppleVoiceRuntimeManager()
    @State private var removeAuthorizationApproval = false
    @State private var backendApproval = false
    @State private var brandingApproval = false
    @State private var installingBackend = true
    @StateObject private var virtualMicrophone = VirtualMicrophoneMonitor()
    @State private var showingInputHelp = false

    private var configurationLocked: Bool {
        voice.isListening || voice.isStarting || voice.isFinalizing || remoteVoice.isConnecting || remoteVoice.isSubscribed || authorization.busy || runtime.busy
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XvicoLayout.sectionSpacing) {
                SettingsSection(title: "语音输入", symbol: "waveform") {
                    inputSettings
                    Divider().padding(.vertical, 2)
                    if voice.inputSource == .siriRemote {
                        if !runtime.available { runtimeImport }
                        persistentAuthorization
                    }
                    VoiceStatusPanel(onToggle: toggleListening).disabled(authorization.busy || runtime.busy)
                    recognizedText
                }
                voiceCommands
                advancedDiagnostics
            }
            .frame(maxWidth: XvicoLayout.contentWidth)
            .padding(XvicoLayout.pageInset)
            .frame(maxWidth: .infinity)
        }.buttonStyle(XvicoActionButtonStyle()).onDisappear { virtualMicrophone.stop() }
        .onAppear { authorization.refresh(); runtime.refresh() }
        .alert(XvicoLocalization.string(installingBackend ? "安装 Xvico 系统语音后端？" : "卸载 Xvico 系统语音后端？", locale: model.interfaceLocale), isPresented: $backendApproval) {
            Button(XvicoLocalization.string("取消", locale: model.interfaceLocale), role: .cancel) { }
            Button(XvicoLocalization.string("继续并请求管理员批准", locale: model.interfaceLocale)) { backend.manage(installing: installingBackend) }
        } message: {
            XvicoLocalizedText("将\(installingBackend ? "安装" : "移除") Xvico 独立的 CoreAudio 虚拟麦克风和后台组件，并重启系统音频服务，当前音频会短暂中断。安装后只有启动语音采集才运行后台采集服务；如需安装 Apple 诊断配置，须由你亲自审核；兼容采集模式可不依赖该配置。")
                .environment(\.locale, model.interfaceLocale)
        }.alert(XvicoLocalization.string("更新系统麦克风名称？", locale: model.interfaceLocale), isPresented: $brandingApproval) {
            Button(XvicoLocalization.string("取消", locale: model.interfaceLocale), role: .cancel) { }
            Button(XvicoLocalization.string("继续并请求管理员批准", locale: model.interfaceLocale)) { backend.updateBranding() }
        } message: {
            XvicoLocalizedText("将已安装的虚拟麦克风更名为 Xvico Microphone，并重启系统音频服务。当前音频会短暂中断；设备身份和已保存的麦克风选择保持不变，不会启动录音或蓝牙诊断。")
                .environment(\.locale, model.interfaceLocale)
        }.alert(XvicoLocalization.string("配置遥控器语音后台？", locale: model.interfaceLocale), isPresented: $captureApproval) {
            Button(XvicoLocalization.string("取消", locale: model.interfaceLocale), role: .cancel) { }
            Button(XvicoLocalization.string("保存授权并安装后台", locale: model.interfaceLocale)) { Task { await authorization.install() } }
            Button(XvicoLocalization.string("仅启动本次（临时授权）", locale: model.interfaceLocale)) { startCapture(usePersistentApproval: false) }
        } message: {
            XvicoLocalizedText("保存授权会安装仅供 Xvico 调用的系统后台，需要管理员批准一次；安装本身不启动采音。以后点击启动即可复用授权，重开应用仍有效。每次采集仍会临时启用 HCISkipAuth 与蓝牙文件日志，可能含其他设备数据，可能短暂影响蓝牙连接；单次最多一小时。停止或退出后删除临时采集并恢复诊断设置，系统日志可能另留。可随时移除后台授权。也可选择仅授权本次。")
                .environment(\.locale, model.interfaceLocale)
        }.alert(XvicoLocalization.string("移除已保存的后台授权？", locale: model.interfaceLocale), isPresented: $removeAuthorizationApproval) {
            Button(XvicoLocalization.string("取消", locale: model.interfaceLocale), role: .cancel) { }
            Button(XvicoLocalization.string("移除后台授权", locale: model.interfaceLocale), role: .destructive) { Task { await authorization.remove() } }
        } message: {
            XvicoLocalizedText("将停止并移除持久语音后台，今后启动需重新批准；虚拟麦克风、按键映射和语音设置会保留。移除需要系统管理员批准。")
                .environment(\.locale, model.interfaceLocale)
        }.sheet(isPresented: $showingVoiceCommands) {
            VStack(spacing: 0) {
                HStack { Spacer(); Button("完成") { showingVoiceCommands = false } }.padding(12)
                VoiceCommandsEditorView()
            }.frame(width: 660, height: 520)
                .xvicoGlassPanel(cornerRadius: 22, floating: true)
                .xvicoPresentationSettings()
        }
    }

    private var persistentAuthorization: some View {
        HStack(spacing: 12) {
            Image(systemName: authorization.ready ? "checkmark.shield.fill" : "lock.shield")
                .font(.system(size: 22)).foregroundStyle(authorization.ready ? Color.green : Color.blue)
            VStack(alignment: .leading, spacing: 5) {
                XvicoLocalizedText(authorization.status).font(.system(size: 12, weight: .semibold))
                XvicoLocalizedText("一次安装，按需启动；记住授权不会持续收音。").font(XvicoTypography.caption)
                    .foregroundStyle(XvicoTheme.secondaryText)
            }
            Spacer(minLength: 8)
            if !authorization.ready {
                Button("保存后台授权") { captureApproval = true }.disabled(configurationLocked || !runtime.available)
            }
        }.padding(13).xvicoGlassPanel(cornerRadius: 12)
    }

    private var runtimeImport: some View {
        VStack(alignment: .leading, spacing: 9) {
            XvicoLocalizedLabel(runtime.status, systemImage: "shippingbox").font(.system(size: 12, weight: .semibold))
            XvicoLocalizedText("公开安装包不附带 Apple 工具。导入官方 PacketLogger.app 后即可配置遥控器语音，应用签名保持不变。")
                .font(XvicoTypography.caption).foregroundStyle(XvicoTheme.secondaryText)
            HStack {
                Button("导入 Apple 语音运行时") { runtime.chooseRuntime(locale: model.interfaceLocale) }.disabled(configurationLocked)
                Link("获取 Apple 官方工具", destination: URL(string: "https://developer.apple.com/download/all/")!)
                    .font(XvicoTypography.caption)
            }
        }.padding(13).xvicoGlassPanel(cornerRadius: 12)
    }

    private var inputSettings: some View {
        VStack(alignment: .leading, spacing: XvicoLayout.rowSpacing) {
            VoiceSettingRow(title: "麦克风来源") {
                XvicoOptionPicker(title: "麦克风来源", selection: $voice.inputSource,
                    options: VoiceInputSource.allCases.map { XvicoOption(value: $0, title: $0.rawValue, symbol: $0 == .siriRemote ? "appletvremote.gen3" : "mic") })
                    .disabled(configurationLocked)
            }
            VoiceSettingRow(title: "识别方式") {
                XvicoOptionPicker(title: "识别方式", selection: $voice.recognitionMode,
                    options: VoiceRecognitionMode.allCases.map { XvicoOption(value: $0, title: $0.rawValue, symbol: $0 == .local ? "waveform" : "keyboard") })
                    .disabled(configurationLocked)
            }
            HStack(spacing: 8) {
                XvicoLocalizedText(voice.recognitionMode == .inputMethod ? "文字由输入法识别并写入。" : "使用 macOS 本机语音识别。")
                    .font(XvicoTypography.caption).foregroundStyle(XvicoTheme.secondaryText)
                Spacer()
                Button { showingInputHelp.toggle() } label: {
                    Image(systemName: "questionmark.circle").font(.system(size: 14))
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(XvicoTheme.secondaryText)
                    .help("了解当前输入方式").accessibilityLabel("了解当前输入方式")
                    .popover(isPresented: $showingInputHelp) { inputHelp.xvicoPresentationSettings() }
            }
            if voice.inputSource == .siriRemote {
                if voice.recognitionMode == .inputMethod {
                    VoiceSettingRow(title: "输入法触发键") {
                        Picker("输入法触发键（无修饰键）", selection: $voice.inputMethodTriggerKey) {
                            ForEach(KeyboardOutput.all) { XvicoLocalizedText($0.name).tag($0.name) }
                        }.labelsHidden().controlSize(.large)
                            .frame(width: XvicoLayout.keyboardPickerWidth(for: voice.inputMethodTriggerKey))
                            .disabled(configurationLocked)
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        Button("将 Xvico Microphone 设为系统输入") {
                            do { model.show("系统输入：" + (try MacMicrophones.selectVirtualInput())) }
                            catch { model.show(error.localizedDescription) }
                        }.controlSize(.regular)
                        XvicoLocalizedText("会更改其他应用的默认输入。输入法支持单独选设备时，可直接选择 Xvico Microphone。")
                            .font(XvicoTypography.caption).foregroundStyle(XvicoTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Toggle("按住 Siri 说话，松开后输入前台应用", isOn: $voice.remotePushToTalk)
                        .toggleStyle(.switch).controlSize(.small)
                        .disabled(voice.isListening || voice.isStarting || voice.isFinalizing)
                    XvicoLocalizedText("开启后 Siri 键用于语音输入；关闭后使用原按键映射。")
                        .font(XvicoTypography.caption).foregroundStyle(XvicoTheme.secondaryText)
                }
            }
        }
    }

    private var inputHelp: some View {
        VStack(alignment: .leading, spacing: 12) {
            XvicoLocalizedText(voice.recognitionMode.rawValue).font(XvicoTypography.sectionTitle)
            if voice.recognitionMode == .inputMethod {
                if voice.inputSource == .siriRemote {
                    XvicoLocalizedText("Xvico 提供遥控器音频，输入法负责识别与写入文字。")
                    XvicoLocalizedText("单击、双击和长按各自执行你设置的映射。实际发出所选输入法触发键时，遥控器麦克风会切换收音状态；停止聆听会关闭麦克风。")
                } else {
                    XvicoLocalizedText("输入法直接使用 Mac 麦克风，负责识别与写入文字。")
                    XvicoLocalizedText("在目标输入框使用输入法的语音快捷键，并在输入法中选择麦克风。Xvico 无需启动语音后端。")
                }
            } else {
                XvicoLocalizedText("使用系统本机模型识别语音。识别结果会保留在本页，可复制或输入到目标应用。")
                if voice.inputSource == .siriRemote {
                    XvicoLocalizedText("启用按住 Siri 输入后，先启动遥控器音频通道，再到目标输入框按住 Siri 说话；松开后等待最终文字。")
                } else {
                    XvicoLocalizedText("点击开始聆听后使用 Mac 麦克风说话，停止后等待最终文字。")
                }
            }
        }.font(XvicoTypography.body).padding(18).frame(width: 340)
            .xvicoGlassPanel(cornerRadius: 18, floating: true)
    }

    @ViewBuilder private var recognizedText: some View {
        if voice.recognitionMode == .local && !voice.transcript.isEmpty {
            Divider().padding(.vertical, 2)
            XvicoLocalizedText("识别文本").font(XvicoTypography.caption).foregroundStyle(XvicoTheme.secondaryText)
            Text(voice.transcript).font(.system(size: 13)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .background(XvicoTheme.iconTile.opacity(0.5), in: RoundedRectangle(cornerRadius: 9))
            HStack {
                Button("复制") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(voice.transcript, forType: .string) }
                Button("输入到 \(model.currentApp)") { model.insertVoiceText(voice.transcript) }.buttonStyle(XvicoActionButtonStyle(prominent: true))
                Button("用当前场景执行") { executePhrase(voice.transcript) }
            }.controlSize(.small)
        }
    }

    private var voiceCommands: some View {
        SettingsSection(title: "语音命令", symbol: "list.bullet.rectangle") {
            Button("管理语音短语动作") { showingVoiceCommands = true }.controlSize(.regular)
            if model.shortcuts.isEmpty {
                XvicoLocalizedText("添加语音短语，为它配置开发命令或其他动作。")
                    .font(XvicoTypography.caption).foregroundStyle(XvicoTheme.secondaryText)
            } else {
                ForEach(model.shortcuts.filter(\.enabled)) { command in
                    HStack {
                        Image(systemName: "waveform").foregroundStyle(.blue)
                        XvicoLocalizedText("\"\(command.phrase)\"").font(.system(size: 12, weight: .medium))
                        Spacer()
                        XvicoLocalizedText(command.action.rawValue).font(XvicoTypography.caption).foregroundStyle(XvicoTheme.secondaryText)
                        Button("执行") { execute(command) }.controlSize(.small)
                    }
                }
            }
        }
    }

    private var advancedDiagnostics: some View {
        SettingsSection(title: "高级诊断", symbol: "slider.horizontal.3") {
            DisclosureGroup("系统语音后端与采集信息") {
                VStack(alignment: .leading, spacing: XvicoLayout.rowSpacing) {
                    VoiceLatencyView(voice: voice)
                    XvicoLocalizedText(backend.status).font(.system(size: 12, weight: .semibold))
                    XvicoLocalizedText("Siri Remote 采集仅在你启动时运行，停止后恢复原诊断设置。音频可提供给本机识别和 Xvico Microphone。安装虚拟麦克风不会更改系统默认输入。")
                        .font(XvicoTypography.caption).foregroundStyle(XvicoTheme.secondaryText)
                    HStack {
                        if backend.needsBrandingUpdate {
                            Button("更新麦克风名称") { brandingApproval = true }
                                .disabled(backend.busy || configurationLocked || virtualMicrophone.running)
                        }
                        Button(LocalizedStringKey(backend.installed ? "卸载虚拟麦克风后端" : "安装虚拟麦克风后端")) {
                            installingBackend = !backend.installed; backendApproval = true
                        }.disabled(backend.busy || remoteVoice.isConnecting || remoteVoice.isSubscribed || voice.isListening)
                        Button("检查状态") { backend.refresh() }.disabled(backend.busy)
                    }
                    if authorization.installed {
                        Button("重新安装授权后台") { captureApproval = true }
                            .disabled(configurationLocked || backend.busy)
                        Button("移除后台授权") { removeAuthorizationApproval = true }
                            .disabled(configurationLocked || backend.busy)
                    }
                    Button("检查后台授权") { authorization.refresh() }.disabled(authorization.busy)
                    if runtime.available {
                        Button("重新导入 Apple 运行时") { runtime.chooseRuntime(locale: model.interfaceLocale) }.disabled(configurationLocked)
                    }
                    if voice.inputSource == .siriRemote {
                        VStack(alignment: .leading, spacing: 6) {
                            XvicoLocalizedText(remoteVoice.status)
                            XvicoLocalizedText("收到通知 \(remoteVoice.notifications) · 已解码 \(remoteVoice.decodedFrames) 帧 · 未确认格式 \(remoteVoice.unknownFrames) 帧")
                            XvicoLocalizedText("麦克风控制：\(remoteVoice.microphoneControlStatus)")
                        }.font(XvicoTypography.caption).foregroundStyle(XvicoTheme.secondaryText).textSelection(.enabled)
                    }
                    if backend.installed {
                        Button(LocalizedStringKey(virtualMicrophone.running ? "停止电平检测" : "检测虚拟麦克风（10秒）")) {
                            if virtualMicrophone.running { virtualMicrophone.stop() } else { virtualMicrophone.start() }
                        }
                        XvicoLocalizedLabel(virtualMicrophone.status, systemImage: virtualMicrophone.peak > 0.0001 ? "checkmark.circle.fill" : virtualMicrophone.running ? "waveform" : "info.circle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(virtualMicrophone.peak > 0.0001 ? Color.green : Color.primary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .background((virtualMicrophone.peak > 0.0001 ? Color.green : Color.blue).opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
                        XvicoLocalizedText("点击检测后按住 Siri 说话，此处显示系统虚拟麦克风的电平检测结果。")
                            .font(XvicoTypography.caption).foregroundStyle(XvicoTheme.secondaryText)
                    }
                }.padding(.top, 8)
            }
        }
    }

    private func startCapture(usePersistentApproval: Bool = true) {
        voice.startRemoteChannel(model: model, usePersistentApproval: usePersistentApproval)
    }

    private func toggleListening() {
        if voice.isListening || voice.isStarting || voice.isFinalizing || remoteVoice.isConnecting || remoteVoice.isSubscribed {
            remoteVoice.stop(); voice.stop(); return
        }
        if voice.inputSource == .siriRemote {
            guard runtime.available else { model.show("请先在语音设置中导入官方 Apple 运行时"); return }
            authorization.refresh()
            if authorization.ready { startCapture() }
            else { captureApproval = true }
            return
        }
        if voice.recognitionMode == .inputMethod {
            model.show("请在目标输入框使用输入法的语音快捷键；Xvico 不启动本机识别")
            return
        }
        remoteVoice.stop(); voice.toggle()
    }

    private func executePhrase(_ phrase: String) {
        guard let command = model.shortcuts.first(where: { $0.enabled && phrase.localizedCaseInsensitiveContains($0.phrase) }) else {
            model.show("没有匹配的语音动作，可在语音设置中添加语音短语"); return
        }
        execute(command)
    }
    private func execute(_ command: UserShortcut) {
        model.perform(KeyBinding(action: command.action, value: command.value))
    }
}

private struct VoiceLatencyView: View {
    @ObservedObject var voice: VoiceService
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            XvicoLocalizedText("本轮语音耗时").font(.system(size: 12, weight: .semibold))
            if voice.latency.began == nil {
                XvicoLocalizedText("下一次语音输入后显示各阶段耗时。")
            } else {
                metric("识别或通道就绪", voice.latency.readyMilliseconds)
                metric("收到首帧音频", voice.latency.firstAudioMilliseconds)
                if voice.measuringInputMethod {
                    XvicoLocalizedText("输入法负责识别和落字，Xvico 不读取其文字或推测识别耗时。")
                } else {
                    metric("出现首段文字", voice.latency.firstTextMilliseconds)
                    metric("松开到最终文字", voice.latency.finalMilliseconds)
                    metric("写入原输入框", voice.latency.deliveryMilliseconds)
                }
            }
        }.font(XvicoTypography.caption).foregroundStyle(XvicoTheme.secondaryText)
    }
    private func metric(_ title: String, _ value: Double?) -> some View {
        HStack {
            XvicoLocalizedText(title)
            Spacer()
            Text(value.map { String(format: "%.0f ms", $0) } ?? "—").monospacedDigit()
        }
    }
}

private struct VoiceSettingRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        HStack(spacing: 14) {
            Text(LocalizedStringKey(title)).frame(width: 100, alignment: .leading)
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct VoiceStatusPanel: View {
    @EnvironmentObject private var voice: VoiceService
    @EnvironmentObject private var remoteVoice: RemoteVoiceService
    let onToggle: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let presentation = snapshot.presentation(at: context.date)
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: symbol(for: presentation.stage))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(color(for: presentation.stage))
                    .frame(width: 36, height: 36)
                    .background(color(for: presentation.stage).opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 5) {
                    XvicoLocalizedText(presentation.title).font(.system(size: 13, weight: .semibold))
                    XvicoLocalizedText(presentation.detail).font(XvicoTypography.caption)
                        .foregroundStyle(presentation.stage == .needsAttention ? Color.orange : XvicoTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if voice.inputSource == .siriRemote || voice.recognitionMode == .local {
                    Button(action: onToggle) {
                        XvicoLocalizedLabel(active ? "停止聆听" : voice.inputSource == .siriRemote ? "启动系统语音后端" : "开始聆听",
                              systemImage: active ? "stop.fill" : "mic.fill")
                            .font(.system(size: 12, weight: .medium))
                    }.buttonStyle(XvicoActionButtonStyle(prominent: true))
                }
            }.padding(14).background(XvicoTheme.iconTile.opacity(0.5), in: RoundedRectangle(cornerRadius: 11))
        }
    }

    private var active: Bool {
        voice.isListening || voice.isStarting || voice.isFinalizing || remoteVoice.isConnecting || remoteVoice.isSubscribed
    }

    private var snapshot: VoiceActivitySnapshot {
        VoiceActivitySnapshot(source: voice.inputSource, mode: voice.recognitionMode,
            channelConnecting: remoteVoice.isConnecting, channelReady: remoteVoice.isSubscribed,
            microphoneRequested: remoteVoice.microphoneHeld, lastAudioAt: remoteVoice.lastAudioAt,
            recognitionStarting: voice.isStarting, recognitionListening: voice.isListening,
            finalizing: voice.isFinalizing, recognitionStatus: voice.status,
            channelError: remoteVoice.errorMessage, microphoneError: remoteVoice.microphoneControlError,
            recognitionError: voice.errorMessage, inputMethodTriggerKey: voice.inputMethodTriggerKey)
    }

    private func color(for stage: VoiceStage) -> Color {
        switch stage {
        case .idle: .secondary
        case .ready, .completed: .green
        case .awaitingAudio, .capturing, .needsAttention: .orange
        case .starting, .recognizing, .finalizing: .blue
        }
    }

    private func symbol(for stage: VoiceStage) -> String {
        switch stage {
        case .idle: "mic"
        case .starting: "hourglass"
        case .ready, .completed: "checkmark.circle"
        case .awaitingAudio: "mic"
        case .capturing: "waveform"
        case .recognizing, .finalizing: "text.bubble"
        case .needsAttention: "exclamationmark.circle"
        }
    }
}
