import AppKit
import Combine

@MainActor final class AudioBackendManager: ObservableObject {
    @Published private(set) var installed = false
    @Published private(set) var needsBrandingUpdate = false
    @Published private(set) var busy = false
    @Published private(set) var status = "尚未安装语音后端"
    init() { refresh() }
    func refresh() {
        installed = FileManager.default.isExecutableFile(atPath: "/Library/Application Support/Xvibe/AudioBackend/XvibeBackendRunner")
            && FileManager.default.fileExists(atPath: "/Library/Audio/Plug-Ins/HAL/XvibeMicrophone.driver")
        let info = NSDictionary(contentsOfFile: "/Library/Audio/Plug-Ins/HAL/XvibeMicrophone.driver/Contents/Info.plist")
        needsBrandingUpdate = installed && info?["CFBundleDisplayName"] as? String != "Xvico Microphone"
        if !busy {
            status = !installed ? "尚未安装语音后端"
                : needsBrandingUpdate ? "语音后端已安装，麦克风名称待更新" : "后台服务与 Xvico Microphone 已安装"
        }
    }
    func manage(installing: Bool) {
        perform(installing ? "install" : "uninstall")
    }
    func updateBranding() { perform("rebrand") }
    private func perform(_ operation: String) {
        guard !busy else { return }
        busy = true; status = "等待系统管理员批准"
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/AudioBackend/XvibeBackendHelper").path
        let values = operation == "uninstall" ? [helper, operation] : [helper, operation, Bundle.main.bundleURL.path]
        let command = values.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
        let literal = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        Task {
            let message = await Task.detached { () -> String? in
                var error: NSDictionary?
                guard let script = NSAppleScript(source: "do shell script \"\(literal)\" with administrator privileges") else { return "无法请求系统批准" }
                script.executeAndReturnError(&error)
                return error?[NSAppleScript.errorMessage] as? String
            }.value
            busy = false; refresh()
            if let message { status = message }
        }
    }
}
