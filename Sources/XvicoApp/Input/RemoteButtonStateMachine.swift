import Foundation

/// Button recognition only. The caller supplies monotonic time and executes
/// effects; this type never posts input, reads preferences, or starts tasks.
struct RemoteButtonStateMachine {
    static let holdDelay = 0.35
    static let doubleTapDelay = 0.20

    struct Context: Equatable {
        var application: String
        var scene: UUID?
        var ringToggleKey: String
        var volumeMode: VolumeKeyMode
        var volumeScrollStep: Double
    }

    struct TimerID: Hashable { fileprivate let value: UInt64 }

    enum Effect: Equatable {
        case keyboard(KeyBinding, down: Bool)
        case mouse(MouseClickButton, down: Bool, key: RemoteKey)
        case tap(KeyBinding, key: RemoteKey)
        case disabled(RemoteKey)
        case switchMicrophone(Int)
        case scroll(Int32)
        case cycleRing
        case schedule(TimerID, after: Double)
        case cancel(TimerID)
    }

    private enum Held {
        case keyboard(KeyBinding)
        case mouse(MouseClickButton)
    }
    private struct Press {
        var binding: KeyBinding
        var context: Context
        var held: Held?
        var holdTimer: TimerID?
        var holdDeadline: Double?
        var holdFired = false
    }
    private enum State {
        case mapped(Press)
        // Disabled keys, special volume modes and a ring-toggle second press
        // still own a physical down/up pair, even though no output is held.
        case suppressed
    }
    private struct PendingTap {
        var binding: KeyBinding
        var context: Context
        var timer: TimerID
        var deadline: Double
    }
    private struct RingTap {
        var key: RemoteKey
        var binding: KeyBinding
        var context: Context
        var time: Double
    }
    private var states: [RemoteKey: State] = [:]
    private var pending: [RemoteKey: PendingTap] = [:]
    private var ringTap: RingTap?
    private var nextTimer: UInt64 = 0

    var isHolding: Bool { !states.isEmpty }
    var hasPendingTap: Bool { !pending.isEmpty }
    var heldMouseButtons: [MouseClickButton] {
        RemoteKey.allCases.compactMap { key in
            guard case .mapped(let press) = states[key], case .mouse(let button) = press.held else { return nil }
            return button
        }
    }

    mutating func press(_ key: RemoteKey, binding: KeyBinding, context: Context, now: Double) -> [Effect] {
        guard states[key] == nil else { return [] }
        var effects: [Effect] = []
        // A different app, scene or edited binding starts a separate gesture.
        // Finish the old single instead of turning two unrelated taps into a double.
        if let tap = pending[key], tap.deadline <= now || tap.binding != binding || tap.context != context {
            effects += finishTap(key)
        }
        if let previous = ringTap, previous.key == key, key.rawValue == context.ringToggleKey,
           previous.binding == binding, previous.context == context,
           now >= previous.time, now - previous.time <= Self.doubleTapDelay {
            ringTap = nil
            states[key] = .suppressed
            return effects + [.cycleRing]
        }
        if key == .volumeUp || key == .volumeDown, context.volumeMode != .key {
            states[key] = .suppressed
            if context.volumeMode == .microphone {
                return effects + [.switchMicrophone(key == .volumeUp ? -1 : 1)]
            }
            return effects + [.scroll(Int32(context.volumeScrollStep) * (key == .volumeUp ? 1 : -1))]
        }
        guard binding.enabled else {
            states[key] = .suppressed
            return effects + [.disabled(key)]
        }
        var press = Press(binding: binding, context: context)
        let doubleTap = supportsDouble(key, binding)
        if binding.action == .click && !doubleTap {
            press.held = .mouse(binding.mouseButton)
            effects.append(.mouse(binding.mouseButton, down: true, key: key))
        } else if binding.action == .key && ((key == .voice && binding.siriMode == "长按模式") || (!binding.longPressEnabled && !doubleTap)) {
            press.held = .keyboard(binding)
            effects.append(.keyboard(binding, down: true))
        } else if binding.longPressEnabled && binding.action == .key {
            let timer = makeTimer()
            press.holdTimer = timer
            press.holdDeadline = now + Self.holdDelay
            effects.append(.schedule(timer, after: Self.holdDelay))
        }
        states[key] = .mapped(press)
        return effects
    }

