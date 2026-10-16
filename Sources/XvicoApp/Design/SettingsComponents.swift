import SwiftUI

/// Stable reading surfaces stay opaque; optical effects belong to floating controls.
struct XvicoSettingsCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content.padding(XvicoLayout.cardInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(XvicoTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.055), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
    }
}

struct XvicoSectionHeading<Trailing: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder let trailing: Trailing
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                XvicoLocalizedText(title).font(.system(size: 16, weight: .semibold))
                if let detail {
                    XvicoLocalizedText(detail).font(XvicoTypography.caption)
                        .foregroundStyle(XvicoTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

struct XvicoStatusBadge: View {
    let title: String
    let symbol: String
    var color: Color = .secondary
    var body: some View {
        XvicoLocalizedLabel(title, systemImage: symbol)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(color.opacity(0.09), in: Capsule())
            .fixedSize()
    }
}

/// One hit area and focus ring for both icon-only and text toolbar actions.
struct XvicoToolbarButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var prominent = false
    var destructive = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12).frame(minWidth: 40, minHeight: 40)
            .foregroundStyle(destructive ? Color.red : prominent ? XvicoTheme.optionForeground(selected: true, scheme: scheme) : .primary)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(prominent ? XvicoTheme.selectionTint(scheme) : Color.primary.opacity(0.035))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(prominent ? XvicoTheme.selectionOutline(scheme) : Color.primary.opacity(0.09), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
            .xvicoPointerLight(cornerRadius: 12, active: true)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(!enabled ? 0.4 : configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content
    var body: some View {
        XvicoSettingsCard {
            VStack(alignment: .leading, spacing: 16) {
                Label(LocalizedStringKey(title), systemImage: symbol)
                    .font(XvicoTypography.sectionTitle)
                content
            }.font(XvicoTypography.body)
        }
    }
}
