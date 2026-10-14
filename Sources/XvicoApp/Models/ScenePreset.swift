import Foundation

struct ScenePreset: Identifiable {
    let id: String
    let name: String
    let detail: String
    let symbol: String
    let suggestedBundleID: String
    var tags: [String] {
        switch id {
        case "video": ["视频", "浏览器"]
        case "zoom": ["会议", "社群"]
        case "presentation": ["演示", "办公"]
        case "reading": ["阅读", "浏览"]
        case "music": ["音乐", "媒体"]
        default: ["Codex", "开发"]
        }
    }

    static let all: [ScenePreset] = [
        .init(id: "video", name: "网页视频 · 沙发模式", detail: "播放暂停、方向控制和退出全屏，适合浏览器与播放器。", symbol: "play.rectangle.fill", suggestedBundleID: "com.apple.Safari"),
        .init(id: "zoom", name: "Zoom · 会议讨论", detail: "遥控静音、摄像头和聊天面板，适合会议与社群讨论。", symbol: "person.3.fill", suggestedBundleID: "us.zoom.xos"),
        .init(id: "presentation", name: "演示与提案", detail: "翻页、开始播放和退出演示，适合 Keynote 与 PowerPoint。", symbol: "rectangle.on.rectangle.angled", suggestedBundleID: "com.apple.iWork.Keynote"),
        .init(id: "reading", name: "阅读与长页面", detail: "连续滚动、整页翻动和返回，适合文档、网页与电子书。", symbol: "book.pages.fill", suggestedBundleID: "com.apple.Preview"),
        .init(id: "music", name: "音乐控制", detail: "使用系统媒体键控制播放、切歌和音量，不依赖前台播放器。", symbol: "music.note", suggestedBundleID: "com.apple.Music"),
        .init(id: "codex", name: "Codex 多任务", detail: "外圈切换第 1–9 个任务，点击盘负责方向、确认和返回。", symbol: "terminal.fill", suggestedBundleID: "com.openai.codex")
    ]

    var bindings: [String: KeyBinding] {
        var result: [String: KeyBinding] = [:]
        func key(_ key: RemoteKey, _ value: String, _ flags: Set<KeyboardModifier> = []) {
            result[key.rawValue] = KeyBinding(action: .key, value: value, modifiers: flags)
        }
        switch id {
        case "video", "codex": key(.center, "Return")
        case "zoom":
            key(.tv, "H", [.command, .shift])
            key(.mute, "A", [.command, .shift])
            key(.playPause, "V", [.command, .shift])
        case "presentation", "reading":
            key(.touchUp, "Page Up"); key(.touchDown, "Page Down")
        case "music":
            key(.mute, "Mute"); key(.playPause, "Play / Pause (Media)")
            key(.touchUp, "Volume Up"); key(.touchDown, "Volume Down")
            key(.touchLeft, "Previous Track"); key(.touchRight, "Next Track")
        default: break
        }
        return result
    }
}
