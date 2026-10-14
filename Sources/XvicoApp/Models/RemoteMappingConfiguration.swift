import Foundation

/// The reset boundary is remote behavior, never appearance, launch settings,
/// system permissions, voice input preferences, or the saved scene contents.
struct RemoteMappingConfiguration: Codable, Equatable {
    var bindings: [String: KeyBinding]
    var volumeKeyMode: VolumeKeyMode
    var autoSwitchScenes: Bool
    var touchEnabled: Bool
    var ringEnabled: Bool
    var ringAction: RingAction
    var ringToggleKey: String
    var wheelStyle: WheelStyle

    init(_ settings: XvicoSettings) {
        bindings = settings.globalBindings
        volumeKeyMode = settings.volumeKeyMode
        autoSwitchScenes = settings.autoSwitchScenes
        touchEnabled = settings.touchEnabled
        ringEnabled = settings.ringEnabled
        ringAction = settings.ringAction
        ringToggleKey = settings.ringToggleKey
        wheelStyle = settings.wheelStyle
    }

    func applying(to settings: XvicoSettings) -> XvicoSettings {
        var result = settings
        result.globalBindings = bindings
        result.volumeKeyMode = volumeKeyMode
        result.autoSwitchScenes = autoSwitchScenes
        result.touchEnabled = touchEnabled
        result.ringEnabled = ringEnabled
        result.ringAction = ringAction
        result.ringToggleKey = ringToggleKey
        result.wheelStyle = wheelStyle
        return result
    }

    static var initial: RemoteMappingConfiguration { .init(XvicoSettings()) }
}

struct MappingRestoreSnapshot: Codable {
    var configuration: RemoteMappingConfiguration
    var sceneEnabled: [String: Bool]
    var selectedSceneID: UUID?
    var editingGlobalMapping: Bool
}
