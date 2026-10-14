import SwiftUI

struct SceneEditor: View {
    @EnvironmentObject private var model: AppModel
    let sceneID: UUID
    let onDone: () -> Void
    private var scene: XvicoScene? { model.scenes.first { $0.id == sceneID } }
    private var ring: Binding<RingAction?> {
        Binding(get: { scene?.ringAction }, set: { model.setSceneRing($0, for: sceneID) })
    }
    private var wheel: Binding<WheelStyle?> {
        Binding(get: { scene?.wheelStyle }, set: { model.setSceneWheel($0, for: sceneID) })
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ApplicationIcon(bundleID: scene?.bundleID ?? "", size: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Group {
                        if let scene { Text(scene.name) } else { XvicoLocalizedText("应用场景") }
                    }.font(.system(size: 20, weight: .bold))
                    XvicoLocalizedText("这个 App 在前台时的映射").font(.system(size: 12)).foregroundStyle(XvicoTheme.secondaryText)
                }
                Spacer()
                Button("完成", action: onDone).buttonStyle(.borderedProminent)
            }.padding(20)
            Divider()
            ScrollView {
                VStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 12) {
                        XvicoLocalizedText("外圈滚轮（本场景）").font(.system(size: 13, weight: .semibold)).foregroundStyle(XvicoTheme.secondaryText)
                        XvicoLocalizedText("圆环旋转动作").font(.system(size: 13, weight: .semibold))
                        Picker("圆环旋转动作", selection: ring) {
                            XvicoLocalizedText("跟随全局").tag(Optional<RingAction>.none)
                            ForEach(RingAction.allCases) { XvicoLocalizedText($0.rawValue).tag(Optional($0)) }
                        }.pickerStyle(.segmented).labelsHidden()
                        XvicoLocalizedText("选「Codex 任务（⌘1–9）」后，在这个 App 里转外圈会依次发出 ⌘1、⌘2…⌘9，用于切换 Codex 任务。").font(.system(size: 11)).foregroundStyle(XvicoTheme.secondaryText)
                        XvicoLocalizedText("滚轮手感").font(.system(size: 13, weight: .semibold))
                        Picker("滚轮手感", selection: wheel) {
                            XvicoLocalizedText("跟随全局").tag(Optional<WheelStyle>.none)
                            ForEach(WheelStyle.allCases) { XvicoLocalizedText($0.rawValue).tag(Optional($0)) }
                        }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 300, alignment: .leading)
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .xvicoGlassPanel(cornerRadius: 14)
                    Divider().padding(.vertical, 2)
                    ForEach(RemoteKey.physicalOrder) { key in
                        SceneBindingRow(key: key, binding: Binding(
                            get: { model.sceneBinding(for: key, sceneID: sceneID) },
                            set: { model.setSceneBinding($0, key: key, sceneID: sceneID) }))
                    }
                }.padding(16)
            }
        }.frame(width: 720, height: 700)
            .xvicoGlassPanel(cornerRadius: 22, floating: true)
    }
}

struct SceneBindingRow: View {
    @Environment(\.locale) private var locale
    let key: RemoteKey
    @Binding var binding: KeyBinding
    @State private var keyboardOpen = false
    @State private var choosingApp = false

