import Foundation
import IterModel
import IterSources

/// One valid time to fetch and the files that can supply it, most preferred first: HRRR cycles (newest first), then GFS
/// cycles (newest first), at most three per model. The provider takes the first file that is actually posted.
public struct NOMADSPlannedHour: Sendable, Hashable {
    public let validTime: Date
    public let alternatives: [NOMADSFileRef]
    public var primary: NOMADSFileRef? { alternatives.first }
}

/// The hours to fetch for a span.
public struct NOMADSHourPlan: Sendable, Hashable {
    public let hours: [NOMADSPlannedHour]
    /// True when the span exceeded 72 h and only 3-hourly valid times were planned.
    public let thinned: Bool

    public var isEmpty: Bool { hours.isEmpty }
    /// The preferred file of every hour: what a normal run requests.
    public var primaryFiles: [NOMADSFileRef] { hours.compactMap(\.primary) }
}

/// Which model cycles are likely posted at a time, and which (model, cycle, forecast hour) files cover a span. Pure.
///
/// Posting times are estimates from observation (SOURCES.md §2.2: HRRR f01 about 53 min after the cycle) and general
/// knowledge: HRRR file `fh` appears about 53 min + 1.5 min × fh after its cycle (f01 about 55 min, f18 about 1 h 20 min,
/// f48 about 2 h 5 min); GFS file `fh` about 3 h 30 min + 9 s × fh (f001 about 3.5 h, f384 about 4.5 h). The provider does
/// not trust them: a 404 moves it to the previous cycle.
///
/// No interpolation: rows stay at each model's native valid times. HRRR is hourly; GFS is hourly to f120 and 3-hourly to
/// f384. For a valid time both models can supply, HRRR is preferred. Valid times before a model's first hour are never
/// invented: the first row of a cycle is its f01.
public enum NOMADSCyclePlanner {
    /// Spans longer than this plan 3-hourly valid times only (UTC hours divisible by 3), to bound the request count.
    public static let thinningThreshold: TimeInterval = 72 * 3600
    /// Most cycles considered per model for one valid time.
    public static let maxCyclesPerModel = 3

    // MARK: Posting

    /// When a file is likely to be on the server.
    public static func likelyAvailable(_ ref: NOMADSFileRef) -> Date {
        let fh = Double(ref.forecastHour)
        switch ref.model {
        case .hrrr: return ref.cycle.addingTimeInterval(53 * 60 + 90 * fh)
        case .gfs: return ref.cycle.addingTimeInterval(3.5 * 3600 + 9 * fh)
        }
    }

    public static func isLikelyPosted(_ ref: NOMADSFileRef, now: Date) -> Bool { likelyAvailable(ref) <= now }

    /// The newest cycle at or before `time`.
    static func newestCycle(_ model: NOMADSModel, atOrBefore time: Date) -> Date {
        let h = NOMADSTime.floorHour(time)
        let hour = NOMADSTime.hour(of: h)
        let back = hour % model.cycleStepHours
        return h.addingTimeInterval(-TimeInterval(back) * 3600)
    }

    /// Candidate cycles, newest first, whose file for `forecastHour` is likely posted at `now` (at most `count`).
    public static func candidateCycles(_ model: NOMADSModel, now: Date, count: Int = maxCyclesPerModel,
                                       forecastHour: Int = 1) -> [Date] {
        var result: [Date] = []
        var cycle = newestCycle(model, atOrBefore: now)
        let lookback = model == .hrrr ? 30 : 8
        for _ in 0..<lookback where result.count < count {
            let ref = NOMADSFileRef(model: model, cycle: cycle, forecastHour: forecastHour)
            if model.publishes(forecastHour: forecastHour, cycleHourUTC: ref.cycleHourUTC), isLikelyPosted(ref, now: now) {
                result.append(cycle)
            }
            cycle = cycle.addingTimeInterval(-TimeInterval(model.cycleStepHours) * 3600)
        }
        return result
    }

    /// The files that can supply `validTime`, preferred first (see `NOMADSPlannedHour`). `unavailable` removes files
    /// already known to be missing.
    public static func alternatives(for validTime: Date, now: Date, models: [NOMADSModel],
                                    unavailable: (NOMADSFileRef) -> Bool = { _ in false }) -> [NOMADSFileRef] {
        var result: [NOMADSFileRef] = []
        for model in NOMADSModel.allCases where models.contains(model) {
            var cycle = newestCycle(model, atOrBefore: now)
            var found = 0
            let lookback = model == .hrrr ? 30 : 8
            for _ in 0..<lookback where found < maxCyclesPerModel {
                let fh = Int(((validTime.timeIntervalSince(cycle)) / 3600).rounded())
                let ref = NOMADSFileRef(model: model, cycle: cycle, forecastHour: fh)
                if model.publishes(forecastHour: fh, cycleHourUTC: ref.cycleHourUTC), isLikelyPosted(ref, now: now),
                   !unavailable(ref) {
                    result.append(ref)
                    found += 1
                }
                cycle = cycle.addingTimeInterval(-TimeInterval(model.cycleStepHours) * 3600)
            }
        }
        return result
    }

    // MARK: Plan

    /// The valid times to fetch for `span`: every available valid time inside it plus the one at or before its start and
    /// the one at or after its end (to bracket both ends), each with its alternatives.
    ///
    /// - A span entirely before the first available valid time, or entirely after the last, gives an empty plan.
    /// - A span starting before the first available valid time starts there (rows are never invented).
    /// - Spans over 72 h keep only valid times at UTC hours divisible by 3, for both models.
    public static func plan(span: TimeSpan, now: Date, models: [NOMADSModel] = NOMADSModel.allCases,
                            unavailable: (NOMADSFileRef) -> Bool = { _ in false }) -> NOMADSHourPlan {
        let thin = span.duration > thinningThreshold
        let earliest = NOMADSTime.floorHour(now).addingTimeInterval(-48 * 3600)
        let latest = NOMADSTime.floorHour(now).addingTimeInterval(400 * 3600)
        var t = max(earliest, NOMADSTime.floorHour(span.start).addingTimeInterval(-3 * 3600))
        let end = min(latest, NOMADSTime.ceilHour(span.end).addingTimeInterval(3 * 3600))
        var all: [NOMADSPlannedHour] = []
        while t <= end {
            if !thin || NOMADSTime.hour(of: t) % 3 == 0 {
                let alts = alternatives(for: t, now: now, models: models, unavailable: unavailable)
                if !alts.isEmpty { all.append(NOMADSPlannedHour(validTime: t, alternatives: alts)) }
            }
            t = t.addingTimeInterval(3600)
        }
        guard let first = all.first, let last = all.last, span.end >= first.validTime, span.start <= last.validTime else {
            return NOMADSHourPlan(hours: [], thinned: thin)
        }
        let lo = all.lastIndex { $0.validTime <= span.start } ?? 0
        let hi = all.firstIndex { $0.validTime >= span.end } ?? (all.count - 1)
        return NOMADSHourPlan(hours: Array(all[lo...max(lo, hi)]), thinned: thin)
    }
}
