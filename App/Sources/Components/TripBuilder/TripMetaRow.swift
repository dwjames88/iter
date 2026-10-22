import SwiftUI
import IterDesign

/// One fact in the header's meta row: a symbol and a line, optionally a button (the dates open Change Dates).
struct TripMetaItem: Identifiable {
    var symbol: String
    var text: String
    var help: Text?
    var action: (() -> Void)?

    var id: String { symbol }

    init(symbol: String, text: String, help: Text? = nil, action: (() -> Void)? = nil) {
        self.symbol = symbol
        self.text = text
        self.help = help
        self.action = action
    }
}

/// A symbol (secondary) and a 13 pt line (the dark body grey), 8 pt apart.
struct TripMetaItemView: View {
    let item: TripMetaItem

    var body: some View {
        if let action = item.action {
            Button(action: action) { content }
                .buttonStyle(.plain)
                .help(item.help ?? Text(item.text))
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 8) {
            Image(systemName: item.symbol)
                .font(BuilderType.body)
                .foregroundStyle(IterColor.textSecondary)
                .accessibilityHidden(true)
            Text(item.text)
                .font(BuilderType.body)
                .monospacedDigit()
                .foregroundStyle(IterColor.textSecondary)
                .lineLimit(1)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

/// The header's facts, 20 pt apart on one line; they wrap to two and then one per line when the card is narrow.
struct TripMetaRow: View {
    let items: [TripMetaItem]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) { ForEach(items) { TripMetaItemView(item: $0) } }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 20) { ForEach(items.prefix(2)) { TripMetaItemView(item: $0) } }
                ForEach(items.dropFirst(2)) { TripMetaItemView(item: $0) }
            }
            VStack(alignment: .leading, spacing: 4) { ForEach(items) { TripMetaItemView(item: $0) } }
        }
    }
}

#Preview("Meta row, light") { MetaRowPreview().preferredColorScheme(.light) }
#Preview("Meta row, dark") { MetaRowPreview().preferredColorScheme(.dark) }

private struct MetaRowPreview: View {
    var body: some View {
        TripMetaRow(items: TripMetaItem.sample)
            .padding(IterSpace.xl)
            .frame(width: 560, alignment: .leading)
            .background(IterColor.backgroundContent)
    }
}

extension TripMetaItem {
    static var sample: [TripMetaItem] { [
        TripMetaItem(symbol: "calendar", text: "Tue, Oct 6 – Fri, Oct 9", action: {}),
        TripMetaItem(symbol: "point.topleft.filled.down.to.point.bottomright.curvepath", text: "4 days • 6 stops"),
        TripMetaItem(symbol: "car.fill", text: "490 miles • 9hrs, 34mins"),
    ] }
}
