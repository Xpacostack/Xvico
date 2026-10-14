import AppKit

struct KeyboardOutput: Identifiable {
    let name: String
    let keyCode: UInt16?
    let systemCode: Int?
    var id: String { name }
    var primaryModifier: KeyboardModifier? {
        switch name {
        case "Fn": .function
        case "Left Command", "Right Command": .command
        case "Left Option", "Right Option": .option
        case "Left Control", "Right Control": .control
        case "Left Shift", "Right Shift": .shift
        default: nil
        }
    }
    static let all: [KeyboardOutput] = [
        .init(name: "Fn", keyCode: 63, systemCode: nil),
        .init(name: "Left Command", keyCode: 55, systemCode: nil),
        .init(name: "Right Command", keyCode: 54, systemCode: nil),
        .init(name: "Left Option", keyCode: 58, systemCode: nil),
        .init(name: "Right Option", keyCode: 61, systemCode: nil),
        .init(name: "Left Shift", keyCode: 56, systemCode: nil),
        .init(name: "Right Shift", keyCode: 60, systemCode: nil),
        .init(name: "Left Control", keyCode: 59, systemCode: nil),
        .init(name: "Right Control", keyCode: 62, systemCode: nil),
        .init(name: "Caps Lock", keyCode: 57, systemCode: nil),
        .init(name: "Up Arrow", keyCode: 126, systemCode: nil),
        .init(name: "Down Arrow", keyCode: 125, systemCode: nil),
        .init(name: "Left Arrow", keyCode: 123, systemCode: nil),
        .init(name: "Right Arrow", keyCode: 124, systemCode: nil),
        .init(name: "Return", keyCode: 36, systemCode: nil),
        .init(name: "Escape", keyCode: 53, systemCode: nil),
        .init(name: "Space", keyCode: 49, systemCode: nil),
        .init(name: "Tab", keyCode: 48, systemCode: nil),
        .init(name: "Delete", keyCode: 51, systemCode: nil),
        .init(name: "Forward Delete", keyCode: 117, systemCode: nil),
        .init(name: "Home", keyCode: 115, systemCode: nil),
        .init(name: "End", keyCode: 119, systemCode: nil),
        .init(name: "Page Up", keyCode: 116, systemCode: nil),
        .init(name: "Page Down", keyCode: 121, systemCode: nil),
        .init(name: "-", keyCode: 27, systemCode: nil),
        .init(name: "=", keyCode: 24, systemCode: nil),
        .init(name: "[", keyCode: 33, systemCode: nil),
        .init(name: "]", keyCode: 30, systemCode: nil),
        .init(name: ";", keyCode: 41, systemCode: nil),
        .init(name: "'", keyCode: 39, systemCode: nil),
        .init(name: ",", keyCode: 43, systemCode: nil),
        .init(name: ".", keyCode: 47, systemCode: nil),
        .init(name: "/", keyCode: 44, systemCode: nil),
        .init(name: "\\", keyCode: 42, systemCode: nil),
        .init(name: "`", keyCode: 50, systemCode: nil),
        .init(name: "A", keyCode: 0, systemCode: nil),
        .init(name: "B", keyCode: 11, systemCode: nil),
        .init(name: "C", keyCode: 8, systemCode: nil),
        .init(name: "D", keyCode: 2, systemCode: nil),
        .init(name: "E", keyCode: 14, systemCode: nil),
        .init(name: "F", keyCode: 3, systemCode: nil),
        .init(name: "G", keyCode: 5, systemCode: nil),
        .init(name: "H", keyCode: 4, systemCode: nil),
        .init(name: "I", keyCode: 34, systemCode: nil),
        .init(name: "J", keyCode: 38, systemCode: nil),
        .init(name: "K", keyCode: 40, systemCode: nil),
        .init(name: "L", keyCode: 37, systemCode: nil),
        .init(name: "M", keyCode: 46, systemCode: nil),
        .init(name: "N", keyCode: 45, systemCode: nil),
        .init(name: "O", keyCode: 31, systemCode: nil),
        .init(name: "P", keyCode: 35, systemCode: nil),
        .init(name: "Q", keyCode: 12, systemCode: nil),
        .init(name: "R", keyCode: 15, systemCode: nil),
        .init(name: "S", keyCode: 1, systemCode: nil),
        .init(name: "T", keyCode: 17, systemCode: nil),
        .init(name: "U", keyCode: 32, systemCode: nil),
        .init(name: "V", keyCode: 9, systemCode: nil),
        .init(name: "W", keyCode: 13, systemCode: nil),
        .init(name: "X", keyCode: 7, systemCode: nil),
        .init(name: "Y", keyCode: 16, systemCode: nil),
        .init(name: "Z", keyCode: 6, systemCode: nil),
        .init(name: "0", keyCode: 29, systemCode: nil),
        .init(name: "1", keyCode: 18, systemCode: nil),
        .init(name: "2", keyCode: 19, systemCode: nil),
        .init(name: "3", keyCode: 20, systemCode: nil),
        .init(name: "4", keyCode: 21, systemCode: nil),
        .init(name: "5", keyCode: 23, systemCode: nil),
        .init(name: "6", keyCode: 22, systemCode: nil),
        .init(name: "7", keyCode: 26, systemCode: nil),
        .init(name: "8", keyCode: 28, systemCode: nil),
        .init(name: "9", keyCode: 25, systemCode: nil),
        .init(name: "F1", keyCode: 122, systemCode: nil),
        .init(name: "F2", keyCode: 120, systemCode: nil),
        .init(name: "F3", keyCode: 99, systemCode: nil),
        .init(name: "F4", keyCode: 118, systemCode: nil),
        .init(name: "F5", keyCode: 96, systemCode: nil),
        .init(name: "F6", keyCode: 97, systemCode: nil),
        .init(name: "F7", keyCode: 98, systemCode: nil),
        .init(name: "F8", keyCode: 100, systemCode: nil),
        .init(name: "F9", keyCode: 101, systemCode: nil),
        .init(name: "F10", keyCode: 109, systemCode: nil),
        .init(name: "F11", keyCode: 103, systemCode: nil),
        .init(name: "F12", keyCode: 111, systemCode: nil),
        .init(name: "F13", keyCode: 105, systemCode: nil),
        .init(name: "F14", keyCode: 107, systemCode: nil),
        .init(name: "F15", keyCode: 113, systemCode: nil),
        .init(name: "F16", keyCode: 106, systemCode: nil),
        .init(name: "F17", keyCode: 64, systemCode: nil),
        .init(name: "F18", keyCode: 79, systemCode: nil),
        .init(name: "F19", keyCode: 80, systemCode: nil),
        .init(name: "F20", keyCode: 90, systemCode: nil),
        .init(name: "Keypad Clear", keyCode: 71, systemCode: nil),
        .init(name: "Keypad =", keyCode: 81, systemCode: nil),
        .init(name: "Keypad /", keyCode: 75, systemCode: nil),
        .init(name: "Keypad *", keyCode: 67, systemCode: nil),
        .init(name: "Keypad -", keyCode: 78, systemCode: nil),
        .init(name: "Keypad +", keyCode: 69, systemCode: nil),
        .init(name: "Keypad Enter", keyCode: 76, systemCode: nil),
        .init(name: "Keypad .", keyCode: 65, systemCode: nil),
        .init(name: "Keypad 0", keyCode: 82, systemCode: nil),
        .init(name: "Keypad 1", keyCode: 83, systemCode: nil),
        .init(name: "Keypad 2", keyCode: 84, systemCode: nil),
        .init(name: "Keypad 3", keyCode: 85, systemCode: nil),
        .init(name: "Keypad 4", keyCode: 86, systemCode: nil),
        .init(name: "Keypad 5", keyCode: 87, systemCode: nil),
        .init(name: "Keypad 6", keyCode: 88, systemCode: nil),
        .init(name: "Keypad 7", keyCode: 89, systemCode: nil),
        .init(name: "Keypad 8", keyCode: 91, systemCode: nil),
        .init(name: "Keypad 9", keyCode: 92, systemCode: nil),
        .init(name: "Help", keyCode: 114, systemCode: nil),
        .init(name: "Volume Up", keyCode: nil, systemCode: 0),
        .init(name: "Volume Down", keyCode: nil, systemCode: 1),
        .init(name: "Mute", keyCode: nil, systemCode: 7),
        .init(name: "Brightness Up", keyCode: nil, systemCode: 2),
        .init(name: "Brightness Down", keyCode: nil, systemCode: 3),
        .init(name: "Play / Pause (Media)", keyCode: nil, systemCode: 16),
        .init(name: "Next Track", keyCode: nil, systemCode: 17),
        .init(name: "Previous Track", keyCode: nil, systemCode: 18),
        .init(name: "Keyboard Brightness Up", keyCode: nil, systemCode: 21),
        .init(name: "Keyboard Brightness Down", keyCode: nil, systemCode: 22),
        .init(name: "Keyboard Brightness Toggle", keyCode: nil, systemCode: 23),
        .init(name: "Eject", keyCode: nil, systemCode: 14),
    ]
    static func named(_ name: String) -> KeyboardOutput? { all.first { $0.name == name } }
    var symbol: String {
        switch name {
        case "Fn": "fn"
        case "Escape": "⎋"
        case "Return": "↩"
        case "Space": "␣"
        case "Tab": "⇥"
        case "Up Arrow": "↑"
        case "Down Arrow": "↓"
        case "Left Arrow": "←"
        case "Right Arrow": "→"
        default: name
        }
    }
}

