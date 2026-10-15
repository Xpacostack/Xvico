import AppKit
import Combine

struct AppleVoiceRuntimeStore: Sendable {
    let home: URL
    let app: URL
    let verify: @Sendable (URL) throws -> Void

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser, app: URL = Bundle.main.bundleURL,
         verify: @escaping @Sendable (URL) throws -> Void = { try AppleVoiceRuntimeStore.verifyAppleSignatures($0) }) {
        self.home = home.resolvingSymlinksInPath(); self.app = app; self.verify = verify
    }
    func sourceRoot(_ source: URL) -> URL {
        let source = source.standardizedFileURL
        if source.pathExtension == "app" { return source.appendingPathComponent("Contents") }
        if VoiceRuntimeLocation.hasLayout(source) { return source }
        return source.appendingPathComponent("Contents")
    }
    func available() -> Bool {
        guard let runtime = VoiceRuntimeLocation.resolve(app: app, home: home) else { return false }
        return (try? verify(runtime)) != nil
    }
    func importRuntime(from source: URL) throws {
        let fm = FileManager.default
        let input = sourceRoot(source)
        guard VoiceRuntimeLocation.hasLayout(input) else { throw failure("所选目录缺少 Apple 语音运行时组件") }
        try verify(input)
        let output = VoiceRuntimeLocation.imported(in: home)
        let parent = output.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard parent.resolvingSymlinksInPath() == parent.standardizedFileURL else { throw failure("语音运行时目录包含不安全链接") }
        let stage = parent.appendingPathComponent(".runtime-stage-\(UUID())")
        let previous = parent.appendingPathComponent(".runtime-previous-\(UUID())")
        try fm.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: stage) }
        for (relative, _) in VoiceRuntimeLocation.components {
            let destination = stage.appendingPathComponent(relative)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: input.appendingPathComponent(relative), to: destination)
        }
        if let entries = fm.enumerator(at: stage, includingPropertiesForKeys: nil) {
            for case let path as URL in entries {
                guard VoiceRuntimeLocation.containsResolvedItem(path, within: stage) else {
                    throw failure("语音运行时目录包含不安全链接")
                }
            }
        }
        try verify(stage)
        var movedPrevious = false
        if fm.fileExists(atPath: output.path) {
            try fm.moveItem(at: output, to: previous); movedPrevious = true
        }
        do { try fm.moveItem(at: stage, to: output) }
        catch {
            if movedPrevious { try? fm.moveItem(at: previous, to: output) }
            throw error
        }
        if movedPrevious { try? fm.removeItem(at: previous) }
    }
    private func failure(_ message: String) -> Error {
        NSError(domain: "Xvico.VoiceRuntime", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    static func verifyAppleSignatures(_ root: URL) throws {
        for (relative, identifier) in VoiceRuntimeLocation.components {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            process.arguments = ["--verify", "--strict", "--all-architectures", "-R",
                "=identifier \"\(identifier)\" and anchor apple", root.appendingPathComponent(relative).path]
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw NSError(domain: "Xvico.VoiceRuntime", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Apple 签名验证失败，未导入运行时"])
            }
        }
    }
}

@MainActor final class AppleVoiceRuntimeManager: ObservableObject {
    @Published private(set) var available = false
    @Published private(set) var busy = false
    @Published private(set) var status = "遥控器语音需要 Apple 运行时"
    private let store: AppleVoiceRuntimeStore
    init(store: AppleVoiceRuntimeStore = AppleVoiceRuntimeStore()) { self.store = store }

    // StateObject initialization happens inside SwiftUI's graph update. Process
    // waitUntilExit spins a run loop, so signature checks must never run there
    // or anywhere else on the main thread.
    @discardableResult func refresh() -> Task<Void, Never>? {
        guard !busy else { return nil }
        busy = true
        let store = store
        return Task { [weak self] in
            let ready = await Task.detached { store.available() }.value
            guard let self else { return }
            self.available = ready
            self.status = ready ? "Apple 语音运行时已就绪" : "遥控器语音需要 Apple 运行时"
            self.busy = false
        }
    }
    func chooseRuntime(locale: Locale = .current) {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.message = XvicoLocalization.string("请选择官方 PacketLogger.app 或语音运行时目录", locale: locale)
        guard panel.runModal() == .OK, let source = panel.url else { return }
        busy = true; status = "正在验证并导入 Apple 运行时"
        let store = store
        Task { [weak self] in
            do {
                let ready = try await Task.detached {
                    try store.importRuntime(from: source)
                    return store.available()
                }.value
                self?.available = ready
                self?.status = ready ? "Apple 语音运行时已就绪" : "遥控器语音需要 Apple 运行时"
            } catch { self?.status = error.localizedDescription }
            self?.busy = false
        }
    }
}
