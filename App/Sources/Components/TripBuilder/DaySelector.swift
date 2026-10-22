import SwiftUI
import IterCore
import IterFeatures
import IterDesign

/// What a day selector card shows, as plain text, so the card draws in previews and on both platforms.
struct DaySelectorItem: Identifiable, Equatable {
    var index: Int
    /// "Day 1"
    var dayName: String
    /// "Tuesday"
    var weekday: String
    /// "1 Stop"
    var stops: String
    /// "Sunset"; nil with no stops.
    var session: String?
    /// "Day 1, Tuesday, October 6, 1 stop, Sunset"
    var spoken: String

    var id: Int { index }

    init(index: Int, dayName: String, weekday: String, stops: String, session: String?, spoken: String) {
        self.index = index
        self.dayName = dayName
        self.weekday = weekday
        self.stops = stops
        self.session = session
        self.spoken = spoken
    }

    init(_ summary: TripDaySummary) {
        let name = TimeText.dayName(index: summary.index)
        let session = summary.stopCount > 0 ? summary.primarySession.map { LightText.name($0) } : nil
        let stops = TimeText.stopCountTitle(summary.stopCount)
        self.init(index: summary.index, dayName: name, weekday: TimeText.weekdayName(summary.date), stops: stops, session: session,
                  spoken: ([name, TimeText.longDay(summary.date), stops.lowercased()] + [session].compactMap { $0 }).joined(separator: ", "))
    }
}

/// One card of the selector: 153 pt wide, the day above its weekday, the stop count above the session. The selected day
/// is filled with the accent and set in white; the others sit on the control fill.
struct DaySelectorCard: View {
    let item: DaySelectorItem
    var isSelected = false

    var body: some View {
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
struct DaySelector: View {
    let items: [DaySelectorItem]
    let selectedDay: Int?
    /// Called with the chosen day, or nil when the selected day was chosen again.
    let onSelect: (Int?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(items) { item in
                    Button { onSelect(item.index == selectedDay ? nil : item.index) } label: {
                        DaySelectorCard(item: item, isSelected: item.index == selectedDay)
                    }
                    .buttonStyle(.plain)
                    .help(Text("Show this day on the map", comment: "Tooltip"))
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
        .accessibilityLabel(Text("Trip days", comment: "Accessibility label of the day selector"))
    }
}

#Preview("Day selector, light") { DaySelectorPreview().preferredColorScheme(.light) }
#Preview("Day selector, dark") { DaySelectorPreview().preferredColorScheme(.dark) }

struct DaySelectorPreview: View {
    static let items = [
        DaySelectorItem(index: 0, dayName: "Day 1", weekday: "Tuesday", stops: "1 Stop", session: "Sunset", spoken: "Day 1, Tuesday, October 6, 1 stop, Sunset"),
        DaySelectorItem(index: 1, dayName: "Day 2", weekday: "Wednesday", stops: "2 Stops", session: "Sunset", spoken: "Day 2, Wednesday, October 7, 2 stops, Sunset"),
        DaySelectorItem(index: 2, dayName: "Day 3", weekday: "Thursday", stops: "No Stops", session: nil, spoken: "Day 3, Thursday, October 8, no stops"),
    ]
    var body: some View {
        DaySelector(items: Self.items, selectedDay: 0) { _ in }
            .frame(width: 640)
            .background(IterColor.backgroundWindow)
    }
}
