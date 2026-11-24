import Foundation
import IterModel

/// The three searches offered before anything is typed. No new scoring: each runs the ordinary discovery over a region, and the
/// day only decides which day's Conditions the score chips ask the shared store for.
public enum FindQuickChoice: String, CaseIterable, Identifiable, Sendable {
    case today, tomorrow, nearYou

    public var id: String { rawValue }

    /// Days after today the scores are for.
    public var dayOffset: Int { self == .tomorrow ? 1 : 0 }

    /// How far "Near You" reaches, in miles (the old app's setting, which the new Settings does not carry: a day-trip's drive).
    public static let nearYouRadiusMiles = 100.0
    /// The span Today and Tomorrow search when the map has not reported a region yet: about a hundred miles square.
    static let fallbackSpanDegrees = 1.5

    /// What a choice resolves to: the region discovery runs over and the day to score.
    public struct Plan: Equatable, Sendable {
        public var query: String
        public var region: GeoRegion
        public var dayOffset: Int
    }

    /// The plan for a choice, or nil when it needs a place to start from and has none (no map region and no location).
    /// Today and Tomorrow search the part of the map in view, else around you; Near You is a square around you whose half-side is
    /// `nearYouRadiusMiles`.
    public func plan(mapRegion: GeoRegion?, location: Coordinate?) -> Plan? {
        let query = "photo spots in this area"
        switch self {
        case .today, .tomorrow:
            if let mapRegion { return Plan(query: query, region: mapRegion, dayOffset: dayOffset) }
            guard let location else { return nil }
            let span = Self.fallbackSpanDegrees
            return Plan(query: query, region: GeoRegion(center: location, latitudeDelta: span, longitudeDelta: span), dayOffset: dayOffset)
        case .nearYou:
            guard let location else { return nil }
            let latDelta = 2 * Self.nearYouRadiusMiles / 69.0
            let lonDelta = latDelta / max(0.2, cos(location.latitude * .pi / 180))
            return Plan(query: query, region: GeoRegion(center: location, latitudeDelta: latDelta, longitudeDelta: min(lonDelta, 180)),
                        dayOffset: 0)
        }
    }
}

extension FindModel {
    /// Whether the quick choices are offered: nothing typed, nothing searched, no place open.
    public var offersQuickChoices: Bool { phase == .idle && text.isEmpty && card == nil }

    /// Runs a quick choice. Without a starting point it says so in `notice` and runs nothing.
    public func runQuickChoice(_ choice: FindQuickChoice) {
        guard let plan = choice.plan(mapRegion: region, location: location.current) else {
            notice = choice == .nearYou ? "Iter needs your location to look around you." : "Move the map to the area you want to search."
            return
        }
        notice = nil
        runDiscovery(plan.query, region: plan.region, quick: choice)
    }
}

// MARK: Today with no light left

/// Whether Today still has light to offer, decided from the windows the Conditions stage reports for each result and the clock.
public enum FindTodayLight {
    /// True when a window of daytime light (golden or blue hour) is still open or ahead at `now`.
    public static func hasLightLeft(windows: [LightWindowSpan], now: Date) -> Bool {
        windows.contains { $0.kind.isDaytimeLight && $0.end > now }
    }

    /// True when at least one result has reported and none of them has daytime light left: Today is over for all of them.
    /// Results still loading do not count either way, so the line never flashes while scores arrive.
    public static func isOver(results: [[LightWindowSpan]], now: Date) -> Bool {
        let reported = results.filter { !$0.isEmpty }
        return !reported.isEmpty && !reported.contains { hasLightLeft(windows: $0, now: now) }
    }
}

public struct LightWindowSpan: Equatable, Sendable {
    public var kind: LightWindowKind
    public var end: Date
    public init(kind: LightWindowKind, end: Date) { self.kind = kind; self.end = end }
}

extension FindModel {
    /// True while the Today choice's results have no daytime light left at the clock's now. The list says so in one quiet line and
    /// offers Tomorrow instead of a list of chips with nothing to show.
    public var todayLightIsOver: Bool {
        guard activeQuickChoice == .today, phase == .finished, let source = scoreSource else { return false }
        let windows: [[LightWindowSpan]] = scoreTargets.values.map { target in
            guard let report = source.state(for: target.place.id, day: target.day).report else { return [] }
            return report.daylight.windows.map { LightWindowSpan(kind: $0.kind, end: $0.span.end) }
        }
        return FindTodayLight.isOver(results: windows, now: now())
    }
}

extension LaunchOptions {
    /// `-IterNow 2026-11-23T01:19:00Z`: the clock a screenshot runs on, honoured only with `-IterInMemoryStore YES` so it can
    /// never move a real library's day. Nil when absent, malformed or not in-memory.
    public var fixedNow: Date? {
        guard inMemoryStore, let i = arguments.firstIndex(of: "-IterNow"), i + 1 < arguments.count else { return nil }
        return ISO8601DateFormatter().date(from: arguments[i + 1])
    }
}
