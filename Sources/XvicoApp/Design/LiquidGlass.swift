import SwiftUI
import AppKit

// Floating controls opt into background-only glass sampling. Reading cards
// retain a stable opaque surface for legibility.
private struct XvicoImmersiveGlassKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var xvicoImmersiveGlass: Bool {
        get { self[XvicoImmersiveGlassKey.self] }
        set { self[XvicoImmersiveGlassKey.self] = newValue }
    }
}

/// Samples only content within Xvico's window. The material softens detail;
/// its own alpha is separate from foreground text and controls.
struct XvicoFrostedBackdrop: NSViewRepresentable {
    @Environment(\.colorScheme) private var scheme
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .withinWindow
        view.state = .active
        view.wantsLayer = true
        configure(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) { configure(view) }

    private func configure(_ view: NSVisualEffectView) {
        view.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        view.alphaValue = scheme == .dark ? 0.42 : 0.30
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
    }
}

#if compiler(>=6.2) && !XVICO_LEGACY_MATERIAL
@available(macOS 26.0, *)
struct XvicoNativeClearGlass: NSViewRepresentable {
    let cornerRadius: CGFloat
    let tint: Color?
    let interactive: Bool
    var surfaceOpacity: CGFloat = 1

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.style = .clear
        view.contentView = NSView()
        configure(view)
        return view
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) { configure(view) }

    private func configure(_ view: NSGlassEffectView) {
        view.cornerRadius = cornerRadius
        view.alphaValue = surfaceOpacity
        view.tintColor = tint.map { NSColor($0).withAlphaComponent(0.04) }
        #if compiler(>=6.4)
        if #available(macOS 27.0, *) { view.effectIsInteractive = interactive }
        #endif
    }
}
#endif

/// No frame timer, global event monitor or model updates. Pointer position
/// invalidates only this small optical layer. It never intercepts input.
private struct XvicoGlassPointerLight: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var location = CGPoint.zero
    @State private var hovering = false
    let cornerRadius: CGFloat
    let active: Bool
    let subtle: Bool

    func body(content: Content) -> some View {
        content.overlay {
            if active && enabled && !reduceTransparency {
                GeometryReader { proxy in
                    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    let center = reduceMotion ? UnitPoint.topLeading : UnitPoint(
                        x: min(1, max(0, location.x / max(1, proxy.size.width))),
                        y: min(1, max(0, location.y / max(1, proxy.size.height))))
                    let light = RadialGradient(
                        colors: [.white.opacity(scheme == .dark ? 0.65 : 0.95), .white.opacity(0.12), .clear],
                        center: center, startRadius: 0, endRadius: subtle ? 230 : 150)
                    ZStack {
                        if !subtle { shape.fill(light).opacity(scheme == .dark ? 0.13 : 0.22) }
                        shape.strokeBorder(light, lineWidth: subtle ? 1.2 : 1.5)
                    }
                    .opacity(hovering ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovering)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                guard active, enabled, !reduceTransparency else { return }
                if !reduceMotion { location = point }
                if !hovering { hovering = true }
            case .ended:
                hovering = false
            }
        }
        .onChange(of: active) { if !$0 { hovering = false } }
        .onChange(of: enabled) { if !$0 { hovering = false } }
        .onChange(of: reduceTransparency) { if $0 { hovering = false } }
        .onDisappear { hovering = false }
    }
}

extension View {
    func xvicoPointerLight(cornerRadius: CGFloat, active: Bool, subtle: Bool = false) -> some View {
        modifier(XvicoGlassPointerLight(cornerRadius: cornerRadius, active: active, subtle: subtle))
    }
}

// Controls inside a glass panel use an optical inset, not another native
// glass sampling layer. Stacked glass can blur the control's own labels.
struct XvicoInsetGlassButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var selected = false
    var cornerRadius: CGFloat = 11

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.08 : 0.32),
                                                   .white.opacity(scheme == .dark ? 0.025 : 0.10)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(selected ? XvicoTheme.selectionOutline(scheme) : Color.primary.opacity(0.10), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .xvicoPointerLight(cornerRadius: cornerRadius, active: true)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.85), value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

/// Shared raised sidebar material. Pointer state stays inside this
/// surface; neither the app model nor the remote scene redraws on mouse motion.
struct XvicoRaisedGlassButtonStyle: ButtonStyle {
    var selected = false
    var cornerRadius: CGFloat = 14
    var hitPadding: CGFloat = 0
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(XvicoRaisedGlassSurface(
            pressed: configuration.isPressed, selected: selected, cornerRadius: cornerRadius))
            .padding(hitPadding)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius + hitPadding, style: .continuous))
    }
}

extension View {
    /// A decorative raised face for a status card, without adding a button action.
    func xvicoRaisedGlassPanel(cornerRadius: CGFloat) -> some View {
        modifier(XvicoRaisedGlassSurface(pressed: false, selected: false, cornerRadius: cornerRadius))
    }
}

