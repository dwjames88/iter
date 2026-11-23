import Foundation
import CoreGraphics
import IterFeatures
import IterModel
import IterSky
import IterSources
import IterUI

/// Pure words and geometry for the Conditions screens. Nothing here reads a clock or a view; every value is passed in, so
/// the tests can pin each sentence.
enum ConditionsFormat {
    // MARK: Numbers

    /// "55%", or an en dash when the value is missing (a gap is never a number).
    static func percent(_ fraction: Double?) -> String {
        guard let fraction else { return "\u{2013}" }
        return "\(Int((min(1, max(0, fraction)) * 100).rounded()))%"
    }

    static func percentValue(_ percent: Double?) -> String {
        guard let percent else { return "\u{2013}" }
        return "\(Int(percent.rounded()))%"
    }

    /// "54\u{00B0}" in the locale's temperature unit (Fahrenheit for the US).
    static func temperature(_ c: Double?, locale: Locale = .current) -> String {
        guard let c else { return "\u{2013}" }
        return Measurement(value: c, unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))).locale(locale))
    }

    /// "7 mph" or "11 km/h": the locale's wind unit.
    static func wind(_ ms: Double?, locale: Locale = .current) -> String {
        guard let ms else { return "\u{2013}" }
        return Measurement(value: ms, unit: UnitSpeed.metersPerSecond)
            .formatted(.measurement(width: .abbreviated, usage: .wind, numberFormatStyle: .number.precision(.fractionLength(0))).locale(locale))
    }

    /// "15 mi" or "24 km", from the same road convention as every other distance on screen.
    static func visibility(_ km: Double?, locale: Locale = .current) -> String {
        guard let km else { return "\u{2013}" }
        return TimeText.distance(kilometers: km, locale: locale)
    }

    // MARK: Compass

    private static let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

    /// "N", "NE", ... for a bearing in degrees.
    static func cardinal(_ azimuth: Double) -> String {
        let wrapped = (azimuth.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return points[Int(((wrapped + 22.5) / 45).rounded(.down)) % 8]
    }

    /// "96\u{00B0} E".
    static func azimuth(_ azimuth: Double) -> String {
        let wrapped = (azimuth.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return "\(Int(wrapped.rounded()) % 360)\u{00B0} \(cardinal(wrapped))"
    }

    /// "12\u{00B0} up" or "4\u{00B0} below the horizon".
    static func altitude(_ degrees: Double) -> String {
        degrees > 0 ? "\(Int(degrees.rounded()))\u{00B0} up" : "\(Int(abs(degrees).rounded()))\u{00B0} below the horizon"
    }

    /// A point on the sky chart: the centre is straight up, the rim is the horizon (altitude 0), north at the top. Altitudes
    /// below the horizon sit just outside the rim and stop at 12 degrees below.
    static func skyPoint(azimuth: Double, altitude: Double, radius: CGFloat, center: CGPoint) -> CGPoint {
        let alt = min(90, max(-12, altitude))
        let r = radius * CGFloat((90 - alt) / 90)
        let a = azimuth * .pi / 180
        return CGPoint(x: center.x + r * CGFloat(sin(a)), y: center.y - r * CGFloat(cos(a)))
    }

    /// The point on a circle of `radius` at a compass bearing.
    static func rimPoint(azimuth: Double, radius: CGFloat, center: CGPoint) -> CGPoint {
        let a = azimuth * .pi / 180
        return CGPoint(x: center.x + radius * CGFloat(sin(a)), y: center.y - radius * CGFloat(cos(a)))
    }

    /// "Sun 12\u{00B0} up at 96\u{00B0} E".
    static func sunLine(_ r: CompassReadout) -> String {
        "Sun \(altitude(r.sun.altitude)), \(azimuth(r.sun.azimuth))"
    }

    static func moonLine(_ r: CompassReadout, day: CompassDay) -> String {
        let phase = "\(Int((day.moonIllumination * 100).rounded()))% lit"
        return r.moonIsUp ? "Moon \(altitude(r.moon.altitude)), \(azimuth(r.moon.azimuth)), \(phase)" : "Moon below the horizon, \(phase)"
    }

    static func milkyWayLine(_ r: CompassReadout, day: CompassDay, zone: TimeZone) -> String? {
        guard let mw = day.milkyWay else { return nil }
        if r.milkyWayCore.altitude > 0 {
            let dark = r.coreIsInDark ? ", in the dark" : ""
            return "Milky Way core \(altitude(r.milkyWayCore.altitude)), \(azimuth(r.milkyWayCore.azimuth))\(dark)"
        }
        return mw.isVisible
            ? "Milky Way core rises to \(Int(mw.peakAltitude.rounded()))\u{00B0} at \(TimeText.time(mw.peakTime, in: zone))"
            : "Milky Way core is not up in the dark this night"
    }

    static func facingLine(_ facing: Double?) -> String {
        facing.map { "Facing \(azimuth($0))" } ?? "Facing unknown"
    }

    /// "Sun rises at 96\u{00B0} E, inside your view" style line for the compass; nil when the sun does not rise or set.
    static func riseSetLine(_ day: CompassDay, facing: Double?, zone: TimeZone, scrub: Date) -> String? {
        let upcoming: (String, EventPoint)?
        if let rise = day.sunrise, scrub <= day.solarNoon { upcoming = ("rises", rise) }
        else if let set = day.sunset { upcoming = ("sets", set) }
        else if let rise = day.sunrise { upcoming = ("rises", rise) }
        else { upcoming = nil }
        guard let (verb, point) = upcoming else { return "The sun does not rise or set on this day" }
        var line = "Sun \(verb) at \(azimuth(point.azimuth)), \(TimeText.time(point.time, in: zone))"
        if let facing {
            let off = angleBetween(point.azimuth, facing)
            line += off <= 35 ? ", inside the view" : ", \(Int((off - 35).rounded()))\u{00B0} outside the view"
        }
        return line
    }

    /// The smaller angle between two bearings, 0...180.
    static func angleBetween(_ a: Double, _ b: Double) -> Double {
        let d = abs((a - b).truncatingRemainder(dividingBy: 360))
        return d > 180 ? 360 - d : d
    }

    // MARK: Headlines

    /// "Sunset at 18:14": the window's name and the moment that matters (the sun event for a golden window, else the start).
    static func headlineTitle(kind: LightWindowKind, timeline: LightTimeline, windows: [WindowDetail], zone: TimeZone) -> String {
        let name = ConditionsText.name(kind)
        let moment: Date?
        switch kind {
        case .goldenEvening: moment = timeline.sunset ?? windows.first { $0.kind == kind }?.span.start
        case .goldenMorning: moment = timeline.sunrise ?? windows.first { $0.kind == kind }?.span.start
        default: moment = windows.first { $0.kind == kind }?.span.start ?? timeline.windows.first { $0.kind == kind }?.span.start
        }
        guard let moment else { return name }
        return "\(name) at \(TimeText.time(moment, in: zone))"
    }

    /// "Best: Sat, Oct 10 \u{00B7} Sunset 72".
    static func bestLine(_ best: WhenToGo, locale: Locale = .current) -> String {
        "Best: \(TimeText.day(best.day, locale: locale)) \u{00B7} \(ConditionsText.name(best.kind)) \(best.score)"
    }

    /// One line of why the best window is the best: the strongest factor of that window when its day is on screen, else the
    /// band and how sure the forecast is.
    static func whenToGoReason(_ best: WhenToGo, windows: [WindowDetail], selectedDay: LocalDay) -> String {
        if best.day == selectedDay, let top = windows.first(where: { $0.kind == best.kind })?.contributors.first {
            return ConditionsText.reason(top)
        }
        return "\(ConditionsText.name(best.band)) light, \(ConditionsText.name(best.confidence).lowercased())"
    }

    // MARK: States

    enum StateTone: Equatable { case info, data }

    struct StateLine: Equatable {
        var tone: StateTone
        var text: String
        var data: DataStateKind?
    }

    /// The honest line at the top of the stack. nil when everything is complete and fresh.
    static func stateLine(_ status: ConditionsStatus, placeName: String, generatedAt: Date?, offlineNote: String?, zone: TimeZone) -> StateLine? {
        switch status {
        case .loading:
            return StateLine(tone: .data, text: "Loading", data: .loading)
        case .pastDay:
            return StateLine(tone: .info, text: "This day is over, so no forecast is fetched for it.", data: nil)
        case .quick:
            return StateLine(tone: .info, text: "Quick forecast from MET Norway; NOAA forecast loading", data: nil)
        case .nearTerm:
            return StateLine(tone: .info, text: "Near-term forecast; the long range is still loading", data: nil)
        case .complete:
            return nil
        case .stale(let age):
            let asOf = generatedAt.map { TimeText.time($0.addingTimeInterval(-age), in: zone) }
            return StateLine(tone: .data, text: asOf.map { "Stale, as of \($0)" } ?? "Stale", data: .stale(age: age))
        case .offline(let lastGood, let age):
            let ago = age.map { ", \(ConditionsText.age($0)) old" } ?? ""
            let text = offlineNote ?? (lastGood.map { "Forecast from \(TimeText.time($0, in: zone)), offline\(ago)" } ?? "Offline")
            return StateLine(tone: .data, text: text, data: .offline(lastUpdated: lastGood))
        case .outOfCoverage:
            return StateLine(tone: .data, text: "No forecast source covers \(placeName)", data: .unavailable(reason: "No forecast source covers \(placeName)."))
        case .unavailable(let reasons):
            let why = reasons.isEmpty ? "No forecast is available." : reasons.map(ConditionsText.phrase).joined(separator: "; ").capitalizedFirst + "."
            return StateLine(tone: .data, text: why, data: .unavailable(reason: why))
        }
    }

    // MARK: Station

    /// "Canyonlands Field (KCNY), 38 km, 47 min ago".
    static func observationTitle(_ o: StationObservation) -> String {
        var name = o.stationName ?? o.stationID ?? "Nearest station"
        if let id = o.stationID, o.stationName != nil, o.stationName != id { name += " (\(id))" }
        var parts = [name]
        if let km = o.distanceKm { parts.append(TimeText.distance(kilometers: km)) }
        parts.append("\(ConditionsText.age(o.ageSeconds)) ago")
        return parts.joined(separator: ", ")
    }

    // MARK: Around the place

    /// "MET Norway's cloud forecast differs by up to 42% from the main forecast."
    static func comparisonLine(_ c: ComparisonInfo) -> String {
        guard let d = c.maxCloudDifference else { return "\(c.sourceName) is also loaded for comparison." }
        let pct = Int((d * 100).rounded())
        return c.disagrees
            ? "\(c.sourceName) shows up to \(pct)% different cloud cover than the main forecast. Confidence is lowered."
            : "\(c.sourceName) agrees with the main forecast on cloud, within \(pct)%."
    }

    /// "Sun sets behind terrain at 17:42, 12 min early" (evening) or "Sun clears terrain at 07:41, 12 min late" (morning).
    static func terrainLine(_ s: HorizonInfo.Shortened, zone: TimeZone) -> String {
        let minutes = Int((s.lostSeconds / 60).rounded())
        switch s.kind {
        case .goldenEvening, .blueEvening:
            return "\(ConditionsText.name(s.kind)): sun sets behind terrain at \(TimeText.time(s.effective.end, in: zone)), \(minutes) min early"
        case .goldenMorning, .blueMorning:
            return "\(ConditionsText.name(s.kind)): sun clears terrain at \(TimeText.time(s.effective.start, in: zone)), \(minutes) min late"
        case .night:
            return "Night: terrain shortens the window by \(minutes) min"
        }
    }

    static func smokeLines(_ s: SmokeInfo) -> [String] {
        var out: [String] = []
        if let d = s.density {
            switch d {
            case .none: out.append("Smoke analysis: no smoke over this place")
            case .light: out.append("Smoke analysis: light smoke overhead")
            case .medium: out.append("Smoke analysis: medium smoke overhead")
            case .heavy: out.append("Smoke analysis: heavy smoke overhead")
            }
        }
        if let ug = s.nearSurfaceMaxUgm3 { out.append("Near-surface smoke up to \(Int(ug.rounded())) \u{00B5}g/m\u{00B3}") }
        out.append(contentsOf: s.notes)
        return out
    }

    static func auroraLine(_ a: AuroraInfo) -> String {
        var parts: [String] = []
        if let p = a.probabilityPercent { parts.append("Aurora chance \(Int(p.rounded()))%") } else { parts.append("Aurora chance unknown") }
        if let kp = a.peakKp { parts.append("peak Kp \(String(format: "%.0f", kp)) over the next day") }
        if a.isStale { parts.append("old data") }
        return parts.joined(separator: ", ")
    }

    /// "Light Pollution: no free source". A gap is named, never a number.
    static func gapLine(_ g: GapRow) -> String {
        if g.reasons.contains(where: { $0.contains("no source provides") }) || g.reasons.isEmpty { return "\(g.title): no free source" }
        return "\(g.title): \(g.reasons.joined(separator: "; "))"
    }

    // MARK: Hours

    /// "07:00" style label for a table row.
    static func hourLabel(_ date: Date, zone: TimeZone) -> String { TimeText.time(date, in: zone) }

    // MARK: Window reasons

    static func noteText(_ n: SkyNote) -> String {
        switch n {
        case .missing(let input): "\(ConditionsText.input(input)) was missing, so it was left out of the score."
        case .persistence: "Beyond the forecast: the last forecast day's weather is carried forward."
        case .precipitationFromAmount: "Rain was judged from the forecast amount; no chance was given."
        case .stale(let age): "The forecast is \(ConditionsText.age(age)) old."
        case .sourceSpread(let low, let high): "Two forecasts disagree about cloud: \(percent(low)) to \(percent(high))."
        case .terrainEndsWindowEarly(let by): "Terrain ends this window \(Int((by / 60).rounded())) min early."
        case .transparencyFromProxy: "Transparency is estimated, not measured."
        case .clampedLow: "The score was held up to its floor."
        case .clampedHigh: "The score was held down to its ceiling."
        case .observationTooOld: "The nearest station report is too old to use."
        case .observationTooFar: "The nearest station is too far away to use."
        case .observationDistanceUnknown: "The distance to the nearest station is unknown."
        case .noObservation: "No station report is available."
        }
    }

    static func flagText(_ f: SkyFlag, zone: TimeZone) -> String {
        switch f {
        case .fogPossible: "Mist is possible in the valleys."
        case .aurora(let p, let kp):
            "Aurora is plausible" + [p.map { "\(Int($0.rounded()))% chance" }, kp.map { "Kp \(String(format: "%.0f", $0))" }].compactMap { $0 }.joined(separator: ", ").prefixed(": ") + "."
        case .milkyWayCore(let best, let peak):
            "The Milky Way core is up to \(Int(peak.rounded()))\u{00B0}" + (best.map { ", best \(TimeText.timeRange($0, in: zone))" } ?? "") + "."
        case .longExposureWind: "Wind may shake long exposures."
        }
    }

    struct FactorText: Equatable { var name: String; var symbol: String; var value: String }

    static func factor(_ c: LightContributor) -> FactorText {
        switch c.factor {
        case .lowCloud: FactorText(name: "Low Cloud", symbol: "cloud.fill", value: percent(c.value))
        case .midHighCloud: FactorText(name: "Mid and High Cloud", symbol: "cloud", value: percent(c.value))
        case .totalCloud: FactorText(name: "Cloud Cover", symbol: "cloud", value: percent(c.value))
        case .clearSky: FactorText(name: "Clear Sky", symbol: "sun.max", value: "\(percent(c.value)) cloud")
        case .precipitation: FactorText(name: "Rain", symbol: "cloud.rain", value: c.value > 1 ? String(format: "%.1f mm/h", c.value) : percent(c.value))
        case .visibility: FactorText(name: "Visibility", symbol: "eye", value: visibility(c.value))
        case .moonlight: FactorText(name: "Moonlight", symbol: "moon.fill", value: "\(percent(c.value)) lit")
        case .darkSky: FactorText(name: "Dark Sky", symbol: "moon.stars", value: "moon \(percent(c.value)) lit")
        case .wind: FactorText(name: "Wind", symbol: "wind", value: wind(c.value))
        case .aerosol: FactorText(name: "Haze and Smoke", symbol: "smoke", value: String(format: "%.2f", c.value))
        case .fog: FactorText(name: "Fog Risk", symbol: "cloud.fog", value: String(format: "%.1f\u{00B0} spread", c.value))
        case .humidity: FactorText(name: "Humidity", symbol: "humidity", value: "\(Int(c.value.rounded()))%")
        case .terrain: FactorText(name: "Terrain Skyline", symbol: "mountain.2", value: c.value <= 1 ? percent(c.value) : "\(Int(c.value.rounded()))\u{00B0}")
        case .milkyWay: FactorText(name: "Milky Way Core", symbol: "sparkles", value: "up to \(Int(c.value.rounded()))\u{00B0}")
        case .transparency: FactorText(name: "Transparency", symbol: "circle.dotted", value: percent(c.value))
        case .lightPollution: FactorText(name: "Light Pollution", symbol: "building.2", value: "Bortle \(Int(c.value.rounded()))")
        case .seeing: FactorText(name: "Seeing", symbol: "scope", value: String(format: "%.1f arcsec", c.value))
        }
    }

    static func confidenceLevel(_ c: Confidence) -> ConfidenceLevel {
        switch c {
        case .low: .low
        case .medium: .medium
        case .high: .high
        }
    }

    /// "Likely 72\u{2013}100" for a score range wider than a point.
    static func likely(_ range: ClosedRange<Int>?) -> String? {
        guard let range, range.lowerBound != range.upperBound else { return nil }
        return "Likely \(range.lowerBound)\u{2013}\(range.upperBound)"
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
    fileprivate func prefixed(_ p: String) -> String { isEmpty ? "" : p + self }
}
