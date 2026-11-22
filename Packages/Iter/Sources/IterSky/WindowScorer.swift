import Foundation
import IterModel
import IterAstro

/// Aurora facts for one window, already reduced from the outlook.
struct AuroraSignal: Equatable {
    /// An outlook exists (even when it says nothing is likely).
    var outlookPresent = false
    var probabilityPercent: Double?
    /// Highest Kp of the steps overlapping the window.
    var kp: Double?
    /// Probability at least 10% or Kp at or above the latitude threshold.
    var triggered = false
}

/// What the score needs beyond the weather.
struct ScoringExtras: Equatable {
    /// Golden and blue windows: what the skyline does. nil means no horizon is known.
    var terrain: TerrainAssessment?
    /// Night: the galactic core over the window.
    var milkyWay: MilkyWayVisibility?
    var aurora: AuroraSignal?
    var bortle: Double?
    var seeing: Double?
    var latitude: Double = 0
}

struct ScoredWindow: Equatable {
    /// Clamped to 0...100.
    var value: Int
    /// Rounded raw score before clamping.
    var raw: Int
    var contributors: [LightContributor]
    /// Cloud layers were needed for this window's kind and were missing, so the total-cloud fallback was used.
    var usedLayerFallback: Bool
    var notes: [SkyNote] = []
    var flags: [SkyFlag] = []
    var used: [SkyInput] = []
    var missingPrimary: [SkyInput] = []
    var missingSecondary: [SkyInput] = []
    var transparency: Double?
}

/// Pure scoring heuristics. A score is a neutral baseline of 60 plus signed points per factor, clamped to 0...100
/// (D14: the old floor of 5 hid how bad a window was; a clamp is now reported as a note).
/// Every curve is piecewise linear, so a small change in weather moves the score a small amount.
/// There is no "best at" boost and no placeholder value: the inputs are the weather, the sky and the moon, nothing else.
///
/// The old curves (cloud, precipitation, visibility, moon) are ported unchanged. The factors added in Phase 3
/// (aerosol, humidity, wind, terrain, Milky Way, Bortle, seeing) are first guesses pending calibration against
/// photographers' ratings; they are small on purpose.
enum WindowScorer {
    static let baseline = 60.0
    static let floor = 0.0
    static let ceiling = 100.0

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
    /// Precipitation by amount (mm per hour), used only when the source gives no chance. Reaches the same -40 as a
    /// 100% chance at 2 mm/h (steady rain); 0.2 mm/h (drizzle) costs 4 points, 0.5 mm/h 12, 1 mm/h 25.
    static let precipitationAmount: [(Double, Double)] = [(0, 0), (0.05, 0), (0.2, -4), (0.5, -12), (1, -25), (2, -40)]
    static let visibilityGolden: [(Double, Double)] = [(0, -28), (5, -8), (8, 0), (12, 0), (20, 2)]
    static let visibilityOther: [(Double, Double)] = [(0, -30), (5, -10), (10, 0), (12, 0), (20, 2)]

    // MARK: Curves added in Phase 3 (first guesses, pending calibration)

    /// Golden and blue, by aerosol optical depth at 550 nm: light to moderate aerosol scatters the red a little more
    /// (+4 at 0.15 to 0.3), heavy aerosol dims everything (-10 at 0.6, -20 from 1.0).
    static let aerosolColourAOD: [(Double, Double)] = [(0, 0), (0.05, 0), (0.15, 4), (0.30, 4), (0.60, -10), (1.0, -20)]
    /// The same, by near-surface smoke in micrograms per cubic metre (+4 at 10 to 30, -20 from 150).
    static let aerosolColourSmoke: [(Double, Double)] = [(0, 0), (5, 0), (10, 4), (30, 4), (60, -4), (100, -12), (150, -20)]
    /// Night, by AOD: transparency only, so a monotone penalty.
    static let aerosolNightAOD: [(Double, Double)] = [(0, 0), (0.10, 0), (0.30, -3), (0.60, -8), (1.0, -14)]
    static let aerosolNightSmoke: [(Double, Double)] = [(0, 0), (10, 0), (30, -3), (100, -9), (150, -14)]
    /// Night humidity above 90%: dew on the lens and a little less transparency, up to -4.
    static let humidityNight: [(Double, Double)] = [(90, 0), (100, -4)]
    /// Blue hour with a tall skyline toward the sun: -4 at 8 degrees and up.
    static let blueSkyline: [(Double, Double)] = [(5, 0), (8, -4)]
    /// Golden hour: points lost at the fraction of the window the skyline takes (-30 when all of it).
    static let terrainGoldenLoss = -30.0
    static let milkyWayBonus = 4.0
    /// Bortle class (1 darkest): 1 to 3 helps, 7 to 9 hurts. Only applied when the caller supplies it.
    static let bortle: [(Double, Double)] = [(1, 6), (3, 3), (4, 0), (5, -2), (6, -5), (7, -8), (9, -14)]
    /// Seeing in arcseconds (smaller is steadier). Only applied when the caller supplies it.
    static let seeing: [(Double, Double)] = [(1.0, 3), (1.5, 3), (2.5, 0), (4, -4)]

