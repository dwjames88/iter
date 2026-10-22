import SwiftUI
import IterFeatures
import IterDesign

/// One row's slice of a day card: the content fill with its top corners rounded on the first row and its bottom corners on
/// the last, no stroke. Rows stack with no gap, so the slices join into one rounded card. Used as `listRowBackground`.
struct DayCardBackground: View {
    let position: TripBuilderRowPosition
    /// The inset from the list's edge to the card.
    var inset: CGFloat = BuilderMetrics.panelInset

    var body: some View {
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
struct DayCard<Header: View, Content: View>: View {
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(16)
            VStack(alignment: .leading, spacing: 4) { content }.padding(BuilderMetrics.bodyInset)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: BuilderMetrics.cardCorner, style: .continuous))
        .background { BuilderCardBackground() }
    }
}

#Preview("Day card slices, light") { SlicesPreview().preferredColorScheme(.light) }
#Preview("Day card slices, dark") { SlicesPreview().preferredColorScheme(.dark) }

private struct SlicesPreview: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach([TripBuilderRowPosition.first, .middle, .last], id: \.self) { position in
                Color.clear.frame(height: 40).background(DayCardBackground(position: position))
            }
            Color.clear.frame(height: 24)
            Color.clear.frame(height: 40).background(DayCardBackground(position: .only))
        }
        .frame(width: 400)
        .background(IterColor.backgroundWindow)
    }
}