    mutating func release(_ key: RemoteKey, now: Double) -> [Effect] {
        var effects: [Effect] = []
        // If the main actor was busy at the deadline, recognize elapsed hold
        // time before releasing instead of misclassifying it as a short tap.
        if case .mapped(let press) = states[key], let timer = press.holdTimer,
           let deadline = press.holdDeadline, now >= deadline {
            effects.append(.cancel(timer))
            effects += timerFired(timer, now: now)
        }
        guard let state = states.removeValue(forKey: key), case .mapped(let press) = state else { return [] }
        if key.rawValue == press.context.ringToggleKey {
            ringTap = RingTap(key: key, binding: press.binding, context: press.context, time: now)
        }
        if let timer = press.holdTimer { effects.append(.cancel(timer)) }
        if let held = press.held { return effects + releaseEffect(held, key: key) }
        if press.holdFired { return effects }
        if supportsDouble(key, press.binding) {
            if let previous = pending[key], previous.deadline >= now,
               previous.binding == press.binding, previous.context == press.context {
                pending.removeValue(forKey: key)
                effects.append(.cancel(previous.timer))
                effects.append(.tap(doubleBinding(key, press.binding), key: key))
            } else {
                effects += finishTap(key)
                let timer = makeTimer()
                pending[key] = PendingTap(binding: press.binding, context: press.context,
                                          timer: timer, deadline: now + Self.doubleTapDelay)
                effects.append(.schedule(timer, after: Self.doubleTapDelay))
            }
        } else { effects.append(.tap(press.binding, key: key)) }
        return effects
    }

    mutating func timerFired(_ timer: TimerID, now: Double) -> [Effect] {
        for key in RemoteKey.allCases {
            if case .mapped(var press) = states[key], press.holdTimer == timer, let deadline = press.holdDeadline {
                guard now >= deadline else { return [.schedule(timer, after: deadline - now)] }
                press.holdTimer = nil
                press.holdDeadline = nil
                press.holdFired = true
                var effects: [Effect] = []
                if !press.binding.holdNoOutput {
                    var held = KeyBinding(action: .key, value: press.binding.longPressValue.isEmpty ? "F1" : press.binding.longPressValue,
                                          modifiers: press.binding.longPressModifiers)
                    held.rightModifiers = press.binding.longPressRightModifiers
                    press.held = .keyboard(held)
                    effects.append(.keyboard(held, down: true))
                }
                states[key] = .mapped(press)
                return effects
            }
            if let tap = pending[key], tap.timer == timer {
                guard now >= tap.deadline else { return [.schedule(timer, after: tap.deadline - now)] }
                pending.removeValue(forKey: key)
                return [.tap(tap.binding, key: key)]
            }
        }
        // A cancelled callback can arrive after a new press or reset. Its ID
        // must never be reused for the new gesture.
        return []
    }

    mutating func reset() -> [Effect] {
        var effects: [Effect] = []
        for key in RemoteKey.allCases {
            if case .mapped(let press) = states[key] {
                if let timer = press.holdTimer { effects.append(.cancel(timer)) }
                if let held = press.held { effects += releaseEffect(held, key: key) }
            }
            if let tap = pending[key] { effects.append(.cancel(tap.timer)) }
        }
        states.removeAll()
        pending.removeAll()
        ringTap = nil
        return effects
    }

    private mutating func finishTap(_ key: RemoteKey) -> [Effect] {
        guard let tap = pending.removeValue(forKey: key) else { return [] }
        return [.cancel(tap.timer), .tap(tap.binding, key: key)]
    }

    private mutating func makeTimer() -> TimerID {
        nextTimer += 1
        return TimerID(value: nextTimer)
    }

    private func releaseEffect(_ held: Held, key: RemoteKey) -> [Effect] {
        switch held {
        case .keyboard(let binding): return [.keyboard(binding, down: false)]
        case .mouse(let button): return [.mouse(button, down: false, key: key)]
        }
    }

    private func supportsDouble(_ key: RemoteKey, _ binding: KeyBinding) -> Bool {
        binding.doubleClickEnabled && (key == .power || (key == .voice && binding.action == .key && binding.siriMode == "分段模式"))
    }

    private func doubleBinding(_ key: RemoteKey, _ binding: KeyBinding) -> KeyBinding {
        if key == .power {
            let action: XvicoAction = binding.powerDoubleClickAction == .lockScreen ? .lockScreen
                : binding.powerDoubleClickAction == .systemSleep ? .systemSleep : .screenOff
            return KeyBinding(action: action, value: "")
        }
        var result = KeyBinding(action: .key, value: binding.doubleClickValue.isEmpty ? "Return" : binding.doubleClickValue,
                                modifiers: binding.doubleClickModifiers)
        result.rightModifiers = binding.doubleClickRightModifiers
        return result
    }
}