extension KeyboardModifier {
    var symbol: String {
        switch self {
        case .command: "⌘"
        case .option: "⌥"
        case .control: "⌃"
        case .shift: "⇧"
        case .function: "fn"
        }
    }
    var flag: CGEventFlags {
        switch self {
        case .command: .maskCommand
        case .option: .maskAlternate
        case .control: .maskControl
        case .shift: .maskShift
        case .function: .maskSecondaryFn
        }
    }
    func code(right: Bool) -> UInt16 {
        switch self {
        case .command: right ? 54 : 55
        case .option: right ? 61 : 58
        case .control: right ? 62 : 59
        case .shift: right ? 60 : 56
        case .function: 63
        }
    }
}

extension KeyBinding {
    var normalizedKeyboard: KeyBinding {
        var result = self
        for (glyph, modifier) in [("⌘", KeyboardModifier.command), ("⌥", .option), ("⌃", .control), ("⇧", .shift)] {
            if result.value.contains(glyph) {
                result.modifiers.insert(modifier)
                result.value = result.value.replacingOccurrences(of: glyph, with: "")
            }
        }
        let aliases = ["↩": "Return", "⇥": "Tab", "⎋": "Escape", "␣": "Space", "←": "Left Arrow", "→": "Right Arrow", "↑": "Up Arrow", "↓": "Down Arrow", "+": "=", " ": "Space"]
        if result.value == "+" { result.modifiers.insert(.shift) }
        result.value = aliases[result.value] ?? result.value
        if KeyboardOutput.named(result.value) == nil { result.value = result.value.uppercased() }
        return result
    }
}
