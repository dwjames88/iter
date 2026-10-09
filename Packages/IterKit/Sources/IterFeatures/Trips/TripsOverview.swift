import Foundation
import IterCore
import IterData

/// A trip as the All Trips page draws it: the stored record (for menus and filing) and its summary (for text).
public struct TripEntry: Identifiable {
    public let record: TripRecord
    public let summary: TripSummary
    public var id: UUID { summary.id }

    /// The spot whose image fronts the trip: the first stop in trip order.
    public var coverSpot: Spot? { record.orderedStops.lazy.compactMap { $0.plan?.spot }.first }
}

/// A folder as the page draws it: one tile in the grid, holding every trip filed in it (pinned and featured ones too).
public struct TripFolderTile: Identifiable {
    public let id: UUID
    public var name: String
    public var isPinned: Bool
    public var entries: [TripEntry]
}

/// Everything the All Trips page shows: the hero trip, then pinned trips, folder tiles and the remaining trips. The
/// hero is left out of `pinned` and `others` so it shows once.
public struct TripsOverview {
    public var hero: TripEntry?
    public var pinned: [TripEntry]
    public var folders: [TripFolderTile]
    public var others: [TripEntry]
    public var tripCount: Int
    public var isEmpty: Bool { tripCount == 0 }
}

extension TripsHomeModel {
    /// The trip to feature: the one under way or next to start (earliest start among trips that have not ended),
    /// else the most recently finished.
    public static func heroID(among summaries: [TripSummary], today: LocalDay) -> UUID? {
        let upcoming = summaries.filter { $0.endDay >= today }
        if let next = upcoming.min(by: { ($0.startDay, $0.id.uuidString) < ($1.startDay, $1.id.uuidString) }) { return next.id }
        return summaries.max(by: { ($0.endDay, $0.id.uuidString) < ($1.endDay, $1.id.uuidString) })?.id
    }

    /// The page's content. `featuring: false` shows no hero and leaves every trip in its group (the folder and filtered
    /// pages). Folders always show, empty or not, so there is somewhere to drop a trip.
    public func overview(today: LocalDay, featuring: Bool = true) -> TripsOverview {
        _ = store.revision
        let clock = now()
        let all = store.trips()
        let entries = all.map { TripEntry(record: $0, summary: Self.summary(of: $0.plan, engine: engine, now: clock)) }
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        let heroID = featuring ? Self.heroID(among: entries.map(\.summary), today: today) : nil

        func visible(_ trips: [TripRecord]) -> [TripEntry] {
            trips.compactMap { byID[$0.id] }.filter { $0.id != heroID }
        }

        let folders = store.folders(kind: .trips).map { root in
            // Nothing makes subfolders any more; trips left in one show with their parent folder.
            let filed = store.trips(in: root) + store.subfolders(of: root).flatMap { store.trips(in: $0) }
            return TripFolderTile(id: root.id, name: root.name, isPinned: root.isPinned, entries: filed.compactMap { byID[$0.id] })
        }
        return TripsOverview(hero: heroID.flatMap { byID[$0] },
                             pinned: visible(store.pinnedTrips()),
                             folders: folders,
                             others: visible(store.trips(in: nil).filter { !$0.isPinned }),
                             tripCount: entries.count)
    }
}
