import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// Sizes of the All Trips page. The corner is Sean's measured Maps card corner (GLASS-RULES.md); imagery inside a card is
/// inset and takes `ConcentricRectangle`, so it follows that corner.
enum TripsMetrics {
    static let columnMax: CGFloat = 1040
    static let margin = IterSpace.xxl
    static let corner: CGFloat = 27.5
    static let heroHeight: CGFloat = 380
    static let cardHeight: CGFloat = 308
    static let gridMinimum: CGFloat = 340
    static let inset = IterSpace.md
}

/// The next session as one line: "Next: Mesa Arch", its event unit, the weekday. `onImage` = white text over a photo.
struct TripNextLine: View {
    let summary: TripSummary
    var onImage = false

    private var muted: Color { onImage ? .white.opacity(0.85) : .secondary }

    var body: some View {
        if let next = summary.next {
            HStack(alignment: .center, spacing: IterSpace.sm) {
                Text("Next: \(next.spotName)", comment: "A trip card's next spot, before its session")
                    .font(IterFont.secondary)
                    .foregroundStyle(onImage ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(IterColor.textSecondary))
                    .lineLimit(1)
                EventScore(kind: next.kind, start: next.start, zone: next.timeZone, variant: .compact)
                    .padding(onImage ? IterSpace.xxs : 0)
                    .background(onImage ? AnyShapeStyle(IterColor.backgroundModule) : AnyShapeStyle(Color.clear),
                                in: RoundedRectangle(cornerRadius: IterRadius.card, style: .continuous))
                Text(TimeText.weekday(next.day))
                    .font(IterFont.secondary)
                    .foregroundStyle(onImage ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(IterColor.textSecondary))
                    .lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(LightText.nextSession(next)))
        } else if summary.stopCount == 0 {
            Label {
                Text("No stops yet. Open the trip to add the first.", comment: "Trip card with no stops")
            } icon: {
                Image(systemName: "plus.circle").foregroundStyle(onImage ? AnyShapeStyle(.white) : AnyShapeStyle(IterColor.accent))
            }
            .font(IterFont.secondary)
            .foregroundStyle(onImage ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(IterColor.textSecondary))
        } else {
            Label {
                Text("All sessions have passed", comment: "Trip card when every session is in the past")
            } icon: {
                Image(systemName: "checkmark.circle")
            }
            .font(IterFont.secondary)
            .foregroundStyle(onImage ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(IterColor.textSecondary))
        }
    }
}

/// One trip in the grid: date eyebrow, serif title, size and next session, and its picture on the lower half. A soft
/// content-layer card (no glass); it lifts a little under the pointer.
struct TripCardView: View {
    @Environment(AppNavigation.self) private var navigation
    @Environment(AppModel.self) private var model
    let entry: TripEntry
    @Binding var prompt: TripNamePrompt?
    @State private var isHovering = false

    private var summary: TripSummary { entry.summary }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: TripsMetrics.corner, style: .continuous) }

    var body: some View {
        Button { navigation.show(.trip(summary.id)) } label: {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: IterSpace.xs) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(TimeText.dateRange(from: summary.startDay, to: summary.endDay))
                            .font(IterFont.captionStrong)
                            .foregroundStyle(IterColor.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: IterSpace.sm)
                        if entry.record.isPinned {
                            Image(systemName: "pin.fill")
                                .font(IterFont.caption)
                                .foregroundStyle(IterColor.textSecondary)
                                .accessibilityHidden(true)
                        }
                    }
                    Text(summary.name)
                        .font(IterFont.titleSpot)
                        .foregroundStyle(IterColor.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(TimeText.dayAndStops(days: summary.dayCount, stops: summary.stopCount))
                        .font(IterFont.callout)
                        .foregroundStyle(IterColor.textSecondary)
                    TripNextLine(summary: summary)
                        .padding(.top, IterSpace.xxs)
                }
                .padding(.horizontal, IterSpace.lg + IterSpace.xs)
                .padding(.top, IterSpace.lg + IterSpace.xs)
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: IterSpace.md)

                TripCover(spot: entry.coverSpot)
                    .frame(height: TripsMetrics.cardHeight * 0.38)
                    .clipShape(ConcentricRectangle())
                    .padding(TripsMetrics.inset)
            }
            .frame(height: TripsMetrics.cardHeight)
            .containerShape(shape)
            .background(ModuleFill(), in: shape)
            .contentShape(shape)
            .scaleEffect(isHovering ? 1.012 : 1)
            .shadow(color: .black.opacity(isHovering ? 0.14 : 0.05), radius: isHovering ? 16 : 6, y: isHovering ? 8 : 2)
            .animation(.smooth(duration: 0.2), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .draggable(LibraryDragItem.trip(summary.id))
        .contextMenu { TripEntryMenu(trip: entry.record, prompt: $prompt) }
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens the trip", comment: "VoiceOver hint"))
    }
}

/// The featured trip: its picture full width under the HIG's 35 % dimming layer, with name, dates, size, the next
/// session and the one prominent action. Only the Open control is glass, as a control over media should be.
struct TripHeroView: View {
    @Environment(AppNavigation.self) private var navigation
    let entry: TripEntry
    let today: LocalDay
    @Binding var prompt: TripNamePrompt?

    private var summary: TripSummary { entry.summary }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: TripsMetrics.corner, style: .continuous) }

    private var eyebrow: String {
        if summary.endDay < today { return String(localized: "Latest Trip", comment: "Hero eyebrow: the most recent finished trip") }
        if summary.startDay <= today { return String(localized: "Under Way", comment: "Hero eyebrow: the trip happening now") }
        return String(localized: "Up Next", comment: "Hero eyebrow: the next trip to start")
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            TripCover(spot: entry.coverSpot)
            Color.black.opacity(0.35)
            content
        }
        .frame(height: TripsMetrics.heroHeight)
        .containerShape(shape)
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture { navigation.show(.trip(summary.id)) }
        .draggable(LibraryDragItem.trip(summary.id))
        .contextMenu { TripEntryMenu(trip: entry.record, prompt: $prompt) }
        .accessibilityElement(children: .contain)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            Spacer(minLength: 0)
            Text("\(eyebrow) · \(TimeText.dateRange(from: summary.startDay, to: summary.endDay))", comment: "Hero eyebrow: which trip, then its dates")
                .font(IterFont.captionStrong)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            Text(summary.name)
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(TimeText.dayAndStops(days: summary.dayCount, stops: summary.stopCount))
                .font(IterFont.callout)
                .foregroundStyle(.white.opacity(0.9))
            HStack(alignment: .center, spacing: IterSpace.lg) {
                TripNextLine(summary: summary, onImage: true)
                Spacer(minLength: IterSpace.md)
                Button { navigation.show(.trip(summary.id)) } label: {
                    Text("Open", comment: "Hero button: opens the featured trip")
                        .frame(minWidth: IterSpace.xxl * 2)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
            .padding(.top, IterSpace.xs)
        }
        .padding(IterSpace.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
