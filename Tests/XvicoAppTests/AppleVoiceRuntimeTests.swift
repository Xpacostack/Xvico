import XCTest
@testable import XvicoApp

final class AppleVoiceRuntimeTests: XCTestCase {
    private var temporary: URL!
    private var home: URL { temporary.appendingPathComponent("home") }
    private var app: URL { temporary.appendingPathComponent("Xvico.app") }
    private var source: URL { temporary.appendingPathComponent("PacketLogger.app/Contents") }
    override func setUpWithError() throws {
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: temporary) }
    private func fixture(_ root: URL) throws {
        let tool = root.appendingPathComponent("Resources/packetlogger")
        try FileManager.default.createDirectory(at: tool.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture only, never executed".utf8).write(to: tool)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tool.path)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Frameworks/PacketDecoder.framework"), withIntermediateDirectories: true)
    }
    func testResolutionPrefersBundledRuntimeAndFallsBackToImportedRuntime() throws {
        XCTAssertNil(VoiceRuntimeLocation.resolve(app: app, home: home))
        let imported = VoiceRuntimeLocation.imported(in: home)
        try fixture(imported)
        XCTAssertEqual(VoiceRuntimeLocation.resolve(app: app, home: home)?.path, imported.path)
        let bundled = app.appendingPathComponent("Contents/Resources/PacketLoggerRuntime")
        try fixture(bundled)
        XCTAssertEqual(VoiceRuntimeLocation.resolve(app: app, home: home)?.path, bundled.path)
    }
    func testImportLeavesAppBundleUntouchedAndCopiesOnlyKnownComponents() throws {
        try fixture(source)
        try Data("must not be imported".utf8).write(to: source.appendingPathComponent("extra"))
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let seal = app.appendingPathComponent("bundle-marker")
        try Data("unchanged app seal".utf8).write(to: seal)
        let store = AppleVoiceRuntimeStore(home: home, app: app, verify: { _ in })
        XCTAssertEqual(store.sourceRoot(source.deletingLastPathComponent()), source)
        try store.importRuntime(from: source.deletingLastPathComponent())
        XCTAssertTrue(store.available())
        XCTAssertEqual(try String(contentsOf: seal), "unchanged app seal")
        XCTAssertFalse(FileManager.default.fileExists(atPath: VoiceRuntimeLocation.imported(in: home).appendingPathComponent("extra").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/Resources/PacketLoggerRuntime").path))
    }
    func testUnsignedRuntimeIsRejectedByProductionSignatureValidator() throws {
        try fixture(source)
        let store = AppleVoiceRuntimeStore(home: home, app: app)
        XCTAssertThrowsError(try store.importRuntime(from: source))
        XCTAssertFalse(store.available())
        XCTAssertFalse(FileManager.default.fileExists(atPath: VoiceRuntimeLocation.imported(in: home).path))
    }
    func testStagedValidationFailurePreservesPreviousRuntime() throws {
        try fixture(source)
        let output = VoiceRuntimeLocation.imported(in: home)
        try fixture(output)
        try Data("old marker".utf8).write(to: output.appendingPathComponent("old-marker"))
        let store = AppleVoiceRuntimeStore(home: home, app: app, verify: { root in
            if root.lastPathComponent.hasPrefix(".runtime-stage-") { throw NSError(domain: "Test", code: 1) }
        })
        XCTAssertThrowsError(try store.importRuntime(from: source))
        XCTAssertEqual(try String(contentsOf: output.appendingPathComponent("old-marker")), "old marker")
    }
    func testEscapingFrameworkLinkIsRejectedAndStageRemoved() throws {
        try fixture(source)
        try FileManager.default.createSymbolicLink(atPath: source.appendingPathComponent("Frameworks/PacketDecoder.framework/escape").path,
                                                   withDestinationPath: temporary.path)
        let store = AppleVoiceRuntimeStore(home: home, app: app, verify: { _ in })
        XCTAssertThrowsError(try store.importRuntime(from: source))
        let parent = VoiceRuntimeLocation.imported(in: home).deletingLastPathComponent()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: parent.path), [])
    }
    func testLocallySuppliedAppleRuntimeImportsWithItsOriginalSignatures() throws {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let runtime = project.appendingPathComponent(".build/voice-runtime/PacketLoggerRuntime")
        guard VoiceRuntimeLocation.hasLayout(runtime) else { throw XCTSkip("No user-supplied Apple runtime in this environment") }
        let store = AppleVoiceRuntimeStore(home: home, app: app)
        try store.importRuntime(from: runtime)
        XCTAssertTrue(store.available())
        try AppleVoiceRuntimeStore.verifyAppleSignatures(VoiceRuntimeLocation.imported(in: home))
    }
}
