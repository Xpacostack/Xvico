import SwiftUI
import AppKit

enum XvicoTheme {
    static let card = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 28.0 / 255, alpha: 1) : .white
    })
    static let border = Color(nsColor: .separatorColor)
    static let iconTile = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 44.0 / 255, alpha: 1)
            : NSColor(red: 242.0 / 255, green: 242.0 / 255, blue: 247.0 / 255, alpha: 1)
    })
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .black : Color(red: 242.0 / 255, green: 242.0 / 255, blue: 247.0 / 255)
    }
    static func panelSurface(_ scheme: ColorScheme, floating: Bool = false) -> Color {
        (scheme == .dark ? Color(white: 28.0 / 255) : .white).opacity(floating ? 0.75 : 0.90)
    }
    static func sidebarSurface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.92) : canvas(scheme).opacity(0.92)
    }
    static func selectionTint(_ scheme: ColorScheme) -> Color {
        Color.accentColor.opacity(scheme == .dark ? 0.15 : 0.10)
    }
    static func selectionOutline(_ scheme: ColorScheme) -> Color {
        Color.accentColor.opacity(scheme == .dark ? 0.70 : 0.45)
    }
    static let darkSelectionSurface = Color.accentColor.opacity(0.16)
    static func optionForeground(selected: Bool, scheme: ColorScheme) -> Color {
        selected ? (scheme == .dark ? Color(red: 0.38, green: 0.70, blue: 1) : .accentColor) : .primary
    }
}

enum XvicoTypography {
    static let sectionTitle = Font.system(size: 14, weight: .semibold)
    static let body = Font.system(size: 12)
    static let caption = Font.system(size: 11)
}

