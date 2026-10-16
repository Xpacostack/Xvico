import AppKit
import SwiftUI

struct ApplicationChoice: Identifiable, Equatable {
    let id: String
    let name: String
    let url: URL?
}

@MainActor
enum ApplicationCatalog {
    static func running() -> [ApplicationChoice] {
        var ids = Set<String>()
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, !app.isTerminated,
                  let id = app.bundleIdentifier, ids.insert(id).inserted else { return nil }
            return ApplicationChoice(id: id, name: app.localizedName ?? id, url: app.bundleURL)
        }.sorted { $0.name.compare($1.name, options: [.caseInsensitive, .numeric]) == .orderedAscending }
    }
    static func installed(_ id: String) -> ApplicationChoice? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        let bundle = Bundle(url: url)
        let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        return ApplicationChoice(id: id, name: name, url: url)
    }
}

struct ApplicationIcon: View {
    let bundleID: String
    var size: CGFloat = 28
    var body: some View {
        Group {
            if let choice = ApplicationCatalog.installed(bundleID), let url = choice.url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
            } else { Image(systemName: "app").resizable().foregroundStyle(.secondary) }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct ApplicationPicker: View {
    let onSelect: (ApplicationChoice) -> Void
    let onCancel: () -> Void
    @State private var choices: [ApplicationChoice] = []
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("选择一个 App").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("取消", action: onCancel).buttonStyle(XvicoToolbarButtonStyle())
            }.padding(16)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(choices) { app in
                        Button { onSelect(app) } label: {
                            HStack(spacing: 12) {
                                ApplicationIcon(bundleID: app.id, size: 24)
                                Text(app.name).font(.system(size: 14))
                                Spacer()
                            }.padding(.horizontal, 16).frame(height: 52).contentShape(Rectangle())
                        }.buttonStyle(XvicoInsetGlassButtonStyle(cornerRadius: 12)).accessibilityLabel(app.name)
                            .padding(.horizontal, 8)
                        if app.id != choices.last?.id { Divider().padding(.leading, 52).padding(.trailing, 16) }
                    }
                }.padding(.vertical, 8)
            }
        }.frame(width: 420, height: 520)
            .xvicoGlassPanel(cornerRadius: 22, floating: true)
            .onAppear { choices = ApplicationCatalog.running() }
    }
}
