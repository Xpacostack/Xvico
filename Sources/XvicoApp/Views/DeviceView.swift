import SwiftUI
import Combine
import CoreBluetooth
import AVFoundation
import Speech
import IOKit.hid

struct DeviceView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var voice: VoiceService
    @AppStorage("xvibe.appearance") private var appearance = XvicoAppearance.system.rawValue
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var inputGranted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    @State private var showingGuide = false
    @State private var inputDiagnosticsExpanded = false
    @State private var microphoneLabel = VoiceService.microphonePermissionLabel
    @State private var speechLabel = VoiceService.speechPermissionLabel
    private let permissionTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    private let toggleKeys: [RemoteKey] = [.voice, .tv, .menu, .power, .mute, .volumeUp, .volumeDown, .playPause, .center, .touchUp, .touchDown, .touchLeft, .touchRight]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XvicoLayout.sectionSpacing) {
                SettingsSection(title: "权限", symbol: "hand.raised") {
                    XvicoLocalizedText("允许遥控器控制 Mac").font(.headline)
                    XvicoLocalizedText("按键映射、光标和滚动需要辅助功能与输入监控权限。").font(.caption).foregroundStyle(XvicoTheme.secondaryText)
                    if !accessibilityGranted || !inputGranted {
                        XvicoLocalizedText("系统尚未授权当前 Xvico 控制 Mac。此版本已采用固定开发签名；从旧临时签名迁移时需授权一次，后续构建会保留同一签名身份。").font(.caption).foregroundStyle(.orange)
                    }
                    HStack(spacing: 8) {
                        PermissionTile(name: "辅助功能", symbol: "accessibility", granted: accessibilityGranted,
                                       actionTitle: "打开辅助功能设置") {
                            openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                        }
                        PermissionTile(name: "输入监控", symbol: "keyboard", granted: inputGranted,
                                       actionTitle: "打开输入监控设置") {
                            openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
                        }
                        PermissionTile(name: "蓝牙", symbol: "antenna.radiowaves.left.and.right",
                                       granted: CBManager.authorization == .allowedAlways, actionTitle: "打开蓝牙设置") {
                            openSettings("x-apple.systempreferences:com.apple.Bluetooth")
                        }
                        PermissionTile(name: "麦克风", symbol: "mic", granted: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
                                       actionTitle: AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined ? "请求麦克风权限" : "打开麦克风设置",
                                       statusText: microphoneLabel, canRequest: AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined) {
                            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                                Task { await voice.requestMicrophonePermission(); microphoneLabel = VoiceService.microphonePermissionLabel }
                            } else {
                                openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
                            }
                        }
                        PermissionTile(name: "语音识别", symbol: "waveform", granted: SFSpeechRecognizer.authorizationStatus() == .authorized,
                                       actionTitle: SFSpeechRecognizer.authorizationStatus() == .notDetermined ? "请求语音识别权限" : "打开语音识别设置",
                                       statusText: speechLabel, canRequest: SFSpeechRecognizer.authorizationStatus() == .notDetermined) {
                            if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
                                Task { await voice.requestSpeechPermission(); speechLabel = VoiceService.speechPermissionLabel }
                            } else {
                                openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
                            }
                        }
                    }
                    XvicoLocalizedText("麦克风与语音识别由应用请求授权，系统页面无需也无法手动添加应用。已拒绝时在对应隐私设置中开启。").font(.caption).foregroundStyle(XvicoTheme.secondaryText)
                }
                SettingsSection(title: "遥控器输入源", symbol: "switch.2") {
                    HStack { VStack(alignment: .leading, spacing: 4) { XvicoLocalizedText("快速连接遥控器").font(.headline); XvicoLocalizedText("重新扫描上次使用的 Siri Remote。").font(.caption).foregroundStyle(XvicoTheme.secondaryText) }; Spacer(); Button("快速连接") { model.reidentifyRemote(); model.startRemoteVoiceConnection() }.buttonStyle(XvicoActionButtonStyle(prominent: true)) }
                    statusLine("Siri Remote 按键", model.remoteStatus)
                    statusLine("Siri Remote 触控板", model.touchStatus)
                    DisclosureGroup("输入诊断", isExpanded: $inputDiagnosticsExpanded) {
                        if inputDiagnosticsExpanded { RemoteDiagnosticsView() }
                    }
                    Button("重新识别遥控器触控板") { model.reidentifyRemote() }
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 5) {
                            XvicoLocalizedText("阻止遥控器触发系统关机（推荐）").font(.headline)
                            XvicoLocalizedText("只拦截遥控器的按键接口，触控板使用的接口保持独立，不会影响鼠标移动。Xvico 运行期间请保持开启。").font(.caption).foregroundStyle(XvicoTheme.secondaryText)
                        }
                        Spacer(minLength: 8)
                        Toggle("阻止遥控器触发系统关机（推荐）", isOn: $model.settings.interceptRemoteButtons).labelsHidden().toggleStyle(.switch)
                    }
                    if let detail = model.powerInterceptionDetail { XvicoLocalizedText(detail).font(.caption).foregroundStyle(XvicoTheme.secondaryText) }
                    XvicoLocalizedLabel(model.powerIntercepted ? "系统电源动作已拦截" : "系统电源动作未拦截", systemImage: model.powerIntercepted ? "checkmark.shield.fill" : "exclamationmark.shield.fill").font(.caption).foregroundStyle(model.powerIntercepted ? .green : .orange)
                }
                SettingsSection(title: "触控板", symbol: "hand.draw") {
                    Toggle("启用触控板输入", isOn: $model.settings.touchEnabled)
                    XvicoLocalizedText("关闭后不移动光标、外圈手势不生效；五个机械点击区仍使用独立按键映射。").font(.caption).foregroundStyle(XvicoTheme.secondaryText)
                    slider("指针移动灵敏度", value: $model.settings.pointerSensitivity, range: 0.2...3, suffix: "×")
                    XvicoOptionPicker(title: "指针响应", selection: $model.settings.pointerProfile,
                                      options: PointerResponseProfile.allCases.map {
                        XvicoOption(value: $0, title: $0.rawValue, symbol: $0 == .precise ? "scope" : $0 == .fast ? "hare" : "cursorarrow")
                    })
                    Toggle("中心点击稳定", isOn: $model.settings.clickStabilityEnabled)
                    XvicoLocalizedText("均衡保留原有速度曲线；精准适合小目标，快速适合大屏移动。按下中心键时短暂稳定指针，明显移动后立即允许拖拽。")
                        .font(.caption).foregroundStyle(XvicoTheme.secondaryText)
                    slider("拖动加速", value: $model.settings.dragAcceleration, range: 1...2.5, suffix: "×")
                    XvicoLocalizedText("仅在按住鼠标映射键拖动时生效：慢移保持精准，快滑增加距离；设为 1× 恢复原有拖动速度。")
                        .font(.caption).foregroundStyle(XvicoTheme.secondaryText)
                    Toggle("启用外圈旋转", isOn: $model.settings.ringEnabled).disabled(!model.settings.touchEnabled)
                    XvicoOptionPicker(title: "外圈旋转动作", selection: ringModeBinding, options: [
                        XvicoOption(value: .switchApp, title: "切换 App", symbol: "rectangle.2.swap"),
                        XvicoOption(value: .scroll, title: "滚轮", symbol: "arrow.up.arrow.down"),
                        XvicoOption(value: .codexTasks, title: "Codex 任务（⌘1–9）", symbol: "command")
                    ]).disabled(!model.settings.touchEnabled || !model.settings.ringEnabled)
                    XvicoLocalizedText(model.activeScene == nil
                         ? "当前实际动作：\(model.effectiveRingAction.rawValue)（全局）"
                         : "\(model.currentApp) 当前使用「\(model.activeScene?.name ?? "")」场景：\(model.effectiveRingAction.rawValue)").font(.caption).foregroundStyle(XvicoTheme.secondaryText)
                    HStack(spacing: 12) {
                        XvicoLocalizedText("快速双击切换按键")
                        Picker("快速双击切换按键", selection: $model.settings.ringToggleKey) {
                            XvicoLocalizedText("不使用").tag("")
                            ForEach(toggleKeys) { XvicoLocalizedText($0.displayName).tag($0.rawValue) }
                        }.labelsHidden().controlSize(.large).frame(width: 148)
                        Spacer(minLength: 0)
                    }
                    XvicoLocalizedText("第一次点击仍执行原功能；第二次切换外圈动作。不使用可关闭此功能。").font(.caption).foregroundStyle(XvicoTheme.secondaryText)
                    XvicoOptionPicker(title: "滚轮手感", selection: $model.settings.wheelStyle,
                                      options: WheelStyle.allCases.map { XvicoOption(value: $0, title: $0.rawValue, symbol: $0 == .continuous ? "waveform.path" : "line.3.horizontal") })
                    slider("识别灵敏度", value: $model.settings.ringSensitivity, range: 0.6...1.8, suffix: "×")
                    HStack { XvicoLocalizedText("外圈判定范围"); Slider(value: $model.settings.ringRadius, in: 0.22...0.48); XvicoLocalizedText("\(Int(model.settings.ringRadius * 100))%").monospacedDigit().frame(width: 45) }
                    HStack { XvicoLocalizedText("推荐默认：识别灵敏度 1.08×，外圈判定 33%").font(.caption).foregroundStyle(XvicoTheme.secondaryText); Spacer(); Button("恢复默认") { model.resetRingDefaults() } }
                }
                SettingsSection(title: "功能映射", symbol: "keyboard") {
                    XvicoLocalizedText("默认映射与按 App 场景独立保存，未匹配 App 时使用默认映射。").font(.caption).foregroundStyle(XvicoTheme.secondaryText)
                    Button("前往「功能映射」") { model.selectSceneForMapping(nil) }
                    Toggle("根据前台 App 自动切换映射", isOn: $model.settings.autoSwitchScenes)
                }
                SettingsSection(title: "音量键功能", symbol: "speaker.wave.2") {
                    XvicoOptionPicker(title: "音量加减键做什么", selection: $model.settings.volumeKeyMode,
                                      options: VolumeKeyMode.allCases.map { XvicoOption(value: $0, title: $0.rawValue, symbol: $0 == .microphone ? "mic" : $0 == .scroll ? "arrow.up.arrow.down" : "keyboard") })
                    XvicoLocalizedText("切换麦克风＝加/减切到上/下一个系统输入麦克风；滚动＝上下滚动；普通按键＝使用独立映射。").font(.caption).foregroundStyle(XvicoTheme.secondaryText)
                    HStack { XvicoLocalizedText("滚动步长"); Slider(value: $model.settings.volumeScrollStep, in: 20...240, step: 1); XvicoLocalizedText("\(Int(model.settings.volumeScrollStep))").monospacedDigit().frame(width: 40) }.disabled(model.settings.volumeKeyMode != .scroll)
                }
                SettingsSection(title: "语音", symbol: "waveform") {
                    XvicoLocalizedText("选择麦克风来源、识别方式与语音输入设置。")
                        .font(XvicoTypography.caption).foregroundStyle(XvicoTheme.secondaryText)
                    Button("前往「语音设置」管理详细设置") { model.page = .voice }
                }
                SettingsSection(title: "外观与后台", symbol: "circle.lefthalf.filled") {
                    HStack(spacing: 12) {
                        XvicoLocalizedText("界面语言").frame(width: 64, alignment: .leading)
                        Picker("界面语言", selection: $model.settings.interfaceLanguage) {
                            ForEach(InterfaceLanguage.allCases) { XvicoLocalizedText($0.rawValue).tag($0) }
                        }.labelsHidden().controlSize(.large).frame(width: 140)
                        Spacer(minLength: 0)
                    }
                    XvicoOptionPicker(title: "界面外观", selection: $appearance,
                                      options: XvicoAppearance.allCases.map { XvicoOption(value: $0.rawValue, title: $0.rawValue, symbol: $0 == .system ? "desktopcomputer" : $0 == .light ? "sun.max" : "moon") })
                    HStack(spacing: 10) {
                        BackgroundToggleTile(title: "程序坞显示", help: "在程序坞显示 Xvico", isOn: $model.settings.showDockIcon)
                        BackgroundToggleTile(title: "菜单栏显示", help: "在菜单栏显示 Xvico", isOn: $model.settings.showMenuBarIcon)
                            .disabled(!model.settings.showDockIcon)
                        BackgroundToggleTile(title: "关闭后继续运行", help: "关掉主窗口后在菜单栏继续运行", isOn: $model.settings.keepRunningWhenClosed)
                    }
                }
                HStack(alignment: .top, spacing: XvicoLayout.sectionSpacing) {
                    SettingsSection(title: "帮助", symbol: "questionmark.circle") {
                        VStack(alignment: .leading, spacing: 12) {
                            XvicoLocalizedText("连接、权限和按键设置的使用说明。")
                                .font(.caption).foregroundStyle(XvicoTheme.secondaryText)
                            Button("重新查看引导") { showingGuide = true }
                            Spacer(minLength: 0)
                        }.frame(height: 132)
                    }.frame(width: 180)
                    SettingsSection(title: "联系开发者", symbol: "bubble.left.and.bubble.right") {
                        HStack(spacing: 16) {
                            if let image = XvicoArtwork.developerQRCode {
                                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                                    .frame(width: 132, height: 132)
                                    .background(.white, in: RoundedRectangle(cornerRadius: 8))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .accessibilityLabel("微信联系开发者二维码")
                            } else {
                                XvicoLocalizedLabel("二维码加载失败", systemImage: "exclamationmark.triangle")
                                    .frame(width: 132, height: 132)
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                XvicoLocalizedText("微信扫码添加开发者").font(.system(size: 13, weight: .semibold))
                                XvicoLocalizedText("使用中遇到问题、有功能建议或反馈，欢迎联系我。")
                                    .font(.caption).foregroundStyle(XvicoTheme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(height: 132)
                    }
                }
            }.font(XvicoTypography.body).frame(maxWidth: XvicoLayout.contentWidth).padding(XvicoLayout.pageInset)
        }
        .buttonStyle(XvicoActionButtonStyle())
        .onReceive(permissionTimer) { _ in
            let accessibility = AXIsProcessTrusted()
            let input = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
            let microphone = VoiceService.microphonePermissionLabel
            let speech = VoiceService.speechPermissionLabel
            if accessibilityGranted != accessibility { accessibilityGranted = accessibility }
            if inputGranted != input { inputGranted = input }
            if microphoneLabel != microphone { microphoneLabel = microphone }
            if speechLabel != speech { speechLabel = speech }
        }
        .toggleStyle(.switch)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)) { _ in accessibilityGranted = AXIsProcessTrusted(); inputGranted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted }
        .sheet(isPresented: $showingGuide) {
            VStack(alignment: .leading, spacing: 16) {
                XvicoLocalizedText("Siri Remote 使用引导").font(.title2.bold())
                XvicoLocalizedText("1. 在 macOS 蓝牙设置中连接遥控器，并授予 Xvico 辅助功能和输入监控权限。")
                XvicoLocalizedText("2. 在功能映射页点击 3D 模型配置机械按键；拖动松手后模型自动回正。")
                XvicoLocalizedText("3. 设备设置配置指针、外圈、音量键和双击切换；App 场景可覆盖默认映射。")
                XvicoLocalizedText("4. 在语音设置中选择 Mac 或 Siri Remote 麦克风，使用本机识别或输入法语音输入。").foregroundStyle(XvicoTheme.secondaryText)
                HStack { Spacer(); Button("完成") { showingGuide = false }.buttonStyle(.borderedProminent) }
            }.padding(24).frame(width: 500)
                .xvicoGlassPanel(cornerRadius: 22, floating: true)
                .xvicoPresentationSettings()
        }
    }
    private var ringModeBinding: Binding<RingAction> {
        Binding(get: { model.effectiveRingAction }, set: { action in
            if let scene = model.activeScene, let index = model.scenes.firstIndex(where: { $0.id == scene.id }) { model.scenes[index].ringAction = action }
            else { model.settings.ringAction = action }
        })
    }
    private func statusLine(_ label: String, _ status: String) -> some View { HStack { XvicoLocalizedText(label); Spacer(); XvicoLocalizedText(status).font(.caption).foregroundStyle(XvicoTheme.secondaryText).multilineTextAlignment(.trailing) } }
    private func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View { HStack { XvicoLocalizedText(label); Slider(value: value, in: range); XvicoLocalizedText(String(format: "%.2f", value.wrappedValue) + suffix).monospacedDigit().frame(width: 55) } }
    private func openSettings(_ path: String) {
        if let url = URL(string: path) { NSWorkspace.shared.open(url) }
    }
}

