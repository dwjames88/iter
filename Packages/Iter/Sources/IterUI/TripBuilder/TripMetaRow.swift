import IterModel
import SwiftUI

/// One fact in the header's meta row: a symbol and a line, optionally a button (the dates open Change Dates).
public struct TripMetaItem: Identifiable {
    public var symbol: String
    public var text: String
    public var help: Text?
    public var action: (() -> Void)?

    public var id: String { symbol }

    public init(symbol: String, text: String, help: Text? = nil, action: (() -> Void)? = nil) {
        self.symbol = symbol
        self.text = text
        self.help = help
        self.action = action
    }

    /// "Tue, Oct 6 – Fri, Oct 9"; one date when the trip is a single day.
    public static func dates(from first: LocalDay, to last: LocalDay, locale: Locale = .current,
                             help: Text? = nil, action: (() -> Void)? = nil) -> TripMetaItem {
        let a = TimeText.day(first, locale: locale)
        let text = first == last ? a : "\(a) – \(TimeText.day(last, locale: locale))"
        return TripMetaItem(symbol: "calendar", text: text, help: help, action: action)
    }

    /// "4 days • 6 stops"
    public static func size(days: Int, stops: Int, locale: Locale = .current) -> TripMetaItem {
        TripMetaItem(symbol: "point.topleft.filled.down.to.point.bottomright.curvepath",
                     text: TripBuilderText.tripSize(days: days, stops: stops, locale: locale))
    }

    /// "490 mi • 9 hr, 34 min"
    public static func driving(seconds: TimeInterval, meters: Double, locale: Locale = .current) -> TripMetaItem {
        TripMetaItem(symbol: "car.fill", text: TripBuilderText.drivingTotal(seconds: seconds, meters: meters, locale: locale))
    }
}

/// A symbol (secondary) and a 13 pt line (the dark body grey), 8 pt apart.
public struct TripMetaItemView: View {
    public let item: TripMetaItem

    public init(item: TripMetaItem) { self.item = item }

    public var body: some View {
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
/// Figma part: trip meta row.
public struct TripMetaRow: View {
    public let items: [TripMetaItem]

    public init(items: [TripMetaItem]) { self.items = items }

    /// The three arrangements `ViewThatFits` tries, widest first, as the item indices on each line: all on one line;
    /// the first two together with the rest one per line; one per line.
    public static func arrangements(itemCount n: Int) -> [[[Int]]] {
        let all: [Int] = n > 0 ? Array(0..<n) : []
        var two: [[Int]] = []
        if !all.isEmpty { two.append(Array(all.prefix(2))) }
        for i in all.dropFirst(2) { two.append([i]) }
        var one: [[Int]] = []
        for i in all { one.append([i]) }
        return [all.isEmpty ? [] : [all], two, one]
    }

    public var body: some View {
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
