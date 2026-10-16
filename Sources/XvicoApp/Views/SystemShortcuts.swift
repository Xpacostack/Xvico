import SwiftUI
import Foundation

struct SystemShortcut: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
}
struct ShortcutCommandResult: Sendable { let status: Int32; let output: String }
protocol ShortcutCommandRunning: Sendable {
    func execute(_ arguments: [String]) async throws -> ShortcutCommandResult
}
struct MacShortcutCommandRunner: ShortcutCommandRunning {
    func execute(_ arguments: [String]) async throws -> ShortcutCommandResult {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = arguments
            // A GUI parent has no interactive input; shortcuts otherwise waits for EOF.
            process.standardInput = FileHandle.nullDevice
            let pipe = Pipe()
            process.standardOutput = pipe; process.standardError = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return ShortcutCommandResult(status: process.terminationStatus, output: String(data: data, encoding: .utf8) ?? "")
        }.value
    }
}

@MainActor
final class SystemShortcutsService: ObservableObject {
    @Published private(set) var shortcuts: [SystemShortcut] = []
    @Published private(set) var refreshing = false
    @Published private(set) var runningID: UUID?
    @Published private(set) var message: String?
    @Published private(set) var errorMessage: String?
    enum ExecutionMode { case callback, command }
    private let runner: any ShortcutCommandRunning
    private let executionMode: ExecutionMode
    private let urlOpener: (URL) -> Bool
    private var callbackToken: UUID?
    private var pendingShortcut: SystemShortcut?
    private var reminderTask: Task<Void, Never>?
    init(runner: any ShortcutCommandRunning = MacShortcutCommandRunner(), executionMode: ExecutionMode = .callback, urlOpener: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        self.runner = runner; self.executionMode = executionMode; self.urlOpener = urlOpener
    }
    static func callbackRunURL(_ shortcut: SystemShortcut, token: UUID) -> URL {
        var components = URLComponents()
        components.scheme = "shortcuts"; components.host = "x-callback-url"; components.path = "/run-shortcut"
        var queryItems: [URLQueryItem] = [URLQueryItem(name: "name", value: shortcut.name)]
        for outcome in ["success", "error", "cancel"] {
            let callback = "xvico://shortcut/\(outcome)?token=\(token.uuidString)"
            queryItems.append(URLQueryItem(name: "x-\(outcome)", value: callback))
        }
        components.queryItems = queryItems
        return components.url!
    }
    @discardableResult func handleCallback(_ url: URL) -> Bool {
        guard ["xvico", "xpavi", "xvibe"].contains(url.scheme?.lowercased() ?? ""), url.host == "shortcut", let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
              let expected = callbackToken, token == expected.uuidString, let shortcut = pendingShortcut else { return false }
        switch url.path {
        case "/success": message = "已运行：\(shortcut.name)"
        case "/cancel": message = "已取消：\(shortcut.name)"
        case "/error":
            let error = components.queryItems?.first(where: { $0.name == "errorMessage" })?.value ?? "系统快捷指令未返回成功状态"
            errorMessage = "运行失败：" + String(error.prefix(600))
        default: return false
        }
        reminderTask?.cancel(); reminderTask = nil
        runningID = nil; callbackToken = nil; pendingShortcut = nil
        return true
    }
    func stopWaiting() {
        reminderTask?.cancel(); reminderTask = nil
        runningID = nil; callbackToken = nil; pendingShortcut = nil
        message = "已停止等待结果；正在执行的动作请在「快捷指令.app」中停止。"
    }

