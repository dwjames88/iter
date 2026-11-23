import Foundation
import IterConditions
import IterModel
import IterSky

// The Add Stop popover's list: saved places, nearest to where the day starts from first, each with its compact score for
// that day. Added by the Build screens worker because the screens cannot reach the library from a `BuildModel`.

/// One saved place the Add Stop popover offers for a day.
public struct BuildAddCandidate: Equatable, Sendable, Identifiable {
    public var place: Place
    /// From the day's last stop (or the previous day's last, or the start place); nil when there is nothing to measure from.
    public var distanceMeters: Double?
    /// The place already has a stop on this day.
    public var isOnDay: Bool
    /// The window the score belongs to (the best scored one, else the place's own best light); nil when the sun makes none.
    public var window: BuildWindowOption?
    public var id: UUID { place.id }

    public init(place: Place, distanceMeters: Double?, isOnDay: Bool, window: BuildWindowOption?) {
        self.place = place
        self.distanceMeters = distanceMeters
        self.isOnDay = isOnDay
        self.window = window
    }
}

/// The list the popover shows and the name of what it is measured from.
public struct BuildAddStopList: Equatable, Sendable {
    public var anchorName: String?
    public var candidates: [BuildAddCandidate]

    public init(anchorName: String? = nil, candidates: [BuildAddCandidate] = []) {
        self.anchorName = anchorName
        self.candidates = candidates
    }
}

extension BuildModel {
    /// Saved places for `day`, filtered by `query` (name or locality), nearest the day's anchor first; with no anchor, by name.
    public func addStopList(forDay day: Int, query: String = "") -> BuildAddStopList {
        guard let trip else { return BuildAddStopList(anchorName: nil, candidates: []) }
        let ordered = Self.ordered(trip.stops)
        let anchorStop = ordered.last { $0.dayIndex == day } ?? ordered.last { $0.dayIndex < day }
        let anchorPlace = anchorStop?.place ?? startPlace.flatMap { library.places.value(id: $0.placeID) }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let onDay = Set(trip.stops.filter { $0.dayIndex == day }.map(\.place.id))
        let date = trip.day(day)
        var list: [BuildAddCandidate] = []
        for place in library.places.savedValues() {
            if !needle.isEmpty, !place.name.localizedCaseInsensitiveContains(needle),
               !place.locality.localizedCaseInsensitiveContains(needle) { continue }
            list.append(BuildAddCandidate(place: place, distanceMeters: anchorPlace.map { $0.coordinate.distance(to: place.coordinate) },
                                          isOnDay: onDay.contains(place.id), window: window(for: place, on: date)))
        }
        list.sort {
            if let a = $0.distanceMeters, let b = $1.distanceMeters, a != b { return a < b }
            return $0.place.name.localizedStandardCompare($1.place.name) == .orderedAscending
        }
        return BuildAddStopList(anchorName: anchorPlace?.name, candidates: list)
    }

    /// Asks Conditions for the nearest saved places on `day`, so the popover's scores arrive (call when it opens).
    public func requestAddStopScores(forDay day: Int, limit: Int = 12) {
        guard let trip else { return }
        let date = trip.day(day)
        for candidate in addStopList(forDay: day).candidates.prefix(limit) {
            conditions.request(candidate.place, day: date, priority: .onScreen)
        }
    }

    private func window(for place: Place, on day: LocalDay) -> BuildWindowOption? {
        let light = engine.dayLight(for: place, on: day, inputs: nil, unavailable: [], now: now())
        let scores = conditions.sample(placeID: place.id, day: day).scores
        if let best = scores.max(by: { $0.value < $1.value }), let w = light.window(best.key) {
            return BuildWindowOption(kind: w.kind, start: w.span.start, end: w.span.end, score: best.value)
        }
        let intent = place.bestLight.compactMap(\.intent).first ?? .sunset
        guard let w = light.headline(for: intent) else { return nil }
        return BuildWindowOption(kind: w.kind, start: w.span.start, end: w.span.end, score: nil)
    }
}
