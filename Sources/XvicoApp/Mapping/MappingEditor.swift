import SwiftUI
import AppKit

struct MappingView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var idleDismissal = MappingIdleDismissal()
    var body: some View {
        GeometryReader { geometry in
            let editorWidth = min(345, geometry.size.width * 0.45)
            ZStack(alignment: .leading) {
                RemoteDrawing(selected: model.selectedKey, editorWidth: editorWidth) { key in
                    withAnimation(.easeInOut(duration: 0.30)) { model.selectedKey = key }
                }
                .frame(maxWidth: .infinity)
                .frame(height: min(565, geometry.size.height * 0.84))
                .compositingGroup()
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.44 : 0.20), radius: 18, x: 8, y: 14)
                .offset(y: -40)
                if let key = model.selectedKey {
                    MappingEditor(key: key, maximumHeight: geometry.size.height - 28)
                        .frame(width: editorWidth)
                        .id("\(model.editingGlobalMapping ? "global" : model.selectedSceneID?.uuidString ?? "default")-\(key.rawValue)")
                        .padding(.leading, max(32, min(110, geometry.size.width * 0.12)))
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.30), value: model.selectedKey != nil)
            .overlay(alignment: .bottom) {
                if model.selectedKey == nil {
                    XvicoLocalizedLabel("按遥控器，或者是点击遥控器模型来编辑", systemImage: "hand.point.up.left.fill")
                        .font(.system(size: 12)).foregroundStyle(XvicoTheme.secondaryText)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .xvicoGlassPanel(cornerRadius: 30).padding(.bottom, 22)
                }
            }
        }
        .onAppear { updateIdleDismissal() }
        .onChange(of: model.selectedKey) { _ in updateIdleDismissal() }
        .onReceive(model.mappingInteraction) { _ in idleDismissal.recordActivity() }
        .onDisappear { idleDismissal.stop() }
    }

    private func updateIdleDismissal() {
        if model.selectedKey != nil {
            idleDismissal.begin(isInteracting: { model.isHoldingRemoteButton }) {
                withAnimation(.easeInOut(duration: 0.30)) { model.selectedKey = nil }
            }
        } else {
            idleDismissal.stop()
        }
    }
}

struct MappingEditor: View {
    @EnvironmentObject private var model: AppModel
    let key: RemoteKey
    var maximumHeight: CGFloat = 660
    @State private var binding = KeyBinding(action: .key, value: "Return")
    @State private var loaded = false
    @State private var contentHeight: CGFloat = 400
    private let splitHelp = "短按=上面的键(轻点一下)；按住=下面的键(一直按住)，适合“按住说话”的语音识别。"

