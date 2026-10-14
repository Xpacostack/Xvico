import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var page: XvicoPage = .mapping
    @Published var scenes: [XvicoScene] = [] { didSet { persist() } }
    @Published var selectedSceneID: UUID? { didSet { persist() } }
    @Published var selectedKey: RemoteKey?
    @Published var editingGlobalMapping = true
    @Published private(set) var manuallyActiveSceneID: UUID?
    @Published private var mappingRestoreSnapshot: MappingRestoreSnapshot?
    var canUndoMappingRestore: Bool { mappingRestoreSnapshot != nil }
    @Published var touchStatus = "等待遥控器触控接口"
    @Published var powerIntercepted = false
    let inputDiagnostics = RemoteInputDiagnostics()
    let mappingInteraction = PassthroughSubject<Void, Never>()
    @Published var powerInterceptionDetail: String?
    @Published var shortcuts: [UserShortcut] = [] { didSet { persist() } }
    @Published var settings = XvicoSettings() { didSet {
        persist()
        if !restoring && oldValue.interceptRemoteButtons != settings.interceptRemoteButtons {
            inputMonitor.setButtonInterception(settings.interceptRemoteButtons)
        }
    } }
    @Published var currentApp = "Finder"
    @Published var currentBundleID = "com.apple.finder"
    @Published var remoteStatus = "尚未连接"
    @Published var toast: String?
    @Published var running = true
    var lastAction: String {
        get { inputDiagnostics.lastAction }
        set { inputDiagnostics.recordAction(newValue) }
    }
    @Published var isLearning = false
    @Published var learnedUsages: [String: String] = [:]
    @Published var siriPressBehavior = "分段模式"
    @Published var siriLongBehavior = "语音识别"
    @Published var siriDoubleEnabled = true
    @Published var siriDoubleBinding = KeyBinding(action: .key, value: "↩")

    private let defaults: UserDefaults
    private let accessibilityCheck: () -> Bool
    private let eventPoster: (CGEvent) -> Void
    private let scrollEventSource = CGEventSource(stateID: .combinedSessionState)
    private let keyboardEventSource = CGEventSource(stateID: .combinedSessionState)
    private let realKeyboardTiming: Bool
    private var keyboardDownTimes: [UInt16: Double] = [:]
    private let microphoneSwitcher: (Int) throws -> String
    private var restoring = true
    private var sceneObserver: NSObjectProtocol?
    let remoteVoice = RemoteVoiceService()
    private let inputMonitor = RemoteInputMonitor()
    private var pressTasks: [RemoteKey: Task<Void, Never>] = [:]
    private var singleTapTasks: [RemoteKey: Task<Void, Never>] = [:]
    private var lastTap: [RemoteKey: Date] = [:]
    private var pressedBindings: [RemoteKey: KeyBinding] = [:]
    private var heldBindings: [RemoteKey: KeyBinding] = [:]
    private var heldMouseBindings: [RemoteKey: MouseClickButton] = [:]
    var siriVoiceHandler: ((Bool) -> Bool)?
    var mappedKeyboardHandler: ((KeyBinding, Bool) -> Void)?
    var controlStopped: (() -> Void)?
    private var siriVoiceConsumed = false
    var isHoldingRemoteButton: Bool { !pressedBindings.isEmpty || siriVoiceConsumed || !ringToggleSuppressed.isEmpty }
    private var centerMouseSequence = MouseClickSequence()
    private var mouseClickCounts: [MouseClickButton: Int64] = [:]
    private let mouseClickTime: () -> Double
    private var holdDidFire = Set<RemoteKey>()
    private var ringToggleLastTap: Date?
    private var ringToggleSuppressed = Set<RemoteKey>()
    private var gestureProcessor = RemoteGestureProcessor()
    private var pointerTarget: CGPoint?
    private var touchSamplesReceived = 0
    private var lastTouchCountUpdate = 0.0
    private var lastTouchWasActive = false
    private var appSwitcherHeld = false
    private var codexTaskNumber = 1
    private var screenSleeping = CGDisplayIsAsleep(CGMainDisplayID()) != 0
    private var displayObservers: [NSObjectProtocol] = []

    init(defaults: UserDefaults = .standard, observeSystem: Bool = true,
         accessibilityCheck: @escaping () -> Bool = AXIsProcessTrusted,
         eventPoster: @escaping (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) },
         microphoneSwitcher: @escaping (Int) throws -> String = MacMicrophones.switchInput,
         mouseClickTime: @escaping () -> Double = { Date.timeIntervalSinceReferenceDate }) {
        self.defaults = defaults
        self.accessibilityCheck = accessibilityCheck
        self.eventPoster = eventPoster
        self.realKeyboardTiming = observeSystem
        self.microphoneSwitcher = microphoneSwitcher
        self.mouseClickTime = mouseClickTime
        restore()
        migrateLegacyMappingDefaults()
        restoring = false
        persist()
        for name in observeSystem ? [NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification] : [] {
            displayObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let sleeping = note.name == NSWorkspace.screensDidSleepNotification
                Task { @MainActor [weak self] in self?.screenSleeping = sleeping }
            })
        }
        inputMonitor.onStatus = { [weak self] in self?.remoteStatus = $0 }
        inputMonitor.onDiagnostic = { [weak self] message in
            self?.inputDiagnostics.buttonCount += 1
            self?.inputDiagnostics.lastButton = message
        }
        inputMonitor.onUsage = { [weak self] page, usage, pressed in
            self?.handleHIDUsage(page: page, usage: usage, pressed: pressed)
        }
        inputMonitor.onTouch = { [weak self] sample in
            guard let self else { return }
            self.touchSamplesReceived += 1
            let now = ProcessInfo.processInfo.systemUptime
            // Keep the settings counter from redrawing the entire SwiftUI
            // window on every hardware frame. Input processing stays immediate.
            if (self.lastTouchWasActive && !sample.touching) || now - self.lastTouchCountUpdate >= 0.25 {
                self.inputDiagnostics.touchCount = self.touchSamplesReceived
                self.lastTouchCountUpdate = now
            }
            self.lastTouchWasActive = sample.touching
            self.handleTouch(sample)
        }
        inputMonitor.onTouchStatus = { [weak self] status in self?.touchStatus = status }
        inputMonitor.onInterception = { [weak self] intercepted in self?.powerIntercepted = intercepted }
        inputMonitor.onInterceptionDetail = { [weak self] in self?.powerInterceptionDetail = $0 }
        if observeSystem { sceneObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            guard app.bundleIdentifier != "work.xvibe.remote" else { return }
            let name = app.localizedName ?? "未知应用"
            let bundleID = app.bundleIdentifier ?? ""
            Task { @MainActor [weak self] in
                self?.manuallyActiveSceneID = nil
                self?.currentApp = name
                self?.currentBundleID = bundleID
            }
        } }
        if observeSystem, let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != "work.xvibe.remote" {
            currentApp = frontmost.localizedName ?? "未知应用"
            currentBundleID = frontmost.bundleIdentifier ?? ""
        }
    }

    deinit {
        if let sceneObserver { NSWorkspace.shared.notificationCenter.removeObserver(sceneObserver) }
        for observer in displayObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    var selectedScene: XvicoScene? {
        get { scenes.first { $0.id == selectedSceneID } }
        set {
            guard let newValue, let index = scenes.firstIndex(where: { $0.id == newValue.id }) else { return }
            scenes[index] = newValue
        }
    }

    var activeScene: XvicoScene? {
        if let id = manuallyActiveSceneID, let scene = scenes.first(where: { $0.id == id && $0.enabled }) { return scene }
        guard settings.autoSwitchScenes else { return nil }
        return scenes.first { $0.enabled && !$0.bundleID.isEmpty && $0.bundleID == currentBundleID }
    }

    func binding(for key: RemoteKey, in scene: XvicoScene? = nil) -> KeyBinding {
        if let scene { return resolvedBinding(for: key, scene: scene) }
        if editingGlobalMapping { return settings.globalBindings[key.rawValue] ?? key.referenceBinding }
        return resolvedBinding(for: key, scene: selectedScene)
    }

    var mappingScopeName: String { editingGlobalMapping ? "默认映射" : selectedScene?.name ?? "默认映射" }
    var controlStatusLabel: String { running ? "控制已启用" : "控制已停止" }
    var remoteConnected: Bool { remoteStatus.hasPrefix("已发现") || remoteStatus.contains("已连接") }
    var remoteConnectionLabel: String {
        if !running { return "控制已停止" }
        if remoteConnected { return "控制已启用" }
        if remoteStatus.contains("失败") { return "连接失败" }
        if remoteStatus.hasPrefix("正在") { return "连接中" }
        return "等待连接"
    }
    func selectSceneForMapping(_ scene: XvicoScene?) {
        editingGlobalMapping = scene == nil
        if let scene { selectedSceneID = scene.id }
        selectedKey = nil
        page = .mapping
    }
    func runtimeBinding(for key: RemoteKey) -> KeyBinding {
        resolvedBinding(for: key, scene: activeScene)
    }
    private func resolvedBinding(for key: RemoteKey, scene: XvicoScene?) -> KeyBinding {
        let global = settings.globalBindings[key.rawValue] ?? key.referenceBinding
        guard var binding = scene?.bindings[key.rawValue] else { return global }
        switch binding.longPressOverride {
        case .inherit:
            binding.longPressEnabled = global.longPressEnabled
            binding.longPressAction = global.longPressAction
            binding.longPressValue = global.longPressValue
            binding.longPressModifiers = global.longPressModifiers
            binding.longPressRightModifiers = global.longPressRightModifiers
            binding.holdNoOutput = global.holdNoOutput
            binding.siriMode = global.siriMode
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
        case .disabled: binding.doubleClickEnabled = false
        case .custom: break
        }
        return binding
    }

    func updateBinding(_ binding: KeyBinding, for key: RemoteKey) {
        if editingGlobalMapping { settings.globalBindings[key.rawValue] = binding; return }
        guard var scene = selectedScene else { return }
        scene.bindings[key.rawValue] = binding
        selectedScene = scene
    }

    func addScene(name: String, bundleID: String = "") {
        if let existing = scenes.first(where: { !$0.bundleID.isEmpty && $0.bundleID == bundleID }) {
            selectedSceneID = existing.id; return
        }
        var scene = XvicoScene.coding(name: name, bundleID: bundleID, color: "blue")
        scene.id = UUID()
        scenes.append(scene)
        selectedSceneID = scene.id
    }

    @discardableResult
    func addScene(for app: ApplicationChoice) -> UUID {
        addScene(name: app.name, bundleID: app.id)
        return scenes.first { $0.bundleID == app.id }!.id
    }
    func sceneBinding(for key: RemoteKey, sceneID: UUID) -> KeyBinding {
        scenes.first { $0.id == sceneID }?.bindings[key.rawValue]
            ?? settings.globalBindings[key.rawValue] ?? key.referenceBinding
    }
    func setSceneBinding(_ binding: KeyBinding, key: RemoteKey, sceneID: UUID) {
        guard let index = scenes.firstIndex(where: { $0.id == sceneID }) else { return }
        scenes[index].bindings[key.rawValue] = binding
    }
    func setSceneRing(_ action: RingAction?, for sceneID: UUID) {
        guard let index = scenes.firstIndex(where: { $0.id == sceneID }) else { return }
        scenes[index].ringAction = action
    }
    func setSceneWheel(_ style: WheelStyle?, for sceneID: UUID) {
        guard let index = scenes.firstIndex(where: { $0.id == sceneID }) else { return }
        scenes[index].wheelStyle = style
    }

    func applyPreset(_ preset: ScenePreset, bundleID: String) {
        guard !bundleID.isEmpty else { return }
        if let index = scenes.firstIndex(where: { $0.bundleID == bundleID }) {
            scenes[index].bindings = preset.bindings
            scenes[index].enabled = true
            scenes[index].ringAction = preset.id == "codex" ? .codexTasks : nil
            scenes[index].wheelStyle = nil
            selectedSceneID = scenes[index].id
        } else {
            var scene = XvicoScene(name: ApplicationCatalog.installed(bundleID)?.name ?? preset.name, bundleID: bundleID, color: "blue", bindings: preset.bindings)
            scene.ringAction = preset.id == "codex" ? .codexTasks : nil
            scenes.append(scene)
            selectedSceneID = scene.id
        }
        editingGlobalMapping = false
        show("已应用预设：\(preset.name)")
    }

    func restoreInitialRemoteMapping() {
        // Repeated clicks must not replace the useful pre-reset snapshot with
        // the already reset state. Keep the scene contents available for reuse.
        let alreadyInitial = RemoteMappingConfiguration(settings) == .initial
            && scenes.allSatisfy { !$0.enabled } && manuallyActiveSceneID == nil
        guard !alreadyInitial else { show("当前已是初始键位"); return }
        let snapshot = MappingRestoreSnapshot(configuration: .init(settings),
            sceneEnabled: Dictionary(uniqueKeysWithValues: scenes.map { ($0.id.uuidString, $0.enabled) }),
            selectedSceneID: selectedSceneID, editingGlobalMapping: editingGlobalMapping)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: "xvico.mappingRestoreSnapshot")
        mappingRestoreSnapshot = snapshot
        clearMappingInputState()
        restoring = true
        settings = RemoteMappingConfiguration.initial.applying(to: settings)
        scenes = scenes.map { scene in var paused = scene; paused.enabled = false; return paused }
        manuallyActiveSceneID = nil
        editingGlobalMapping = true
        isLearning = false
        selectedKey = nil
        restoring = false
        persist()
        show("已恢复初始键位；已有场景已暂停，可随时重新启用")
    }

    func undoInitialRemoteMappingRestore() {
        guard let snapshot = mappingRestoreSnapshot else { return }
        clearMappingInputState()
        restoring = true
        settings = snapshot.configuration.applying(to: settings)
        // Do not resurrect deleted scenes or remove scenes added since reset.
        scenes = scenes.map { scene in
            var restoredScene = scene
            if let enabled = snapshot.sceneEnabled[scene.id.uuidString] { restoredScene.enabled = enabled }
            return restoredScene
        }
        manuallyActiveSceneID = nil
        selectedSceneID = scenes.contains { $0.id == snapshot.selectedSceneID } ? snapshot.selectedSceneID : scenes.first?.id
        editingGlobalMapping = snapshot.editingGlobalMapping
        selectedKey = nil
        mappingRestoreSnapshot = nil
        defaults.removeObject(forKey: "xvico.mappingRestoreSnapshot")
        restoring = false
        persist()
        show("已撤销初始键位恢复")
    }

    func deleteScene(_ scene: XvicoScene) {
        scenes.removeAll { $0.id == scene.id }
        if selectedSceneID == scene.id { selectedSceneID = scenes.first?.id }
    }

    func perform(_ binding: KeyBinding) {
        guard binding.enabled else { show("这个按键映射已暂停"); return }
        switch binding.action {
        case .none: show("此按键尚未设置动作")
        case .key:
            guard !binding.value.isEmpty else { show("请先配置快捷键"); return }
            guard KeyboardOutput.named(binding.normalizedKeyboard.value) != nil else { show("未识别的按键：\(binding.value)，请重新录制"); return }
            if sendKeyboard(binding, down: true) {
                _ = sendKeyboard(binding, down: false)
                lastAction = "快捷键 \(binding.value)"
            }
            else { show("请在系统设置中授予 Xvico 辅助功能权限") }
        case .openApp:
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: binding.value) { NSWorkspace.shared.openApplication(at: url, configuration: .init()) }
            else { show("找不到应用：\(binding.value)") }
        case .text, .textAndReturn:
            guard accessibilityCheck() else { show("请授予 Xvico 辅助功能权限"); return }
            let text = Array((binding.action == .textAndReturn ? binding.textValue : binding.value).utf16)
            text.withUnsafeBufferPointer { buffer in
                for down in [true, false] {
                    let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)
                    event?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
                    if let event { eventPoster(event) }
                }
            }
            if binding.action == .textAndReturn { _ = sendKeyboard(KeyBinding(action: .key, value: "Return"), down: true); _ = sendKeyboard(KeyBinding(action: .key, value: "Return"), down: false) }
            lastAction = "文本已输入"
        case .screenOff:
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            task.arguments = ["displaysleepnow"]
            try? task.run()
        case .lockScreen:
            _ = postShortcut("⌃⌘Q")
        case .systemSleep:
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            task.arguments = ["sleepnow"]
            try? task.run()
        case .click:
            guard accessibilityCheck() else { show("请授予 Xvico 辅助功能权限"); return }
            let button: CGMouseButton = binding.mouseButton == .right ? .right : binding.mouseButton == .middle ? .center : .left
            let point = CGEvent(source: nil)?.location ?? .zero
            let down: CGEventType = binding.mouseButton == .right ? .rightMouseDown : binding.mouseButton == .middle ? .otherMouseDown : .leftMouseDown
            let up: CGEventType = binding.mouseButton == .right ? .rightMouseUp : binding.mouseButton == .middle ? .otherMouseUp : .leftMouseUp
            if let event = CGEvent(mouseEventSource: scrollEventSource, mouseType: down, mouseCursorPosition: point, mouseButton: button) {
                event.setIntegerValueField(.mouseEventClickState, value: 1)
                event.setIntegerValueField(.eventSourceUserData, value: 0x7876696265)
                eventPoster(event)
            }
            if let event = CGEvent(mouseEventSource: scrollEventSource, mouseType: up, mouseCursorPosition: point, mouseButton: button) {
                event.setIntegerValueField(.mouseEventClickState, value: 1)
                event.setIntegerValueField(.eventSourceUserData, value: 0x7876696265)
                eventPoster(event)
            }
            lastAction = "鼠标点击"
        case .scroll:
            guard accessibilityCheck() else { show("请授予 Xvico 辅助功能权限"); return }
            let amount = Int32(binding.value) ?? (binding.value.contains("下") ? -3 : 3)
            if let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: amount, wheel2: 0, wheel3: 0) { eventPoster(event) }
            lastAction = amount < 0 ? "页面向下滚动" : "页面向上滚动"
        case .voice:
            page = .voice
            if !remoteVoice.isConnecting && !remoteVoice.isSubscribed { startRemoteVoiceConnection() }
        case .nextScene:
            guard !scenes.isEmpty else { return }
            let enabled = scenes.filter(\.enabled)
            guard !enabled.isEmpty else { show("没有启用的场景"); return }
            let index = enabled.firstIndex(where: { $0.id == activeScene?.id }) ?? -1
            let next = enabled[(index + 1) % enabled.count]
            manuallyActiveSceneID = next.id
            selectedSceneID = next.id
            show("已切换到 \(selectedScene?.name ?? "新场景")")
        }
    }

    func insertVoiceText(_ text: String, targetBundleID: String? = nil) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let target = targetBundleID ?? currentBundleID
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: target).first,
              target != "work.xvibe.remote" else {
            show("先切换到需要输入文字的应用"); return
        }
        guard accessibilityCheck() else { show("请授予 Xvico 辅助功能权限"); return }
        app.activate(options: [.activateIgnoringOtherApps])
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
                self?.show("目标应用尚未在前台，未输入文字"); return
            }
            self?.perform(KeyBinding(action: .text, value: text))
        }
    }

    func startControl() {
        running = true
        inputMonitor.start(interceptButtons: settings.interceptRemoteButtons)
        if remoteStatus == "尚未连接" { remoteStatus = "等待 Siri Remote 连接" }
    }

    func learnSelectedKey() {
        guard selectedKey != nil else { return }
        isLearning = true
        modelToastForLearn()
    }

    func startRemoteVoiceConnection() {
        remoteVoice.start()
    }

    func stopControl() {
        running = false
        controlStopped?()
        clearMappingInputState()
        inputMonitor.stop()
        remoteVoice.stop()
        remoteStatus = "控制已停止"
    }

    private func clearMappingInputState() {
        if siriVoiceConsumed { _ = siriVoiceHandler?(false) }
        siriVoiceConsumed = false
        endAppSwitcher()
        gestureProcessor = RemoteGestureProcessor()
        pointerTarget = nil
        for task in pressTasks.values { task.cancel() }
        for task in singleTapTasks.values { task.cancel() }
        for held in heldBindings.values { _ = sendKeyboard(held, down: false) }
        for button in heldMouseBindings.values { sendMouseButton(button, down: false) }
        heldMouseBindings.removeAll()
        centerMouseSequence = MouseClickSequence(); mouseClickCounts.removeAll()
        pressTasks.removeAll(); singleTapTasks.removeAll(); pressedBindings.removeAll(); heldBindings.removeAll(); holdDidFire.removeAll(); lastTap.removeAll()
        ringToggleSuppressed.removeAll(); ringToggleLastTap = nil
    }

    func handleHIDUsage(page: Int, usage: Int, pressed: Bool) {
        let identity = "\(page):\(usage)"
        if isLearning, pressed, let key = selectedKey {
            learnedUsages[identity] = key.rawValue
            defaults.set(learnedUsages, forKey: "xvibe.learnedUsages")
            isLearning = false
            show("已将 HID \(identity) 绑定到「\(key.rawValue)」")
            return
        }
        let keyName = learnedUsages[identity] ?? standardRemoteKey(page: page, usage: usage)?.rawValue
        guard let keyName, let key = RemoteKey(rawValue: keyName) else { return }
        if pressed && self.page == .mapping {
            // A hardware press edits the exact mapping that will be executed,
            // not an unrelated global or previously selected app scene.
            if let active = activeScene { editingGlobalMapping = false; selectedSceneID = active.id }
            else { editingGlobalMapping = true }
            selectedKey = key
        }
        handleRemotePress(key, pressed: pressed)

    }

    private func standardRemoteKey(page: Int, usage: Int) -> RemoteKey? {
        RemoteInputMonitor.standardKey(page: page, usage: usage)
    }

    private func modelToastForLearn() { show("按下 Siri Remote 上要绑定的实体按键") }

    private func postShortcut(_ shortcut: String) -> Bool {
        var binding = KeyBinding(action: .key, value: shortcut)
        for (glyph, modifier) in [("⌘", KeyboardModifier.command), ("⌥", .option), ("⌃", .control), ("⇧", .shift)] {
            if binding.value.contains(glyph) { binding.modifiers.insert(modifier); binding.value = binding.value.replacingOccurrences(of: glyph, with: "") }
        }
        let aliases = ["↩": "Return", "⇥": "Tab", "←": "Left Arrow", "→": "Right Arrow", "↑": "Up Arrow", "↓": "Down Arrow", "+": "=", " ": "Space"]
        binding.value = aliases[binding.value] ?? binding.value
        if KeyboardOutput.named(binding.value) == nil { binding.value = binding.value.uppercased() }
        let sent = sendKeyboard(binding, down: true)
        _ = sendKeyboard(binding, down: false)
        return sent
    }

    private func sendKeyboard(_ binding: KeyBinding, down: Bool, manageModifiers: Bool = true) -> Bool {
        let binding = binding.normalizedKeyboard
        guard accessibilityCheck() else {
            if down { show("快捷键未发送：请检查 Xvico 辅助功能权限") }
            return false
        }
        guard let output = KeyboardOutput.named(binding.value) else {
            if down { show("未识别的按键：\(binding.value)，请重新录制") }
            return false
        }
        mappedKeyboardHandler?(binding, down)
        var flags = binding.modifiers.reduce(CGEventFlags()) { $0.union($1.flag) }
        if let primary = output.primaryModifier {
            if down { flags.insert(primary.flag) }
            else { flags.remove(primary.flag) }
        }
        if let systemCode = output.systemCode {
            let data1 = (systemCode << 16) | (down ? 0xA00 : 0xB00)
            if let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags.rawValue)), timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)?.cgEvent { eventPoster(event) }
            return true
        }
        guard let code = output.keyCode else { return false }
        if realKeyboardTiming && !down, let started = keyboardDownTimes.removeValue(forKey: code) {
            let remaining = 0.015 - (ProcessInfo.processInfo.systemUptime - started)
            if remaining > 0 { Thread.sleep(forTimeInterval: remaining) }
        }
        var modifierFlags = CGEventFlags()
        for modifier in KeyboardModifier.allCases where manageModifiers && binding.modifiers.contains(modifier) && down {
            modifierFlags.insert(modifier.flag)
            let event = CGEvent(keyboardEventSource: keyboardEventSource, virtualKey: modifier.code(right: binding.rightModifiers.contains(modifier)), keyDown: true)
            event?.type = .flagsChanged
            event?.flags = modifierFlags
            if let event { event.setIntegerValueField(.eventSourceUserData, value: 0x7876696265); eventPoster(event) }
            if realKeyboardTiming { Thread.sleep(forTimeInterval: 0.004) }
        }
        let event = CGEvent(keyboardEventSource: keyboardEventSource, virtualKey: code, keyDown: down)
        if output.primaryModifier != nil { event?.type = .flagsChanged }
        event?.flags = flags
        if let event { event.setIntegerValueField(.eventSourceUserData, value: 0x7876696265); eventPoster(event) }
        if down {
            keyboardDownTimes[code] = ProcessInfo.processInfo.systemUptime
            lastAction = "快捷键 " + binding.modifiers.sorted { $0.rawValue < $1.rawValue }.map(\.symbol).joined() + binding.value
        }
        for modifier in KeyboardModifier.allCases.reversed() where manageModifiers && binding.modifiers.contains(modifier) && !down {
            flags.remove(modifier.flag)
            let event = CGEvent(keyboardEventSource: keyboardEventSource, virtualKey: modifier.code(right: binding.rightModifiers.contains(modifier)), keyDown: false)
            event?.type = .flagsChanged
            event?.flags = flags
            if let event { event.setIntegerValueField(.eventSourceUserData, value: 0x7876696265); eventPoster(event) }
            if realKeyboardTiming { Thread.sleep(forTimeInterval: 0.004) }
        }
        return true
    }

    // Short tap, held key, and double tap have distinct output paths. Releases
    // always use the binding captured at press time, even after an app switch.
    func handleRemotePress(_ key: RemoteKey, pressed: Bool) {
        guard running else { return }
        mappingInteraction.send()
        if key == .voice {
            if siriVoiceConsumed {
                if !pressed { siriVoiceConsumed = false; _ = siriVoiceHandler?(false) }
                return
            }
            if pressed && siriVoiceHandler?(true) == true { siriVoiceConsumed = true; return }
            if !pressed { _ = siriVoiceHandler?(false) }
        }
        if ringToggleSuppressed.contains(key) {
            if !pressed { ringToggleSuppressed.remove(key) }
            return
        }
        if pressed && pressedBindings[key] == nil && key.rawValue == settings.ringToggleKey, let previous = ringToggleLastTap, Date().timeIntervalSince(previous) <= 0.2 {
            ringToggleLastTap = nil
            ringToggleSuppressed.insert(key)
            cycleRingAction()
            return
        }
        if key == .volumeUp || key == .volumeDown, settings.volumeKeyMode != .key {
            guard pressed else { return }
            if settings.volumeKeyMode == .microphone {
                do { lastAction = "麦克风：" + (try microphoneSwitcher(key == .volumeUp ? -1 : 1)) }
                catch { show(error.localizedDescription) }
            } else {
                guard accessibilityCheck() else { show("请授予 Xvico 辅助功能权限"); return }
                postScroll(Int32(settings.volumeScrollStep) * (key == .volumeUp ? 1 : -1), pixels: true)
            }
            return
        }
        if pressed {
            guard pressedBindings[key] == nil else { return }
            let binding = runtimeBinding(for: key)
            guard binding.enabled else { show("\(key.displayName)在当前映射中已停用"); return }
            pressedBindings[key] = binding
            let doubleTap = binding.doubleClickEnabled && (key == .power || (key == .voice && binding.action == .key && binding.siriMode == "分段模式"))
            if binding.action == .click && !doubleTap {
                heldMouseBindings[key] = binding.mouseButton
                sendMouseButton(binding.mouseButton, down: true, key: key)
                return
            }
            if binding.action == .key && ((key == .voice && binding.siriMode == "长按模式") || (!binding.longPressEnabled && !doubleTap)) {
                heldBindings[key] = binding
                _ = sendKeyboard(binding, down: true)
                return
            }
            if binding.longPressEnabled && binding.action == .key {
                pressTasks[key] = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    guard !Task.isCancelled, let self, self.pressedBindings[key] != nil else { return }
                    self.holdDidFire.insert(key)
                    if !binding.holdNoOutput {
                        var held = KeyBinding(action: .key, value: binding.longPressValue.isEmpty ? "F1" : binding.longPressValue, modifiers: binding.longPressModifiers)
                        held.rightModifiers = binding.longPressRightModifiers
                        self.heldBindings[key] = held
                        _ = self.sendKeyboard(held, down: true)
                    }
                }
            }
        } else {
            guard let binding = pressedBindings.removeValue(forKey: key) else { return }
            if key.rawValue == settings.ringToggleKey { ringToggleLastTap = Date() }
            if let button = heldMouseBindings.removeValue(forKey: key) {
                sendMouseButton(button, down: false)
                return
            }
            pressTasks.removeValue(forKey: key)?.cancel()
            if let held = heldBindings.removeValue(forKey: key) { _ = sendKeyboard(held, down: false); holdDidFire.remove(key); return }
            if holdDidFire.remove(key) != nil { return }
            if binding.doubleClickEnabled && (key == .power || (key == .voice && binding.action == .key && binding.siriMode == "分段模式")) {
                let now = Date()
                if let previous = lastTap[key], now.timeIntervalSince(previous) <= 0.2 {
                    singleTapTasks.removeValue(forKey: key)?.cancel()
                    lastTap[key] = nil
                    if key == .power {
                        let action: XvicoAction = binding.powerDoubleClickAction == .lockScreen ? .lockScreen : binding.powerDoubleClickAction == .systemSleep ? .systemSleep : .screenOff
                        perform(KeyBinding(action: action, value: ""))
                    } else {
                        var double = KeyBinding(action: .key, value: binding.doubleClickValue.isEmpty ? "Return" : binding.doubleClickValue, modifiers: binding.doubleClickModifiers)
                        double.rightModifiers = binding.doubleClickRightModifiers
                        perform(double)
                    }
                } else {
                    lastTap[key] = now
                    singleTapTasks[key] = Task { [weak self] in
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        guard !Task.isCancelled, let self else { return }
                        self.lastTap[key] = nil
                        self.dispatchTap(binding, key: key)
                    }
                }
            } else { dispatchTap(binding, key: key) }
        }
    }

    private func dispatchTap(_ binding: KeyBinding, key: RemoteKey) {
        if key == .power && binding.action == .textAndReturn && !screenSleeping { return }
        perform(binding)
    }

    var effectiveRingAction: RingAction { activeScene?.ringAction ?? settings.ringAction }
    var effectiveWheelStyle: WheelStyle { activeScene?.wheelStyle ?? settings.wheelStyle }
    func cycleRingAction() {
        endAppSwitcher()
        let modes: [RingAction] = activeScene == nil ? [.switchApp, .scroll] : [.switchApp, .scroll, .codexTasks]
        let index = modes.firstIndex(of: effectiveRingAction) ?? 0
        let next = modes[(index + 1) % modes.count]
        if let active = activeScene, let sceneIndex = scenes.firstIndex(where: { $0.id == active.id }) {
            scenes[sceneIndex].ringAction = next
        } else { settings.ringAction = next }
        show("外圈动作：\(next.rawValue)")
    }
    func resetRingDefaults() { settings.ringSensitivity = 1.08; settings.ringRadius = 0.33 }
    func reidentifyRemote() {
        endAppSwitcher()
        gestureProcessor = RemoteGestureProcessor()
        if running { inputMonitor.reidentifyTouch() }
    }
    func handleTouch(_ sample: RemoteTouchSample) {
        guard running else { return }
        if sample.touching { mappingInteraction.send() }
        if !sample.touching || !settings.touchEnabled { pointerTarget = nil }
        var touchSettings = settings
        touchSettings.wheelStyle = effectiveWheelStyle
        if !heldMouseBindings.isEmpty { touchSettings.ringEnabled = false }
        let outputs = gestureProcessor.process(sample, settings: touchSettings, mode: effectiveRingAction)
        // Resting fingers, contact acquisition and filtered noise have no
        // events to post. Avoid a system trust query on those hardware frames.
        guard !outputs.isEmpty else { return }
        guard accessibilityCheck() else { pointerTarget = nil; return }
        for output in outputs {
            switch output {
            case .pointer(let dx, let dy):
                // Accumulate the target while a finger is down. Reading
                // the cursor anew per queued event can discard pending motion.
                var point = pointerTarget ?? CGEvent(source: nil)?.location ?? .zero
                point.x += dx; point.y += dy
                point = clampPointerToDisplay(point)
                pointerTarget = point
                let held = heldMouseBindings.values.first
                let type: CGEventType = held == .right ? .rightMouseDragged : held == .middle ? .otherMouseDragged : held == .left ? .leftMouseDragged : .mouseMoved
                let button: CGMouseButton = held == .right ? .right : held == .middle ? .center : .left
                if let event = CGEvent(mouseEventSource: scrollEventSource, mouseType: type, mouseCursorPosition: point, mouseButton: button) {
                    event.setIntegerValueField(.eventSourceUserData, value: 0x7876696265)
                    eventPoster(event)
                }
            case .scroll(let distance, let pixels): postScroll(distance, pixels: pixels)
            case .appStep(let direction):
                if !appSwitcherHeld {
                    appSwitcherHeld = true
                    _ = sendKeyboard(KeyBinding(action: .key, value: "Left Command"), down: true)
                }
                let binding = KeyBinding(action: .key, value: "Tab", modifiers: direction < 0 ? [.command, .shift] : [.command])
                _ = sendKeyboard(binding, down: true, manageModifiers: false)
                _ = sendKeyboard(binding, down: false, manageModifiers: false)
            case .appEnd: endAppSwitcher()
            case .taskStep(let direction):
                guard activeScene != nil else { show("Codex 任务切换需要匹配 App 场景"); continue }
                codexTaskNumber = min(9, max(1, codexTaskNumber + direction))
                perform(KeyBinding(action: .key, value: String(codexTaskNumber), modifiers: [.command]))
            }
        }
    }
    private func clampPointerToDisplay(_ point: CGPoint) -> CGPoint {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return point }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return point }
        let candidates = displays.prefix(Int(count)).map { id -> CGPoint in
            let bounds = CGDisplayBounds(id)
            return CGPoint(x: min(bounds.maxX - 1, max(bounds.minX, point.x)),
                           y: min(bounds.maxY - 1, max(bounds.minY, point.y)))
        }
        return candidates.min { hypot($0.x - point.x, $0.y - point.y) < hypot($1.x - point.x, $1.y - point.y) } ?? point
    }
    private func sendMouseButton(_ button: MouseClickButton, down: Bool, key: RemoteKey? = nil) {
        guard accessibilityCheck() else { return }
        let code: CGMouseButton = button == .right ? .right : button == .middle ? .center : .left
        let type: CGEventType = button == .right ? (down ? .rightMouseDown : .rightMouseUp)
            : button == .middle ? (down ? .otherMouseDown : .otherMouseUp) : (down ? .leftMouseDown : .leftMouseUp)
        let point = pointerTarget ?? CGEvent(source: nil)?.location ?? .zero
        if down {
            mouseClickCounts[button] = key == .center && button == .left
                ? centerMouseSequence.click(at: point, time: mouseClickTime(), interval: NSEvent.doubleClickInterval) : 1
        }
        if let event = CGEvent(mouseEventSource: scrollEventSource, mouseType: type, mouseCursorPosition: point, mouseButton: code) {
            event.setIntegerValueField(.mouseEventClickState, value: mouseClickCounts[button] ?? 1)
            event.setIntegerValueField(.eventSourceUserData, value: 0x7876696265)
            eventPoster(event)
            lastAction = button.rawValue + (down ? "按下" : "松开")
        }
        if !down { mouseClickCounts.removeValue(forKey: button) }
    }
    private func endAppSwitcher() {
        if appSwitcherHeld { _ = sendKeyboard(KeyBinding(action: .key, value: "Left Command"), down: false); appSwitcherHeld = false }
    }
    private func postScroll(_ amount: Int32, pixels: Bool) {
        // Use a combined-session source with two axes, the inactive
        if let event = CGEvent(scrollWheelEvent2Source: scrollEventSource, units: pixels ? .pixel : .line, wheelCount: 2, wheel1: amount, wheel2: 0, wheel3: 0) {
            event.setIntegerValueField(.eventSourceUserData, value: 0x7876696265)
            eventPoster(event)
        }
        inputDiagnostics.recordAction("滚动 \(amount)\(pixels ? " 像素" : " 格")", throttled: true)
    }

    private func migrateLegacyMappingDefaults() {
        guard !defaults.bool(forKey: "xvibe.mappingReferenceMigration.v1") else { return }
        if let data = defaults.data(forKey: "xvibe.scenes") { defaults.set(data, forKey: "xvibe.scenes.beforeReferenceMigration.v1") }
        let oldDefaults: [RemoteKey: KeyBinding] = [
            .menu: KeyBinding(action: .key, value: "⌘W"), .tv: KeyBinding(action: .key, value: "⌘⇥"),
            .playPause: KeyBinding(action: .key, value: "⌘↩"), .volumeUp: KeyBinding(action: .key, value: "⌘+"),
            .volumeDown: KeyBinding(action: .key, value: "⌘-"), .mute: KeyBinding(action: .voice, value: ""),
            .voice: KeyBinding(action: .voice, value: "语音设置页 / 短按动作")]
        for index in scenes.indices {
            for key in RemoteKey.allCases {
                if let old = oldDefaults[key], scenes[index].bindings[key.rawValue] == old {
                    scenes[index].bindings[key.rawValue] = key.referenceBinding
                }
            }
        }
        defaults.set(true, forKey: "xvibe.mappingReferenceMigration.v1")
    }


    func importPreset() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let count = try importScenes(from: url); show("已导入 \(count) 个场景") }
        catch { show("未能读取场景文件：\(error.localizedDescription)") }
    }

    @discardableResult
    func importScenes(from url: URL) throws -> Int {
        let imported = try JSONDecoder().decode([XvicoScene].self, from: Data(contentsOf: url))
        guard !imported.isEmpty, imported.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw NSError(domain: "Xvico.Preset", code: 1, userInfo: [NSLocalizedDescriptionKey: "场景文件为空或缺少场景名称"])
        }
        var ids = Set(scenes.map(\.id))
        let values = imported.map { source -> XvicoScene in
            var scene = source
            if ids.contains(scene.id) { scene.id = UUID() }
            ids.insert(scene.id)
            return scene
        }
        scenes.append(contentsOf: values)
        return values.count
    }

    func exportScenes(_ scene: XvicoScene? = nil) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Xvico-Scenes.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try exportScenes(to: url, scene: scene); show("场景已导出") } catch { show(error.localizedDescription) }
    }
    func exportScenes(to url: URL, scene: XvicoScene? = nil) throws {
        try JSONEncoder.pretty.encode(scene.map { [$0] } ?? scenes).write(to: url, options: .atomic)
    }

    func exportGlobalPreset(to url: URL) throws {
        try JSONEncoder.pretty.encode(GlobalPreset(settings: settings)).write(to: url, options: .atomic)
    }
    func importGlobalPreset(from url: URL) throws {
        let preset = try JSONDecoder().decode(GlobalPreset.self, from: Data(contentsOf: url))
        guard ["Xvico.GlobalPreset", "Xpavi.GlobalPreset", "Xvibe.GlobalPreset"].contains(preset.format), preset.version == 1 else { throw NSError(domain: "Xvico.Preset", code: 2, userInfo: [NSLocalizedDescriptionKey: "不支持的全局配置格式"]) }
        settings = preset.settings
        if !settings.showDockIcon { settings.showMenuBarIcon = true }
    }
    func chooseGlobalPreset(importing: Bool) {
        if importing {
            let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do { try importGlobalPreset(from: url); reidentifyRemote(); show("全局配置已导入") }
            catch { show("无法导入全局配置：\(error.localizedDescription)") }
        } else {
            let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Xvico-Global.json"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do { try exportGlobalPreset(to: url); show("全局配置已导出") }
            catch { show(error.localizedDescription) }
        }
    }

    func show(_ message: String) {
        toast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
            if self?.toast == message { self?.toast = nil }
        }
    }

    private func persist() {
        guard !restoring else { return }
        defaults.set(try? JSONEncoder().encode(scenes), forKey: "xvibe.scenes")
        defaults.set(selectedSceneID?.uuidString, forKey: "xvibe.selectedScene")
        defaults.set(try? JSONEncoder().encode(shortcuts), forKey: "xvibe.shortcuts")
        defaults.set(try? JSONEncoder().encode(settings), forKey: "xvibe.settings")
    }

    private func restore() {
        if let data = defaults.data(forKey: "xvico.mappingRestoreSnapshot") {
            mappingRestoreSnapshot = try? JSONDecoder().decode(MappingRestoreSnapshot.self, from: data)
        }
        siriPressBehavior = defaults.string(forKey: "xvibe.siriPressBehavior") ?? "分段模式"
        siriLongBehavior = defaults.string(forKey: "xvibe.siriLongBehavior") ?? "语音识别"
        siriDoubleEnabled = defaults.object(forKey: "xvibe.siriDoubleEnabled") as? Bool ?? true
        if let data = defaults.data(forKey: "xvibe.siriDoubleBinding"), let value = try? JSONDecoder().decode(KeyBinding.self, from: data) { siriDoubleBinding = value }
        if let value = defaults.dictionary(forKey: "xvibe.learnedUsages") as? [String: String] { learnedUsages = value }
        let savedScenes = defaults.data(forKey: "xvibe.scenes").flatMap { try? JSONDecoder().decode([XvicoScene].self, from: $0) }
        if let savedScenes { scenes = savedScenes }
        // A saved empty list means the user removed every scene. Bootstrap
        // defaults only when there is no decodable saved scene collection.
        if savedScenes == nil {
            scenes = [
                .coding(name: "Codex", bundleID: "com.openai.codex", color: "blue"),
                .coding(name: "Cursor", bundleID: "com.todesktop.230313mzl4w4u92", color: "green"),
                .coding(name: "终端", bundleID: "com.apple.Terminal", color: "orange")
            ]
        }
        if let id = defaults.string(forKey: "xvibe.selectedScene").flatMap(UUID.init(uuidString:)) { selectedSceneID = id }
        if selectedSceneID == nil || !scenes.contains(where: { $0.id == selectedSceneID }) { selectedSceneID = scenes.first?.id }
        if let data = defaults.data(forKey: "xvibe.shortcuts"), let value = try? JSONDecoder().decode([UserShortcut].self, from: data) { shortcuts = value }
        if let data = defaults.data(forKey: "xvibe.settings"), let value = try? JSONDecoder().decode(XvicoSettings.self, from: data) { settings = value }
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
