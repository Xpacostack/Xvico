import Foundation

enum XvicoPage: String, CaseIterable, Identifiable {
    case mapping = "映射"
    case scenes = "场景"
    case commands = "快捷指令"
    case device = "设备设置"
    case voice = "语音工作流"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .mapping: "功能映射"
        case .scenes: "预设场景"
        case .voice: "语音设置"
        default: rawValue
        }
    }
    var symbol: String {
        switch self {
        case .mapping: "square.grid.2x2"
        case .scenes: "square.3.layers.3d"
        case .commands: "command"
        case .device: "gearshape"
        case .voice: "waveform"
        }
    }
}

enum RemoteKey: String, CaseIterable, Identifiable, Codable {
    case power = "电源键"
    case menu = "返回"
    case tv = "TV / 多任务"
    case playPause = "播放 / 暂停"
    case volumeUp = "音量 +"
    case volumeDown = "音量 -"
    case mute = "静音"
    case center = "触控板中心"
    case ring = "触控板外圈"
    case touchUp = "点击盘上"
    case touchDown = "点击盘下"
    case touchLeft = "点击盘左"
    case touchRight = "点击盘右"
    case voice = "Siri 键"
    case siriHold = "Siri 键（按住）"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .power: "power"
        case .menu: "chevron.left"
        case .tv: "display"
        case .playPause: "playpause"
        case .volumeUp: "plus"
        case .volumeDown: "minus"
        case .mute: "speaker.slash"
        case .center: "hand.tap"
        case .ring: "arrow.clockwise"
        case .touchUp: "arrow.up"
        case .touchDown: "arrow.down"
        case .touchLeft: "arrow.left"
        case .touchRight: "arrow.right"
        case .voice, .siriHold: "waveform"
        }
    }

    var family: RemoteKeyFamily {
        switch self {
        case .power: .power
        case .voice, .siriHold: .siri
        case .center: .touchSurface
        case .ring, .touchUp, .touchDown, .touchLeft, .touchRight: .touchGesture
        default: .button
        }
    }
}

enum RemoteKeyFamily { case power, button, touchSurface, touchGesture, siri }

enum XvicoAction: String, CaseIterable, Identifiable, Codable {
    case none = "不执行"
    case key = "发送快捷键"
    case openApp = "打开应用"
    case text = "输入文本"
    case click = "鼠标点击"
    case scroll = "滚动页面"
    case voice = "语音命令"
    case nextScene = "切换场景"
    case screenOff = "熄屏"
    case lockScreen = "锁定屏幕"
    case systemSleep = "系统睡眠"
    case textAndReturn = "输入文本并回车"

    var id: String { rawValue }
}

struct KeyBinding: Codable, Equatable {
    var action: XvicoAction
    var value: String
    // Text and keyboard mappings retain their own content when the user
    var textValue: String = ""
    var enabled: Bool = true
    var modifiers: Set<KeyboardModifier> = []
    var mouseButton: MouseClickButton = .left
    var longPressEnabled = false
    var longPressAction: XvicoAction = .none
    var longPressValue = ""
    var longPressModifiers: Set<KeyboardModifier> = []
    var longPressOverride: PressBehaviorOverride = .inherit
    var doubleClickEnabled = false
    var doubleClickAction: XvicoAction = .none
    var doubleClickValue = ""
    var doubleClickModifiers: Set<KeyboardModifier> = []
    var doubleClickOverride: PressBehaviorOverride = .inherit
    var powerDoubleClickAction: PowerDoubleClickAction = .inherit
    var rightModifiers: Set<KeyboardModifier> = []
    var longPressRightModifiers: Set<KeyboardModifier> = []
    var doubleClickRightModifiers: Set<KeyboardModifier> = []
    var holdNoOutput = false
    var siriMode = "分段模式"