    private var actionChoices: [XvicoAction] {
        var choices: [XvicoAction] = key == .power ? [.screenOff, .key, .click, .textAndReturn]
            : key == .center ? [.click, .key, .textAndReturn] : [.click, .key]
        if !choices.contains(binding.action) { choices.append(binding.action) }
        return choices
    }
    private var summary: String {
        guard binding.enabled else { return "未映射" }
        switch binding.action {
        case .click: return binding.mouseButton == .right ? "鼠标右键" : "鼠标左键"
        case .screenOff: return "熄屏"
        case .textAndReturn: return binding.textValue.isEmpty ? "尚未输入数字" : "文本 + 回车"
        default: return binding.value
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: key == .voice ? 14 : 17) {
                HStack(spacing: 12) {
                    Image(systemName: key.symbol).font(.system(size: 23)).foregroundStyle(.blue)
                        .frame(width: 48, height: 48).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 4) {
                        XvicoLocalizedText(key.displayName).font(.system(size: 18, weight: .semibold))
                        XvicoLocalizedText(summary).font(XvicoTypography.body).foregroundStyle(XvicoTheme.secondaryText)
                    }
                    Spacer()
                    Button { withAnimation(.easeInOut(duration: 0.30)) { model.selectedKey = nil } } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26).background(Color.accentColor, in: Circle())
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).help("关闭").accessibilityLabel("关闭")
                }
                Divider()
                VStack(alignment: .leading, spacing: 9) {
                    caption(key == .power ? "电源键动作" : "按键动作")
                    Picker(LocalizedStringKey(key == .power ? "电源键动作" : "按键动作"), selection: $binding.action) {
                        ForEach(actionChoices) { action in XvicoLocalizedText(actionLabel(action)).tag(action) }
                    }.pickerStyle(.segmented).labelsHidden()
                    if (key == .volumeUp || key == .volumeDown) && model.settings.volumeKeyMode != .key {
                    VStack(alignment: .leading, spacing: 8) {
                        XvicoLocalizedText("当前设备设置优先：\(model.settings.volumeKeyMode.rawValue)，下面的普通按键映射不会执行。")
                            .font(.caption).foregroundStyle(.orange)
                        Button("改用自定义按键映射") { model.settings.volumeKeyMode = .key }
                    }
                }
                if key == .power {
                        hint("这是「单击」的动作。选「文本 + 回车」时只在屏幕熄着时才发送——屏幕亮着时按电源键不会把密码打进当前窗口。注意 macOS 自己也会响应电源键弹出关机对话框，Xvico 拦不拦得住取决于系统版本。")
                    }
                }
                if key == .power { powerDoubleEditor }
                Group {
                    switch binding.action {
                    case .click: mouseEditor
                    case .textAndReturn: textEditor
                    case .key: keyboardEditor
                    case .openApp:
                        VStack(alignment: .leading, spacing: 8) {
                            caption("打开应用")
                            XvicoLocalizedText(binding.value.isEmpty ? "尚未选择应用" : binding.value).font(.caption).foregroundStyle(XvicoTheme.secondaryText)
                            Button("选择应用") {
                                let panel = NSOpenPanel()
                                panel.allowedContentTypes = [.applicationBundle]
                                panel.directoryURL = URL(fileURLWithPath: "/Applications")
                                if panel.runModal() == .OK, let url = panel.url, let identifier = Bundle(url: url)?.bundleIdentifier {
                                    binding.value = identifier
                                }
                            }
                        }
                    default: EmptyView()
                    }
                }.disabled(!binding.enabled)
                if key != .voice || binding.action == .click {
                    Toggle("启用此按键", isOn: $binding.enabled).toggleStyle(.switch).font(.system(size: 13, weight: .semibold))
                }
            }
            .padding(20)
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { proxy in
                Color.clear
                    .onAppear { contentHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { contentHeight = $0 }
            })
        }
        .frame(height: min(contentHeight, maximumHeight))
        .font(XvicoTypography.body)
        .tint(.blue)
        .xvicoGlassPanel(cornerRadius: 22, floating: true)
        .onAppear {
            binding = model.binding(for: key)
            if key == .voice && binding.action == .key { binding.enabled = true }
            loaded = true
        }
        .onChange(of: binding) { value in
            guard loaded else { return }
            model.updateBinding(value, for: key)
        }
        .onChange(of: binding.action) { action in
            // Re-enable when leaving a disabled mouse mapping so the keyboard
            // branch cannot become inaccessible.
            if key == .voice && action == .key { binding.enabled = true }
        }
    }

    private var powerDoubleEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            detailToggle("双击电源键", description: "快速按两下电源键执行下面的动作。注意：开了双击，单击会延迟约 0.2 秒（为了区分是不是双击）。关掉这个开关，单击就即时生效。", isOn: $binding.doubleClickEnabled)
            if binding.doubleClickEnabled {
                Picker("双击时执行", selection: $binding.powerDoubleClickAction) {
                    XvicoLocalizedText("熄屏").tag(PowerDoubleClickAction.sleepDisplay)
                    XvicoLocalizedText("锁屏").tag(PowerDoubleClickAction.lockScreen)
                    XvicoLocalizedText("睡眠").tag(PowerDoubleClickAction.systemSleep)
                }.pickerStyle(.segmented).labelsHidden()
                hint("熄屏＝只黑屏。锁屏＝立刻要求输入密码。睡眠＝整机睡眠（蓝牙遥控器不一定叫得醒 Mac）。")
            }
            Divider()
        }
    }
    private var mouseEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            caption("鼠标点击")
            Picker("鼠标按键", selection: $binding.mouseButton) {
                XvicoLocalizedText("鼠标左键").tag(MouseClickButton.left)
                XvicoLocalizedText("鼠标右键").tag(MouseClickButton.right)
            }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 200)
            hint("按下时在当前指针位置触发所选鼠标按键。")
        }
    }
    private var textEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            caption(key == .power ? "解锁文本" : "文本 + 回车")
            TextField(LocalizedStringKey(key == .power ? "例如：MyPass123!" : "要输入的文本"), text: $binding.textValue).textFieldStyle(.roundedBorder)
                .onChange(of: binding.textValue) { text in if text.count > 64 { binding.textValue = String(text.prefix(64)) } }
            hint("数字、英文字母和标点都可以，最长 64 个字符。会依次输入上面的文本，最后自动按一次回车。")
        }
    }
    private var keyboardEditor: some View {
        VStack(alignment: .leading, spacing: key == .voice ? 10 : 13) {
            HStack {
                caption("映射成快捷键")
                Spacer()
                Menu {
                    Button("调度中心 Mission Control") { binding.value = "Up Arrow"; binding.modifiers = [.control]; binding.rightModifiers = [] }
                    Button("应用窗口 App Expose") { binding.value = "Down Arrow"; binding.modifiers = [.control]; binding.rightModifiers = [] }
                    Button("上一个桌面") { binding.value = "Left Arrow"; binding.modifiers = [.control]; binding.rightModifiers = [] }
                    Button("下一个桌面") { binding.value = "Right Arrow"; binding.modifiers = [.control]; binding.rightModifiers = [] }
                } label: { XvicoLocalizedLabel("快捷操作", systemImage: "bolt.fill").font(.system(size: 11)) }.menuStyle(.borderlessButton).fixedSize()
            }
            KeyboardShortcutEditor(value: $binding.value, modifiers: $binding.modifiers, rightModifiers: $binding.rightModifiers)
            if key == .voice {
                caption("按住行为")
                Picker("按住行为", selection: $binding.siriMode) {
                    XvicoLocalizedText("分段模式").tag("分段模式")
                    XvicoLocalizedText("长按模式").tag("长按模式")
                }.pickerStyle(.segmented).labelsHidden()
                hint(binding.siriMode == "分段模式" ? "短按和按住分开处理，可以再细分下面的行为。" : "按住遥控器＝键盘上这个键一直被按住，松开才抬起。适配豆包这类按住说话的输入法。")
            }
            if key != .voice || binding.siriMode == "分段模式" {
                detailToggle("短按 / 按住 分开设置", description: splitHelp, isOn: $binding.longPressEnabled)
                if binding.longPressEnabled {
                    detailToggle("按住不发键", description: "按住时不发送任何键（纯用于按住说话）", isOn: $binding.holdNoOutput)
                    if !binding.holdNoOutput {
                        caption("按住时发送")
                        KeyboardShortcutEditor(value: $binding.longPressValue, modifiers: $binding.longPressModifiers, rightModifiers: $binding.longPressRightModifiers)
                    }
                }
                if key == .voice {
                    detailToggle("双击独立按键", description: "快速双击此键 = 发下面这个键（默认回车），像一个单独按键一样。注意：开了双击，单击会延迟约 0.2 秒（为了区分是不是双击）。", isOn: $binding.doubleClickEnabled)
                    if binding.doubleClickEnabled {
                        caption("双击时发送")
                        KeyboardShortcutEditor(value: $binding.doubleClickValue, modifiers: $binding.doubleClickModifiers, rightModifiers: $binding.doubleClickRightModifiers)
                    }
                }
            }
        }
    }
    private func actionLabel(_ action: XvicoAction) -> String {
        switch action {
        case .key: "快捷键"
        case .textAndReturn: "文本 + 回车"
        default: action.rawValue
        }
    }
    private func caption(_ text: String) -> some View { XvicoLocalizedText(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(XvicoTheme.secondaryText) }
    private func hint(_ text: String) -> some View { XvicoLocalizedText(text).font(XvicoTypography.caption).foregroundStyle(XvicoTheme.secondaryText).fixedSize(horizontal: false, vertical: true) }
    private func detailToggle(_ title: String, description: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                XvicoLocalizedText(title).font(.system(size: 13, weight: .semibold))
                hint(description)
                    .lineLimit(title == "短按 / 按住 分开设置" ? 1 : nil)
                    .help(LocalizedStringKey(description))
            }
            Spacer(minLength: 4)
            Toggle(LocalizedStringKey(title), isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }
}

