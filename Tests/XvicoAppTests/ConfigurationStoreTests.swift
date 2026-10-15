import XCTest
@testable import XvicoApp

final class ConfigurationStoreTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("XvicoConfig.\(UUID())")
    }
    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
    private var initial: AppConfiguration {
        .init(settings: .init(), scenes: [], shortcuts: [], learnedUsages: [:])
    }
    private func bootstrap() throws -> ConfigurationStore {
        let store = ConfigurationStore(directory: directory)
        let (value, failure) = store.bootstrap(fallback: initial, legacyArchive: ["original": Data([1, 2, 3])])
        XCTAssertNil(failure); XCTAssertEqual(value, initial)
        return store
    }

    func testMigrationKeepsOriginalArchiveAndEmptySceneCollection() throws {
        let store = try bootstrap()
        XCTAssertEqual(try AppConfiguration.decode(Data(contentsOf: store.fileURL)), initial)
        let archive = try PropertyListSerialization.propertyList(from: Data(contentsOf: directory.appendingPathComponent("legacy-pre-migration.plist")), format: nil) as? [String: Data]
        XCTAssertEqual(archive?["original"], Data([1, 2, 3]))
        let next = ConfigurationStore(directory: directory)
        let (loaded, issue) = next.bootstrap(fallback: .init(settings: .init(), scenes: [.coding(name: "Unused", bundleID: "unused", color: "blue")], shortcuts: [], learnedUsages: [:]), legacyArchive: [:])
        XCTAssertNil(issue); XCTAssertTrue(loaded.scenes.isEmpty)
    }

    func testInvalidEditRetainsLastGoodAndValidRepairReloads() throws {
        let store = try bootstrap()
        let good = try Data(contentsOf: store.lastGoodURL)
        let invalid = Data("{\"settings\":".utf8)
        try invalid.write(to: store.fileURL, options: .atomic)
        XCTAssertThrowsError(try store.reload()) { XCTAssertEqual($0 as? ConfigurationFailure, .invalid) }
        XCTAssertEqual(store.accepted, initial)
        XCTAssertEqual(try Data(contentsOf: store.fileURL), invalid)
        XCTAssertEqual(try Data(contentsOf: store.lastGoodURL), good)
        var repaired = initial; repaired.settings.dragAcceleration = 2
        try repaired.encoded().write(to: store.fileURL, options: .atomic)
        XCTAssertEqual(try store.reload(), repaired)
        XCTAssertNil(try store.reload())
    }

    func testCorruptRestartUsesBackupWithoutOverwritingBadFile() throws {
        let store = try bootstrap()
        let bad = Data("not json".utf8)
        try bad.write(to: store.fileURL)
        let restarted = ConfigurationStore(directory: directory)
        let (value, issue) = restarted.bootstrap(fallback: initial, legacyArchive: [:])
        XCTAssertEqual(value, initial); XCTAssertEqual(issue, .invalid)
        XCTAssertEqual(try Data(contentsOf: restarted.fileURL), bad)
    }

    func testUnsupportedVersionAndDuplicateIDsAreRejected() throws {
        var value = initial; value.schemaVersion = 99
        let raw = try JSONEncoder().encode(value)
        XCTAssertThrowsError(try AppConfiguration.decode(raw)) { XCTAssertEqual($0 as? ConfigurationFailure, .unsupported) }
        value = initial
        let scene = XvicoScene.coding(name: "Duplicate", bundleID: "test", color: "blue")
        value.scenes = [scene, scene]
        XCTAssertThrowsError(try value.encoded())
        value = initial; value.settings.dragAcceleration = .infinity
        XCTAssertThrowsError(try value.encoded())
    }

    func testStaleWriterCannotOverwriteExternalEditAndExplicitSaveArchivesIt() throws {
        let first = try bootstrap()
        let second = ConfigurationStore(directory: directory)
        _ = second.bootstrap(fallback: initial, legacyArchive: [:])
        var external = initial; external.settings.pointerSensitivity = 2
        try first.save(external)
        let externalBytes = try Data(contentsOf: first.fileURL)
        var local = initial; local.settings.dragAcceleration = 2.2
        XCTAssertThrowsError(try second.save(local)) { XCTAssertEqual($0 as? ConfigurationFailure, .conflict) }
        XCTAssertEqual(try Data(contentsOf: first.fileURL), externalBytes)
        XCTAssertTrue(second.preserveUnsaved(local))
        XCTAssertEqual(try AppConfiguration.decode(Data(contentsOf: second.unsavedURL)), local)
        try second.save(local, replacingExternal: true)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("config.external-backup.json")), externalBytes)
        XCTAssertEqual(try AppConfiguration.decode(Data(contentsOf: first.fileURL)), local)
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.unsavedURL.path))
    }

    func testWriteFailureLeavesPrimaryCompleteAndRetryWorks() throws {
        let original = try bootstrap()
        let bytes = try Data(contentsOf: original.fileURL)
        var failWrites = false
        let failing = ConfigurationStore(directory: directory) { data, url in
            if failWrites && url.lastPathComponent == "config.json" { throw ConfigurationFailure.io }
            try ConfigurationStore.atomicWrite(data, to: url)
        }
        _ = failing.bootstrap(fallback: initial, legacyArchive: [:])
        failWrites = true
        var next = initial; next.settings.pointerSensitivity = 1.9
        XCTAssertThrowsError(try failing.save(next))
        XCTAssertEqual(try Data(contentsOf: original.fileURL), bytes)
        XCTAssertEqual(failing.accepted, initial)
        failWrites = false
        try failing.save(next)
        XCTAssertEqual(try AppConfiguration.decode(Data(contentsOf: original.fileURL)), next)
    }

    func testMissingPrimaryDoesNotRecreateDefaultsDuringReloadOrRestart() throws {
        let store = try bootstrap()
        try FileManager.default.removeItem(at: store.fileURL)
        XCTAssertThrowsError(try store.reload()) { XCTAssertEqual($0 as? ConfigurationFailure, .missing) }
        let other = ConfigurationStore(directory: directory)
        let (value, issue) = other.bootstrap(fallback: initial, legacyArchive: [:])
        XCTAssertEqual(value, initial); XCTAssertEqual(issue, .missing)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
        try other.save(value, replacingExternal: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    func testAtomicFilesArePrivateAndLeaveNoTemporaryFiles() throws {
        let store = try bootstrap()
        var next = initial; next.settings.dragAcceleration = 2
        try store.save(next)
        for file in [store.fileURL, store.lastGoodURL] {
            let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
            XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertFalse(names.contains { $0.hasPrefix(".config.") && $0 != ".config.lock" })
    }

    func testOversizedFileIsRejectedWithoutReplacement() throws {
        let store = try bootstrap()
        let handle = try FileHandle(forWritingTo: store.fileURL)
        try handle.truncate(atOffset: UInt64(AppConfiguration.maximumBytes + 1))
        try handle.close()
        XCTAssertThrowsError(try store.reload()) { XCTAssertEqual($0 as? ConfigurationFailure, .invalid) }
        XCTAssertThrowsError(try store.save(initial, replacingExternal: true))
        let size = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.size] as? NSNumber
        XCTAssertEqual(size?.intValue, AppConfiguration.maximumBytes + 1)
    }

    func testCanonicalEncodingSortsModifierSetsAndRejectsConsentFields() throws {
        var value = initial
        value.settings.globalBindings[RemoteKey.menu.rawValue] = .init(action: .key, value: "A", modifiers: [.shift, .command, .control])
        let encoded = try value.encoded()
        for _ in 0..<10 { XCTAssertEqual(try AppConfiguration.decode(encoded).encoded(), encoded) }
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["serviceConsent"] = true
        XCTAssertThrowsError(try AppConfiguration.decode(JSONSerialization.data(withJSONObject: object)))
    }

    func testInvalidLegacySnapshotNeverEntersRuntimeAndRawArchiveSurvives() throws {
        let store = ConfigurationStore(directory: directory)
        var bad = initial
        let scene = XvicoScene.coding(name: "Duplicate", bundleID: "test", color: "blue")
        bad.scenes = [scene, scene]
        let (loaded, issue) = store.bootstrap(fallback: bad, legacyArchive: ["raw": "retain me"])
        XCTAssertEqual(issue, .invalid)
        XCTAssertTrue(loaded.scenes.isEmpty)
        XCTAssertNoThrow(try loaded.encoded())
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("legacy-pre-migration.plist").path))
    }
}