    static let windSustainedLimit = 8.0
    static let windGustLimit = 12.0
    static let fogSpreadLimit = 2.0
    static let fogHumidityLimit = 95.0
    static let fogWindLimit = 3.0

    // MARK: Scoring

    static func score(kind: LightWindowKind, conditions c: WindowConditions, moon: MoonLight?,
                      extras: ScoringExtras = ScoringExtras()) -> ScoredWindow {
        var parts: [(LightContributor.Factor, Double, Double)] = []   // factor, points, value
        var fallback = false
        var notes: [SkyNote] = []
        var flags: [SkyFlag] = []
        var used: [SkyInput] = []
        var missingPrimary: [SkyInput] = []
        var missingSecondary: [SkyInput] = []
        var transparency: Double?
        var ceilingAdjust = 0.0
        let total = c.totalCloud
        let clear = total < 0.10

        if c.totalCloudIsDerived {
            missingPrimary.append(.cloudTotal)
        } else {
            used.append(.cloudTotal)
        }

        switch kind {
        case .goldenMorning, .goldenEvening:
            if let low = c.low, let mid = c.mid, let high = c.high {
                let colour = max(mid, high)
                parts.append((clear ? .clearSky : .midHighCloud, interp(colour, goldenColour) - baseline, clear ? total : colour))
                parts.append((.lowCloud, interp(low, goldenLow), low))
                used.append(.cloudLayers)
            } else {
                fallback = true
                missingPrimary.append(.cloudLayers)
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
                used.append(.cloudLayers)
            } else {
                fallback = true
                missingPrimary.append(.cloudLayers)
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
                used.append(.moon)
            }
        }

        // Precipitation (a primary input).
        if let chance = c.precipChance {
            parts.append((.precipitation, interp(chance, precipitation), chance))
            used.append(.precipitation)
        } else if let mm = c.precipMm {
            // The contributor's value is mm per hour here (see SkyNote.precipitationFromAmount).
            parts.append((.precipitation, interp(mm, precipitationAmount), mm))
            notes.append(.precipitationFromAmount)
            used.append(.precipitation)
        } else {
            missingPrimary.append(.precipitation)
        }

        // Visibility (secondary).
        if let visibility = c.visibilityKm {
            parts.append((.visibility, interp(visibility, kind.isGolden ? visibilityGolden : visibilityOther), visibility))
            used.append(.visibility)
        } else {
            missingSecondary.append(.visibility)
        }

        // Aerosol and smoke (secondary): every window kind.
        if let aod = c.aod550 {
            let curve = kind == .night ? aerosolNightAOD : aerosolColourAOD
            parts.append((.aerosol, interp(aod, curve), aod))
            used.append(.aerosol)
        } else if let smoke = c.smokeUgm3 {
            let curve = kind == .night ? aerosolNightSmoke : aerosolColourSmoke
            parts.append((.aerosol, interp(smoke, curve), smoke))
            used.append(.smoke)
        } else {
            missingSecondary.append(.aerosol)
        }

        // Fog and mist: a flag on morning windows, no points.
        if kind == .blueMorning || kind == .goldenMorning {
            let damp = (c.dewpointSpreadC.map { $0 <= fogSpreadLimit } ?? false) || (c.rhPercent.map { $0 >= fogHumidityLimit } ?? false)
            if damp, let wind = c.windMs, wind < fogWindLimit { flags.append(.fogPossible) }
        }

        // Wind (blue and night, secondary): a small penalty and a flag.
        if kind.isBlue || kind == .night {
            if c.windMs != nil || c.gustMs != nil {
                used.append(.wind)
                let sustained = c.windMs ?? 0, gust = c.gustMs ?? 0
                if sustained > windSustainedLimit || gust > windGustLimit {
                    let excess = max((sustained - windSustainedLimit) / windSustainedLimit, (gust - windGustLimit) / windGustLimit, 0)
                    parts.append((.wind, -(2 + 4 * min(1, excess / 0.5)), max(sustained, gust / 1.5)))
                    flags.append(.longExposureWind)
                }
            } else {
                missingSecondary.append(.wind)
            }
        }

        // Terrain horizon (golden and blue, secondary).
        if kind != .night {
            if let t = extras.terrain {
                used.append(.horizon)
                if kind.isGolden {
                    if t.fractionLost > 0 {
                        parts.append((.terrain, terrainGoldenLoss * t.fractionLost, t.fractionLost))
                        notes.append(.terrainEndsWindowEarly(by: t.lostSeconds))
                    }
                } else if let skyline = t.skylineDegrees {
                    parts.append((.terrain, interp(skyline, blueSkyline), skyline))
                }
            } else {
                missingSecondary.append(.horizon)
            }
        }

        // Night-only terms.
        if kind == .night {
            if let rh = c.rhPercent {
                parts.append((.humidity, interp(rh, humidityNight), rh))
                used.append(.humidity)
            } else {
                missingSecondary.append(.humidity)
            }

            if let mw = extras.milkyWay {
                used.append(.galacticCentre)
                if mw.isVisible {
                    flags.append(.milkyWayCore(best: mw.bestWindow, peakAltitude: mw.peakAltitude))
                    if mw.bestWindow != nil { parts.append((.milkyWay, milkyWayBonus, mw.peakAltitude)) }
                }
            }

            if let aurora = extras.aurora {
                if aurora.outlookPresent {
                    used.append(.aurora)
                    if aurora.triggered { flags.append(.aurora(probability: aurora.probabilityPercent, kp: aurora.kp)) }
                } else if abs(extras.latitude) >= 45 {
                    missingSecondary.append(.aurora)
                }
            }

            if let bortle = extras.bortle {
                parts.append((.lightPollution, interp(bortle, Self.bortle), bortle))
                used.append(.lightPollution)
            } else {
                missingSecondary.append(.lightPollution)
            }
            if let seeing = extras.seeing {
                parts.append((.seeing, interp(seeing, Self.seeing), seeing))
                used.append(.seeing)
            } else {
                missingSecondary.append(.seeing)
            }

            transparency = transparencyProxy(c)
            if transparency != nil { notes.append(.transparencyFromProxy) }
        }

        var raw = baseline + parts.reduce(0) { $0 + $1.1 }
        if kind != .night {
            let limit = interp(total, overcastCeiling)
            if raw > limit {
                ceilingAdjust = limit - raw
                raw = limit
            }
        }
        if ceilingAdjust != 0 {
            if let i = parts.firstIndex(where: { $0.0 == .totalCloud }) {
                parts[i].1 += ceilingAdjust
            } else {
                parts.append((.totalCloud, ceilingAdjust, total))
            }
        }

        let rawRounded = Int(raw.rounded())
        let value = Int(min(ceiling, max(floor, raw)).rounded())
        if rawRounded < 0 { notes.append(.clampedLow) }
        if rawRounded > 100 { notes.append(.clampedHigh) }

        // Round each contributor, then put any rounding residue on the largest so the bars sum to the raw score.
        var rounded = parts.map { (factor: $0.0, points: Int($0.1.rounded()), value: $0.2) }
        let residue = rawRounded - (Int(baseline) + rounded.reduce(0) { $0 + $1.points })
        if residue != 0, let i = rounded.indices.max(by: { abs(rounded[$0].points) < abs(rounded[$1].points) }) {
            rounded[i].points += residue
        }
        // The primary cloud factor always appears; others only when they moved the score.
        let primary = rounded.first?.factor
        let layers: CloudLayers? = {
            guard let low = c.low, let mid = c.mid, let high = c.high else { return nil }
            return CloudLayers(low: low, mid: mid, high: high)
        }()
        let contributors = rounded
            .filter { $0.points != 0 || $0.factor == primary }
            .map { LightContributor(factor: $0.factor, effect: $0.points >= 2 ? .helps : ($0.points <= -2 ? .hurts : .neutral),
                                    points: $0.points, value: $0.value,
                                    layers: ($0.factor == .midHighCloud || $0.factor == .lowCloud) ? layers : nil) }
            .sorted { a, b in
                abs(a.points) != abs(b.points) ? abs(a.points) > abs(b.points) : a.factor.rawValue < b.factor.rawValue
            }

        for input in missingPrimary + missingSecondary { notes.append(.missing(input)) }
        return ScoredWindow(value: value, raw: rawRounded, contributors: contributors, usedLayerFallback: fallback, notes: notes,
                            flags: flags, used: used, missingPrimary: missingPrimary, missingSecondary: missingSecondary,
                            transparency: transparency)
    }

    /// Night transparency 0...1 (1 clear and dry) from aerosol, humidity and high cloud. It needs an aerosol figure and at
    /// least one other component; weights are 0.5, 0.25 and 0.25 over the components present. An estimate, not a measurement.
    static func transparencyProxy(_ c: WindowConditions) -> Double? {
        let aerosol: Double? = c.aod550.map { min(1, $0 / 1.0) } ?? c.smokeUgm3.map { min(1, $0 / 150) }
        guard let aerosol else { return nil }
        var weighted = 0.5 * aerosol, weight = 0.5
        if let rh = c.rhPercent {
            weighted += 0.25 * min(1, max(0, (rh - 60) / 40))
            weight += 0.25
        }
        if let high = c.high {
            weighted += 0.25 * min(1, max(0, high))
            weight += 0.25
        }
        guard weight > 0.5 else { return nil }
        return min(1, max(0, 1 - weighted / weight))
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