private struct RemoteDiagnosticsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var voice: VoiceService
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(model.currentApp)
                    Text(model.currentBundleID).textSelection(.enabled)
                }
            } label: { XvicoLocalizedText("当前目标应用") }
            LabeledContent {
                if let scene = model.activeScene { Text(scene.name) }
                else { XvicoLocalizedText("全局映射") }
            } label: { XvicoLocalizedText("实际生效场景") }
            if model.activeScene != nil {
                XvicoLocalizedText(model.manuallyActiveSceneID == nil ? "按应用自动匹配" : "手动选择场景")
            }
            if !model.running { XvicoLocalizedText("控制已停止，以下仅显示配置解析结果。") }
            else if model.activeScene == nil {
                XvicoLocalizedText(model.settings.autoSwitchScenes ? "未匹配启用的场景，使用全局映射。" : "自动切换已关闭，使用全局映射。")
            }
            LabeledContent {
                HStack {
                    XvicoLocalizedText(model.effectiveRingAction.rawValue)
                    XvicoLocalizedText(model.activeScene?.ringAction == nil ? "全局映射" : "应用场景")
                        .foregroundStyle(XvicoTheme.secondaryText)
                }
            } label: { XvicoLocalizedText("实际外圈动作") }
            if model.effectiveRingAction == .codexTasks && model.activeScene == nil {
                XvicoLocalizedText("Codex 任务切换需要匹配 App 场景")
            }
            Divider()
            ForEach(RemoteKey.physicalOrder) { key in
                let resolution = model.runtimeResolution(for: key)
                HStack(alignment: .top) {
                    XvicoLocalizedText(key.displayName).frame(width: 88, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) {
                        if key == .voice && voice.inputSource == .siriRemote && voice.recognitionMode == .local && voice.remotePushToTalk {
                            XvicoLocalizedText("由内建语音接管")
                        } else if (key == .volumeUp || key == .volumeDown) && model.settings.volumeKeyMode != .key {
                            XvicoLocalizedText(model.settings.volumeKeyMode.rawValue)
                            XvicoLocalizedText("音量键全局模式优先于按键映射")
                                .foregroundStyle(XvicoTheme.secondaryText)
                        } else {
                            HStack {
                                XvicoLocalizedText(resolution.binding.enabled ? resolution.binding.action.rawValue : "已关闭")
                                Text(resolution.binding.diagnosticValue).textSelection(.enabled)
                            }
                            if resolution.binding.longPressEnabled && resolution.binding.action == .key {
                                HStack { XvicoLocalizedText("长按来源"); XvicoLocalizedText(resolution.holdSource.rawValue) }
                                    .foregroundStyle(XvicoTheme.secondaryText)
                            }
                            if resolution.binding.doubleClickEnabled && (key == .power || key == .voice && resolution.binding.action == .key && resolution.binding.siriMode == "分段模式") {
                                HStack { XvicoLocalizedText("双击来源"); XvicoLocalizedText(resolution.doubleSource.rawValue) }
                                    .foregroundStyle(XvicoTheme.secondaryText)
                            }
                        }
                    }
                    Spacer(minLength: 4)
                    XvicoLocalizedText((key == .volumeUp || key == .volumeDown) && model.settings.volumeKeyMode != .key
                                      ? BindingSource.global.rawValue : resolution.source.rawValue).foregroundStyle(XvicoTheme.secondaryText)
                }
            }
            Divider()
            RemoteOutputView(diagnostics: model.inputDiagnostics)
            XvicoLocalizedText("其他鼠标与触控板保持 macOS 原生功能，不参与遥控器映射。")
        }.font(.caption).foregroundStyle(XvicoTheme.secondaryText).padding(.top, 6)
    }
}