    init(action: XvicoAction, value: String, enabled: Bool = true,
         modifiers: Set<KeyboardModifier> = [], mouseButton: MouseClickButton = .left,
         longPressEnabled: Bool = false, longPressAction: XvicoAction = .none,
         longPressValue: String = "", longPressModifiers: Set<KeyboardModifier> = [],
         longPressOverride: PressBehaviorOverride = .inherit,
         doubleClickEnabled: Bool = false, doubleClickAction: XvicoAction = .none,
         doubleClickValue: String = "", doubleClickModifiers: Set<KeyboardModifier> = [],
         doubleClickOverride: PressBehaviorOverride = .inherit,
         powerDoubleClickAction: PowerDoubleClickAction = .inherit) {
        self.action = action
        self.value = value
        self.textValue = action == .textAndReturn ? value : ""
        self.enabled = enabled
        self.modifiers = modifiers
        self.mouseButton = mouseButton
        self.longPressEnabled = longPressEnabled
        self.longPressAction = longPressAction
        self.longPressValue = longPressValue
        self.longPressModifiers = longPressModifiers
        self.longPressOverride = longPressOverride
        self.doubleClickEnabled = doubleClickEnabled
        self.doubleClickAction = doubleClickAction
        self.doubleClickValue = doubleClickValue
        self.doubleClickModifiers = doubleClickModifiers
        self.doubleClickOverride = doubleClickOverride
        self.powerDoubleClickAction = powerDoubleClickAction
    }

    private enum CodingKeys: String, CodingKey {
        case action, value, textValue, enabled, modifiers, mouseButton, longPressEnabled, longPressAction
        case longPressValue, longPressModifiers, longPressOverride, doubleClickEnabled
        case doubleClickAction, doubleClickValue, doubleClickModifiers, doubleClickOverride
        case powerDoubleClickAction, rightModifiers, longPressRightModifiers, doubleClickRightModifiers, holdNoOutput, siriMode
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            action: try values.decode(XvicoAction.self, forKey: .action),
            value: try values.decodeIfPresent(String.self, forKey: .value) ?? "",
            enabled: try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
            modifiers: try values.decodeIfPresent(Set<KeyboardModifier>.self, forKey: .modifiers) ?? [],
            mouseButton: try values.decodeIfPresent(MouseClickButton.self, forKey: .mouseButton) ?? .left,
            longPressEnabled: try values.decodeIfPresent(Bool.self, forKey: .longPressEnabled) ?? false,
            longPressAction: try values.decodeIfPresent(XvicoAction.self, forKey: .longPressAction) ?? .none,
            longPressValue: try values.decodeIfPresent(String.self, forKey: .longPressValue) ?? "",
            longPressModifiers: try values.decodeIfPresent(Set<KeyboardModifier>.self, forKey: .longPressModifiers) ?? [],
            longPressOverride: try values.decodeIfPresent(PressBehaviorOverride.self, forKey: .longPressOverride) ?? .inherit,
            doubleClickEnabled: try values.decodeIfPresent(Bool.self, forKey: .doubleClickEnabled) ?? false,
            doubleClickAction: try values.decodeIfPresent(XvicoAction.self, forKey: .doubleClickAction) ?? .none,
            doubleClickValue: try values.decodeIfPresent(String.self, forKey: .doubleClickValue) ?? "",
            doubleClickModifiers: try values.decodeIfPresent(Set<KeyboardModifier>.self, forKey: .doubleClickModifiers) ?? [],
            doubleClickOverride: try values.decodeIfPresent(PressBehaviorOverride.self, forKey: .doubleClickOverride) ?? .inherit,
            powerDoubleClickAction: try values.decodeIfPresent(PowerDoubleClickAction.self, forKey: .powerDoubleClickAction) ?? .inherit
        )
        rightModifiers = try values.decodeIfPresent(Set<KeyboardModifier>.self, forKey: .rightModifiers) ?? []
        longPressRightModifiers = try values.decodeIfPresent(Set<KeyboardModifier>.self, forKey: .longPressRightModifiers) ?? []
        doubleClickRightModifiers = try values.decodeIfPresent(Set<KeyboardModifier>.self, forKey: .doubleClickRightModifiers) ?? []
        holdNoOutput = try values.decodeIfPresent(Bool.self, forKey: .holdNoOutput) ?? false
        siriMode = try values.decodeIfPresent(String.self, forKey: .siriMode) ?? "分段模式"
        textValue = try values.decodeIfPresent(String.self, forKey: .textValue) ?? (action == .textAndReturn ? value : "")
        if action == .textAndReturn && !values.contains(.textValue) { value = "Return" }
    }
}

enum KeyboardModifier: String, Codable, CaseIterable, Hashable, Identifiable {
    case command = "Command", option = "Option", control = "Control", shift = "Shift", function = "Fn"
    var id: String { rawValue }
}

enum MouseClickButton: String, Codable, CaseIterable, Identifiable {
    case left = "左键", right = "右键", middle = "中键"
    var id: String { rawValue }
}