private struct XvicoRaisedGlassSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var hovering = false
    @State private var location = CGPoint.zero
    @State private var bounds = CGSize(width: 1, height: 1)
    let pressed: Bool
    let selected: Bool
    let cornerRadius: CGFloat

    private var pointer: UnitPoint {
        guard !reduceMotion else { return .center }
        return UnitPoint(x: min(1, max(0, location.x / max(1, bounds.width))),
                         y: min(1, max(0, location.y / max(1, bounds.height))))
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let lifted = hovering && enabled && !pressed
        content
            .background {
                lens(shape)
                    .overlay {
                        if !reduceTransparency {
                            specularLight(shape).opacity(lifted ? 1 : 0)
                        }
                    }
                    .shadow(color: .black.opacity(scheme == .dark ? 0.30 : 0.14),
                            radius: pressed ? 1 : lifted ? 7 : 4, x: 0, y: pressed ? 1 : lifted ? 5 : 3)
                    .shadow(color: .black.opacity(scheme == .dark ? 0.25 : 0.10),
                            radius: 0.6, x: 0, y: pressed ? 0 : 1.5)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            // Only the optical face and label move. The native backdrop stays
            // in window coordinates so perspective cannot corrupt its sampling.
            .rotation3DEffect(.degrees(!reduceMotion && lifted ? (pointer.y - 0.5) * -5 : 0), axis: (x: 1, y: 0, z: 0))
            .rotation3DEffect(.degrees(!reduceMotion && lifted ? (pointer.x - 0.5) * 5 : 0), axis: (x: 0, y: 1, z: 0))
            .scaleEffect(reduceMotion ? 1 : pressed ? 0.985 : lifted ? 1.018 : 1)
            .offset(y: reduceMotion ? 0 : pressed ? 1 : lifted ? -1.5 : 0)
            .background {
                GeometryReader { proxy in
                    material(shape)
                        .onAppear { bounds = proxy.size }
                        .onChange(of: proxy.size) { bounds = $0 }
                }
                .allowsHitTesting(false).accessibilityHidden(true)
            }
            .contentShape(shape)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82), value: pressed)
            .animation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.85), value: hovering)
            .onHover { inside in
                hovering = inside && enabled
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    guard enabled else { return }
                    if !reduceMotion { location = point }
                    if !hovering { hovering = true }
                case .ended: hovering = false
                }
            }
            .onChange(of: enabled) { if !$0 { hovering = false } }
            .onDisappear { hovering = false }
    }

    private func specularLight(_ shape: RoundedRectangle) -> some View {
        GeometryReader { proxy in
            ZStack {
                // A narrow moving reflection remains visible on white surfaces
                // without darkening the whole button or tinting it blue.
                Rectangle().fill(LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color(red: 0.66, green: 0.73, blue: 0.80).opacity(scheme == .dark ? 0.06 : 0.15), location: 0.26),
                    .init(color: .white.opacity(scheme == .dark ? 0.28 : 0.75), location: 0.50),
                    .init(color: .white.opacity(0.06), location: 0.74),
                    .init(color: .clear, location: 1)
                ], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(24, proxy.size.width * 0.32), height: proxy.size.height * 3)
                    .rotationEffect(.degrees(24))
                    .position(x: proxy.size.width * (0.12 + pointer.x * 0.76), y: proxy.size.height / 2)
                shape.strokeBorder(RadialGradient(
                    colors: [.white.opacity(scheme == .dark ? 0.95 : 1), .white.opacity(0.08), .clear],
                    center: pointer, startRadius: 0, endRadius: max(40, proxy.size.width * 0.75)), lineWidth: 1.5)
            }.clipShape(shape)
        }
    }

    private func lens(_ shape: RoundedRectangle) -> some View {
        ZStack {
            shape.fill(LinearGradient(stops: [
                .init(color: .white.opacity(scheme == .dark ? 0.18 : 0.82), location: 0),
                .init(color: .white.opacity(scheme == .dark ? 0.045 : 0.24), location: 0.38),
                .init(color: .clear, location: 0.58),
                .init(color: .black.opacity(scheme == .dark ? 0.13 : 0.075), location: 1)
            ], startPoint: .top, endPoint: .bottom))
            shape.strokeBorder(LinearGradient(stops: [
                .init(color: .white.opacity(scheme == .dark ? 0.72 : 1), location: 0),
                .init(color: .white.opacity(0.14), location: 0.40),
                .init(color: .black.opacity(scheme == .dark ? 0.50 : 0.22), location: 0.78),
                .init(color: .white.opacity(scheme == .dark ? 0.26 : 0.55), location: 1)
            ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.25)
            shape.inset(by: 2).strokeBorder(LinearGradient(
                colors: [.white.opacity(scheme == .dark ? 0.18 : 0.70), .clear, .black.opacity(0.07)],
                startPoint: .top, endPoint: .bottom), lineWidth: 0.75)
            if selected {
                shape.inset(by: 0.5).strokeBorder(XvicoTheme.selectionOutline(scheme), lineWidth: 1)
            }
        }
    }

    @ViewBuilder private func material(_ shape: RoundedRectangle) -> some View {
        if reduceTransparency { shape.fill(XvicoTheme.card) }
        else {
            #if compiler(>=6.2) && !XVICO_LEGACY_MATERIAL
            if #available(macOS 26.0, *) { shape.fill(.clear).glassEffect(.clear, in: shape) }
            else { shape.fill(.ultraThinMaterial) }
            #else
            shape.fill(.ultraThinMaterial)
            #endif
        }
    }
}
