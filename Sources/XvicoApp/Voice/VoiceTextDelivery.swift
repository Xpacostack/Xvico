import AppKit
import ApplicationServices
import Carbon

struct VoiceFocusEvidence: Equatable {
    var pid: pid_t
    var elementIdentity: CFHashCode
    var contentHash: Int
    var selectionLocation: Int
    var selectionLength: Int
    var secure: Bool
    var editable: Bool
}

enum VoiceDeliveryResult: Equatable {
    case inserted, focusChanged, secureField, unavailable, writeFailed
    var message: String {
        switch self {
        case .inserted: return "文字已写入原输入框"
        case .focusChanged: return "输入位置已变化，文字保留在语音设置中。"
        case .secureField: return "安全输入状态下不写入语音文字。"
        case .unavailable: return "目标输入框不支持安全写入，文字保留在语音设置中。"
        case .writeFailed: return "未能确认文字写入，识别结果已保留，请检查输入框后复制。"
        }
    }
}

enum VoiceInsertionPolicy {
    static func validate(_ original: VoiceFocusEvidence, current: VoiceFocusEvidence?) -> VoiceDeliveryResult? {
        guard let current else { return .unavailable }
        guard !original.secure, !current.secure else { return .secureField }
        guard original.editable, current.editable else { return .unavailable }
        guard original == current else { return .focusChanged }
        return nil
    }
}

/// AX references are immutable and used only on this service's serial worker.
/// The target retains hashes/ranges, never a copy of the original editor text.
final class VoiceTextTarget: @unchecked Sendable {
    let evidence: VoiceFocusEvidence
    fileprivate let element: AXUIElement
    init(evidence: VoiceFocusEvidence, element: AXUIElement) { self.evidence = evidence; self.element = element }
}

@MainActor
protocol VoiceTextDelivering {
    func capture(expectedBundleID: String) async -> VoiceTextTarget?
    func insert(_ text: String, into target: VoiceTextTarget?) async -> VoiceDeliveryResult
}

@MainActor
final class VoiceTextDelivery: VoiceTextDelivering {
    private let queue = DispatchQueue(label: "work.xvico.voice-text", qos: .userInitiated)

    func capture(expectedBundleID: String) async -> VoiceTextTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == expectedBundleID, expectedBundleID != "work.xvibe.remote" else { return nil }
        let pid = app.processIdentifier
        return await withCheckedContinuation { continuation in
            queue.async {
                guard let state = Self.readFocus(pid: pid) else { continuation.resume(returning: nil); return }
                continuation.resume(returning: VoiceTextTarget(evidence: state.evidence, element: state.element))
            }
        }
    }

    func insert(_ text: String, into target: VoiceTextTarget?) async -> VoiceDeliveryResult {
        guard let target, !text.isEmpty else { return .unavailable }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.evidence.pid else { return .focusChanged }
        return await withCheckedContinuation { continuation in
            queue.async {
                // Resolve focus and apply the write on one ordered worker. AX
                // calls have a deadline and cannot block input/main-thread work.
                guard let current = Self.readFocus(pid: target.evidence.pid) else {
                    continuation.resume(returning: .unavailable); return
                }
                if let rejection = VoiceInsertionPolicy.validate(target.evidence, current: current.evidence) {
                    continuation.resume(returning: rejection); return
                }
                guard CFEqual(target.element, current.element),
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == target.evidence.pid,
                      !IsSecureEventInputEnabled() else {
                    continuation.resume(returning: .focusChanged); return
                }
                // Address the captured element directly. No app activation,
                // clipboard replacement or global keystroke fallback can put
                // the utterance into a newly focused editor.
                let status = AXUIElementSetAttributeValue(target.element, kAXSelectedTextAttribute as CFString, text as CFString)
                let value = Self.attribute(target.element, kAXValueAttribute) as? String
                let original = current.value as NSString
                let range = NSRange(location: current.evidence.selectionLocation, length: current.evidence.selectionLength)
                let expected = original.replacingCharacters(in: range, with: text)
                continuation.resume(returning: status == .success && value == expected ? .inserted : .writeFailed)
            }
        }
    }

    private struct FocusState {
        var element: AXUIElement
        var evidence: VoiceFocusEvidence
        var value: String
    }
    private nonisolated static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    private nonisolated static func readFocus(pid: pid_t) -> FocusState? {
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.05)
        guard let value = attribute(app, kAXFocusedUIElementAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeBitCast(value, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, 0.05)
        let role = attribute(element, kAXRoleAttribute) as? String
        let subrole = attribute(element, kAXSubroleAttribute) as? String
        guard subrole != kAXSecureTextFieldSubrole,
              [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role ?? "") else { return nil }
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue, let content = attribute(element, kAXValueAttribute) as? String,
              content.utf16.count <= 200_000,
              let selection = attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(selection) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(unsafeBitCast(selection, to: AXValue.self), .cfRange, &range),
              range.location >= 0, range.length >= 0, range.location <= content.utf16.count,
              range.length <= content.utf16.count - range.location else { return nil }
        return .init(element: element, evidence: .init(pid: pid, elementIdentity: CFHash(element),
            contentHash: content.hashValue, selectionLocation: range.location, selectionLength: range.length,
            secure: false, editable: true), value: content)
    }
}
