import XCTest
@testable import XvicoApp

@MainActor
final class VoiceBackendAuthorizationTests: XCTestCase {
    private var domain = ""
    private var defaults: UserDefaults!
    private var temp: URL!
    private var bundle: URL { temp.appendingPathComponent("Xvico.app") }
    private var root: URL { temp.appendingPathComponent("installed") }
    private var operations: [String] = []

    override func setUp() async throws {
        domain = "XvicoVoiceAuthorization.\(UUID())"
        defaults = UserDefaults(suiteName: domain)!
        temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        for (relative, name) in [
            ("AudioBackend/XvicoVoiceDaemon", "XvicoVoiceDaemon"),
            ("AudioBackend/XvibeBackendRunner", "XvibeBackendRunner"),
            ("AudioBackend/XvibeAudioRouter", "XvibeAudioRouter"),
            ("AudioBackend/libopus.0.dylib", "libopus.0.dylib"),
            ("VoiceTools/XvibeVoiceCapture", "XvibeVoiceCapture")
        ] {
            try write(name, to: bundle.appendingPathComponent("Contents/Resources/\(relative)"))
            try write(name, to: root.appendingPathComponent(name))
        }
        try write("fixture, never executed", to: root.appendingPathComponent("PacketLoggerRuntime/Resources/packetlogger"))
    }
    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: domain)
        try FileManager.default.removeItem(at: temp)
        defaults = nil; temp = nil; operations = []
    }
    private func write(_ value: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(value.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }
    private func manager(error: String? = nil) -> VoiceBackendAuthorization {
        VoiceBackendAuthorization(defaults: defaults, bundle: bundle, root: root,
            runOperation: { operation, _ in self.operations.append(operation); return error })
    }
    func testNoConsentIsInferredFromPayloadAndOpeningOrCheckingNeverInstallsOrRecords() {
        let authorization = manager()
        XCTAssertTrue(authorization.installed)
        XCTAssertFalse(authorization.ready)
        authorization.refresh()
        XCTAssertTrue(operations.isEmpty)
        XCTAssertFalse(defaults.bool(forKey: VoiceHelperContract.consentKey))
    }
    func testOneApprovedInstallationPersistsAcrossNewInstancesWithoutAnyOperation() async {
        let authorization = manager()
        await authorization.install()
        XCTAssertTrue(authorization.ready)
        XCTAssertEqual(operations, ["install-service"])
        operations = []
        let relaunched = manager()
        relaunched.refresh()
        XCTAssertTrue(relaunched.ready)
        XCTAssertTrue(operations.isEmpty, "A relaunch must neither request admin rights nor start capture")
    }
    func testCancelledApprovalDoesNotRememberConsent() async {
        let authorization = manager(error: "User cancelled")
        await authorization.install()
        XCTAssertFalse(authorization.ready)
        XCTAssertFalse(defaults.bool(forKey: VoiceHelperContract.consentKey))
        XCTAssertEqual(authorization.status, "User cancelled")
    }
    func testChangedPayloadRequiresExplicitUpdateInsteadOfClaimingAuthorizationIsReady() async throws {
        let authorization = manager()
        await authorization.install()
        try write("new runner", to: bundle.appendingPathComponent("Contents/Resources/AudioBackend/XvibeBackendRunner"))
        authorization.refresh()
        XCTAssertFalse(authorization.ready)
        XCTAssertTrue(authorization.installed)
        XCTAssertEqual(operations, ["install-service"])
    }
    func testSuccessfulRemovalClearsConsentAndFailedRemovalPreservesIt() async {
        let authorization = manager()
        await authorization.install()
        let failed = manager(error: "User cancelled")
        await failed.remove()
        XCTAssertTrue(defaults.bool(forKey: VoiceHelperContract.consentKey))
        await authorization.remove()
        XCTAssertFalse(defaults.bool(forKey: VoiceHelperContract.consentKey))
        XCTAssertFalse(authorization.ready)
        XCTAssertEqual(operations, ["install-service", "remove-service", "remove-service"])
    }
    func testStrictSessionIdentifierAndSigningRequirementRejectUntrustedInput() {
        XCTAssertTrue(VoiceHelperContract.validSessionID(UUID().uuidString))
        for invalid in ["../session", "", "$(id)", UUID().uuidString.lowercased(), "/tmp/session"] {
            XCTAssertFalse(VoiceHelperContract.validSessionID(invalid))
        }
        let fingerprint = String(repeating: "A", count: 40)
        XCTAssertNotNil(VoiceHelperContract.requirement(identifier: VoiceHelperContract.label, fingerprint: fingerprint))
        XCTAssertNil(VoiceHelperContract.requirement(identifier: "arbitrary.client", fingerprint: fingerprint))
        XCTAssertNil(VoiceHelperContract.requirement(identifier: VoiceHelperContract.label, fingerprint: "\" or true"))
    }

    func testEquivalentResignedInstalledPayloadRemainsApprovedButTamperingDoesNot() throws {
        // Optional local acceptance against signed artifacts; never launches
        // them, installs a helper, or touches the real preference domain.
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let app = project.appendingPathComponent("dist/Xvico.app")
        let installedRoot = URL(fileURLWithPath: VoiceHelperContract.root)
        guard let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              let fingerprint = info["XvicoVoiceServiceSigningIdentity"] as? String,
              FileManager.default.fileExists(atPath: installedRoot.appendingPathComponent(VoiceHelperContract.executable).path) else {
            throw XCTSkip("Requires a previously approved local helper and a signed local build")
        }
        var differs = false
        func codeHash(_ url: URL) throws -> String? {
            let process = Process(); let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            process.arguments = ["-d", "--verbose=4", url.path]
            process.standardOutput = FileHandle.nullDevice; process.standardError = pipe
            try process.run()
            let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            return text.split(separator: "\n").first { $0.hasPrefix("CDHash=") }.map(String.init)
        }
        for (relative, name) in [
            ("AudioBackend/XvicoVoiceDaemon", "XvicoVoiceDaemon"),
            ("AudioBackend/XvibeBackendRunner", "XvibeBackendRunner"),
            ("AudioBackend/XvibeAudioRouter", "XvibeAudioRouter"),
            ("AudioBackend/libopus.0.dylib", "libopus.0.dylib"),
            ("VoiceTools/XvibeVoiceCapture", "XvibeVoiceCapture")
        ] {
            let bundledURL = app.appendingPathComponent("Contents/Resources/\(relative)")
            let installedURL = installedRoot.appendingPathComponent(name)
            guard let first = try codeHash(bundledURL), let second = try codeHash(installedURL), first == second else {
                throw XCTSkip("The locally installed helper is a different code version")
            }
            let bundled = try Data(contentsOf: bundledURL)
            let installed = try Data(contentsOf: installedURL)
            differs = differs || bundled != installed
            try bundled.write(to: bundle.appendingPathComponent("Contents/Resources/\(relative)"))
            try installed.write(to: root.appendingPathComponent(name))
        }
        guard differs else { throw XCTSkip("No signature-only differences available in current local artifacts") }
        try PropertyListSerialization.data(fromPropertyList: ["XvicoVoiceServiceSigningIdentity": fingerprint], format: .xml, options: 0)
            .write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        defaults.set(true, forKey: VoiceHelperContract.consentKey)
        let authorization = manager()
        XCTAssertTrue(authorization.ready, "Valid signatures and equal CodeDirectories must survive CMS timestamp changes")
        XCTAssertTrue(operations.isEmpty)
        let file = root.appendingPathComponent("XvibeBackendRunner")
        var damaged = try Data(contentsOf: file)
        damaged[32] ^= 1
        try damaged.write(to: file)
        authorization.refresh()
        XCTAssertFalse(authorization.ready, "Modified executable code must fail strict signature validation")
    }
}