enum PressBehaviorOverride: String, Codable, CaseIterable, Identifiable {
    case inherit = "继承全局设置", disabled = "禁用", custom = "自定义"
    var id: String { rawValue }
}

enum PowerDoubleClickAction: String, Codable, CaseIterable, Identifiable {
    case inherit = "继承", sleepDisplay = "熄屏", lockScreen = "锁定屏幕", systemSleep = "系统睡眠", custom = "自定义"
    var id: String { rawValue }
}

struct XvicoScene: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var bundleID: String
    var color: String
    var bindings: [String: KeyBinding]
    var enabled: Bool = true
    var ringAction: RingAction? = nil
    var wheelStyle: WheelStyle? = nil

    static func coding(name: String, bundleID: String, color: String) -> XvicoScene {
        // Only explicit app overrides belong here. Missing keys inherit the
        // user's global mapping, including media and Siri input preferences.
        XvicoScene(name: name, bundleID: bundleID, color: color, bindings: [:])
    }
}

struct UserShortcut: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var phrase: String
    var action: XvicoAction
    var value: String
    var enabled = true
}

enum RingAction: String, Codable, CaseIterable, Identifiable {
    case switchApp = "切换 App", scroll = "滚轮", codexTasks = "Codex 任务（⌘1–9）"
    var id: String { rawValue }
}
enum WheelStyle: String, Codable, CaseIterable, Identifiable {
    case continuous = "无极滚轮", stepped = "分段滑轮"
    var id: String { rawValue }
}
enum VolumeKeyMode: String, Codable, CaseIterable, Identifiable {
    case microphone = "切换麦克风", scroll = "滚动", key = "普通按键"
    var id: String { rawValue }
}
enum InterfaceLanguage: String, Codable, CaseIterable, Identifiable {
    case system = "跟随系统", chinese = "简体中文", english = "English", japanese = "日本語", french = "Français"
    var id: String { rawValue }
    var localeIdentifier: String? {
        switch self {
        case .system: nil
        case .chinese: "zh-Hans"
        case .english: "en"
        case .japanese: "ja"
        case .french: "fr"
        }
    }
}

struct XvicoSettings: Codable, Equatable {
    var autoSwitchScenes = true
    var launchAtLogin = false
    var blockPowerActions = true
    var touchEnabled = true
    var scrollSensitivity = 1.0
    var speechLanguage = "跟随系统"
    var interceptRemoteButtons = true
    var pointerSensitivity = 1.0
    var ringEnabled = true
    var ringAction: RingAction = .scroll
    var ringToggleKey: String = RemoteKey.touchRight.rawValue
    var wheelStyle: WheelStyle = .continuous
    var ringSensitivity = 1.08
    var ringRadius = 0.33
    var volumeKeyMode: VolumeKeyMode = .key
    var volumeScrollStep = 80.0
    var showDockIcon = true
    var showMenuBarIcon = true
    var keepRunningWhenClosed = true
    var interfaceLanguage: InterfaceLanguage = .system
    var globalBindings = Dictionary(uniqueKeysWithValues: RemoteKey.allCases.map { ($0.rawValue, $0.referenceBinding) })

