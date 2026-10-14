import SwiftUI
import AppKit

enum XvicoTheme {
    static let card = Color(nsColor: NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark ? NSColor(red: 0.105, green: 0.145, blue: 0.20, alpha: 1)
                    : NSColor.white
    })
    static let border = Color(nsColor: .separatorColor)
    static let iconTile = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.14, green: 0.19, blue: 0.26, alpha: 1)
            : NSColor(red: 0.90, green: 0.94, blue: 0.98, alpha: 1)
    })
    static let secondaryText = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.74, green: 0.80, blue: 0.87, alpha: 1)
            : NSColor(red: 0.29, green: 0.34, blue: 0.41, alpha: 1)
    })
    static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.045, green: 0.065, blue: 0.10)
                        : Color(red: 0.965, green: 0.978, blue: 0.995)
    }
    static func panelSurface(_ scheme: ColorScheme, floating: Bool = false) -> Color {
        scheme == .dark ? Color(red: 0.105, green: 0.145, blue: 0.20).opacity(floating ? 0.76 : 0.86)
                        : Color.white.opacity(floating ? 0.75 : 0.88)
    }
    static func sidebarSurface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.065, green: 0.09, blue: 0.135).opacity(0.94)
                        : Color(red: 0.91, green: 0.95, blue: 0.99).opacity(0.92)
    }
    static func selectionTint(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.18, green: 0.40, blue: 0.48).opacity(0.60)
                        : Color.accentColor.opacity(0.22)
    }
    static func selectionOutline(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.48, green: 0.76, blue: 0.83).opacity(0.85)
                        : Color.accentColor.opacity(0.42)
    }
    static let darkSelectionSurface = Color(red: 0.16, green: 0.31, blue: 0.38).opacity(0.78)
    static func optionForeground(selected: Bool, scheme: ColorScheme) -> Color {
        if selected { return scheme == .dark ? .primary : .accentColor }
        return scheme == .dark ? .primary.opacity(0.85) : .primary
    }
}

enum XvicoTypography {
    static let sectionTitle = Font.system(size: 14, weight: .semibold)
    static let body = Font.system(size: 12)
    static let caption = Font.system(size: 11)
}

enum XvicoLayout {
    static let sidebarWidth: CGFloat = 172
    static let contentWidth: CGFloat = 720
    static let pageInset: CGFloat = 22
    static let cardInset: CGFloat = 18
    static let sectionSpacing: CGFloat = 16
    static let rowSpacing: CGFloat = 12
    static func keyboardPickerWidth(for name: String) -> CGFloat {
        let textWidth = (name as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width
        return max(112, ceil(textWidth + 48))
    }
}

enum XvicoNavigation {
    // Restore the Shortcuts entry by changing this flag to true.
    static let showsShortcuts = false
    static var sidebarPages: [XvicoPage] {
        [.mapping, .scenes, .commands, .voice, .device].filter { showsShortcuts || $0 != .commands }
    }
}

struct XvicoWindowBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            XvicoTheme.canvas(colorScheme)
            if !reduceTransparency {
                RadialGradient(colors: [.blue.opacity(colorScheme == .dark ? 0.15 : 0.08), .clear],
                               center: .topTrailing, startRadius: 0, endRadius: 760)
                RadialGradient(colors: [.cyan.opacity(colorScheme == .dark ? 0.09 : 0.045), .clear],
                               center: .bottomLeading, startRadius: 0, endRadius: 580)
                RadialGradient(colors: [.indigo.opacity(colorScheme == .dark ? 0.08 : 0.035), .clear],
                               center: .bottomTrailing, startRadius: 0, endRadius: 540)
            }
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct XvicoGlassPanel: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let cornerRadius: CGFloat
    let tint: Color?
    let interactive: Bool
    let bordered: Bool
    let floating: Bool

