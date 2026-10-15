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
    @EnvironmentObject private var model: AppModel
    @AppStorage("xvibe.sidebarVisible") private var sidebarVisible = true
    @AppStorage("xvibe.appearance") private var appearance = XvicoAppearance.system.rawValue

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: sidebarVisible ? XvicoLayout.sidebarWidth : 0, alignment: .leading)
                .clipped()
                .opacity(sidebarVisible ? 1 : 0)
                .allowsHitTesting(sidebarVisible)
                .accessibilityHidden(!sidebarVisible)
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Text(LocalizedStringKey(model.page.displayName)).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Circle().fill(model.running && model.remoteConnected ? .green : .gray).frame(width: 7, height: 7)
                }
                .padding(.leading, sidebarVisible ? 18 : 152).padding(.trailing, 18).frame(height: 52)
                .xvicoGlassPanel(cornerRadius: 0, bordered: false)
                Rectangle().fill(Color.primary.opacity(0.09)).frame(height: 1)
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
        }
        .background(XvicoWindowBackdrop())
        .overlay(alignment: .topLeading) {
            Button {
                withAnimation(.easeInOut(duration: 0.30)) { sidebarVisible.toggle() }
            } label: {
                Image(systemName: "sidebar.left").font(.system(size: 16, weight: .medium))
                    .frame(width: 36, height: 36).xvicoGlassPanel(cornerRadius: 18, interactive: true)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(LocalizedStringKey(sidebarVisible ? "隐藏边栏" : "显示边栏"))
            .accessibilityLabel(LocalizedStringKey(sidebarVisible ? "隐藏边栏" : "显示边栏"))
            .position(x: sidebarVisible ? XvicoLayout.sidebarWidth - 26 : 114, y: 26)
            .frame(height: 52)
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                XvicoLocalizedText(toast).font(.system(size: 12, weight: .medium)).padding(.horizontal, 15).padding(.vertical, 9)
                    .xvicoGlassPanel(cornerRadius: 40).padding(.bottom, 18)
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

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9).fill(Color.blue.opacity(0.09)).frame(width: 32, height: 38)
                    Image(systemName: "appletvremote.gen3.fill").font(.system(size: 21)).foregroundStyle(.blue)
                }
                VStack(alignment: .leading, spacing: 3) {
                    XvicoLocalizedText("Siri Remote").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 5) {
                        ZStack {
                            Circle().stroke((model.running && model.remoteConnected ? Color.green : Color.gray).opacity(0.5), lineWidth: 2)
                            Circle().fill(model.running && model.remoteConnected ? .green : .gray).padding(3)
                        }.frame(width: 13, height: 13)
                        Text(LocalizedStringKey(model.remoteConnected ? "已连接" : model.remoteConnectionLabel))
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(XvicoTheme.secondaryText).lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }.help(XvicoLocalization.string(model.remoteStatus, locale: locale))
                    if model.remoteConnected {
                        Text(LocalizedStringKey(model.controlStatusLabel)).font(XvicoTypography.caption).foregroundStyle(XvicoTheme.secondaryText).lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).frame(minHeight: 78).padding(.vertical, 6)
            .xvicoGlassPanel(cornerRadius: 16)
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
                    }.buttonStyle(XvicoGlassButtonStyle(selected: model.page == page))
                        .overlay(alignment: .leading) {
                            if model.page == page && colorScheme == .dark {
                                Capsule().fill(XvicoTheme.selectionOutline(colorScheme)).frame(width: 3, height: 18)
                                    .padding(.leading, 8).allowsHitTesting(false)
                            }
                        }
                        .accessibilityLabel(LocalizedStringKey(page.displayName))
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
            }.buttonStyle(XvicoGlassButtonStyle(tint: (model.running ? Color.red : Color.accentColor).opacity(0.12), cornerRadius: 24))
                .padding(.horizontal, 12).padding(.bottom, 12)
        }
        .frame(width: XvicoLayout.sidebarWidth)
        .background(XvicoTheme.sidebarSurface(colorScheme))
        .overlay(alignment: .trailing) { Rectangle().fill(XvicoTheme.border).frame(width: 1) }
    }
}