struct XvicoSwitchStyle: ToggleStyle {
    @Environment(\.controlSize) private var size
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var dimensions: CGSize {
        switch size {
        case .mini: CGSize(width: 28, height: 16)
        case .small: CGSize(width: 32, height: 18)
        default: CGSize(width: 38, height: 22)
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        LabeledContent {
            Button { configuration.isOn.toggle() } label: {
                Capsule()
                    .fill(configuration.isOn ? Color(red: 0.20, green: 0.78, blue: 0.35) : Color.secondary.opacity(0.35))
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(.white)
                            .shadow(color: .black.opacity(0.16), radius: 1, y: 1)
                            .frame(width: dimensions.height - 4, height: dimensions.height - 4)
                            .padding(2)
                    }
                    .frame(width: dimensions.width, height: dimensions.height)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(enabled ? 1 : 0.40)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: configuration.isOn)
        } label: {
            configuration.label
        }
        // Preserve native switch accessibility, including its state/actions,
        // while keeping the enabled color independent of macOS accent/focus.
        .accessibilityRepresentation { Toggle(configuration).toggleStyle(.switch) }
    }
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
    var body: some View {
        XvicoTheme.canvas(colorScheme)
            .ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct XvicoGlassPanel: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.xvicoImmersiveGlass) private var immersive
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
        .shadow(color: .black.opacity(immersive && floating ? 0 : bordered ? (floating ? (colorScheme == .dark ? 0.32 : 0.17) : 0.055) : 0),
                radius: floating ? 24 : 9, x: 0, y: floating ? 14 : 3)
        .shadow(color: .black.opacity(bordered && floating && !immersive ? 0.08 : 0), radius: 3, x: 0, y: 1)
        .xvicoPointerLight(cornerRadius: cornerRadius, active: immersive && (interactive || floating), subtle: floating)
    }

    @ViewBuilder private func translucentSurface(_ content: Content, shape: RoundedRectangle) -> some View {
        // Runtime availability alone still type-checks glassEffect against an
        // older SDK. Keep macOS 13+ source builds working with older Xcodes.
        #if compiler(>=6.2) && !XVICO_LEGACY_MATERIAL
        if #available(macOS 26.0, *) {
            if immersive {
                // Glass samples only the background. Keep every label above
                // the optical layer rather than inside a sampling container.
                content.background {
                    ZStack {
                        if floating { XvicoFrostedBackdrop(cornerRadius: cornerRadius) }
                        XvicoNativeClearGlass(cornerRadius: cornerRadius, tint: tint, interactive: interactive,
                                             surfaceOpacity: floating ? (colorScheme == .dark ? 0.34 : 0.24) : 1)
                    }
                        .shadow(color: .black.opacity(floating ? (colorScheme == .dark ? 0.24 : 0.11) : 0),
                                radius: 18, x: 0, y: 10)
                        .allowsHitTesting(false)
                }
            } else {
                content.background(XvicoTheme.panelSurface(colorScheme, floating: floating), in: shape)
                    .glassEffect(.clear.tint(tint).interactive(interactive), in: shape)
            }
        } else {
            materialSurface(content, shape: shape)
        }
        #else
        materialSurface(content, shape: shape)
        #endif
    }

    private func materialSurface(_ content: Content, shape: RoundedRectangle) -> some View {
        content.background(XvicoTheme.panelSurface(colorScheme, floating: floating).opacity(immersive ? 0.30 : 1), in: shape)
            .background(.ultraThinMaterial, in: shape)
            .background(tint?.opacity(0.4) ?? .clear, in: shape)
    }

    @ViewBuilder private func outline(_ shape: RoundedRectangle) -> some View {
        if bordered {
            if immersive {
                shape.strokeBorder(LinearGradient(
                    colors: [.white.opacity(colorScheme == .dark ? 0.50 : 0.90),
                             .white.opacity(0.10), Color.primary.opacity(0.16), .white.opacity(0.42)],
                    startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75)
                    .allowsHitTesting(false)
            } else { ZStack {
                shape.strokeBorder(LinearGradient(
                    colors: [.white.opacity(colorScheme == .dark ? (floating ? 0.50 : 0.29) : 0.98),
                             .white.opacity(colorScheme == .dark ? 0.12 : 0.30),
                             Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.18),
                             .white.opacity(colorScheme == .dark ? 0.32 : 0.72)],
                    startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: floating ? 1.4 : 1)
                shape.inset(by: 2).strokeBorder(.white.opacity(colorScheme == .dark ? 0.08 : 0.32), lineWidth: 0.5)
            }.allowsHitTesting(false) }
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

/// The foreground is a plain button. Native glass samples only its backing,
/// so the window accent cannot turn every navigation item into a solid fill.
struct XvicoGlassButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var selected = false
    var tint: Color? = nil
    var cornerRadius: CGFloat = 14

    var raised = false

    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if raised {
            XvicoRaisedGlassButtonStyle(selected: selected, cornerRadius: cornerRadius).makeBody(configuration: configuration)
        } else { flatBody(configuration) }
    }

    @ViewBuilder private func flatBody(_ configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        configuration.label
            .background { opticalSurface(shape).allowsHitTesting(false) }
            .overlay {
                shape.strokeBorder(LinearGradient(
                    colors: [.white.opacity(colorScheme == .dark ? 0.52 : 0.95),
                             .white.opacity(0.06), Color.primary.opacity(0.14), .white.opacity(0.30)],
                    startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.85)
                    .allowsHitTesting(false)
                if selected {
                    shape.strokeBorder(XvicoTheme.selectionOutline(colorScheme), lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
            .xvicoPointerLight(cornerRadius: cornerRadius, active: true)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.83 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.80), value: configuration.isPressed)
            .contentShape(shape)
    }

    @ViewBuilder private func opticalSurface(_ shape: RoundedRectangle) -> some View {
        if reduceTransparency {
            shape.fill(XvicoTheme.card)
        } else {
            #if compiler(>=6.2) && !XVICO_LEGACY_MATERIAL
            if #available(macOS 26.0, *) {
                shape.fill(.clear).glassEffect(.clear.interactive(), in: shape)
                    .overlay { lensRim(shape) }
            } else { shape.fill(.ultraThinMaterial).overlay { lensRim(shape) } }
            #else
            shape.fill(.ultraThinMaterial).overlay { lensRim(shape) }
            #endif
        }
    }

    private func lensRim(_ shape: RoundedRectangle) -> some View {
        ZStack {
            shape.fill(LinearGradient(
                colors: [.white.opacity(colorScheme == .dark ? 0.11 : 0.40), .clear,
                         .white.opacity(colorScheme == .dark ? 0.025 : 0.10)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            shape.inset(by: 2).strokeBorder(.white.opacity(colorScheme == .dark ? 0.09 : 0.40), lineWidth: 0.5)
        }
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
                        Text(LocalizedStringKey(option.title)).font(.system(size: 12, weight: .semibold)).lineLimit(2).multilineTextAlignment(.center)
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 12))
                            .opacity(selection == option.value ? 1 : 0)
                    }.frame(maxWidth: .infinity).frame(minHeight: 42)
                        .padding(.horizontal, 8)
                        .foregroundStyle(XvicoTheme.optionForeground(selected: selection == option.value, scheme: colorScheme))
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }.buttonStyle(XvicoToolbarButtonStyle(prominent: selection == option.value))
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
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        XvicoToolbarButtonStyle(prominent: prominent).makeBody(configuration: configuration)
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
