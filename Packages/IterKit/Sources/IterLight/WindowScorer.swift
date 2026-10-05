import Foundation
import IterCore

/// Weather averaged over a window (weighted by how long each forecast hour overlaps it).
struct WindowConditions: Equatable {
    var totalCloud: Double
    var low: Double?
    var mid: Double?
    var high: Double?
    var precipitationChance: Double
    var visibilityMeters: Double

    /// All three layers were supplied for every hour of the window.
    var hasLayers: Bool { low != nil && mid != nil && high != nil }
}

/// Moon state at the middle of a window (night scoring only).
struct MoonLight: Equatable {
    var altitude: Double
    var illumination: Double
}

struct ScoredWindow: Equatable {
    var value: Int
    var contributors: [LightContributor]
    /// Cloud layers were needed for this window's kind and were missing, so the total-cloud fallback was used.
    var usedLayerFallback: Bool
}

/// Pure scoring heuristics. A score is a neutral baseline of 60 plus signed points per factor, clamped 5...100.
/// The floor is 5, not 0: a real but terrible forecast must never look like missing data ("0" reads as "nothing").
/// Every curve is piecewise linear, so a small change in weather moves the score a small amount.
/// There is no "best at" boost and no placeholder value: the inputs are the weather and the moon, nothing else.
enum WindowScorer {
    static let baseline = 60.0
    static let floor = 5.0

    // MARK: Curves (x, y). Cloud fractions are 0...1; visibility x is kilometres.

    /// Golden hour, with layers: colour cloud = the larger of mid and high. Peak colour at 30-50%.
    static let goldenColour: [(Double, Double)] = [(0, 66), (0.10, 68), (0.20, 78), (0.30, 82), (0.50, 82), (0.65, 76), (0.85, 58), (1, 46)]
    /// Golden hour without layers: total cloud only. Lower ceiling, because it cannot see where the cloud is.
    static let goldenTotal: [(Double, Double)] = [(0, 66), (0.10, 68), (0.25, 76), (0.50, 76), (0.65, 68), (0.85, 50), (1, 40)]
    /// Low cloud blocks the sun from the horizon. A little is fine, over 70% is poor.
    static let goldenLow: [(Double, Double)] = [(0, 5), (0.10, 3), (0.30, 0), (0.60, -30), (0.70, -48), (1, -58)]
    /// Thick overcast ceiling on the final score. At 85% total cloud the ceiling is 56 (Fair); it never allows Good or above.
    static let overcastCeiling: [(Double, Double)] = [(0.60, 100), (0.85, 56), (1, 40)]

    /// Blue hour is forgiving: a clean or lightly clouded sky gives a smooth gradient, overcast is muted.
    static let blueTotal: [(Double, Double)] = [(0, 74), (0.20, 78), (0.40, 78), (0.60, 68), (0.90, 50), (1, 44)]
    static let blueColourBonus: [(Double, Double)] = [(0, 0), (0.15, 0), (0.30, 8), (0.55, 8), (0.75, 0)]
    static let blueLow: [(Double, Double)] = [(0, 0), (0.40, 0), (0.80, -8), (1, -12)]

    /// Night wants a clear sky.
    static let nightTotal: [(Double, Double)] = [(0, 80), (0.15, 78), (0.40, 42), (0.70, 26), (1, 18)]
    /// Moon points by illuminated fraction while the moon is up (before scaling by altitude when negative).
    static let moonUp: [(Double, Double)] = [(0, 6), (0.25, 0), (0.50, -14), (1, -36)]
    static let moonDownBonus = 6.0

    static let precipitation: [(Double, Double)] = [(0, 0), (0.10, 0), (0.30, -8), (0.60, -25), (1, -40)]
    static let visibilityGolden: [(Double, Double)] = [(0, -28), (5, -8), (8, 0), (12, 0), (20, 2)]
    static let visibilityOther: [(Double, Double)] = [(0, -30), (5, -10), (10, 0), (12, 0), (20, 2)]

    // MARK: Scoring