    init() {}
    private enum CodingKeys: String, CodingKey {
        case autoSwitchScenes, launchAtLogin, blockPowerActions, touchEnabled, scrollSensitivity, speechLanguage
        case interceptRemoteButtons, pointerSensitivity, ringEnabled, ringAction, ringToggleKey, wheelStyle, ringSensitivity, ringRadius
        case volumeKeyMode, volumeScrollStep, showDockIcon, showMenuBarIcon, keepRunningWhenClosed, interfaceLanguage, globalBindings
    }
    init(from decoder: Decoder) throws {
        self.init()
        let v = try decoder.container(keyedBy: CodingKeys.self)
        autoSwitchScenes = try v.decodeIfPresent(Bool.self, forKey: .autoSwitchScenes) ?? autoSwitchScenes
        launchAtLogin = try v.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? launchAtLogin
        blockPowerActions = try v.decodeIfPresent(Bool.self, forKey: .blockPowerActions) ?? blockPowerActions
        touchEnabled = try v.decodeIfPresent(Bool.self, forKey: .touchEnabled) ?? touchEnabled
        scrollSensitivity = try v.decodeIfPresent(Double.self, forKey: .scrollSensitivity) ?? scrollSensitivity
        speechLanguage = try v.decodeIfPresent(String.self, forKey: .speechLanguage) ?? speechLanguage
        interceptRemoteButtons = try v.decodeIfPresent(Bool.self, forKey: .interceptRemoteButtons) ?? blockPowerActions
        pointerSensitivity = try v.decodeIfPresent(Double.self, forKey: .pointerSensitivity) ?? pointerSensitivity
        ringEnabled = try v.decodeIfPresent(Bool.self, forKey: .ringEnabled) ?? ringEnabled
        ringAction = try v.decodeIfPresent(RingAction.self, forKey: .ringAction) ?? ringAction
        ringToggleKey = try v.decodeIfPresent(String.self, forKey: .ringToggleKey) ?? ringToggleKey
        wheelStyle = try v.decodeIfPresent(WheelStyle.self, forKey: .wheelStyle) ?? wheelStyle
        ringSensitivity = try v.decodeIfPresent(Double.self, forKey: .ringSensitivity) ?? ringSensitivity
        ringRadius = try v.decodeIfPresent(Double.self, forKey: .ringRadius) ?? ringRadius
        volumeKeyMode = try v.decodeIfPresent(VolumeKeyMode.self, forKey: .volumeKeyMode) ?? volumeKeyMode
        volumeScrollStep = try v.decodeIfPresent(Double.self, forKey: .volumeScrollStep) ?? volumeScrollStep
        showDockIcon = try v.decodeIfPresent(Bool.self, forKey: .showDockIcon) ?? showDockIcon
        showMenuBarIcon = try v.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? showMenuBarIcon
        keepRunningWhenClosed = try v.decodeIfPresent(Bool.self, forKey: .keepRunningWhenClosed) ?? keepRunningWhenClosed
        interfaceLanguage = try v.decodeIfPresent(InterfaceLanguage.self, forKey: .interfaceLanguage) ?? interfaceLanguage
        globalBindings = try v.decodeIfPresent([String: KeyBinding].self, forKey: .globalBindings) ?? globalBindings
        for key in RemoteKey.allCases where globalBindings[key.rawValue] == nil { globalBindings[key.rawValue] = key.referenceBinding }
        guard pointerSensitivity.isFinite, (0.2...3).contains(pointerSensitivity),
              ringSensitivity.isFinite, (0.6...1.8).contains(ringSensitivity),
              ringRadius.isFinite, (0.22...0.48).contains(ringRadius),
              scrollSensitivity.isFinite, (0.1...10).contains(scrollSensitivity),
              volumeScrollStep.isFinite, (20...240).contains(volumeScrollStep) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Input sensitivity or scrolling step is outside its supported range"))
        }
    }
}

extension RemoteKey {
    var displayName: String {
        switch self {
        case .power: "电源"
        case .center: "点击盘中心"
        case .tv: "TV / Home"
        default: rawValue
        }
    }
    var referenceBinding: KeyBinding {
        switch self {
        case .power: return KeyBinding(action: .screenOff, value: "F12", doubleClickEnabled: true, powerDoubleClickAction: .sleepDisplay)
        case .menu: return KeyBinding(action: .key, value: "Escape")
        case .tv: return KeyBinding(action: .key, value: "Return")
        case .playPause: return KeyBinding(action: .key, value: "Space")
        case .center: return KeyBinding(action: .click, value: "Return")
        case .touchUp: return KeyBinding(action: .key, value: "Up Arrow")
        case .touchDown: return KeyBinding(action: .key, value: "Down Arrow")
        case .touchLeft: return KeyBinding(action: .key, value: "Left Arrow")
        case .touchRight: return KeyBinding(action: .key, value: "Right Arrow")
        case .volumeUp: return KeyBinding(action: .key, value: "Volume Up")
        case .volumeDown: return KeyBinding(action: .key, value: "Volume Down")
        case .mute: return KeyBinding(action: .key, value: "Mute")
        case .voice:
            var result = KeyBinding(action: .key, value: "Fn", longPressEnabled: true, longPressAction: .key, longPressValue: "F1", doubleClickEnabled: true, doubleClickAction: .key, doubleClickValue: "Return")
            result.holdNoOutput = true
            return result
        case .siriHold: return KeyBinding(action: .none, value: "F1")
        case .ring: return KeyBinding(action: .scroll, value: "页面滚动")
        }
    }
}