struct KeyboardShortcutEditor: View {
    @Binding var value: String
    @Binding var modifiers: Set<KeyboardModifier>
    @Binding var rightModifiers: Set<KeyboardModifier>
    @State private var recording = false
    @State private var eventMonitor: Any?
    @State private var standaloneModifier: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { beginRecording() } label: {
                HStack {
                    Image(systemName: "keyboard")
                    XvicoLocalizedText(shortcutLabel).fontWeight(.semibold)
                    Spacer()
                    XvicoLocalizedText(recording ? "按下快捷键…" : "点击录制").font(.system(size: 11))
                }.frame(maxWidth: .infinity).padding(.vertical, 5)
            }.buttonStyle(.borderedProminent)
            HStack(spacing: 7) {
                ForEach(KeyboardModifier.allCases) { modifier in
                    let side = modifiers.contains(modifier) ? (rightModifiers.contains(modifier) ? "右" : "左") : ""
                    Button {
                        if !modifiers.contains(modifier) { modifiers.insert(modifier) }
                        else if !rightModifiers.contains(modifier) { rightModifiers.insert(modifier) }
                        else { modifiers.remove(modifier); rightModifiers.remove(modifier) }
                    } label: {
                        HStack(spacing: 2) {
                            XvicoLocalizedText(modifier.symbol).font(.system(size: 16, weight: .semibold))
                            if !side.isEmpty { XvicoLocalizedText(side).font(.system(size: 9, weight: .medium)) }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .background(modifiers.contains(modifier) ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(modifiers.contains(modifier) ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.1)))
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32, alignment: .center)
                    .help("点击切换：关闭、左侧、右侧")
                }
            }
            XvicoLocalizedText("点修饰键循环：关 → 左 → 右").font(.system(size: 10)).foregroundStyle(XvicoTheme.secondaryText)
            Picker("按键", selection: $value) {
                if KeyboardOutput.named(value) == nil { XvicoLocalizedText(value).tag(value) }
                ForEach(KeyboardOutput.all) { XvicoLocalizedText($0.name).tag($0.name) }
            }.labelsHidden().frame(maxWidth: 230)
        }
        .onDisappear { stopRecording() }
    }
    private var shortcutLabel: String {
        let flags = KeyboardModifier.allCases.filter { modifiers.contains($0) }.map { $0.symbol }.joined()
        return flags + (KeyboardOutput.named(value)?.symbol ?? value)
    }
    private func beginRecording() {
        guard !recording else { stopRecording(); return }
        recording = true
        standaloneModifier = nil
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            guard recording else { return event }
            var detected = Set<KeyboardModifier>()
            for modifier in KeyboardModifier.allCases where UInt64(event.modifierFlags.rawValue) & modifier.flag.rawValue != 0 { detected.insert(modifier) }
            modifiers = detected
            let rightMask: [(KeyboardModifier, UInt, UInt16)] = [(.command, 0x10, 54), (.option, 0x40, 61), (.control, 0x2000, 62), (.shift, 0x4, 60)]
            rightModifiers = Set(rightMask.filter { detected.contains($0.0) && (event.modifierFlags.rawValue & $0.1 != 0 || event.keyCode == $0.2) }.map { $0.0 })
            if event.type == .keyDown, let output = KeyboardOutput.all.first(where: { $0.keyCode == event.keyCode }) {
                value = output.name
                stopRecording()
            } else if event.type == .flagsChanged && event.keyCode == 63 && event.modifierFlags.contains(.function) {
                value = "Fn"; modifiers = []; rightModifiers = []; stopRecording()
            } else if event.type == .flagsChanged,
                      let output = KeyboardOutput.all.first(where: { $0.keyCode == event.keyCode }),
                      let modifier = output.primaryModifier {
                if detected.contains(modifier) { standaloneModifier = output.name }
                else if detected.isEmpty, standaloneModifier == output.name {
                    value = output.name; modifiers = []; rightModifiers = []; stopRecording()
                }
            }
            return nil
        }
    }
    private func stopRecording() {
        recording = false
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        standaloneModifier = nil
    }
}
