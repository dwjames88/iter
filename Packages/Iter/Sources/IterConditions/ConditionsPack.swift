import Foundation
import IterModel
import IterSources
import IterSky

/// A stop's place and the local days to collect for it.
public struct PackStop: Hashable, Sendable {
    public var place: Place
    public var days: [LocalDay]

    public init(place: Place, days: [LocalDay]) {
        self.place = place
        self.days = days
    }
}

/// The offline copy of a trip's conditions (BLUEPRINT §6.4, §10.7): one SkyReport per stop and day, written as one JSON
/// file `<packDirectory>/<tripID>.json`. Parts whose licence forbids storing (`mayStore == false`) are left out of the file.
public struct ConditionsPack: Codable, Hashable, Sendable {
    public struct Entry: Codable, Hashable, Sendable {
        public var placeID: UUID
        public var day: LocalDay
        public var report: SkyReport

        public init(placeID: UUID, day: LocalDay, report: SkyReport) {
            self.placeID = placeID
            self.day = day
            self.report = report
        }
    }

    public static let currentFormat = 1

    public var format: Int
    public var tripID: UUID
    public var builtAt: Date
    public var entries: [Entry]

    public init(format: Int = ConditionsPack.currentFormat, tripID: UUID, builtAt: Date, entries: [Entry]) {
        self.format = format
        self.tripID = tripID
        self.builtAt = builtAt
        self.entries = entries
    }

    /// How old the pack is.
    public func age(now: Date) -> Duration { .interval(max(0, now.timeIntervalSince(builtAt))) }

    public func entry(placeID: UUID, day: LocalDay) -> Entry? { entries.first { $0.placeID == placeID && $0.day == day } }
}

/// Why a pack could not be built or read.
public enum ConditionsError: Error, Sendable, Hashable {
    case packsDisabled
    case packWriteFailed(String)
}

struct PackEntry: Sendable {
    var tripID: UUID
    var builtAt: Date
    var report: SkyReport
}

extension ConditionsPack {
    /// A copy with everything whose licence says "do not store" removed.
    func scrubbedForStorage() -> ConditionsPack {
        var copy = self
        copy.entries = entries.map { Entry(placeID: $0.placeID, day: $0.day, report: $0.report.scrubbedForStorage()) }
        return copy
    }
}

extension SkyReport {
    /// Removes data that may not be written to disk.
    func scrubbedForStorage() -> SkyReport {
        var r = self
        func keep(_ p: Provenance?) -> Bool { p?.licence.mayStore ?? true }
        func gate<T: Sendable>(_ s: DataState<T>) -> DataState<T> { keep(s.provenance) ? s : .none([.notProvidedBySource]) }
        let blocked = Set(fieldProvenance.filter { !$0.provenance.licence.mayStore }.map(\.field))
        if !blocked.isEmpty, case .fresh(var s) = forecast {
            s.value = s.value.removing(blocked)
            r.forecast = .fresh(s)
        } else if !blocked.isEmpty, case .stale(var s, let age) = forecast {
            s.value = s.value.removing(blocked)
            r.forecast = .stale(s, age: age)
        }
        r.fieldProvenance = fieldProvenance.filter { keep($0.provenance) }
        var scrubbedAnything = !blocked.isEmpty
        if !keep(forecast.provenance), case .none = r.forecast {} else if !keep(forecast.provenance) {
            scrubbedAnything = true
            if let remaining = r.fieldProvenance.first?.provenance, let series = r.forecast.value {
                var p = remaining
                p.fetchedAt = r.fieldProvenance.map(\.provenance.fetchedAt).min() ?? remaining.fetchedAt
                let sourced = Sourced(value: series, provenance: p)
                if case .stale(_, let age) = r.forecast { r.forecast = .stale(sourced, age: age) } else { r.forecast = .fresh(sourced) }
            } else {
                r.forecast = .none([.notProvidedBySource])
            }
        }
        if !keep(comparison?.provenance) { r.comparison = nil }
        if !keep(smoke.opticalDepth?.provenance) { r.smoke.opticalDepth = nil }
        r.smoke.analysis = gate(smoke.analysis)
        r.observations = gate(observations)
        r.stationReports = gate(stationReports)
        r.alerts = gate(alerts)
        r.aurora = gate(aurora)
        r.horizon = gate(horizon)
        if scrubbedAnything {
            // Scores and lines were built partly from what may not be stored; they are rebuilt when the pack is read.
            r.daylight.windows = r.daylight.windows.map { LightWindow(kind: $0.kind, span: $0.span, assessment: .unavailable(.notLoaded)) }
            r.provenanceLines = []
        }
        return r
    }
}

extension HourlySeries {
    func removing(_ fields: Set<HourlyField>) -> HourlySeries {
        var s = self
        s.hours = hours.map { h in fields.reduce(h) { $0.setting($1, nil) } }
        for f in fields { s.fieldSources[f] = nil }
        return s
    }
}
