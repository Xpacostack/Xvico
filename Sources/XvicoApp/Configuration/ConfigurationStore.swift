import Foundation
import Darwin

/// All participating Xvico writers serialize on the same advisory lock. External
/// editors need not cooperate: compare their exact bytes immediately before an
/// atomic replace and refuse stale writes. This is optimistic conflict detection,
/// not a transaction guarantee for arbitrary non-cooperating writers.
final class ConfigurationStore {
    let directory: URL
    var fileURL: URL { directory.appendingPathComponent("config.json") }
    var lastGoodURL: URL { directory.appendingPathComponent("config.last-good.json") }
    var unsavedURL: URL { directory.appendingPathComponent("config.unsaved.json") }
    private(set) var accepted: AppConfiguration?
    private var acceptedBytes: Data?
    private let writeFile: (Data, URL) throws -> Void

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Xvico", isDirectory: true)
    }

    init(directory: URL, writeFile: @escaping (Data, URL) throws -> Void = ConfigurationStore.atomicWrite) {
        self.directory = directory
        self.writeFile = writeFile
    }

    func bootstrap(fallback: AppConfiguration, legacyArchive: [String: Any]) -> (AppConfiguration, ConfigurationFailure?) {
        do {
            return try locked {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    let bytes = try read(fileURL)
                    let value = try AppConfiguration.decode(bytes)
                    acceptedBytes = bytes; accepted = value
                    try writeFile(bytes, lastGoodURL)
                    return (value, nil)
                }
                // If the primary was removed, recover the known-good copy in
                // memory. Do not silently recreate or overwrite the user's file.
                if FileManager.default.fileExists(atPath: lastGoodURL.path) {
                    let value = try AppConfiguration.decode(read(lastGoodURL))
                    accepted = value
                    return (value, .missing)
                }
                let archiveURL = directory.appendingPathComponent("legacy-pre-migration.plist")
                if !FileManager.default.fileExists(atPath: archiveURL.path) {
                    let data = try PropertyListSerialization.data(fromPropertyList: legacyArchive, format: .binary, options: 0)
                    try writeFile(data, archiveURL)
                }
                let bytes = try fallback.encoded()
                try writeFile(bytes, fileURL)
                acceptedBytes = bytes; accepted = fallback
                try writeFile(bytes, lastGoodURL)
                return (fallback, nil)
            }
        } catch {
            let issue = (error as? ConfigurationFailure) ?? .io
            if let value = accepted { return (value, issue) }
            if let bytes = try? read(lastGoodURL), let value = try? AppConfiguration.decode(bytes) {
                accepted = value
                return (value, issue)
            }
            // A corrupt file with no backup is left intact. Legacy defaults are
            // used in memory until a user repairs or explicitly replaces it.
            let safeFallback = (try? fallback.encoded()) != nil ? fallback
                : AppConfiguration(settings: .init(), scenes: [], shortcuts: [], learnedUsages: [:])
            return (safeFallback, issue)
        }
    }

    func reload() throws -> AppConfiguration? {
        do {
            return try locked {
                let bytes = try read(fileURL)
                guard bytes != acceptedBytes else { return nil }
                let value = try AppConfiguration.decode(bytes)
                // Keep the previous accepted version if backing up the new
                // value fails. Nothing is partially applied to the runtime.
                try writeFile(bytes, lastGoodURL)
                acceptedBytes = bytes; accepted = value
                return value
            }
        } catch let error as ConfigurationFailure { throw error }
        catch { throw ConfigurationFailure.io }
    }

    func save(_ value: AppConfiguration, replacingExternal: Bool = false) throws {
        let bytes = try value.encoded()
        do {
            try locked {
                let disk = FileManager.default.fileExists(atPath: fileURL.path) ? try read(fileURL) : nil
                if !replacingExternal {
                    guard let acceptedBytes, let disk, disk == acceptedBytes else { throw ConfigurationFailure.conflict }
                } else if let disk, disk != bytes {
                    // Retain even invalid external content before an explicit
                    // replacement. It can be inspected/recovered locally.
                    try writeFile(disk, directory.appendingPathComponent("config.external-backup.json"))
                }
                if value == accepted, disk != nil, disk == acceptedBytes {
                    try writeFile(bytes, lastGoodURL)
                    if FileManager.default.fileExists(atPath: unsavedURL.path) {
                        try FileManager.default.removeItem(at: unsavedURL)
                    }
                    return
                }
                if disk != bytes { try writeFile(bytes, fileURL) }
                acceptedBytes = bytes; accepted = value
                try writeFile(bytes, lastGoodURL)
                if FileManager.default.fileExists(atPath: unsavedURL.path) {
                    try FileManager.default.removeItem(at: unsavedURL)
                }
            }
        } catch let error as ConfigurationFailure { throw error }
        catch { throw ConfigurationFailure.io }
    }

    @discardableResult
    func preserveUnsaved(_ value: AppConfiguration) -> Bool {
        do { try locked { try writeFile(value.encoded(), unsavedURL) }; return true }
        catch { return false }
    }

    func readUnsaved() throws -> AppConfiguration {
        try AppConfiguration.decode(read(unsavedURL))
    }

    private func read(_ url: URL) throws -> Data {
        guard FileManager.default.fileExists(atPath: url.path) else { throw ConfigurationFailure.missing }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= AppConfiguration.maximumBytes else {
            throw ConfigurationFailure.invalid
        }
        let bytes = try Data(contentsOf: url)
        guard bytes.count <= AppConfiguration.maximumBytes else { throw ConfigurationFailure.invalid }
        return bytes
    }

    private func locked<T>(_ operation: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let fd = open(directory.appendingPathComponent(".config.lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw ConfigurationFailure.io }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw ConfigurationFailure.io }
        defer { flock(fd, LOCK_UN) }
        return try operation()
    }

    /// mkstemp creates a private 0600 file before any content is written. fsync
    /// precedes rename, so readers see either the old complete file or the new.
    static func atomicWrite(_ data: Data, to url: URL) throws {
        var template = Array(url.deletingLastPathComponent().appendingPathComponent(".config.XXXXXX").path.utf8CString)
        let fd = mkstemp(&template)
        guard fd >= 0 else { throw ConfigurationFailure.io }
        let temporary = String(cString: template)
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close(); unlink(temporary) }
        try handle.write(contentsOf: data)
        try handle.synchronize()
        guard rename(temporary, url.path) == 0 else { throw ConfigurationFailure.io }
    }
}