    @ViewBuilder func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
            if reduceTransparency {
                content.background {
                    shape.fill(XvicoTheme.card).overlay { shape.fill(tint ?? .clear) }
                }
            } else {
                translucentSurface(content, shape: shape)
            }
        }
        .overlay {
            if !reduceTransparency && bordered {
                shape.fill(LinearGradient(
                    colors: [.white.opacity(colorScheme == .dark ? 0.025 : 0.07), .clear,
                             .white.opacity(colorScheme == .dark ? 0.01 : 0.02)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                    .allowsHitTesting(false)
            }
        }
        .overlay { outline(shape) }
        .shadow(color: .black.opacity(bordered ? (floating ? (colorScheme == .dark ? 0.32 : 0.17) : 0.055) : 0),
                radius: floating ? 24 : 9, x: 0, y: floating ? 14 : 3)
        .shadow(color: .black.opacity(bordered && floating ? 0.08 : 0), radius: 3, x: 0, y: 1)
    }

    @ViewBuilder private func translucentSurface(_ content: Content, shape: RoundedRectangle) -> some View {
        // Runtime availability alone still type-checks glassEffect against an
        // older SDK. Keep macOS 13+ source builds working with older Xcodes.
        #if compiler(>=6.2) && !XVICO_LEGACY_MATERIAL
        if #available(macOS 26.0, *) {
            content.background(XvicoTheme.panelSurface(colorScheme, floating: floating), in: shape)
                .glassEffect(.clear.tint(tint).interactive(interactive), in: shape)
        } else {
            materialSurface(content, shape: shape)
        }
        #else
        materialSurface(content, shape: shape)
        #endif
    }

    private func materialSurface(_ content: Content, shape: RoundedRectangle) -> some View {
        content.background(XvicoTheme.panelSurface(colorScheme, floating: floating), in: shape)
            .background(.ultraThinMaterial, in: shape)
            .background(tint?.opacity(0.4) ?? .clear, in: shape)
    }

    @ViewBuilder private func outline(_ shape: RoundedRectangle) -> some View {
        if bordered {
            ZStack {
                shape.strokeBorder(LinearGradient(
                    colors: [.white.opacity(colorScheme == .dark ? (floating ? 0.50 : 0.29) : 0.98),
                             .white.opacity(colorScheme == .dark ? 0.12 : 0.30),
                             Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.18),
                             .white.opacity(colorScheme == .dark ? 0.32 : 0.72)],
                    startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: floating ? 1.4 : 1)
                shape.inset(by: 2).strokeBorder(.white.opacity(colorScheme == .dark ? 0.08 : 0.32), lineWidth: 0.5)
            }.allowsHitTesting(false)
        }
    }
}

extension View {
    func xvicoGlassPanel(cornerRadius: CGFloat = 16, tint: Color? = nil,
                         interactive: Bool = false, bordered: Bool = true, floating: Bool = false) -> some View {
        modifier(XvicoGlassPanel(cornerRadius: cornerRadius, tint: tint,
                                interactive: interactive, bordered: bordered, floating: floating))
    }
}

struct XvicoGlassButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    var selected = false
    var tint: Color? = nil
    var cornerRadius: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(selected && colorScheme == .dark ? XvicoTheme.darkSelectionSurface : .clear)
                    .xvicoGlassPanel(cornerRadius: cornerRadius,
                        tint: tint ?? (selected ? XvicoTheme.selectionTint(colorScheme) : nil), interactive: true)
            }
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(XvicoTheme.selectionOutline(colorScheme), lineWidth: colorScheme == .dark ? 1.5 : 1)
                        .allowsHitTesting(false)
                }
            }
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct XvicoOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var symbol: String? = nil
    var id: Value { value }
}

struct XvicoOptionPicker<Value: Hashable>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    @Binding var selection: Value
    let options: [XvicoOption<Value>]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options) { option in
                Button { selection = option.value } label: {
                    HStack(spacing: 7) {
                        if let symbol = option.symbol { Image(systemName: symbol).font(.system(size: 15, weight: .medium)) }
                        Text(LocalizedStringKey(option.title)).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 12))
                            .opacity(selection == option.value ? 1 : 0)
                    }.frame(maxWidth: .infinity).frame(minHeight: 42)
                        .padding(.horizontal, 8)
                        .foregroundStyle(XvicoTheme.optionForeground(selected: selection == option.value, scheme: colorScheme))
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }.buttonStyle(XvicoGlassButtonStyle(selected: selection == option.value, cornerRadius: 12))
                    .accessibilityLabel(LocalizedStringKey(option.title))
                    .accessibilityAddTraits(selection == option.value ? .isSelected : [])
            }
        }.padding(5)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(LocalizedStringKey(title))
    }
}

struct XvicoActionButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14).frame(minHeight: 36)
            .foregroundStyle(prominent && colorScheme != .dark ? Color.accentColor : Color.primary)
            .xvicoGlassPanel(cornerRadius: 12, tint: prominent ? XvicoTheme.selectionTint(colorScheme) : nil, interactive: true)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

enum XvicoArtwork {
    static let developerQRCode: NSImage? = {
        guard let url = Bundle.module.url(forResource: "DeveloperWeChatQR", withExtension: "jpg") else { return nil }
        return NSImage(contentsOf: url)
    }()
}

enum XvicoAppearance: String, CaseIterable, Identifiable {
    case system = "跟随系统", light = "浅色", dark = "深色"
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
