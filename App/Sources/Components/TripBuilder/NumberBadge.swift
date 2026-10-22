import SwiftUI
import IterDesign

/// The round stop number: the same coral disc as the stop's pin on the map, or a neutral one for places that are not
/// the plan's own stops.
struct NumberBadge: View {
    enum Style { case accent, neutral }

    let number: Int
    var style: Style = .accent
    var size: CGFloat = 20

    var body: some View {
        Text(number, format: .number)
            .font(BuilderType.bodyStrong)
            .monospacedDigit()
            .foregroundStyle(style == .accent ? IterColor.onAccent : IterColor.textPrimary.color)
            .frame(width: size, height: size)
            .background(fill, in: Circle())
            .accessibilityHidden(true)
    }

    private var fill: AnyShapeStyle {
        style == .accent ? AnyShapeStyle(IterColor.brandDot) : AnyShapeStyle(.quaternary)
    }
}

#Preview("Number badge, light") { NumberBadgePreview().preferredColorScheme(.light) }
#Preview("Number badge, dark") { NumberBadgePreview().preferredColorScheme(.dark) }

private struct NumberBadgePreview: View {
    var body: some View {
        HStack(spacing: IterSpace.lg) {
            NumberBadge(number: 1)
            NumberBadge(number: 12)
            NumberBadge(number: 3, style: .neutral)
        }
        .padding(IterSpace.xl)
        .background(IterColor.backgroundWindow)
    }
}
