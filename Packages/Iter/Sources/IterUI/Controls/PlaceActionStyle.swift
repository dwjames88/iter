import SwiftUI

extension View {
    /// A place card's action, as Maps lays out its action row: the icon over a short title, an equal share of the row.
    /// The row sits in the card's content, so it isn't Liquid Glass (the HIG keeps glass out of the content layer): the
    /// main action is filled with the accent, as Maps' Plan; the rest are the accent on a faint accent fill, as Maps'
    /// Call and Website. One style and shape per row. Figma part: place action.
    public func placeAction(isProminent: Bool = false) -> some View {
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
            styled(content).buttonStyle(.borderedProminent).tint(IterColor.accent)
        } else {
            styled(content).buttonStyle(.bordered).tint(IterColor.accent)
        }
        #endif
    }

    #if !os(macOS)
    private func styled(_ content: Content) -> some View {
        content
            .labelStyle(PlaceActionLabelStyle())
            .buttonSizing(.flexible)
            .buttonBorderShape(.roundedRectangle(radius: PlaceActionMetrics.cornerRadius))
            // The label sets the height (52 pt, a 44 pt hit region and more); the regular size keeps the side insets
            // narrow enough for four actions across an iPhone.
            .controlSize(.regular)
    }
    #endif
}

#if os(macOS)
/// Maps' action tile on the Mac: the main action filled with the accent and on-accent content; the rest the accent on a
/// faint accent fill. Every tile shares one shape and height.
private struct MacTileStyle: ButtonStyle {
    let isProminent: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: PlaceActionMetrics.cornerRadius, style: .continuous)
        configuration.label
            .foregroundStyle(isProminent ? IterColor.onAccent : IterColor.accentText)
            .frame(maxWidth: .infinity, minHeight: PlaceActionMetrics.height)
            .background(isProminent ? IterColor.accent : IterColor.accent.opacity(0.14), in: shape)
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.75 : (isEnabled ? 1 : 0.5))
    }
}
#endif

/// Measured from Maps' place card action row (Plan, Call, Website). Tiles are 50 pt (Mac) or 52 pt (iOS) tall; the
/// design range is 39 to 52 pt.
public enum PlaceActionMetrics {
    #if os(macOS)
    public static let height: CGFloat = 50
    public static let cornerRadius: CGFloat = 16
    public static let glyph: CGFloat = 14
    public static let title = Font.system(size: 11, weight: .semibold)
    public static let labelSpacing: CGFloat = 4
    public static let verticalPadding: CGFloat = 8
    /// Four tiles share the 340 pt column, so the label gets all but 4 pt of each side ("Open in Maps" must not truncate).
    public static let horizontalPadding: CGFloat = 4
    public static let minimumScale: CGFloat = 0.7
    #else
    public static let height: CGFloat = 52
    public static let cornerRadius: CGFloat = 14
    public static let glyph: CGFloat = 17
    public static let title = Font.caption.weight(.semibold)
    public static let labelSpacing: CGFloat = 4
    public static let verticalPadding: CGFloat = 8
    public static let horizontalPadding: CGFloat = 8
    public static let minimumScale: CGFloat = 0.85
    #endif
}

private struct PlaceActionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: PlaceActionMetrics.labelSpacing) {
            configuration.icon.font(.system(size: PlaceActionMetrics.glyph, weight: .semibold))
                .imageScale(.medium)
            configuration.title.font(PlaceActionMetrics.title).lineLimit(1).minimumScaleFactor(PlaceActionMetrics.minimumScale)
        }
        .padding(.vertical, PlaceActionMetrics.verticalPadding)
        .padding(.horizontal, PlaceActionMetrics.horizontalPadding)
        .frame(maxWidth: .infinity, minHeight: PlaceActionMetrics.height)
    }
}
