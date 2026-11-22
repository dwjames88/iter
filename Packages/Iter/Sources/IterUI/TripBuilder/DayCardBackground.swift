import SwiftUI

/// Where a row sits inside its day card, so the row backgrounds join into one rounded card.
public enum DayCardPosition: Hashable, Sendable {
    case first, middle, last, only

    public var roundsTop: Bool { self == .first || self == .only }
    public var roundsBottom: Bool { self == .last || self == .only }
}

/// One row's slice of a day card: the content fill with its top corners rounded on the first row and its bottom corners on
/// the last, no stroke. Rows stack with no gap, so the slices join into one rounded card. Used as `listRowBackground`.
/// Figma part: day card.
public struct DayCardBackground: View {
    public let position: DayCardPosition
    /// The inset from the list's edge to the card.
    public var inset: CGFloat

    public init(position: DayCardPosition, inset: CGFloat = BuilderMetrics.panelInset) {
        self.position = position
        self.inset = inset
    }

    public var body: some View {
        UnevenRoundedRectangle(topLeadingRadius: position.roundsTop ? BuilderMetrics.cardCorner : 0,
                               bottomLeadingRadius: position.roundsBottom ? BuilderMetrics.cardCorner : 0,
                               bottomTrailingRadius: position.roundsBottom ? BuilderMetrics.cardCorner : 0,
                               topTrailingRadius: position.roundsTop ? BuilderMetrics.cardCorner : 0,
                               style: .continuous)
            .fill(IterColor.backgroundContent)
            .padding(.horizontal, inset)
    }
}

/// A day card outside a List (previews, iOS): the header, then the body 4 pt in, on one rounded content fill.
/// Figma part: day card.
public struct DayCard<Header: View, Content: View>: View {
    let header: Header
    let content: Content

    public init(@ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content) {
        self.header = header()
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(16)
            VStack(alignment: .leading, spacing: 4) { content }.padding(BuilderMetrics.bodyInset)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: BuilderMetrics.cardCorner, style: .continuous))
        .background { BuilderCardBackground() }
    }
}
