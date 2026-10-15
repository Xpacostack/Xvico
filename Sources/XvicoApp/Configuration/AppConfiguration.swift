import Foundation

/// Portable behavior only. System consent, credentials, audio/runtime locations
/// and transient input state must never be read from an editable configuration.
struct AppConfiguration: Codable, Equatable {
    var format = "Xvico.Configuration"
    var schemaVersion = 1
    var settings: XvicoSettings
    var scenes: [XvicoScene]
    var shortcuts: [UserShortcut]
    var learnedUsages: [String: String]

    static let maximumBytes = 8 * 1024 * 1024

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        let object = try JSONSerialization.jsonObject(with: encoder.encode(self))
        let data = try JSONSerialization.data(withJSONObject: Self.canonical(object),
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        _ = try Self.decode(data)
        return data
    }

    private static func canonical(_ object: Any) -> Any {
        if let fields = object as? [String: Any] {
            let modifierKeys: Set<String> = ["modifiers", "rightModifiers", "longPressModifiers",
                "longPressRightModifiers", "doubleClickModifiers", "doubleClickRightModifiers"]
            var result: [String: Any] = [:]
            for (key, value) in fields {
                if modifierKeys.contains(key), let modifiers = value as? [String] { result[key] = modifiers.sorted() }
                else { result[key] = canonical(value) }
            }
            return result
        }
        if let elements = object as? [Any] { return elements.map(canonical) }
        return object
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumBytes else { throw ConfigurationFailure.invalid }
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  Set(object.keys).isSubset(of: ["format", "schemaVersion", "settings", "scenes", "shortcuts", "learnedUsages"]) else {
                throw ConfigurationFailure.invalid
            }
            let value = try JSONDecoder().decode(Self.self, from: data)
            guard value.format == "Xvico.Configuration", value.schemaVersion == 1 else {
                throw ConfigurationFailure.unsupported
            }
            guard Set(value.scenes.map(\.id)).count == value.scenes.count,
                  Set(value.shortcuts.map(\.id)).count == value.shortcuts.count,
                  value.scenes.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
                  value.scenes.count <= 2048, value.shortcuts.count <= 4096,
                  value.learnedUsages.values.allSatisfy({ RemoteKey(rawValue: $0) != nil }),
                  value.settings.globalBindings.keys.allSatisfy({ RemoteKey(rawValue: $0) != nil }),
                  value.scenes.allSatisfy({ $0.bindings.keys.allSatisfy { RemoteKey(rawValue: $0) != nil } }),
                  value.settings.showDockIcon || value.settings.showMenuBarIcon else {
                throw ConfigurationFailure.invalid
            }
            return value
        } catch let error as ConfigurationFailure { throw error }
        catch { throw ConfigurationFailure.invalid }
    }
}

enum ConfigurationFailure: Error, Equatable {
    case invalid, unsupported, conflict, missing, io
}

enum ConfigurationSyncState: Equatable {
    case synced, waitingForRelease, invalid, unsupported, conflict, missing, saveFailed

    var message: String {
        switch self {
        case .synced: "配置已同步"
        case .waitingForRelease: "新配置已读取，松开按键和触控后生效。"
        case .invalid: "配置文件无效，继续使用最近有效配置。修正文件后会自动重载。"
        case .unsupported: "配置版本不受支持，继续使用最近有效配置。"
        case .conflict: "文件与界面均有改动，尚未覆盖文件。请选择要使用的版本。"
        case .missing: "配置文件已移走，当前设置仍有效。可重新保存当前配置。"
        case .saveFailed: "配置未能保存，当前设置仍有效。请检查配置目录的写入权限。"
        }
    }

    init(_ failure: ConfigurationFailure) {
        switch failure {
        case .invalid: self = .invalid
        case .unsupported: self = .unsupported
        case .conflict: self = .conflict
        case .missing: self = .missing
        case .io: self = .saveFailed
        }
    }
}