    static func parse(_ text: String) -> [SystemShortcut] {
        var seen = Set<UUID>()
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            let text = String(line)
            guard text.hasSuffix(")"), let opening = text.range(of: " (", options: .backwards),
                  let id = UUID(uuidString: String(text[opening.upperBound..<text.index(before: text.endIndex)])), seen.insert(id).inserted else { return nil }
            return SystemShortcut(id: id, name: String(text[..<opening.lowerBound]))
        }
    }
    func refresh() async {
        guard !refreshing else { return }
        refreshing = true; errorMessage = nil
        defer { refreshing = false }
        do {
            let result = try await runner.execute(["list", "--show-identifiers"])
            guard result.status == 0 else { throw failure(result.output) }
            shortcuts = Self.parse(result.output)
        } catch { shortcuts = []; errorMessage = "无法读取系统快捷指令：\(error.localizedDescription)" }
    }
    func run(_ shortcut: SystemShortcut) async {
        guard runningID == nil else { return }
        runningID = shortcut.id; errorMessage = nil; message = nil
        if executionMode == .callback {
            let token = UUID(); callbackToken = token; pendingShortcut = shortcut
            guard urlOpener(Self.callbackRunURL(shortcut, token: token)) else {
                runningID = nil; callbackToken = nil; pendingShortcut = nil
                errorMessage = "无法打开系统快捷指令。"; return
            }
            message = "等待「快捷指令.app」返回执行结果…"
            reminderTask?.cancel()
            reminderTask = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
                guard self?.callbackToken == token else { return }
                self?.message = "系统尚未返回执行结果。请在「快捷指令.app」中检查，或停止等待。"
            }
            return
        }
        defer { runningID = nil }
        do {
            let result = try await runner.execute(["run", shortcut.id.uuidString])
            guard result.status == 0 else { throw failure(result.output) }
            message = "已运行：\(shortcut.name)"
        } catch { errorMessage = "运行失败：\(error.localizedDescription)" }
    }
    private func failure(_ output: String) -> NSError {
        NSError(domain: "Xvico.Shortcuts", code: 1, userInfo: [NSLocalizedDescriptionKey: output.isEmpty ? "系统快捷指令服务未返回成功状态" : String(output.prefix(600))])
    }
}

struct CommandsView: View {
    @EnvironmentObject private var service: SystemShortcutsService
    @State private var search = ""
    private var filtered: [SystemShortcut] { service.shortcuts.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsSection(title: "系统快捷指令", symbol: "command") {
                    XvicoLocalizedText("这里列出「快捷指令.app」里的 Shortcuts，点「运行」即可一键执行。").font(.system(size: 12)).foregroundStyle(XvicoTheme.secondaryText)
                    HStack {
                        TextField("搜索快捷指令", text: $search).textFieldStyle(.roundedBorder)
                        Button { Task { await service.refresh() } } label: { XvicoLocalizedLabel("刷新", systemImage: "arrow.clockwise") }.buttonStyle(.borderedProminent).disabled(service.refreshing)
                    }
                }
                if service.refreshing { ProgressView("读取系统快捷指令…") }
                if let error = service.errorMessage { XvicoLocalizedText(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
                if let message = service.message { XvicoLocalizedText(message).font(.callout).foregroundStyle(XvicoTheme.secondaryText) }
                if service.runningID != nil { Button("停止等待") { service.stopWaiting() }.help("停止等待回调；实际动作请在快捷指令.app 中停止。") }
                if !filtered.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(filtered) { shortcut in
                            HStack(spacing: 12) {
                                Image(systemName: "square.stack.3d.forward.dottedline").foregroundStyle(.blue)
                                Text(shortcut.name).font(.system(size: 13, weight: .semibold))
                                Spacer()
                                Button { Task { await service.run(shortcut) } } label: { XvicoLocalizedLabel(service.runningID == shortcut.id ? "运行中…" : "运行", systemImage: "play.fill") }.buttonStyle(.borderedProminent).disabled(service.runningID != nil)
                            }.padding(14)
                            if shortcut.id != filtered.last?.id { Divider().padding(.leading, 44) }
                        }
                    }.xvicoGlassPanel(cornerRadius: 16)
                } else if !service.refreshing && service.errorMessage == nil {
                    XvicoLocalizedText(search.isEmpty ? "系统中尚无快捷指令。请先在「快捷指令.app」中创建。" : "没有匹配的快捷指令。").foregroundStyle(XvicoTheme.secondaryText).frame(maxWidth: .infinity).padding(30)
                }
            }.frame(maxWidth: 720).padding(22)
        }.task { await service.refresh() }
    }
}