    static func score(kind: LightWindowKind, conditions c: WindowConditions, moon: MoonLight?) -> ScoredWindow {
        var parts: [(LightContributor.Factor, Double, Double)] = []   // factor, points, value
        var fallback = false
        var ceilingAdjust = 0.0
        let total = c.totalCloud
        let clear = total < 0.10

        switch kind {
        case .goldenMorning, .goldenEvening:
            if let low = c.low, let mid = c.mid, let high = c.high {
                let colour = max(mid, high)
                parts.append((clear ? .clearSky : .midHighCloud, interp(colour, goldenColour) - baseline, clear ? total : colour))
                parts.append((.lowCloud, interp(low, goldenLow), low))
            } else {
                fallback = true
                parts.append((clear ? .clearSky : .totalCloud, interp(total, goldenTotal) - baseline, total))
            }
        case .blueMorning, .blueEvening:
            parts.append((clear ? .clearSky : .totalCloud, interp(total, blueTotal) - baseline, total))
            if let low = c.low, let mid = c.mid, let high = c.high {
                let colour = max(mid, high)
                // Colour in a blue-hour sky needs structure and a clear horizon.
                let horizon = interp(low, [(0, 1), (0.30, 1), (0.60, 0)])
                parts.append((.midHighCloud, interp(colour, blueColourBonus) * horizon, colour))
                parts.append((.lowCloud, interp(low, blueLow), low))
            } else {
                fallback = true
            }
        case .night:
            parts.append((.totalCloud, interp(total, nightTotal) - baseline, total))
            if let moon {
                let illum = moon.illumination
                if moon.altitude <= 0 {
                    parts.append((.darkSky, moonDownBonus, illum))
                } else {
                    var pts = interp(illum, moonUp)
                    if pts < 0 { pts *= min(1, moon.altitude / 10) }
                    parts.append((pts < 0 ? .moonlight : .darkSky, pts, illum))
                }
            }
        }

        parts.append((.precipitation, interp(c.precipitationChance, precipitation), c.precipitationChance))
        let visKm = c.visibilityMeters / 1000
        parts.append((.visibility, interp(visKm, kind.isGolden ? visibilityGolden : visibilityOther), c.visibilityMeters))

        var raw = baseline + parts.reduce(0) { $0 + $1.1 }
        if kind != .night {
            let ceiling = interp(total, overcastCeiling)
            if raw > ceiling {
                ceilingAdjust = ceiling - raw
                raw = ceiling
            }
        }
        if ceilingAdjust != 0 {
            if let i = parts.firstIndex(where: { $0.0 == .totalCloud }) {
                parts[i].1 += ceilingAdjust
            } else {
                parts.append((.totalCloud, ceilingAdjust, total))
            }
        }

        let unclamped = raw
        let value = Int(min(100, max(Self.floor, unclamped)).rounded())

        // Round each contributor, then put any rounding residue on the largest so the bars sum to the score.
        var rounded = parts.map { (factor: $0.0, points: Int($0.1.rounded()), value: $0.2) }
        if unclamped >= Self.floor, unclamped <= 100 {
            let residue = value - (Int(baseline) + rounded.reduce(0) { $0 + $1.points })
            if residue != 0, let i = rounded.indices.max(by: { abs(rounded[$0].points) < abs(rounded[$1].points) }) {
                rounded[i].points += residue
            }
        }
        // The primary cloud factor always appears; others only when they moved the score.
        let primary = rounded.first?.factor
        let contributors = rounded
            .filter { $0.points != 0 || $0.factor == primary }
            .map { LightContributor(factor: $0.factor, effect: $0.points >= 2 ? .helps : ($0.points <= -2 ? .hurts : .neutral),
                                    points: $0.points, value: $0.value) }
            .sorted { a, b in
                abs(a.points) != abs(b.points) ? abs(a.points) > abs(b.points) : a.factor.rawValue < b.factor.rawValue
            }
        return ScoredWindow(value: value, contributors: contributors, usedLayerFallback: fallback)
    }

    // MARK: Confidence

    static func confidence(leadHours: Double, layersMissing: Bool) -> Confidence {
        var level: Int = leadHours <= 36 ? 2 : (leadHours <= 72 ? 1 : 0)
        if layersMissing { level = max(0, level - 1) }
        return level == 2 ? .high : (level == 1 ? .medium : .low)
    }

    static func range(value: Int, confidence: Confidence) -> ClosedRange<Int> {
        let spread: Int
        switch confidence {
        case .high: spread = 0
        case .medium: spread = 8
        case .low: spread = 15
        }
        return max(0, value - spread)...min(100, value + spread)
    }

    // MARK: Helpers

    /// Piecewise-linear interpolation, clamped to the end points.
    static func interp(_ x: Double, _ pts: [(Double, Double)]) -> Double {
        guard let first = pts.first, let last = pts.last else { return 0 }
        if x <= first.0 { return first.1 }
        if x >= last.0 { return last.1 }
        for i in 1..<pts.count where x <= pts[i].0 {
            let (x0, y0) = pts[i - 1], (x1, y1) = pts[i]
            return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
        }
        return last.1
    }
}
