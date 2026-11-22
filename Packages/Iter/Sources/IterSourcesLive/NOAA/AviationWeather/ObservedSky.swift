import Foundation
import IterModel
import IterSources

/// Shared rules for turning observed cloud layers and surface values into `HourlyConditions` (METAR and NWS).
///
/// Cloud bands by base above ground: low below 2000 m, mid 2000 to 6000 m, high above 6000 m.
/// `cloudTotal` is the largest layer fraction (FEW 0.19, SCT 0.44, BKN 0.75, OVC and VV 1.0); CLR, SKC and NSC give 0.
/// `cloudLow` is the largest low-band fraction (0 when the report has a sky group but no low layer). `cloudMid` and
/// `cloudHigh` are set only when a layer exists in the band, or for SKC (a human-confirmed clear sky): automated
/// ceilometers do not see above about 3660 m, so a missing mid or high layer is not evidence of clear sky there.
/// Without a sky group (partial reports, CAVOK) every cloud field stays nil.
enum ObservedSky {
    static let lowBandTopM = 2000.0
    static let midBandTopM = 6000.0

    static func conditions(time: Date, tempC: Double?, dewpointC: Double?, windDirDeg: Double?, windMs: Double?,
                           gustMs: Double?, visibilityKm: Double?, layers: [CloudLayer], hasSkyGroup: Bool,
                           precipMm: Double? = nil, rhPercent: Double? = nil,
                           computeHumidity: Bool = true) -> HourlyConditions {
        var c = HourlyConditions(time: time)
        c.tempC = tempC
        c.dewpointC = dewpointC
        c.windDirDeg = windDirDeg
        c.windMs = windMs
        c.gustMs = gustMs
        c.visibilityKm = visibilityKm
        c.precipMm = precipMm
        if let rh = rhPercent { c.rhPercent = rh } else if computeHumidity, let t = tempC, let d = dewpointC { c.rhPercent = relativeHumidity(tempC: t, dewpointC: d) }
        guard hasSkyGroup, !layers.isEmpty else { return c }
        let clearOnly = layers.allSatisfy { [.skc, .clr, .nsc].contains($0.cover) }
        if clearOnly {
            c.cloudTotal = 0
            c.cloudLow = 0
            if layers.contains(where: { $0.cover == .skc }) { c.cloudMid = 0; c.cloudHigh = 0 }
            return c
        }
        c.cloudTotal = layers.map(\.fraction).max()
        func band(_ range: Range<Double>) -> Double? {
            layers.filter { $0.baseM.map(range.contains) ?? false }.map(\.fraction).max()
        }
        c.cloudLow = band(0..<lowBandTopM) ?? 0
        c.cloudMid = band(lowBandTopM..<midBandTopM)
        c.cloudHigh = band(midBandTopM..<Double.greatestFiniteMagnitude)
        c.cloudBaseM = layers.filter { [.bkn, .ovc, .vv].contains($0.cover) }.compactMap(\.baseM).min()
        return c
    }

    /// Relative humidity from temperature and dewpoint (Magnus, constants 17.625 and 243.04 °C), clamped to 0...100.
    static func relativeHumidity(tempC: Double, dewpointC: Double) -> Double {
        let a = 17.625, b = 243.04
        let rh = 100 * exp(a * dewpointC / (b + dewpointC)) / exp(a * tempC / (b + tempC))
        return min(100, max(0, rh))
    }
}
