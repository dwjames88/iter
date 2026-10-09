import SwiftUI
import IterDesign

extension View {
    /// A place card's action, as Maps lays out its action row: the icon over a short title, an equal share of the row.
    /// The row sits in the card's content, so it isn't Liquid Glass (the HIG keeps glass out of the content layer): the
    /// main action is the prominent bordered style in the accent, as Maps' Plan; the rest are bordered in the accent, as
    /// Maps' Call and Website.
    func placeAction(isProminent: Bool = false) -> some View {
        modifier(PlaceAction(isProminent: isProminent))
    }
}

private struct PlaceAction: ViewModifier {
    let isProminent: Bool

    func body(content: Content) -> some View {
        #if os(macOS)
        // The Mac's bordered styles pad and round to their own control metrics (and a menu ignores the prominent fill),
        // so the Mac draws Maps' tiles with one shape and one height for the whole row.
        content.labelStyle(PlaceActionLabelStyle()).buttonStyle(MacTileStyle(isProminent: isProminent))
        #else
        if isProminent {
            // The one main action carries the accent, as Maps' Plan does.
            styled(content).buttonStyle(.borderedProminent).tint(IterColor.accent)
        } else {
            // As Maps' Call and Website: the accent on a faint accent fill.
            styled(content).buttonStyle(.bordered).tint(IterColor.accent)
        }
        #endif
    }

    private func styled(_ content: Content) -> some View {
        content
            .labelStyle(PlaceActionLabelStyle())
            .buttonSizing(.flexible)
            .buttonBorderShape(.roundedRectangle(radius: PlaceActionMetrics.cornerRadius))
            // The label sets the height (52 pt, a 44 pt hit region and more); the regular size keeps the side insets
            // narrow enough for four actions across an iPhone.
            .controlSize(.regular)
    }
}

#if os(macOS)
/// Maps' action tile on the Mac: the main action filled with the accent and white content; the rest the accent on a
/// faint accent fill (Maps' Call and Website). Every tile shares one shape and height.
private struct MacTileStyle: ButtonStyle {
    let isProminent: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: PlaceActionMetrics.cornerRadius, style: .continuous)
        configuration.label
            .foregroundStyle(isProminent ? AnyShapeStyle(.white) : AnyShapeStyle(IterColor.accentText))
            .frame(maxWidth: .infinity, minHeight: PlaceActionMetrics.height)
            .background(isProminent ? IterColor.accent : IterColor.accent.opacity(0.14), in: shape)
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.75 : (isEnabled ? 1 : 0.5))
    }
}
#endif

/// Measured from Maps' place card action row (Plan, Call, Website).
enum PlaceActionMetrics {
    #if os(macOS)
    static let height: CGFloat = 39
    static let cornerRadius: CGFloat = 15
    static let glyph: CGFloat = 13
    static let title = Font.system(size: 11, weight: .semibold)
    #else
    static let height: CGFloat = 52
    static let cornerRadius: CGFloat = 14
    static let glyph: CGFloat = 17
    static let title = Font.caption.weight(.semibold)
    #endif
}

private struct PlaceActionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 2) {
            configuration.icon.font(.system(size: PlaceActionMetrics.glyph, weight: .semibold))
                .imageScale(.medium)
            configuration.title.font(PlaceActionMetrics.title).lineLimit(1).minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, minHeight: PlaceActionMetrics.height)
    }
}
