import XCTest
@testable import XvicoApp

@MainActor
final class BrandCompatibilityTests: XCTestCase {
    func testOldAndNewGlobalPresetsRestoreMappingsAndNewExportUsesXvico() throws {
        let domain = "XvicoBrandCompatibility.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let model = AppModel(defaults: defaults, observeSystem: false, eventPoster: { _ in })
        defer { model.stopControl() }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        var settings = XvicoSettings()
        settings.pointerSensitivity = 1.73
        settings.globalBindings[RemoteKey.center.rawValue] = .init(action: .click, value: "", mouseButton: .left)
        for format in ["Xvibe.GlobalPreset", "Xpavi.GlobalPreset", "Xvico.GlobalPreset"] {
            var preset = GlobalPreset(settings: settings)
            preset.format = format
            try JSONEncoder().encode(preset).write(to: file)
            try model.importGlobalPreset(from: file)
            XCTAssertEqual(model.settings, settings)
            XCTAssertEqual(model.runtimeBinding(for: .center).action, .click)
        }
        try model.exportGlobalPreset(to: file)
        let exported = try JSONDecoder().decode(GlobalPreset.self, from: Data(contentsOf: file))
        XCTAssertEqual(exported.format, "Xvico.GlobalPreset")
        XCTAssertEqual(exported.settings, settings)
        var invalid = exported
        invalid.format = "foreign.GlobalPreset"
        try JSONEncoder().encode(invalid).write(to: file)
        XCTAssertThrowsError(try model.importGlobalPreset(from: file))
        XCTAssertEqual(model.settings, settings)
    }

    func testStoredRecognitionModeSurvivesBrandChange() {
        XCTAssertEqual(VoiceRecognitionMode.restored(from: "Xvibe 本机识别"), .local)
        XCTAssertEqual(VoiceRecognitionMode.restored(from: "Xpavi 本机识别"), .local)
        XCTAssertEqual(VoiceRecognitionMode.restored(from: "Xvico 本机识别"), .local)
        XCTAssertEqual(VoiceRecognitionMode.restored(from: "输入法语音输入"), .inputMethod)
        XCTAssertEqual(VoiceRecognitionMode.restored(from: nil), .local)
    }

    func testNewShortcutCallbacksUseXvicoAndLegacyCallbacksRemainValid() async throws {
        for scheme in ["xvico", "xpavi", "xvibe"] {
            var opened: URL?
            let service = SystemShortcutsService(urlOpener: { opened = $0; return true })
            await service.run(.init(id: UUID(), name: "Existing shortcut"))
            let runURL = try XCTUnwrap(opened)
            let query = try XCTUnwrap(URLComponents(url: runURL, resolvingAgainstBaseURL: false)?.queryItems)
            let callback = try XCTUnwrap(query.first { $0.name == "x-success" }?.value)
            var components = try XCTUnwrap(URLComponents(string: callback))
            XCTAssertEqual(components.scheme, "xvico")
            components.scheme = scheme
            XCTAssertTrue(service.handleCallback(try XCTUnwrap(components.url)))
            XCTAssertNil(service.runningID)
            XCTAssertEqual(service.message, "已运行：Existing shortcut")
        }
    }
}