private struct RemoteOutputView: View {
    @ObservedObject var diagnostics: RemoteInputDiagnostics
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            XvicoLocalizedText("实体输入：按键 \(diagnostics.buttonCount) 条 / 触控 \(diagnostics.touchCount) 帧 · \(diagnostics.lastButton)")
                .textSelection(.enabled)
            XvicoLocalizedText("最近动作：\(diagnostics.lastAction)")
            if let output = diagnostics.lastOutput {
                HStack { XvicoLocalizedText(output.kind); Text(output.value).textSelection(.enabled) }
                Text(output.targetBundleID).textSelection(.enabled)
                XvicoLocalizedText(output.sent ? "已发送事件；目标应用是否响应需实际确认。" : "未发送按键事件，请查看上方状态。")
            }
        }
    }
}

private struct PermissionTile: View {
    let name: String
    let symbol: String
    let granted: Bool
    let actionTitle: String
    var statusText: String? = nil
    var canRequest = false
    let action: () -> Void

    private var status: String { statusText ?? (granted ? "已授权" : "需检查") }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 22, weight: .medium))
                    .foregroundStyle(granted ? Color.green : Color.orange)
                Text(LocalizedStringKey(name)).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true).frame(height: 28)
                Label(LocalizedStringKey(status), systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 10)).foregroundStyle(XvicoTheme.secondaryText).lineLimit(1)
                XvicoLocalizedText(canRequest ? "请求授权" : "系统设置").font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.blue)
            }.padding(.horizontal, 6).frame(maxWidth: .infinity).frame(height: 112)
                .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }.buttonStyle(XvicoGlassButtonStyle(cornerRadius: 13))
            .help(LocalizedStringKey(actionTitle))
            .accessibilityLabel(LocalizedStringKey(name))
            .accessibilityValue(LocalizedStringKey(status))
            .accessibilityHint(LocalizedStringKey(actionTitle))
    }
}

private struct BackgroundToggleTile: View {
    let title: String
    let help: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(LocalizedStringKey(title)).font(.system(size: 12, weight: .medium)).lineLimit(2)
            Spacer(minLength: 0)
            Toggle(LocalizedStringKey(help), isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }.padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 46)
            .background(XvicoTheme.iconTile.opacity(0.32), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(XvicoTheme.border.opacity(0.6)))
            .help(LocalizedStringKey(help))
    }
}
