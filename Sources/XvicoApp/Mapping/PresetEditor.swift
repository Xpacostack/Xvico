import SwiftUI
import UniformTypeIdentifiers

struct PresetEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let preset: ScenePreset
    @State private var bundleID = ""
    @State private var appName = "选择应用"
    @State private var choosingApp = false
    private let previewKeys: [RemoteKey] = [.voice, .tv, .menu, .mute, .volumeUp, .volumeDown, .playPause, .center, .touchUp, .touchDown, .touchLeft, .touchRight]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { XvicoLocalizedLabel(preset.name, systemImage: preset.symbol).font(.title3.bold()); Spacer(); Button("取消") { dismiss() } }
            XvicoLocalizedText(preset.detail).font(.subheadline).foregroundStyle(XvicoTheme.secondaryText)
            Divider()
            XvicoLocalizedText("应用到哪个 App？").font(.headline)
            Button { chooseApp() } label: {
                HStack { ApplicationIcon(bundleID: bundleID); VStack(alignment: .leading) {
                    if bundleID.isEmpty { XvicoLocalizedText("选择应用") } else { Text(appName) }
                    XvicoLocalizedText(bundleID.isEmpty ? "选择正在运行的 App" : bundleID).font(.caption).foregroundStyle(XvicoTheme.secondaryText)
                }; Spacer(); Image(systemName: "chevron.right") }.padding(12).frame(maxWidth: .infinity)
            }.buttonStyle(.plain).background(XvicoTheme.card, in: RoundedRectangle(cornerRadius: 10))
            XvicoLocalizedText("映射预览").font(.headline)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(previewKeys) { key in
                        let binding = preset.bindings[key.rawValue] ?? model.settings.globalBindings[key.rawValue] ?? key.referenceBinding
                        HStack {
                            Image(systemName: key.symbol).frame(width: 24).foregroundStyle(.blue)
                            XvicoLocalizedText(key.displayName)
                            Text(binding.enabled ? "→" : "·")
                            XvicoLocalizedText(binding.enabled ? label(binding) : "已关闭")
                            Spacer()
                            if preset.bindings[key.rawValue] == nil {
                                XvicoLocalizedText("继承默认映射").font(.caption2).foregroundStyle(XvicoTheme.secondaryText)
                            }
                        }.font(.system(size: 12)).padding(9).foregroundStyle(binding.enabled ? Color.primary : XvicoTheme.secondaryText)
                        if key != previewKeys.last { Divider() }
                    }
                }.background(XvicoTheme.card, in: RoundedRectangle(cornerRadius: 10))
            }.frame(maxHeight: 365)
            if preset.id == "codex" { XvicoLocalizedText("此 App 场景的外圈动作设为 Codex 任务（⌘1–9）。触控输入需要遥控器接口连接后验证。").font(.caption).foregroundStyle(XvicoTheme.secondaryText) }
            HStack { XvicoLocalizedText("已有该 App 场景时替换其映射。").font(.caption).foregroundStyle(XvicoTheme.secondaryText); Spacer(); Button("应用预设") { model.applyPreset(preset, bundleID: bundleID); dismiss() }.buttonStyle(.borderedProminent).disabled(bundleID.isEmpty) }
        }.padding(20).frame(width: 560)
            .xvicoGlassPanel(cornerRadius: 22, floating: true).onAppear {
            if let app = ApplicationCatalog.installed(preset.suggestedBundleID) {
                bundleID = preset.suggestedBundleID
                appName = app.name
            }
        }.sheet(isPresented: $choosingApp) {
            ApplicationPicker(onSelect: { app in bundleID = app.id; appName = app.name; choosingApp = false }, onCancel: { choosingApp = false })
                .xvicoPresentationSettings()
        }
    }
    private func label(_ binding: KeyBinding) -> String {
        if binding.action == .click { return "鼠标左键" }
        return KeyboardModifier.allCases.filter { binding.modifiers.contains($0) }.map(\.symbol).joined() + binding.value
    }
    private func chooseApp() {
        choosingApp = true
    }
}
