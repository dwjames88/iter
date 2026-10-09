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
    static let heroHeight: CGFloat = 320
    static let cardHeight: CGFloat = 268
    static let gridMinimum: CGFloat = 340
    static let inset = IterSpace.md
}

/// The next session as one line: "Next: Mesa Arch", its event unit with the score once the forecast is known, the weekday.
/// `onImage` = white text over a photo.
struct TripNextLine: View {
    @Environment(AppModel.self) private var model
    let entry: TripEntry
    var onImage = false

    private var summary: TripSummary { entry.summary }
    private var text: AnyShapeStyle { onImage ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(IterColor.textSecondary) }

    var body: some View {
        let _ = model.forecasts.revision
        if let next = summary.next {
            let stop = entry.record.plan.stops.first { $0.id == next.stopID }
            HStack(alignment: .center, spacing: IterSpace.sm) {
                Text("Next: \(next.spotName)", comment: "A trip card's next spot, before its session")
                    .font(IterFont.secondary)
                    .foregroundStyle(text)
                    .lineLimit(1)
                if let stop, let window = window(stop, next) {
                    EventScore(window: window, zone: next.timeZone, timeStyle: .start, variant: .compact,
                               isLoading: model.forecasts.isLoading(stop.spot.coordinate))
                } else {
                    EventScore(kind: next.kind, start: next.start, zone: next.timeZone, variant: .compact)
                }
                Text(TimeText.weekday(next.day))
                    .font(IterFont.secondary)
                    .foregroundStyle(text)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(LightText.nextSession(next)))
            .task(id: next.stopID) {
                if let stop { model.forecasts.request(stop.spot.coordinate) }
            }
        } else if summary.stopCount == 0 {
            Label {
                Text("No stops yet. Open the trip to add the first.", comment: "Trip card with no stops")
            } icon: {
                Image(systemName: "plus.circle").foregroundStyle(onImage ? AnyShapeStyle(.white) : AnyShapeStyle(IterColor.accent))
            }
            .font(IterFont.secondary)
            .foregroundStyle(text)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
        } else {
            Label {
                Text("All sessions have passed", comment: "Trip card when every session is in the past")
            } icon: {
                Image(systemName: "checkmark.circle")
            }
            .font(IterFont.secondary)
            .foregroundStyle(text)
        }
    }

    private func window(_ stop: TripStopPlan, _ next: NextSession) -> LightWindow? {
        let state = model.forecasts.state(for: stop.spot.coordinate)
        guard state.forecast != nil else { return nil }
        let light = model.engine.dayLight(for: stop.spot, on: next.day, forecast: state.forecast,
                                          unavailable: state.unavailableReason, now: model.now())
        return light.window(stop.session)
    }
}

/// The shell of every card in the grid: a soft content-layer tile (no glass) with text on top and its picture bleeding
/// to the bottom edge, all clipped by one continuous corner. It lifts a little under the pointer.
struct TripTile<Top: View, Bottom: View>: View {
    let action: () -> Void
    @ViewBuilder var top: Top
    @ViewBuilder var bottom: Bottom
    @State private var isHovering = false

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: TripsMetrics.corner, style: .continuous) }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                top
                    .padding(.horizontal, IterSpace.lg + IterSpace.xs)
                    .padding(.top, IterSpace.lg + IterSpace.xs)
                    .padding(.bottom, IterSpace.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                bottom
                    .frame(maxWidth: .infinity, minHeight: 64, maxHeight: .infinity)
                    .clipped()
            }
            .frame(height: TripsMetrics.cardHeight)
            .background(ModuleFill())
            .clipShape(shape)
            .contentShape(shape)
            .scaleEffect(isHovering ? 1.012 : 1)
            .shadow(color: .black.opacity(isHovering ? 0.14 : 0.05), radius: isHovering ? 16 : 6, y: isHovering ? 8 : 2)
            .animation(.smooth(duration: 0.2), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// One trip in the grid: date eyebrow, serif title, size and next session, and its picture on the lower part.
struct TripCardView: View {
    @Environment(AppNavigation.self) private var navigation
    let entry: TripEntry
    @Binding var prompt: TripNamePrompt?

    private var summary: TripSummary { entry.summary }

    var body: some View {
        TripTile(action: { navigation.show(.trip(summary.id)) }) {
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
                TripNextLine(entry: entry)
                    .padding(.top, IterSpace.xxs)
            }
        } bottom: {
            TripCover(spot: entry.coverSpot)
        }
        .draggable(LibraryDragItem.trip(summary.id))
        .contextMenu { TripEntryMenu(trip: entry.record, prompt: $prompt) }
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens the trip", comment: "VoiceOver hint"))
    }
}

