import SwiftUI
import SceneKit

@main
struct XvicoApp: App {
    @NSApplicationDelegateAdaptor(XvicoApplicationDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    @StateObject private var voice = VoiceService()
    @StateObject private var systemShortcuts = SystemShortcutsService()

    var body: some Scene {
        WindowGroup {
            XvicoWindow()
                .environmentObject(model)
                .environmentObject(voice)
                .environmentObject(model.remoteVoice)
                .environmentObject(systemShortcuts)
                .onOpenURL { url in
                    if systemShortcuts.handleCallback(url) { model.page = .commands; BackgroundController.shared.showWindow() }
                }
                .frame(minWidth: 1050, minHeight: 720)
                .onAppear {
                    let model = model
                    let voice = voice
                    model.siriVoiceHandler = { [weak voice, weak model] pressed in
                        guard let voice, let model else { return false }
                        return voice.handleRemotePush(pressed, model: model)
                    }
                    model.mappedKeyboardHandler = { [weak voice, weak model] binding, down in
                        guard let voice, let model else { return }
                        voice.handleMappedKeyboard(binding, down: down, model: model)
                    }
                    model.controlStopped = { [weak voice] in voice?.stop() }
                    model.startControl()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 810)
    }
}

struct XvicoWindow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var model: AppModel
    @AppStorage("xvibe.sidebarVisible") private var sidebarVisible = true
    @AppStorage("xvibe.appearance") private var appearance = XvicoAppearance.system.rawValue

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .environment(\.xvicoImmersiveGlass, true)
                .frame(width: sidebarVisible ? XvicoLayout.sidebarWidth : 0, alignment: .leading)
                .clipped()
                .opacity(sidebarVisible ? 1 : 0)
                .allowsHitTesting(sidebarVisible)
                // Hidden sidebar views stay alive during the slide. Disable
                // their surfaces too, so hover state cannot survive hiding.
                .disabled(!sidebarVisible)
                .accessibilityHidden(!sidebarVisible)
            Group {
                switch model.page {
                case .mapping: MappingView()
                case .scenes: ScenesView()
                case .commands: CommandsView()
                case .device: DeviceView()
                case .voice: VoiceView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(XvicoWindowBackdrop())
        .overlay(alignment: .topLeading) {
            SidebarToggleButton(expanded: sidebarVisible) {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.36)) { sidebarVisible.toggle() }
            }
            .position(x: sidebarVisible ? XvicoLayout.sidebarWidth - 26 : 43, y: sidebarVisible ? 26 : 49)
            // Fixed overlay coordinates keep the same button alive throughout
            // the move; changing the container height changed its layout origin.
            .frame(height: 100)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.36), value: sidebarVisible)
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                XvicoLocalizedText(toast).font(.system(size: 12, weight: .medium)).padding(.horizontal, 15).padding(.vertical, 9)
                    .xvicoGlassPanel(cornerRadius: 40, floating: true).environment(\.xvicoImmersiveGlass, true).padding(.bottom, 18)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .preferredColorScheme((XvicoAppearance(rawValue: appearance) ?? .system).colorScheme)
        .environment(\.locale, model.interfaceLocale)
        .background(WindowLifecycleView())
        .tint(.blue)
        .onAppear { BackgroundController.shared.configure(model) }
        .onChange(of: model.settings.showDockIcon) { value in
            if !value { model.settings.showMenuBarIcon = true }
            BackgroundController.shared.configure(model)
        }
        .onChange(of: model.settings.showMenuBarIcon) { _ in BackgroundController.shared.configure(model) }
        .onChange(of: model.settings.interfaceLanguage) { _ in BackgroundController.shared.configure(model) }
    }
}