    private func field<T>(_ keyPath: WritableKeyPath<KeyBinding, T>) -> Binding<T> {
        Binding(get: { binding[keyPath: keyPath] }, set: { binding[keyPath: keyPath] = $0 })
    }
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: key.sceneSymbol).font(.system(size: 16)).frame(width: 22).foregroundStyle(XvicoTheme.secondaryText)
            XvicoLocalizedText(key.displayName).font(.system(size: 14, weight: .semibold)).frame(width: 112, alignment: .leading)
            Group {
                switch binding.action {
                case .key:
                    Menu {
                        ForEach(KeyboardQuickAction.allCases) { action in Button(LocalizedStringKey(action.rawValue)) { binding = action.applying(to: binding) } }
                    } label: { Image(systemName: "bolt.fill") }
                    .menuStyle(.borderlessButton).fixedSize().help("快捷操作").disabled(!binding.enabled)
                    Button { keyboardOpen = true } label: {
                        HStack {
                            XvicoLocalizedText(binding.keyboardLabel).font(.system(size: 14, weight: .semibold))
                            Spacer(); Image(systemName: "chevron.down").font(.system(size: 10))
                        }.frame(maxWidth: .infinity).frame(height: 25)
                    }.buttonStyle(.borderedProminent).disabled(!binding.enabled)
                        .accessibilityLabel(XvicoLocalization.string("\(key.displayName)快捷键 \(binding.keyboardLabel)", locale: locale))
                        .popover(isPresented: $keyboardOpen) {
                            KeyboardShortcutEditor(value: field(\.value), modifiers: field(\.modifiers), rightModifiers: field(\.rightModifiers))
                                .padding(14).frame(width: 310)
                                .xvicoGlassPanel(cornerRadius: 18, floating: true)
                                .xvicoPresentationSettings()
                        }
                case .click:
                    Spacer(minLength: 0)
                    Picker(XvicoLocalization.string("\(key.displayName)鼠标按键", locale: locale), selection: field(\.mouseButton)) {
                        XvicoLocalizedText("鼠标左键").tag(MouseClickButton.left)
                        XvicoLocalizedText("鼠标右键").tag(MouseClickButton.right)
                    }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 210).disabled(!binding.enabled)
                    Spacer(minLength: 0)
                case .textAndReturn:
                    TextField("文本 + 回车", text: field(\.textValue)).textFieldStyle(.roundedBorder).disabled(!binding.enabled)
                case .openApp:
                    Button { choosingApp = true } label: {
                        HStack {
                            if !binding.value.isEmpty { ApplicationIcon(bundleID: binding.value, size: 18) }
                            XvicoLocalizedText(ApplicationCatalog.installed(binding.value)?.name ?? "选择 App")
                            Spacer(); Image(systemName: "chevron.down").font(.system(size: 10))
                        }.frame(maxWidth: .infinity).frame(height: 25)
                    }.buttonStyle(.borderedProminent).disabled(!binding.enabled)
                case .screenOff:
                    XvicoLocalizedText("熄屏").foregroundStyle(XvicoTheme.secondaryText).frame(maxWidth: .infinity, alignment: .leading)
                default:
                    XvicoLocalizedText(binding.action.rawValue).foregroundStyle(XvicoTheme.secondaryText).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Menu {
                Button("鼠标点击") { binding.action = .click }
                Button("键盘按键") { binding.action = .key }
                Button("打开 App") { binding.action = .openApp; choosingApp = true }
                if key == .power {
                    Button("文本 + 回车") { binding.action = .textAndReturn }
                    Button("熄屏") { binding.action = .screenOff }
                }
            } label: { Image(systemName: binding.action == .click ? "cursorarrow.click" : binding.action == .textAndReturn ? "number" : binding.action == .openApp ? "app" : binding.action == .screenOff ? "moon.zzz" : "keyboard") }
                .menuStyle(.borderlessButton).fixedSize().help("按键动作")
                .accessibilityLabel(XvicoLocalization.string("\(key.displayName)按键动作", locale: locale))
            Toggle(XvicoLocalization.string("\(key.displayName)启用", locale: locale), isOn: field(\.enabled)).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }.padding(.horizontal, 16).padding(.vertical, 12)
            .xvicoGlassPanel(cornerRadius: 16)
            .sheet(isPresented: $choosingApp) {
                ApplicationPicker(onSelect: { app in binding.value = app.id; choosingApp = false }, onCancel: { choosingApp = false })
                    .xvicoPresentationSettings()
            }
    }
}

enum KeyboardQuickAction: String, CaseIterable, Identifiable {
    case missionControl = "调度中心 Mission Control", expose = "应用窗口 App Exposé"
    case previousDesktop = "上一个桌面", nextDesktop = "下一个桌面"
    var id: String { rawValue }
    func applying(to source: KeyBinding) -> KeyBinding {
        var binding = source
        binding.action = .key; binding.modifiers = [.control]; binding.rightModifiers = []
        binding.value = switch self { case .missionControl: "Up Arrow"; case .expose: "Down Arrow"; case .previousDesktop: "Left Arrow"; case .nextDesktop: "Right Arrow" }
        return binding
    }
}

extension KeyBinding {
    var keyboardLabel: String {
        KeyboardModifier.allCases.filter { modifiers.contains($0) }.map(\.symbol).joined()
            + (KeyboardOutput.named(value)?.symbol ?? value)
    }
}

extension RemoteKey {
    static let physicalOrder: [RemoteKey] = [.voice, .tv, .menu, .power, .mute, .volumeUp, .volumeDown, .playPause, .center, .touchUp, .touchDown, .touchLeft, .touchRight]
    var sceneSymbol: String {
        switch self {
        case .voice: "sparkles"
        case .tv: "tv"
        case .center: "smallcircle.filled.circle"
        case .volumeUp: "speaker.plus.fill"
        case .volumeDown: "speaker.minus.fill"
        default: symbol
        }
    }
}
