import IterModel
import SwiftUI

/// What a day selector card summarises: plain values from the plan.
public struct DaySummary: Identifiable, Equatable, Sendable {
    /// 0-based day within the trip.
    public var index: Int
    public var date: LocalDay
    public var stopCount: Int
    /// The day's main session (its first stop's window); nil with no stops.
    public var session: LightWindowKind?

    public var id: Int { index }

    public init(index: Int, date: LocalDay, stopCount: Int, session: LightWindowKind? = nil) {
        self.index = index
        self.date = date
        self.stopCount = stopCount
        self.session = session
    }
}

/// What a day selector card shows, as plain text, so the card draws in previews and on both platforms.
public struct DaySelectorItem: Identifiable, Equatable, Sendable {
    public var index: Int
    /// "Day 1"
    public var dayName: String
    /// "Tuesday"
    public var weekday: String
    /// "1 Stop"
    public var stops: String
    /// "Sunset"; nil with no stops.
    public var session: String?
    /// "Day 1, Tuesday, October 6, 1 stop, Sunset"
    public var spoken: String

    public var id: Int { index }

    public init(index: Int, dayName: String, weekday: String, stops: String, session: String?, spoken: String) {
        self.index = index
        self.dayName = dayName
        self.weekday = weekday
        self.stops = stops
        self.session = session
        self.spoken = spoken
    }

    public init(_ summary: DaySummary, locale: Locale = .current) {
        let name = TripBuilderText.dayName(index: summary.index, locale: locale)
        let session = summary.stopCount > 0 ? summary.session.map { LightText.name($0) } : nil
        let stops = TripBuilderText.stopCountTitle(summary.stopCount, locale: locale)
        self.init(index: summary.index, dayName: name, weekday: TripBuilderText.weekdayName(summary.date, locale: locale),
                  stops: stops, session: session,
                  spoken: ([name, TimeText.longDay(summary.date, locale: locale), stops.lowercased(with: locale)]
                           + [session].compactMap { $0 }).joined(separator: ", "))
    }
}

/// One card of the selector: 153 pt wide, the day above its weekday, the stop count above the session. The selected day
/// is filled with the accent and set in white; the others sit on the control fill. Figma part: day selector card.
public struct DaySelectorCard: View {
    public let item: DaySelectorItem
    public var isSelected: Bool

    public init(item: DaySelectorItem, isSelected: Bool = false) {
        self.item = item
        self.isSelected = isSelected
    }

    public init(summary: DaySummary, isSelected: Bool = false, locale: Locale = .current) {
        self.init(item: DaySelectorItem(summary, locale: locale), isSelected: isSelected)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.dayName).font(BuilderType.captionLight)
                Text(item.weekday).font(BuilderType.heading).lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.stops).font(BuilderType.captionStrong)
                if let session = item.session { Text(session).font(BuilderType.captionLight) }
            }
        }
        .foregroundStyle(isSelected ? AnyShapeStyle(IterColor.onAccent) : AnyShapeStyle(IterColor.textPrimary))
        .padding(12)
        .frame(width: 153, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background { BuilderCardBackground(fill: isSelected ? IterColor.accent : IterColor.backgroundControl, corner: BuilderMetrics.innerCorner) }
        .contentShape(RoundedRectangle(cornerRadius: BuilderMetrics.innerCorner, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(item.spoken))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The days side by side, scrolling sideways when they overflow. Choosing the selected day again returns to all days.
/// Figma part: day selector.
public struct DaySelector: View {
    public let items: [DaySelectorItem]
    public let selectedDay: Int?
    /// Called with the chosen day, or nil when the selected day was chosen again.
    public let onSelect: (Int?) -> Void

    public init(items: [DaySelectorItem], selectedDay: Int?, onSelect: @escaping (Int?) -> Void) {
        self.items = items
        self.selectedDay = selectedDay
        self.onSelect = onSelect
    }

    public init(summaries: [DaySummary], selectedDay: Int?, locale: Locale = .current, onSelect: @escaping (Int?) -> Void) {
        self.init(items: summaries.map { DaySelectorItem($0, locale: locale) }, selectedDay: selectedDay, onSelect: onSelect)
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(items) { item in
                    Button { onSelect(item.index == selectedDay ? nil : item.index) } label: {
                        DaySelectorCard(item: item, isSelected: item.index == selectedDay)
                    }
                    .buttonStyle(.plain)
                    .help(Text("Show this day on the map", bundle: .module, comment: "Tooltip"))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            // Room for the cards' shadow, which a scroll view would clip.
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .scrollClipDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Trip days", bundle: .module, comment: "Accessibility label of the day selector"))
    }
}