private struct SidebarToggleButton: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    let expanded: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "sidebar.left").font(.system(size: 16, weight: .medium))
                .frame(width: 40, height: 40)
        }.buttonStyle(XvicoRaisedGlassButtonStyle(cornerRadius: 20, hitPadding: 4))
            .opacity(expanded || hovered || reduceTransparency ? 1 : 0.45)
            .onHover { hovered = $0 }
            .onChange(of: expanded) { _ in hovered = false }
            .onDisappear { hovered = false }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovered)
            .help(LocalizedStringKey(expanded ? "隐藏边栏" : "显示边栏"))
            .accessibilityLabel(LocalizedStringKey(expanded ? "隐藏边栏" : "显示边栏"))
    }
}

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "appletvremote.gen3")
                        .font(.system(size: 21, weight: .medium)).foregroundStyle(.blue)
                        .frame(width: 24, height: 28)
                    Text("Siri Remote").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                let connectionTitle = model.remoteConnected ? "已连接" : model.remoteConnectionLabel
                let connection = HStack(spacing: 5) {
                    Circle().fill(model.remoteConnected ? Color.green : .gray).frame(width: 6, height: 6)
                    XvicoLocalizedText(connectionTitle)
                        .font(.system(size: 10, weight: .medium))
                }
                let control = XvicoLocalizedText(model.controlStatusLabel)
                    .font(.system(size: 9)).foregroundStyle(XvicoTheme.secondaryText)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 5) { connection; Spacer(minLength: 2); if model.running { control } }
                        .fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 5) { connection; if model.running { control } }
                }
            }
            .padding(12).frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
            .xvicoRaisedGlassPanel(cornerRadius: 18)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Siri Remote")
            .accessibilityValue(Text((model.running ? [model.remoteConnected ? "已连接" : model.remoteConnectionLabel, model.controlStatusLabel]
                                     : [model.remoteConnectionLabel])
                .map { XvicoLocalization.string($0, locale: locale) }.joined(separator: ", ")))
            .help(XvicoLocalization.string(model.remoteStatus, locale: locale))
            .padding(.horizontal, 12).padding(.top, 58).padding(.bottom, 18)

            VStack(spacing: 10) {
                ForEach(XvicoNavigation.sidebarPages) { page in
                    Button {
                        if page == .mapping { model.selectSceneForMapping(nil) }
                        else { model.page = page }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: page.symbol).font(.system(size: 16, weight: .medium)).frame(width: 20)
                            Text(LocalizedStringKey(page.displayName))
                                .font(.system(size: 12, weight: .semibold)).lineLimit(2).multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 10).frame(maxWidth: .infinity).frame(height: 52)
                        .foregroundStyle(XvicoTheme.optionForeground(selected: model.page == page, scheme: colorScheme))
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }.buttonStyle(XvicoGlassButtonStyle(selected: model.page == page, raised: true))
                        .accessibilityLabel(LocalizedStringKey(page.displayName))
                        .accessibilityAddTraits(model.page == page ? .isSelected : [])
                }
            }.padding(.horizontal, 12)

            Spacer()
            Button { model.running ? model.stopControl() : model.startControl() } label: {
                HStack(spacing: 7) {
                    Image(systemName: model.running ? "stop.fill" : "play.fill")
                        .foregroundStyle(model.running ? Color.red : Color.accentColor)
                    Text(LocalizedStringKey(model.running ? "停止控制" : "开始控制")).foregroundStyle(.primary)
                }.font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 42)
                    .contentShape(Capsule())
            }.buttonStyle(XvicoGlassButtonStyle(tint: (model.running ? Color.red : Color.accentColor).opacity(0.12), cornerRadius: 24, raised: true))
                .padding(.horizontal, 12).padding(.bottom, 12)
        }
        .frame(width: XvicoLayout.sidebarWidth)
        .xvicoGlassPanel(cornerRadius: 0, bordered: false, floating: true)
        .overlay(alignment: .trailing) { Rectangle().fill(XvicoTheme.border).frame(width: 1) }
    }
}

