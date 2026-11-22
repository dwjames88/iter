import Foundation
import IterModel

/// Weather averaged over a window (weighted by how long each forecast hour overlaps it).
struct WindowConditions: Equatable {
    /// Mean total cloud over the hours that give it; when none do, the mean of the largest layer per hour
    /// (`totalCloudIsDerived`).
    var totalCloud: Double
    var low: Double?
    var mid: Double?
    var high: Double?
    /// Mean chance over the hours that supply one; nil when none do.
    var precipChance: Double?
    /// Mean amount in mm per hour over the hours that supply one; nil when none do.
    var precipMm: Double?
    /// Mean visibility in km over the hours that supply one; nil when none do.
    var visibilityKm: Double?
    var aod550: Double?
    var smokeUgm3: Double?
    var rhPercent: Double?
    /// Mean sustained wind, m/s.
    var windMs: Double?
    /// Strongest gust of any hour in the window, m/s.
    var gustMs: Double?
    /// Mean of (temperature minus dewpoint) over the hours that have both, C.
    var dewpointSpreadC: Double?
    var totalCloudIsDerived = false

    /// All three layers were supplied for every hour of the window.
    var hasLayers: Bool { low != nil && mid != nil && high != nil }
}

/// Moon state at the middle of a window (night scoring only).
struct MoonLight: Equatable {
    var altitude: Double
    var illumination: Double
}

enum Aggregation {
    case conditions(WindowConditions)
    /// No hour of the series covers the window.
    case noHours
    /// Hours cover the window but give neither total cloud nor all three layers.
    case noCloud
}

extension LightEngine {
    /// Weather averaged over the hours overlapping `span`, weighted by overlap seconds.
    static func aggregate(_ series: HourlySeries, over span: TimeSpan) -> Aggregation {
        var hours = series.hours(overlapping: span).map { h -> (HourlyConditions, Double) in
            let overlap = min(span.end, h.time.addingTimeInterval(3600)).timeIntervalSince(max(span.start, h.time))
            return (h, max(0, overlap))
        }
        if hours.isEmpty || hours.reduce(0, { $0 + $1.1 }) <= 0 {
            // A window that has begun before the first forecast hour, or whose middle sits in a gap, uses the first hour.
            let first = series.hours.min { $0.time < $1.time }
            guard let h = series.hour(at: span.midpoint) ?? (span.midpoint < (first?.time ?? .distantPast) ? first : nil)
            else { return .noHours }
            hours = [(h, 1)]
        }
        func mean(_ f: (HourlyConditions) -> Double?) -> Double? {
            var sum = 0.0, w = 0.0
            for (h, overlap) in hours { if let v = f(h) { sum += v * overlap; w += overlap } }
            return w > 0 ? sum / w : nil
        }
        let hasLayers = hours.allSatisfy { $0.0.cloudLow != nil && $0.0.cloudMid != nil && $0.0.cloudHigh != nil }
        var total = mean(\.cloudTotal)
        var derived = false
        if total == nil, hasLayers {
            total = mean { h in
                guard let l = h.cloudLow, let m = h.cloudMid, let hi = h.cloudHigh else { return nil }
                return max(l, m, hi)
            }
            derived = true
        }
        guard let totalCloud = total else { return .noCloud }
        return .conditions(WindowConditions(
            totalCloud: totalCloud,
            low: hasLayers ? mean(\.cloudLow) : nil,
            mid: hasLayers ? mean(\.cloudMid) : nil,
            high: hasLayers ? mean(\.cloudHigh) : nil,
            precipChance: mean(\.precipChance),
            precipMm: mean(\.precipMm),
            visibilityKm: mean(\.visibilityKm),
            aod550: mean(\.aod550),
            smokeUgm3: mean(\.smokeUgm3),
            rhPercent: mean(\.rhPercent),
            windMs: mean(\.windMs),
            gustMs: hours.compactMap { $0.0.gustMs }.max(),
            dewpointSpreadC: mean { h in
                guard let t = h.tempC, let d = h.dewpointC else { return nil }
                return t - d
            },
            totalCloudIsDerived: derived))
    }

    /// The window's weather, or nil when there is none to read.
    static func conditions(in series: HourlySeries, over span: TimeSpan) -> WindowConditions? {
        if case .conditions(let c) = aggregate(series, over: span) { return c }
        return nil
    }
}
