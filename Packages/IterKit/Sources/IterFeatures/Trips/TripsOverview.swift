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

/// One group on the All Trips page.
public struct TripsSection: Identifiable {
    public enum Kind: Hashable, Sendable {
        case pinned
        case folder(UUID)
        case other
    }

    public var kind: Kind
    /// nil = no header (the page has no other group to tell it apart from).
    public var title: String?
    /// A subfolder shows as "Folder › Sub".
    public var entries: [TripEntry]

    public var id: String {
        switch kind {
        case .pinned: "pinned"
        case .folder(let id): id.uuidString
        case .other: "other"
        }
    }

    public var folderID: UUID? { if case .folder(let id) = kind { id } else { nil } }
}

/// Everything the All Trips page shows: the hero trip, then the pinned, folder and remaining groups.
public struct TripsOverview {
    public var hero: TripEntry?
    public var sections: [TripsSection]
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

    /// The page's content. The hero is left out of the groups so it shows once. Folders always show, empty or not, so
    /// there is somewhere to drop a trip. `pinnedTitle`, `otherTitle` and `subfolderTitle` are the localized words.
    public func overview(today: LocalDay, pinnedTitle: String, otherTitle: String,
                         subfolderTitle: (_ folder: String, _ sub: String) -> String) -> TripsOverview {
        _ = store.revision
        let clock = now()
        let all = store.trips()
        let entries = all.map { TripEntry(record: $0, summary: Self.summary(of: $0.plan, engine: engine, now: clock)) }
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        let heroID = Self.heroID(among: entries.map(\.summary), today: today)
        let hero = heroID.flatMap { byID[$0] }

        func visible(_ trips: [TripRecord]) -> [TripEntry] {
            trips.compactMap { byID[$0.id] }.filter { $0.id != heroID }
        }

        var sections: [TripsSection] = []
        let pinned = visible(store.pinnedTrips())
        if !pinned.isEmpty { sections.append(TripsSection(kind: .pinned, title: pinnedTitle, entries: pinned)) }
        for root in store.folders(kind: .trips) {
            sections.append(TripsSection(kind: .folder(root.id), title: root.name,
                                         entries: visible(store.trips(in: root).filter { !$0.isPinned })))
            for sub in store.subfolders(of: root) {
                sections.append(TripsSection(kind: .folder(sub.id), title: subfolderTitle(root.name, sub.name),
                                             entries: visible(store.trips(in: sub).filter { !$0.isPinned })))
            }
        }
        let other = visible(store.trips(in: nil).filter { !$0.isPinned })
        if !other.isEmpty { sections.append(TripsSection(kind: .other, title: sections.isEmpty ? nil : otherTitle, entries: other)) }
        return TripsOverview(hero: hero, sections: sections, tripCount: entries.count)
    }
}