struct VoiceCommandsEditorView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingEditor = false
    @State private var editing: UserShortcut?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { VStack(alignment: .leading, spacing: 4) { XvicoLocalizedText("语音短语动作").font(.system(size: 16, weight: .semibold)); XvicoLocalizedText("把常用开发动作绑定到 Siri Remote 按键或语音短语。").font(.system(size: 11)).foregroundStyle(XvicoTheme.secondaryText) }; Spacer(); Button { editing = nil; showingEditor = true } label: { XvicoLocalizedLabel("添加动作", systemImage: "plus").font(.system(size: 11, weight: .semibold)) }.buttonStyle(.borderedProminent) }
            VStack(spacing: 0) {
                if model.shortcuts.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "command").font(.system(size: 26)).foregroundStyle(XvicoTheme.secondaryText)
                        XvicoLocalizedText("还没有语音短语动作").font(.system(size: 13, weight: .semibold))
                        XvicoLocalizedText("添加“运行测试”“接受补全”等开发动作。").font(.system(size: 11)).foregroundStyle(XvicoTheme.secondaryText)
                    }.frame(maxWidth: .infinity).frame(height: 220)
                } else {
                    ForEach(model.shortcuts) { shortcut in
                        HStack(spacing: 12) {
                            Image(systemName: "command.circle.fill").font(.system(size: 20)).foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 3) { Text(shortcut.name).font(.system(size: 12, weight: .semibold)); XvicoLocalizedText("语音短语：\(shortcut.phrase)").font(.system(size: 10)).foregroundStyle(XvicoTheme.secondaryText) }
                            Spacer()
                            XvicoLocalizedText(shortcut.action.rawValue).font(.system(size: 10)).foregroundStyle(XvicoTheme.secondaryText)
                            Button("编辑") { editing = shortcut; showingEditor = true }.controlSize(.small)
                            Toggle("启用", isOn: shortcutEnabled(shortcut)).labelsHidden().toggleStyle(XvicoSwitchStyle()).controlSize(.mini)
                            Button(role: .destructive) { model.shortcuts.removeAll { $0.id == shortcut.id } } label: { Image(systemName: "trash") }.buttonStyle(.plain)
                        }.padding(12)
                        if shortcut.id != model.shortcuts.last?.id { Divider() }
                    }
                }
            }.xvicoGlassPanel(cornerRadius: 16)
            Spacer()
        }.padding(22).sheet(isPresented: $showingEditor) { ShortcutEditor(shortcut: editing).xvicoPresentationSettings() }
    }
    private func shortcutEnabled(_ shortcut: UserShortcut) -> Binding<Bool> {
        Binding(get: { model.shortcuts.first(where: { $0.id == shortcut.id })?.enabled ?? false }, set: { v in if let i = model.shortcuts.firstIndex(where: { $0.id == shortcut.id }) { model.shortcuts[i].enabled = v } })
    }
}

struct ShortcutEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let shortcut: UserShortcut?
    @State private var name = ""
    @State private var phrase = ""
    @State private var action: XvicoAction = .key
    @State private var value = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            XvicoLocalizedText(shortcut == nil ? "新建语音短语动作" : "编辑语音短语动作").font(.system(size: 16, weight: .semibold))
            TextField("名称，例如：运行测试", text: $name).textFieldStyle(.roundedBorder)
            TextField("语音短语，例如：运行测试", text: $phrase).textFieldStyle(.roundedBorder)
            Picker("动作", selection: $action) { ForEach(XvicoAction.allCases) { XvicoLocalizedText($0.rawValue).tag($0) } }
            TextField(LocalizedStringKey(action == .key ? "快捷键，如 ⌘R" : "动作参数"), text: $value).textFieldStyle(.roundedBorder)
            HStack { Spacer(); Button("取消") { dismiss() }; Button("保存") { save() }.buttonStyle(.borderedProminent).disabled(name.isEmpty || phrase.isEmpty) }
        }.padding(20).frame(width: 400).onAppear { name = shortcut?.name ?? ""; phrase = shortcut?.phrase ?? ""; action = shortcut?.action ?? .key; value = shortcut?.value ?? "" }
    }
    private func save() {
        if let shortcut, let index = model.shortcuts.firstIndex(where: { $0.id == shortcut.id }) { model.shortcuts[index].name = name; model.shortcuts[index].phrase = phrase; model.shortcuts[index].action = action; model.shortcuts[index].value = value }
        else { model.shortcuts.append(UserShortcut(name: name, phrase: phrase, action: action, value: value)) }
        dismiss()
    }
}