/// A folder in the grid: its name, how many trips it holds, a strip of their pictures. Opens the folder's page; a trip
/// dropped on it is filed there.
struct TripFolderTileView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openTripFolder) private var openFolder
    let tile: TripFolderTile
    @Binding var prompt: TripNamePrompt?
    @State private var isTargeted = false

    var body: some View {
        TripTile(action: { openFolder(tile.id) }) {
            VStack(alignment: .leading, spacing: IterSpace.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Label {
                        Text("Folder", comment: "Eyebrow on a trip folder's tile")
                    } icon: {
                        Image(systemName: "folder.fill")
                    }
                    .font(IterFont.captionStrong)
                    .foregroundStyle(IterColor.textSecondary)
                    Spacer(minLength: IterSpace.sm)
                    if tile.isPinned {
                        Image(systemName: "pin.fill")
                            .font(IterFont.caption)
                            .foregroundStyle(IterColor.textSecondary)
                            .accessibilityHidden(true)
                    }
                }
                Text(tile.name)
                    .font(IterFont.titleSpot)
                    .foregroundStyle(IterColor.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(InflectedCount.string("trip", count: tile.entries.count) {
                    AttributedString(localized: "^[\(tile.entries.count) trip](inflect: true)", comment: "Number of trips in a folder tile")
                })
                    .font(IterFont.callout)
                    .foregroundStyle(IterColor.textSecondary)
            }
        } bottom: {
            HStack(spacing: IterSpace.xxs) {
                let shown = Array(tile.entries.prefix(3))
                if shown.isEmpty {
                    TripCover(spot: nil)
                } else {
                    ForEach(shown) { TripCover(spot: $0.coverSpot) }
                }
            }
        }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: TripsMetrics.corner, style: .continuous)
                    .strokeBorder(IterColor.accent, lineWidth: 3)
            }
        }
        .animation(.smooth(duration: 0.15), value: isTargeted)
        .dropDestination(for: LibraryDragItem.self) { items, _ in
            let trips = items.compactMap(\.tripID).compactMap { model.store.trip(id: $0) }
            guard !trips.isEmpty, let folder = model.store.folder(id: tile.id) else { return false }
            model.store.moveTrips(trips, to: folder, index: nil)
            return true
        } isTargeted: { isTargeted = $0 }
        .contextMenu { TripFolderMenu(folderID: tile.id, prompt: $prompt) }
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens the folder", comment: "VoiceOver hint"))
    }
}

extension EnvironmentValues {
    /// What tapping a folder tile does. The Mac selects the folder in the sidebar's model; iOS filters its list.
    @Entry var openTripFolder: (UUID) -> Void = { _ in }
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
            // Extra weight under the text and the Open control, so the event unit and the button read on any picture.
            LinearGradient(colors: [.clear, .black.opacity(0.3)], startPoint: .center, endPoint: .bottom)
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

    private var openButton: some View {
        Button { navigation.show(.trip(summary.id)) } label: {
            Text("Open", comment: "Hero button: opens the featured trip")
                .frame(minWidth: IterSpace.xxl * 2)
        }
        .buttonStyle(.glassProminent)
        .tint(IterColor.accent)
        .controlSize(.large)
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
            // Side by side when there is room; on a narrow phone the Open button drops under the next-session line.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: IterSpace.lg) {
                    TripNextLine(entry: entry, onImage: true)
                    Spacer(minLength: IterSpace.md)
                    openButton
                }
                VStack(alignment: .leading, spacing: IterSpace.md) {
                    TripNextLine(entry: entry, onImage: true)
                    openButton.frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(.top, IterSpace.xs)
        }
        .padding(IterSpace.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