struct ScenesView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.locale) private var locale
    @State private var showingAdd = false
    @State private var editingScene: XvicoScene?

    @State private var selectedPreset: ScenePreset?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 4) {
                            XvicoLocalizedText("根据前台 App 自动切换映射").font(.system(size: 14, weight: .semibold))
                            XvicoLocalizedText("某个 App 在最前面时，自动套用它的映射规则。").font(.system(size: 11)).foregroundStyle(XvicoTheme.secondaryText)
                        }
                        Toggle("自动切换", isOn: $model.settings.autoSwitchScenes).labelsHidden().toggleStyle(.switch)
                        Spacer()
                        HStack(spacing: 8) {
                            Button { model.restoreInitialRemoteMapping() } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.counterclockwise.circle.fill").font(.system(size: 22))
                                    VStack(alignment: .leading, spacing: 3) {
                                        XvicoLocalizedText("恢复初始键位").font(.system(size: 12, weight: .semibold))
                                        XvicoLocalizedText("恢复音量、静音与默认按键，暂停已有场景").font(.system(size: 10)).lineLimit(2)
                                    }
                                }.padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 64, maxHeight: 64, alignment: .leading)
                                    .contentShape(RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain).foregroundStyle(.blue)
                                .xvicoGlassPanel(cornerRadius: 12, interactive: true)
                                .accessibilityIdentifier("restoreInitialRemoteMapping")
                            Button { model.undoInitialRemoteMappingRestore() } label: {
                                VStack(spacing: 5) {
                                    Image(systemName: "arrow.uturn.backward").font(.system(size: 17, weight: .medium))
                                    XvicoLocalizedText("撤销").font(.system(size: 10, weight: .semibold))
                                }.frame(width: 64, height: 64).contentShape(RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain).foregroundStyle(.blue)
                                .xvicoGlassPanel(cornerRadius: 12, interactive: true)
                                .help("撤销上次恢复")
                                .accessibilityLabel(Text(LocalizedStringKey("撤销上次恢复")))
                                .accessibilityIdentifier("undoInitialRemoteMappingRestore")
                                // Preserve both dimensions while unavailable so
                                // the header and content never move after reset.
                                .opacity(model.canUndoMappingRestore ? 1 : 0)
                                .disabled(!model.canUndoMappingRestore)
                                .allowsHitTesting(model.canUndoMappingRestore)
                                .accessibilityHidden(!model.canUndoMappingRestore)
                        }.frame(width: 332, height: 64)
                    }
                    Divider()
                    HStack {
                        XvicoLocalizedLabel("当前前台：", systemImage: "macwindow").foregroundStyle(XvicoTheme.secondaryText)
                        Text(model.currentApp).fontWeight(.semibold)
                        Spacer()
                        XvicoLocalizedText(model.activeScene?.name ?? "默认映射").foregroundStyle(XvicoTheme.secondaryText)
                    }.font(.system(size: 12))
                }
                .padding(16).xvicoGlassPanel(cornerRadius: 16)

                VStack(alignment: .leading, spacing: 12) {
                    HStack { XvicoLocalizedText("预设库").font(.system(size: 15, weight: .semibold)); Spacer(); Button { model.importPreset() } label: { XvicoLocalizedLabel("导入预设", systemImage: "square.and.arrow.down").font(.system(size: 11, weight: .semibold)) }.buttonStyle(.borderedProminent) }
                    XvicoLocalizedText("选择一套常用映射并绑定到本机 App，也可以导入或导出场景预设。").font(.system(size: 11)).foregroundStyle(XvicoTheme.secondaryText)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(ScenePreset.all) { preset in
                            Button {
                                selectedPreset = preset
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: preset.symbol).font(.system(size: 17)).foregroundStyle(.blue).frame(width: 38, height: 38).background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(LocalizedStringKey(preset.name)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary)
                                        XvicoLocalizedText(preset.detail).font(.system(size: 10)).foregroundStyle(XvicoTheme.secondaryText).lineLimit(2)
                                        Text(preset.tags.map { XvicoLocalization.string($0, locale: locale) }.joined(separator: "  ·  ")).font(.system(size: 9, weight: .medium)).foregroundStyle(XvicoTheme.secondaryText)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                                }.padding(12).frame(maxWidth: .infinity, minHeight: 83, alignment: .leading)
                                    .xvicoGlassPanel(cornerRadius: 14, interactive: true)
                            }.buttonStyle(.plain)
                        }
                    }
                }

                HStack {
                    XvicoLocalizedText("场景").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Button { showingAdd = true } label: { XvicoLocalizedLabel("添加场景", systemImage: "plus").font(.system(size: 11, weight: .semibold)) }.buttonStyle(.borderedProminent)
                }
                VStack(spacing: 0) {
                    ForEach(model.scenes) { scene in
                        HStack(spacing: 12) {
                            ApplicationIcon(bundleID: scene.bundleID, size: 31)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(scene.name).font(.system(size: 12, weight: .semibold))
                                XvicoLocalizedText(scene.bundleID.isEmpty ? "未绑定应用" : scene.bundleID).font(.system(size: 10)).foregroundStyle(XvicoTheme.secondaryText)
                            }
                            Spacer()
                            Button("编辑") { editingScene = scene }.buttonStyle(.borderedProminent).controlSize(.small)
                            Button { model.exportScenes(scene) } label: { Image(systemName: "square.and.arrow.up") }.buttonStyle(.borderedProminent).controlSize(.small).help("导出场景")
                            Toggle("启用", isOn: sceneEnabledBinding(scene)).labelsHidden().toggleStyle(.switch).controlSize(.mini)
                            Button(role: .destructive) { model.deleteScene(scene) } label: { Image(systemName: "trash") }.buttonStyle(.borderedProminent).controlSize(.small).help("删除场景")
                        }.padding(12)
                        if scene.id != model.scenes.last?.id { Divider().padding(.leading, 55) }
                    }
                    if model.scenes.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "square.stack.3d.up").font(.system(size: 28)).foregroundStyle(XvicoTheme.secondaryText)
                            XvicoLocalizedText("还没有场景").font(.system(size: 14, weight: .semibold))
                            XvicoLocalizedText("点击上角「添加场景」，选一个 App，为它单独配一套遥控器映射。").font(.system(size: 12)).foregroundStyle(XvicoTheme.secondaryText).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(45)
                    }
                }
                .xvicoGlassPanel(cornerRadius: 16)
            }.padding(22)
        }
        .sheet(isPresented: $showingAdd) {
            ApplicationPicker(onSelect: { app in
                let id = model.addScene(for: app)
                showingAdd = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { editingScene = model.scenes.first { $0.id == id } }
            }, onCancel: { showingAdd = false }).xvicoPresentationSettings()
        }
        .sheet(item: $editingScene) { SceneEditor(sceneID: $0.id, onDone: { editingScene = nil }).xvicoPresentationSettings() }
        .sheet(item: $selectedPreset) { PresetEditor(preset: $0).xvicoPresentationSettings() }
    }

    private func sceneEnabledBinding(_ scene: XvicoScene) -> Binding<Bool> {
        Binding(get: { model.scenes.first(where: { $0.id == scene.id })?.enabled ?? false }, set: { value in
            guard let index = model.scenes.firstIndex(where: { $0.id == scene.id }) else { return }
            model.scenes[index].enabled = value
        })
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
                            Toggle("启用", isOn: shortcutEnabled(shortcut)).labelsHidden().toggleStyle(.switch).controlSize(.mini)
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

struct SettingsSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: XvicoLayout.rowSpacing) {
            Label(LocalizedStringKey(title), systemImage: symbol).font(XvicoTypography.sectionTitle)
            content
        }.font(XvicoTypography.body).padding(XvicoLayout.cardInset).frame(maxWidth: .infinity, alignment: .leading)
            .xvicoGlassPanel(cornerRadius: 18)
            .shadow(color: .black.opacity(0.045), radius: 13, y: 5)
    }
}
