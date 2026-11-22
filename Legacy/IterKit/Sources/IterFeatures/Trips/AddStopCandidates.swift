import Foundation
import IterCore

/// One row of the "Add stop" list.
public struct AddStopCandidate: Identifiable, Hashable, Sendable {
    public var spot: Spot
    /// Straight-line metres from the anchor; nil when the trip has no stops yet.
    public var distanceMeters: Double?
    public var isSaved: Bool
    /// Already a stop on the day being added to.
    public var isOnDay: Bool

    public var id: String { spot.id }
}

public struct AddStopList: Sendable {
    /// The stop the distances are measured from, if any.
    public var anchor: Spot?
    public var candidates: [AddStopCandidate]
}

/// Ranks spots for "Add stop" on one day: nearest to where that day starts from first (C56).
public enum AddStopCandidates {
    /// The last stop of `day`; if the day is empty, the last stop of the nearest earlier day that has one;
    /// if there is none before it, the first stop of the trip.
    public static func anchor(in plan: TripPlan, day: Int) -> Spot? {
        if let last = plan.stops(onDay: day).last { return last.spot }
        for earlier in stride(from: day - 1, through: 0, by: -1) {
            if let last = plan.stops(onDay: earlier).last { return last.spot }
        }
        return plan.stops.first?.spot
    }

    /// Saved spots and curated spots, merged by id, filtered by `query` (name or locality), nearest first.
    /// With no anchor, saved spots come first and everything is alphabetical.
    public static func make(plan: TripPlan, day: Int, saved: [Spot], curated: [Spot], query: String) -> AddStopList {
        let anchor = anchor(in: plan, day: day)
        let savedIDs = Set(saved.map(\.id))
        let onDay = Set(plan.stops(onDay: day).map(\.spot.id))
        var seen = Set<String>()
        var all: [Spot] = []
        for spot in saved + curated where seen.insert(spot.id).inserted { all.append(spot) }

        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = needle.isEmpty ? all : all.filter {
            $0.name.localizedCaseInsensitiveContains(needle) || $0.locality.localizedCaseInsensitiveContains(needle)
        }
        var rows = filtered.map { spot in
            AddStopCandidate(spot: spot,
                             distanceMeters: anchor.map { $0.coordinate.distance(to: spot.coordinate) },
                             isSaved: savedIDs.contains(spot.id),
                             isOnDay: onDay.contains(spot.id))
        }
        rows.sort { a, b in
            if let da = a.distanceMeters, let db = b.distanceMeters, da != db { return da < db }
            if a.isSaved != b.isSaved { return a.isSaved }
            return a.spot.name.localizedStandardCompare(b.spot.name) == .orderedAscending
        }
        return AddStopList(anchor: anchor, candidates: rows)
    }
}
