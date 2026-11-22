import Foundation
import IterModel
import IterSources

/// Rows from several files stitched into one series, with the provenance text. Pure.
enum NOMADSSeries {
    struct Row: Sendable {
        let ref: NOMADSFileRef
        let conditions: HourlyConditions
        let distanceKm: Double?
    }

    /// Sorts by time, keeps one row per valid time (the earlier row in `rows` wins, so callers list HRRR first) and
    /// records `source` for every field that appears.
    static func series(_ rows: [Row], source: SourceID) -> (series: HourlySeries, used: [Row]) {
        var byTime: [Date: Row] = [:]
        for r in rows where byTime[r.conditions.time] == nil { byTime[r.conditions.time] = r }
        let kept = byTime.values.sorted { $0.conditions.time < $1.conditions.time }
        var sources: [HourlyField: SourceID] = [:]
        for r in kept { for f in r.conditions.presentFields { sources[f] = source } }
        return (HourlySeries(hours: kept.map(\.conditions), fieldSources: sources), kept)
    }

    /// "HRRR 2026-11-22 12Z f01–f18; GFS 2026-11-22 06Z f019–f120", groups ordered by first valid time.
    static func modelDescription(_ refs: [NOMADSFileRef]) -> String {
        struct Key: Hashable { let model: NOMADSModel; let cycle: Date }
        var groups: [Key: [NOMADSFileRef]] = [:]
        for r in refs { groups[Key(model: r.model, cycle: r.cycle), default: []].append(r) }
        let ordered = groups.sorted { a, b in
            let ta = a.value.map(\.validTime).min() ?? .distantFuture, tb = b.value.map(\.validTime).min() ?? .distantFuture
            if ta != tb { return ta < tb }
            return a.key.model.rawValue < b.key.model.rawValue
        }
        return ordered.map { key, files in
            let lo = files.map(\.forecastHour).min() ?? 0, hi = files.map(\.forecastHour).max() ?? 0
            let hours = lo == hi ? key.model.hourLabel(lo) : "\(key.model.hourLabel(lo))–\(key.model.hourLabel(hi))"
            return "\(key.model.label) \(NOMADSTime.cycleLabel(key.cycle)) \(hours)"
        }.joined(separator: "; ")
    }
}
