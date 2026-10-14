import AppKit
import Combine
import CryptoKit
import Security

/// Approval for the installed control service is persistent. Recording itself
/// is never started by init, refresh, installation, or an app relaunch.
@MainActor
final class VoiceBackendAuthorization: ObservableObject {
    @Published private(set) var ready = false
    @Published private(set) var installed = false
    @Published private(set) var busy = false
    @Published private(set) var status = "尚未保存后台授权"
    private let defaults: UserDefaults
    private let bundle: URL
    private let root: URL
    private let runOperation: (String, URL) async -> String?

    init(defaults: UserDefaults = .standard, bundle: URL = Bundle.main.bundleURL,
         root: URL = URL(fileURLWithPath: VoiceHelperContract.root),
         runOperation: @escaping (String, URL) async -> String? = VoiceBackendAuthorization.authorizedOperation) {
        self.defaults = defaults; self.bundle = bundle; self.root = root
        self.runOperation = runOperation
        refresh()
    }
    static func payloadMatches(bundle: URL, root: URL) -> Bool {
        let info = NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist"))
        let fingerprint = info?["XvicoVoiceServiceSigningIdentity"] as? String
        for (relative, name) in [
            ("AudioBackend/XvicoVoiceDaemon", "XvicoVoiceDaemon"),
            ("AudioBackend/XvibeBackendRunner", "XvibeBackendRunner"),
            ("AudioBackend/XvibeAudioRouter", "XvibeAudioRouter"),
            ("AudioBackend/libopus.0.dylib", "libopus.0.dylib"),
            ("VoiceTools/XvibeVoiceCapture", "XvibeVoiceCapture")
        ] {
            let bundledURL = bundle.appendingPathComponent("Contents/Resources/\(relative)")
            let installedURL = root.appendingPathComponent(name)
            guard let bundled = try? Data(contentsOf: bundledURL),
                  let installed = try? Data(contentsOf: root.appendingPathComponent(name)),
                  SHA256.hash(data: bundled) == SHA256.hash(data: installed)
                    || sameSignedCode(bundledURL, installedURL, fingerprint: fingerprint) else { return false }
        }
        return FileManager.default.isExecutableFile(atPath: root.appendingPathComponent("PacketLoggerRuntime/Resources/packetlogger").path)
    }
    private static func sameSignedCode(_ bundled: URL, _ installed: URL, fingerprint: String?) -> Bool {
        guard let fingerprint, fingerprint.count == 40,
              fingerprint.allSatisfy({ "0123456789ABCDEF".contains($0) }) else { return false }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString("certificate leaf = H\"\(fingerprint)\"" as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return false }
        func identity(_ url: URL) -> (String, Data)? {
            var code: SecStaticCode?
            guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
                  SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures), requirement) == errSecSuccess else { return nil }
            var info: CFDictionary?
            guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
                  let values = info as? [String: Any],
                  let identifier = values[kSecCodeInfoIdentifier as String] as? String,
                  let digest = values[kSecCodeInfoUnique as String] as? Data else { return nil }
            return (identifier, digest)
        }
        // CMS signing timestamps differ on a rebuild even when the sealed
        // executable is identical. Compare validated CodeDirectories instead.
        guard let first = identity(bundled), let second = identity(installed) else { return false }
        return first.0 == second.0 && first.1 == second.1
    }
    static func isReady(defaults: UserDefaults = .standard, bundle: URL = Bundle.main.bundleURL) -> Bool {
        defaults.bool(forKey: VoiceHelperContract.consentKey)
            && payloadMatches(bundle: bundle, root: URL(fileURLWithPath: VoiceHelperContract.root))
    }
    func refresh() {
        installed = FileManager.default.isExecutableFile(atPath: root.appendingPathComponent(VoiceHelperContract.executable).path)
        ready = defaults.bool(forKey: VoiceHelperContract.consentKey) && Self.payloadMatches(bundle: bundle, root: root)
        guard !busy else { return }
        status = ready ? "后台授权已保存，按需启动采集" : installed ? "后台授权需要更新或重新确认" : "尚未保存后台授权"
    }
    func install() async {
        guard !busy else { return }
        busy = true; status = "等待系统管理员批准后台安装"
        let error = await runOperation("install-service", bundle)
        if error == nil { defaults.set(true, forKey: VoiceHelperContract.consentKey) }
        busy = false; refresh()
        if let error { status = error }
        else if !ready { status = "后台安装未通过文件核对，请重试" }
    }
    func remove() async {
        guard !busy else { return }
        busy = true; status = "等待系统管理员批准移除后台"
        let error = await runOperation("remove-service", bundle)
        if error == nil { defaults.removeObject(forKey: VoiceHelperContract.consentKey) }
        busy = false; refresh()
        if let error { status = error }
    }
    nonisolated static func authorizedOperation(_ operation: String, _ bundle: URL) async -> String? {
        guard ["install-service", "remove-service"].contains(operation) else { return "无效语音后台操作" }
        let helper = bundle.appendingPathComponent("Contents/Resources/AudioBackend/XvibeBackendHelper")
        let args = operation == "install-service" ? [helper.path, operation, bundle.path, String(getuid())] : [helper.path, operation]
        let command = args.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
        let literal = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return await Task.detached {
            var error: NSDictionary?
            guard let script = NSAppleScript(source: "do shell script \"\(literal)\" with administrator privileges") else { return "无法请求系统批准" }
            script.executeAndReturnError(&error)
            return error?[NSAppleScript.errorMessage] as? String
        }.value
    }
}
