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
    /// Four tiles share a 402 pt phone's card, so the label gets all but 4 pt of each side, as on the Mac ("Add to Trip…" and
    /// "Open in Maps" truncated at 8 pt and 0.85 on the iPhone 17 Pro simulator).
    public static let horizontalPadding: CGFloat = 4
    public static let minimumScale: CGFloat = 0.7
    /// "Open in Maps" still truncated on one line at a 402 pt phone's width; two lines, like Maps' own action tiles.
    public static let titleLines = 2
    #endif
}

private struct PlaceActionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: PlaceActionMetrics.labelSpacing) {
            configuration.icon.font(.system(size: PlaceActionMetrics.glyph, weight: .semibold))
                .imageScale(.medium)
            #if os(macOS)
            configuration.title.font(PlaceActionMetrics.title).lineLimit(1).minimumScaleFactor(PlaceActionMetrics.minimumScale)
            #else
            configuration.title.font(PlaceActionMetrics.title).lineLimit(PlaceActionMetrics.titleLines)
                .multilineTextAlignment(.center).minimumScaleFactor(PlaceActionMetrics.minimumScale)
            #endif
        }
        .padding(.vertical, PlaceActionMetrics.verticalPadding)
        .padding(.horizontal, PlaceActionMetrics.horizontalPadding)
        // maxHeight lets the label (and so the button's fill) take the height `PlaceActionRow` proposes, the tallest tile's.
        .frame(maxWidth: .infinity, minHeight: PlaceActionMetrics.height, maxHeight: .infinity)
    }
}

/// The place card's row of actions: equal widths, and every tile as tall as the tallest. A tile whose title wraps to two lines
/// (or grows with Dynamic Type) lifts its neighbours to the same height; nothing here is a fixed height, so the minimums in
/// `PlaceActionMetrics` and the type size decide.
public struct PlaceActionRow: Layout {
    public var spacing: CGFloat

    public init(spacing: CGFloat = 8) { self.spacing = spacing }

    private func tileWidth(_ count: Int, in width: CGFloat) -> CGFloat {
        guard count > 0 else { return 0 }
        return max(0, (width - spacing * CGFloat(count - 1)) / CGFloat(count))
    }

    private func rowHeight(_ subviews: Subviews, width: CGFloat) -> CGFloat {
        let proposal = ProposedViewSize(width: tileWidth(subviews.count, in: width), height: nil)
        return subviews.map { $0.sizeThatFits(proposal).height }.max() ?? 0
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 340
        return CGSize(width: width, height: rowHeight(subviews, width: width))
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let each = tileWidth(subviews.count, in: bounds.width)
        let height = rowHeight(subviews, width: bounds.width)
        for (i, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + CGFloat(i) * (each + spacing), y: bounds.minY),
                          anchor: .topLeading, proposal: ProposedViewSize(width: each, height: height))
        }
    }
}
