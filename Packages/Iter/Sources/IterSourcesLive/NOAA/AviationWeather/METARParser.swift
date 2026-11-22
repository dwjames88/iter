import Foundation
import IterModel
import IterSources

/// A raw METAR/SPECI parsed into the groups it actually contains. A missing group is nil (or empty), never zero:
/// `METAR KNID 221256Z AUTO A3006 RMK AO2 SLPNO PWINO $` has no wind, visibility or sky.
public struct ParsedMETAR: Sendable, Hashable {
    public var stationID: String?
    public var day: Int?
    public var hour: Int?
    public var minute: Int?
    public var isAutomated = false
    public var isSpecial = false
    public var isCorrection = false
    /// Direction the wind blows from. Nil for variable (VRB) winds and when there is no wind group. 0 for calm (00000KT).
    public var windDirectionDeg: Double?
    public var windIsVariable = false
    public var windMs: Double?
    public var gustMs: Double?
    /// Prevailing visibility in km (SM and metre groups). 9999 is reported as 10 km, P6SM as 6 SM.
    public var visibilityKm: Double?
    public var isCAVOK = false
    /// Cloud groups in report order (lowest first as issued). CLR, SKC and NSC appear as a single layer without base.
    public var cloudLayers: [CloudLayer] = []
    /// True when a cloud or clear-sky group was present (CAVOK does not count: it says nothing above 1500 m).
    public var hasSkyGroup = false
    /// Present weather groups, e.g. "-RA", "BR", "+TSRA". Recent weather (RERA) and trend groups are excluded.
    public var weather: [String] = []
    /// Whole degrees from the body group, or tenths when the remarks' T group is present.
    public var tempC: Double?
    public var dewpointC: Double?
    public var altimeterHPa: Double?
    /// Everything after RMK.
    public var remarks: String?

    /// The observation time on or before `reference` that matches the report's day, hour and minute (UTC).
    public func observationTime(relativeTo reference: Date) -> Date? {
        guard let day, let hour, let minute else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = cal.dateComponents([.year, .month], from: reference)
        for back in 0...2 {
            guard let monthStart = cal.date(from: comps).flatMap({ cal.date(byAdding: .month, value: -back, to: $0) }) else { continue }
            let ym = cal.dateComponents([.year, .month], from: monthStart)
            guard let d = cal.date(from: DateComponents(year: ym.year, month: ym.month, day: day, hour: hour, minute: minute)),
                  cal.component(.day, from: d) == day else { continue }
            if d <= reference.addingTimeInterval(3600) { return d }
        }
        return nil
    }

    /// The parsed values as an observation's conditions at `time` (see `ObservedSky` for the cloud rules).
    public func conditions(time: Date) -> HourlyConditions {
        ObservedSky.conditions(time: time, tempC: tempC, dewpointC: dewpointC, windDirDeg: windDirectionDeg, windMs: windMs,
                               gustMs: gustMs, visibilityKm: visibilityKm, layers: cloudLayers, hasSkyGroup: hasSkyGroup)
    }
}

/// Pure METAR text parser (ICAO Annex 3 / FMH-1 groups). No I/O, no clock.
public enum METARParser {
    static let knotsToMs = 0.514444
    static let statuteMileKm = 1.609344
    static let feetToM = 0.3048

