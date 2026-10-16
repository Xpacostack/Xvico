import SwiftUI

struct ScenesView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.locale) private var locale
    @State private var showingAdd = false
    @State private var editingScene: XvicoScene?
    @State private var selectedPreset: ScenePreset?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                mappingStatus
                presetLibrary
                applicationScenes
            }
            .frame(maxWidth: 920)
            .padding(XvicoLayout.pageInset)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showingAdd) {
            ApplicationPicker(onSelect: { app in
                let id = model.addScene(for: app)
                showingAdd = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { editingScene = model.scenes.first { $0.id == id } }
            }, onCancel: { showingAdd = false }).xvicoPresentationSettings()
        }
        .sheet(item: $editingScene) {
            SceneEditor(sceneID: $0.id, onDone: { editingScene = nil }).xvicoPresentationSettings()
        }
        .sheet(item: $selectedPreset) { PresetEditor(preset: $0).xvicoPresentationSettings() }
    }

    private var mappingStatus: some View {
        XvicoSettingsCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Image(systemName: model.running ? "dot.radiowaves.left.and.right" : "pause.circle")
                        .font(.system(size: 21)).foregroundStyle(model.running ? Color.blue : .secondary)
                        .frame(width: 44, height: 44)
                        .background(Color.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 5) {
                        XvicoLocalizedText(model.running ? "当前生效" : "控制已停止")
                            .font(XvicoTypography.caption).foregroundStyle(XvicoTheme.secondaryText)
                        Text(model.running ? model.activeScene?.name ?? XvicoLocalization.string("默认映射", locale: locale)
                             : XvicoLocalization.string("控制已停止", locale: locale))
                            .font(.system(size: 18, weight: .semibold))
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 4) {
                        XvicoLocalizedText("当前前台：").font(XvicoTypography.caption).foregroundStyle(XvicoTheme.secondaryText)
                        Text(model.currentApp).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    }
                }
                Divider()
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        XvicoLocalizedText("根据前台 App 自动切换映射").font(.system(size: 13, weight: .semibold))
                        XvicoLocalizedText("某个 App 在最前面时，自动套用它的映射规则。")
                            .font(XvicoTypography.caption).foregroundStyle(XvicoTheme.secondaryText)
                    }
                    Spacer(minLength: 8)
                    Toggle("自动切换", isOn: $model.settings.autoSwitchScenes)
                        .labelsHidden().toggleStyle(XvicoSwitchStyle())
                }
                HStack(spacing: 10) {
                    Button { model.restoreInitialRemoteMapping() } label: {
                        XvicoLocalizedLabel("恢复初始键位", systemImage: "arrow.counterclockwise")
                    }.buttonStyle(XvicoToolbarButtonStyle())
                        .accessibilityIdentifier("restoreInitialRemoteMapping")
                    Button { model.undoInitialRemoteMappingRestore() } label: {
                        XvicoLocalizedLabel("撤销", systemImage: "arrow.uturn.backward")
                    }.buttonStyle(XvicoToolbarButtonStyle(prominent: true))
                        .help("撤销上次恢复").accessibilityLabel(Text(LocalizedStringKey("撤销上次恢复")))
                        .accessibilityIdentifier("undoInitialRemoteMappingRestore")
                        .opacity(model.canUndoMappingRestore ? 1 : 0)
                        .disabled(!model.canUndoMappingRestore).allowsHitTesting(model.canUndoMappingRestore)
                        .accessibilityHidden(!model.canUndoMappingRestore)
                    Spacer(minLength: 8)
                    XvicoLocalizedText("恢复音量、静音与默认按键，暂停已有场景")
                        .font(XvicoTypography.caption).foregroundStyle(XvicoTheme.secondaryText)
                        .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var presetLibrary: some View {
        VStack(alignment: .leading, spacing: 14) {
            XvicoSectionHeading(title: "预设库", detail: "选择一套常用映射并绑定到本机 App，也可以导入或导出场景预设。") {
                Button { model.importPreset() } label: { XvicoLocalizedLabel("导入预设", systemImage: "square.and.arrow.down") }
                    .buttonStyle(XvicoToolbarButtonStyle())
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 245), spacing: 12)], spacing: 12) {
                ForEach(ScenePreset.all) { preset in
                    Button { selectedPreset = preset } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Image(systemName: preset.symbol).font(.system(size: 18))
                                    .foregroundStyle(.blue).frame(width: 40, height: 40)
                                    .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                                Text(LocalizedStringKey(preset.name)).font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.primary).lineLimit(2)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                            }
                            XvicoLocalizedText(preset.detail).font(.system(size: 11))
                                .foregroundStyle(XvicoTheme.secondaryText).lineLimit(3)
                                .frame(maxWidth: .infinity, minHeight: 42, alignment: .topLeading)
                        }
                        .padding(16).frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
                    }
                    .buttonStyle(ScenePresetButtonStyle())
                }
            }
        }
    }

    private var applicationScenes: some View {
        VStack(alignment: .leading, spacing: 14) {
            XvicoSectionHeading(title: "应用场景") {
                Button { showingAdd = true } label: { XvicoLocalizedLabel("添加场景", systemImage: "plus") }
                    .buttonStyle(XvicoToolbarButtonStyle(prominent: true))
            }
            if model.scenes.isEmpty {
                XvicoSettingsCard {
                    VStack(spacing: 12) {
                        Image(systemName: "square.stack.3d.up").font(.system(size: 28)).foregroundStyle(XvicoTheme.secondaryText)
                        XvicoLocalizedText("还没有场景").font(.system(size: 14, weight: .semibold))
                        XvicoLocalizedText("点击上角「添加场景」，选一个 App，为它单独配一套遥控器映射。")
                            .font(.system(size: 12)).foregroundStyle(XvicoTheme.secondaryText).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity).padding(.vertical, 26)
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(model.scenes) { scene in
                        XvicoSettingsCard {
                            HStack(spacing: 14) {
                                ApplicationIcon(bundleID: scene.bundleID, size: 38)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(scene.name).font(.system(size: 14, weight: .semibold))
                                    Text(scene.bundleID.isEmpty ? XvicoLocalization.string("未绑定应用", locale: locale) : scene.bundleID)
                                        .font(XvicoTypography.caption).foregroundStyle(XvicoTheme.secondaryText).lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                XvicoStatusBadge(title: scene.enabled ? (model.running && model.activeScene?.id == scene.id ? "当前生效" : "已启用") : "已暂停",
                                                 symbol: scene.enabled ? (model.running && model.activeScene?.id == scene.id ? "checkmark.circle.fill" : "circle") : "pause.circle",
                                                 color: scene.enabled ? (model.running && model.activeScene?.id == scene.id ? .green : .blue) : .secondary)
                                Button("编辑") { editingScene = scene }
                                    .buttonStyle(XvicoToolbarButtonStyle(prominent: true))
                                    .accessibilityLabel(Text(scene.name) + Text(" ") + Text(LocalizedStringKey("编辑")))
                                Menu {
                                    Button { model.exportScenes(scene) } label: { Label("导出场景", systemImage: "square.and.arrow.up") }
                                    Button(role: .destructive) { model.deleteScene(scene) } label: { Label("删除场景", systemImage: "trash") }
                                } label: { Image(systemName: "ellipsis").frame(width: 40, height: 40).contentShape(Rectangle()) }
                                    .menuStyle(.borderlessButton).fixedSize()
                                    .accessibilityLabel(Text(scene.name) + Text(" ") + Text(LocalizedStringKey("场景操作")))
                                Toggle("启用", isOn: sceneEnabledBinding(scene)).labelsHidden()
                                    .toggleStyle(XvicoSwitchStyle())
                                    .accessibilityLabel(Text(scene.name) + Text(" ") + Text(LocalizedStringKey("启用")))
                            }
                        }
                    }
                }
            }
        }
    }

    private func sceneEnabledBinding(_ scene: XvicoScene) -> Binding<Bool> {
        Binding(get: { model.scenes.first(where: { $0.id == scene.id })?.enabled ?? false }, set: { value in
            guard let index = model.scenes.firstIndex(where: { $0.id == scene.id }) else { return }
            model.scenes[index].enabled = value
        })
    }
}

private struct ScenePresetButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(XvicoTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.075), lineWidth: 0.75).allowsHitTesting(false)
            }
            .xvicoPointerLight(cornerRadius: 18, active: true)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
