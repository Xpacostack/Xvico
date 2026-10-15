import Foundation

enum BindingSource: String, Equatable {
    case scene = "应用场景", global = "全局映射", initial = "初始键位"
}

struct BindingResolution: Equatable {
    var binding: KeyBinding
    var source: BindingSource
    var holdSource: BindingSource
    var doubleSource: BindingSource
}

/// Editing, runtime output and the inspector share this resolver. Resolving a
/// mapping has no persistence, input, permission or UI side effects.
enum BindingResolver {
    static func resolve(_ key: RemoteKey, globals: [String: KeyBinding], scene: XvicoScene?) -> BindingResolution {
        let global = globals[key.rawValue] ?? key.referenceBinding
        let fallback: BindingSource = globals[key.rawValue] == nil ? .initial : .global
        guard var binding = scene?.bindings[key.rawValue] else {
            return .init(binding: global, source: fallback, holdSource: fallback, doubleSource: fallback)
        }
        var holdSource = BindingSource.scene
        var doubleSource = BindingSource.scene
        switch binding.longPressOverride {
        case .inherit:
            binding.longPressEnabled = global.longPressEnabled
            binding.longPressAction = global.longPressAction
            binding.longPressValue = global.longPressValue
            binding.longPressModifiers = global.longPressModifiers
            binding.longPressRightModifiers = global.longPressRightModifiers
            binding.holdNoOutput = global.holdNoOutput
            binding.siriMode = global.siriMode
            holdSource = fallback
        case .disabled: binding.longPressEnabled = false; binding.holdNoOutput = false
        case .custom: break
        }
        switch binding.doubleClickOverride {
        case .inherit:
            binding.doubleClickEnabled = global.doubleClickEnabled
            binding.doubleClickAction = global.doubleClickAction
            binding.doubleClickValue = global.doubleClickValue
            binding.doubleClickModifiers = global.doubleClickModifiers
            binding.doubleClickRightModifiers = global.doubleClickRightModifiers
            binding.powerDoubleClickAction = global.powerDoubleClickAction
            doubleSource = fallback
        case .disabled: binding.doubleClickEnabled = false
        case .custom: break
        }
        return .init(binding: binding, source: .scene, holdSource: holdSource, doubleSource: doubleSource)
    }
}

extension KeyBinding {
    /// Never include text contents in diagnostics. A label describes configured
    /// output, not confirmation that the receiving application acted on it.
    var diagnosticValue: String {
        switch action {
        case .key:
            let key = normalizedKeyboard
            return KeyboardModifier.allCases.filter { key.modifiers.contains($0) }.map(\.symbol).joined()
                + (KeyboardOutput.named(key.value)?.symbol ?? key.value)
        case .click: return mouseButton.rawValue
        case .openApp: return value
        case .text, .textAndReturn: return ""
        default: return ""
        }
    }
}
