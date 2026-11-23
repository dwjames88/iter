import IterGoActivity
import IterModel
import IterUI
import SwiftUI
import WidgetKit

/// One moment the widget shows: the snapshot at an entry date. The views count down from `date` on their own.
struct GoNextEntry: TimelineEntry {
    let date: Date
    let snapshot: GoSnapshot
}

/// Reads ONLY the snapshot file in the App Group. Never the store, never the network.
struct GoNextProvider: TimelineProvider {
    static let kind = "IterGoNext"

    func placeholder(in context: Context) -> GoNextEntry {
        GoNextEntry(date: .now, snapshot: GoSample.drivingOnTime.snapshot(now: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (GoNextEntry) -> Void) {
        let now = Date.now
        if context.isPreview {
            completion(GoNextEntry(date: now, snapshot: GoSample.drivingOnTime.snapshot(now: now)))
        } else {
            completion(GoNextEntry(date: now, snapshot: Self.current(now)))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GoNextEntry>) -> Void) {
        let now = Date.now
        let snapshot = Self.current(now)
        completion(Self.timeline(snapshot: snapshot, now: now))
    }

    static func current(_ now: Date) -> GoSnapshot {
        AppGroupSnapshotStore()?.read() ?? .idle(at: now)
    }

    /// An entry now, and one at each upcoming leave-by, arrival, window start and planned departure, so the text changes at
    /// those moments. Reloads after the app's next expected refresh; never when nothing is running.
    static func timeline(snapshot: GoSnapshot, now: Date) -> Timeline<GoNextEntry> {
        switch snapshot.phase {
        case .idle, .finished:
            return Timeline(entries: [GoNextEntry(date: now, snapshot: snapshot)], policy: .never)
        default:
            break
        }
        let candidates: [Date?] = [
            snapshot.leave?.leaveBy, snapshot.drive?.arrival, snapshot.sky?.windowStart, snapshot.next?.windowStart,
            snapshot.next?.setUpBy, snapshot.stay?.plannedDeparture, snapshot.stay?.latestDeparture, snapshot.sky?.windowEnd,
            // The snapshot turns "old" at 15 minutes; an entry there makes the age line appear without a reload.
            snapshot.generatedAt.addingTimeInterval(GoPresentation.oldAfter + 1),
        ]
        let horizon = now.addingTimeInterval(24 * 3600)
        let moments = Set(candidates.compactMap { $0 }.filter { $0 > now && $0 < horizon }).sorted().prefix(16)
        let entries = [GoNextEntry(date: now, snapshot: snapshot)] + moments.map { GoNextEntry(date: $0, snapshot: snapshot) }
        let next = snapshot.freshness.nextRefreshAt.flatMap { $0 > now ? $0 : nil } ?? now.addingTimeInterval(30 * 60)
        return Timeline(entries: entries, policy: .after(next))
    }
}

struct GoNextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: GoNextProvider.kind, provider: GoNextProvider()) { entry in
            GoNextEntryView(entry: entry)
        }
        .configurationDisplayName(Text("Next Stop"))
        .description(Text("Where you are heading, when to leave and how the light looks."))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct GoNextEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GoNextEntry

    /// The system draws the accessory backgrounds; only the home screen families get a solid content colour.
    private var background: Color {
        switch family {
        case .accessoryRectangular, .accessoryCircular, .accessoryInline, .accessoryCorner: .clear
        default: IterColor.backgroundContent
        }
    }

    var body: some View {
        GoWidgetView(snapshot: entry.snapshot, clock: .live(entry.date), family: GoWidgetFamily(family))
            .widgetURL(GoDeepLink.go)
            .containerBackground(for: .widget) { background }
    }
}

extension GoWidgetFamily {
    init(_ family: WidgetFamily) {
        switch family {
        case .systemMedium: self = .medium
        case .accessoryRectangular: self = .accessoryRectangular
        case .accessoryCircular: self = .accessoryCircular
        case .accessoryInline: self = .accessoryInline
        default: self = .small
        }
    }
}