    public static func parse(_ raw: String) -> ParsedMETAR {
        var out = ParsedMETAR()
        var tenthsTemp: Double?, tenthsDew: Double?
        var tokens = raw.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" }).map(String.init)
        if let rmk = tokens.firstIndex(of: "RMK") {
            let rest = tokens[(rmk + 1)...].joined(separator: " ")
            out.remarks = rest.isEmpty ? nil : rest
            // The remarks' T group carries temperature and dewpoint in tenths: T10221050 is -2.2 and -5.0 degrees.
            if let m = tokens[(rmk + 1)...].compactMap({ $0.wholeMatch(of: #/^T([01])(\d{3})([01])(\d{3})$/#) }).first,
               let t = Double(m.output.2), let d = Double(m.output.4) {
                tenthsTemp = (m.output.1 == "1" ? -t : t) / 10
                tenthsDew = (m.output.3 == "1" ? -d : d) / 10
            }
            tokens = Array(tokens[..<rmk])
        }
        var i = 0
        var sawStation = false
        var sawWind = false
        while i < tokens.count {
            let t = tokens[i]
            i += 1
            if t == "TEMPO" || t == "BECMG" { break }
            switch t {
            case "METAR": continue
            case "SPECI": out.isSpecial = true; continue
            case "AUTO": out.isAutomated = true; continue
            case "COR": out.isCorrection = true; continue
            case "CAVOK":
                out.isCAVOK = true
                out.visibilityKm = 10
                continue
            case "SKC", "CLR", "NSC", "NCD":
                out.hasSkyGroup = true
                out.cloudLayers.append(CloudLayer(cover: t == "SKC" ? .skc : (t == "NSC" ? .nsc : .clr), baseM: nil))
                continue
            default: break
            }
            if !sawStation {
                if t.count == 4, t.allSatisfy({ $0.isLetter || $0.isNumber }), t.first!.isLetter {
                    out.stationID = t
                    sawStation = true
                    continue
                }
            }
            if out.day == nil, let m = t.wholeMatch(of: #/^(\d{2})(\d{2})(\d{2})Z$/#) {
                out.day = Int(m.output.1)
                out.hour = Int(m.output.2)
                out.minute = Int(m.output.3)
                continue
            }
            if !sawWind, let m = t.wholeMatch(of: #/^(\d{3}|VRB|\/\/\/)(\d{2,3}|\/\/)(?:G(\d{2,3}))?(KT|MPS|KMH)$/#) {
                sawWind = true
                let factor: Double = switch String(m.output.4) { case "KT": knotsToMs; case "KMH": 1 / 3.6; default: 1 }
                if m.output.1 == "VRB" { out.windIsVariable = true } else if let d = Double(m.output.1) { out.windDirectionDeg = d }
                if let s = Double(m.output.2) { out.windMs = s * factor }
                if let g = m.output.3.flatMap({ Double($0) }) { out.gustMs = g * factor }
                continue
            }
            if t.wholeMatch(of: #/^\d{3}V\d{3}$/#) != nil { continue }
            if out.visibilityKm == nil, let km = visibility(t, next: i < tokens.count ? tokens[i] : nil, consumedNext: &i) {
                out.visibilityKm = km
                continue
            }
            if let m = t.wholeMatch(of: #/^(FEW|SCT|BKN|OVC|VV)(\d{3}|\/\/\/)(CB|TCU|\/\/\/)?$/#) {
                out.hasSkyGroup = true
                let cover: CloudLayer.Cover = switch String(m.output.1) {
                case "FEW": .few; case "SCT": .sct; case "BKN": .bkn; case "OVC": .ovc; default: .vv
                }
                let base = Double(m.output.2).map { $0 * 100 * feetToM }
                let type = m.output.3.map(String.init).flatMap { $0 == "///" ? nil : $0 }
                out.cloudLayers.append(CloudLayer(cover: cover, baseM: base, type: type))
                continue
            }
            if out.tempC == nil, let m = t.wholeMatch(of: #/^(M?\d{2}|\/\/)\/(M?\d{2}|\/\/)?$/#) {
                out.tempC = signedTemp(m.output.1)
                out.dewpointC = m.output.2.flatMap { signedTemp($0) }
                continue
            }
            if let m = t.wholeMatch(of: #/^A(\d{4})$/#), let v = Double(m.output.1) {
                out.altimeterHPa = v / 100 * 33.8639
                continue
            }
            if let m = t.wholeMatch(of: #/^Q(\d{4})$/#), let v = Double(m.output.1) {
                out.altimeterHPa = v
                continue
            }
            if isWeatherGroup(t) { out.weather.append(t) }
        }
        if out.tempC != nil, let tenthsTemp {
            out.tempC = tenthsTemp
            if out.dewpointC != nil, let tenthsDew { out.dewpointC = tenthsDew }
        }
        return out
    }

    private static func signedTemp(_ s: Substring) -> Double? {
        if s == "//" { return nil }
        if s.hasPrefix("M") { return Double(s.dropFirst()).map { -$0 } }
        return Double(s)
    }

    /// Visibility groups: `9999`, `7000NDV`, `10SM`, `P6SM`, `M1/4SM`, `1/2SM`, and `1 1/2SM` (consumes the next token).
    private static func visibility(_ t: String, next: String?, consumedNext i: inout Int) -> Double? {
        if let m = t.wholeMatch(of: #/^(\d{4})(?:NDV)?$/#), let metres = Double(m.output.1) {
            return metres == 9999 ? 10 : metres / 1000
        }
        if t.hasSuffix("SM") {
            var body = String(t.dropLast(2))
            if body.hasPrefix("P") || body.hasPrefix("M") { body.removeFirst() }
            guard let v = fraction(body) else { return nil }
            return v * statuteMileKm
        }
        if t.wholeMatch(of: #/^\d{1,2}$/#) != nil, let next, next.hasSuffix("SM"), next.contains("/"),
           let whole = Double(t), let frac = fraction(String(next.dropLast(2))) {
            i += 1
            return (whole + frac) * statuteMileKm
        }
        return nil
    }

    private static func fraction(_ s: String) -> Double? {
        if let slash = s.firstIndex(of: "/") {
            guard let n = Double(s[..<slash]), let d = Double(s[s.index(after: slash)...]), d != 0 else { return nil }
            return n / d
        }
        return Double(s)
    }

    private static let qualifiers: Set<String> = ["MI", "PR", "BC", "DR", "BL", "SH", "TS", "FZ"]
    private static let phenomena: Set<String> = [
        "DZ", "RA", "SN", "SG", "IC", "PL", "GR", "GS", "UP", "BR", "FG", "FU", "VA", "DU", "SA", "HZ", "PY", "PO", "SQ", "FC",
        "SS", "DS",
    ]

    /// `-RA`, `+TSRA`, `VCSH`, `BR`, `FZFG`, `TS`. `NSW` and recent weather (`RERA`) are not present weather.
    static func isWeatherGroup(_ token: String) -> Bool {
        var s = Substring(token)
        if s.hasPrefix("+") || s.hasPrefix("-") { s = s.dropFirst() } else if s.hasPrefix("VC") { s = s.dropFirst(2) }
        guard !s.isEmpty, s.count % 2 == 0 else { return false }
        var chunks: [String] = []
        var idx = s.startIndex
        while idx < s.endIndex {
            let end = s.index(idx, offsetBy: 2)
            chunks.append(String(s[idx..<end]))
            idx = end
        }
        return chunks.allSatisfy { qualifiers.contains($0) || phenomena.contains($0) }
    }
}
