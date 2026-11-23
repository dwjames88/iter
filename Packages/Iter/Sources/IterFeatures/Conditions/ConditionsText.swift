import Foundation
import IterModel
import IterSources
import IterSky
import IterAstro
import IterConditions

/// Plain words for the domain's structured values (the sky and conditions targets produce no user-facing strings). Title-Style
/// names, no all-caps, and honest about what is missing.
public enum ConditionsText {
    public static func name(_ kind: LightWindowKind) -> String {
        switch kind {
        case .blueMorning: "Morning Blue Hour"
        case .goldenMorning: "Sunrise"
        case .goldenEvening: "Sunset"
        case .blueEvening: "Evening Blue Hour"
        case .night: "Night"
        }
    }

    public static func name(_ band: LightBand) -> String {
        switch band {
        case .poor: "Poor"
        case .fair: "Fair"
        case .good: "Good"
        case .great: "Great"
        case .epic: "Epic"
        }
    }

    public static func name(_ confidence: Confidence) -> String {
        switch confidence {
        case .low: "Low Confidence"
        case .medium: "Medium Confidence"
        case .high: "High Confidence"
        }
    }

    /// "2 h 10 min", "45 min", "3 days".
    public static func age(_ seconds: TimeInterval) -> String {
        let minutes = Int((max(0, seconds) / 60).rounded())
        if minutes < 1 { return "under a minute" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        if hours < 36 { return minutes % 60 == 0 ? "\(hours) h" : "\(hours) h \(minutes % 60) min" }
        return "\(Int((Double(hours) / 24).rounded())) days"
    }

    /// Why confidence is not at its ceiling.
    public static func phrase(_ cause: ConfidenceCause) -> String {
        switch cause {
        case .leadTime(let hours): "The window is \(Int(hours.rounded())) hours after the forecast run."
        case .missingPrimary(let missing): "\(Self.input(missing)) is missing."
        case .missingSecondary(let missing): "\(Self.input(missing)) is missing, which matters less."
        case .stale(let age): "The forecast is \(Self.age(age)) old."
        case .sourceSpread: "Two forecasts disagree about cloud."
        case .persistence: "Beyond the forecast: the last forecast day is carried forward."
        }
    }

    public static func input(_ input: SkyInput) -> String {
        switch input {
        case .cloudLayers: "Cloud by height"
        case .cloudTotal: "Total cloud"
        case .precipitation: "Rain chance"
        case .visibility: "Visibility"
        case .aerosol: "Aerosol"
        case .smoke: "Smoke"
        case .humidity: "Humidity"
        case .wind: "Wind"
        case .horizon: "Terrain horizon"
        case .moon: "Moon"
        case .galacticCentre: "Galactic core"
        case .aurora: "Aurora"
        case .lightPollution: "Light pollution"
        case .seeing: "Seeing"
        }
    }

    /// One line per contributor: what it was and which way it pushed the score.
    public static func reason(_ c: LightContributor) -> String {
        let pct = { (v: Double) in "\(Int((v * 100).rounded()))%" }
        let what: String
        switch c.factor {
        case .lowCloud: what = "Low cloud \(pct(c.value))"
        case .midHighCloud: what = "Mid and high cloud \(pct(c.value))"
        case .totalCloud: what = "Cloud cover \(pct(c.value))"
        case .clearSky: what = "Clear sky (\(pct(c.value)) cloud), clean but flat"
        case .precipitation: what = c.value > 1 ? String(format: "Rain %.1f mm/h", c.value) : "Rain chance \(pct(c.value))"
        case .visibility: what = String(format: "Visibility %.0f km", c.value)
        case .moonlight: what = "Moon up, \(pct(c.value)) lit"
        case .darkSky: what = "Dark sky, moon \(pct(c.value)) lit"
        case .wind: what = String(format: "Wind %.0f m/s", c.value)
        case .aerosol: what = "Haze or smoke in the air"
        case .fog: what = String(format: "Fog risk, dewpoint spread %.1f°", c.value)
        case .humidity: what = "Humidity \(Int(c.value.rounded()))%"
        case .terrain: what = "Terrain skyline"
        case .milkyWay: what = String(format: "Galactic core up to %.0f°", c.value)
        case .transparency: what = "Transparency estimated"
        case .lightPollution: what = String(format: "Bortle class %.0f", c.value)
        case .seeing: what = String(format: "Seeing %.1f arcseconds", c.value)
        }
        let sign = c.points > 0 ? "+\(c.points)" : "\(c.points)"
        switch c.effect {
        case .helps: return "\(what): helps (\(sign))"
        case .hurts: return "\(what): hurts (\(sign))"
        case .neutral: return what
        }
    }

    public static func phrase(_ unavailable: SkyUnavailable) -> String {
        switch unavailable {
        case .inThePast: "This window is over."
        case .beyondHorizon: "Beyond the forecast: no hours cover this window yet."
        case .noForecast(let reasons): reasons.isEmpty ? "No forecast is available." : "No forecast: " + reasons.map(phrase).joined(separator: "; ")
        case .notLoaded: "Not loaded yet."
        }
    }

    public static func phrase(_ reason: NoDataReason) -> String {
        switch reason {
        case .outsideCoverage: "no source covers this place"
        case .needsKey(let id): "needs a key for \(id.rawValue)"
        case .offline(let last): "offline" + (last.map { _ in ", showing the last good data" } ?? "")
        case .rateLimited: "rate limited, try again later"
        case .sourceError(let id, let text): "\(id.rawValue) failed (\(text))"
        case .notProvidedBySource: "no source provides it yet"
        case .appleIntelligenceUnavailable: "Apple Intelligence is unavailable"
        }
    }

    public static func title(_ subject: GapSubject) -> String {
        switch subject {
        case .field(let f): "Forecast field: \(f.rawValue)"
        case .forecast: "Forecast"
        case .observations: "Observations"
        case .alerts: "Alerts"
        case .aurora: "Aurora"
        case .smokeAnalysis: "Smoke analysis"
        case .horizon: "Terrain horizon"
        case .lightPollution: "Light Pollution"
        case .seeing: "Seeing"
        }
    }
}
