import Foundation
import IterCore

/// Every user-facing phrase about light. The package returns structured values; this is where they become words,
/// all of them through the String Catalog.
enum LightText {
    // MARK: Windows and intents

    /// The name printed beside every score: "Sunset · 38".
    static func name(_ kind: LightWindowKind) -> String {
        switch kind {
        case .blueMorning: String(localized: "Morning blue hour", comment: "Light window: civil twilight before sunrise")
        case .goldenMorning: String(localized: "Sunrise", comment: "Light window: golden hour after sunrise")
        case .goldenEvening: String(localized: "Sunset", comment: "Light window: golden hour before sunset")
        case .blueEvening: String(localized: "Evening blue hour", comment: "Light window: civil twilight after sunset")
        case .night: String(localized: "Night", comment: "Light window: astronomical night")
        }
    }

    /// Short form for tight places (map pins, day chips).
    static func shortName(_ kind: LightWindowKind) -> String {
        switch kind {
        case .blueMorning: String(localized: "Blue AM", comment: "Short light window name for pins")
        case .goldenMorning: String(localized: "Sunrise", comment: "Short light window name for pins")
        case .goldenEvening: String(localized: "Sunset", comment: "Short light window name for pins")
        case .blueEvening: String(localized: "Blue PM", comment: "Short light window name for pins")
        case .night: String(localized: "Night", comment: "Short light window name for pins")
        }
    }

    static func name(_ intent: LightIntent) -> String {
        switch intent {
        case .sunrise: String(localized: "Sunrise", comment: "Light intent")
        case .sunset: String(localized: "Sunset", comment: "Light intent")
        case .blueHour: String(localized: "Blue hour", comment: "Light intent")
        case .night: String(localized: "Night", comment: "Light intent")
        }
    }

    static func symbol(_ kind: LightWindowKind) -> String {
        switch kind {
        case .blueMorning: "sun.horizon"
        case .goldenMorning: "sunrise"
        case .goldenEvening: "sunset"
        case .blueEvening: "moon.haze"
        case .night: "moon.stars"
        }
    }

    static func symbol(_ intent: LightIntent) -> String {
        switch intent {
        case .sunrise: "sunrise"
        case .sunset: "sunset"
        case .blueHour: "moon.haze"
        case .night: "moon.stars"
        }
    }

    static func name(_ best: BestLight) -> String {
        switch best {
        case .sunrise: String(localized: "Sunrise", comment: "Best light a spot is known for")
        case .sunset: String(localized: "Sunset", comment: "Best light a spot is known for")
        case .blueHour: String(localized: "Blue hour", comment: "Best light a spot is known for")
        case .night: String(localized: "Night sky", comment: "Best light a spot is known for")
        case .midday: String(localized: "Midday", comment: "Best light a spot is known for")
        case .overcast: String(localized: "Overcast", comment: "Best light a spot is known for")
        }
    }

    // MARK: Bands and confidence

    static func name(_ band: LightBand) -> String {
        switch band {
        case .poor: String(localized: "Poor", comment: "Light Index band")
        case .fair: String(localized: "Fair", comment: "Light Index band")
        case .good: String(localized: "Good", comment: "Light Index band")
        case .great: String(localized: "Great", comment: "Light Index band")
        case .epic: String(localized: "Epic", comment: "Light Index band")
        }
    }

    static func name(_ confidence: Confidence) -> String {
        switch confidence {
        case .high: String(localized: "High confidence", comment: "Light Index confidence")
        case .medium: String(localized: "Medium confidence", comment: "Light Index confidence")
        case .low: String(localized: "Low confidence", comment: "Light Index confidence")
        }
    }

    static func shortName(_ confidence: Confidence) -> String {
        switch confidence {
        case .high: String(localized: "High", comment: "Short confidence label")
        case .medium: String(localized: "Medium", comment: "Short confidence label")
        case .low: String(localized: "Low", comment: "Short confidence label")
        }
    }

    /// "Sunset · 38" — the headline format used everywhere a score appears.
    static func headline(_ window: LightWindow) -> String {
        if let score = window.assessment.lightScore {
            return String(localized: "\(name(window.kind)) · \(score.value)", comment: "Window name and Light Index score, e.g. Sunset · 38")
        }
        return String(localized: "\(name(window.kind)) · No forecast", comment: "Window name with no score")
    }

    /// "55–75" for a range, nil when the range is a single value.
    static func range(_ score: LightScore) -> String? {
        guard score.range.lowerBound != score.range.upperBound else { return nil }
        return String(localized: "\(score.range.lowerBound)–\(score.range.upperBound)", comment: "Plausible score range")
    }

    /// The VoiceOver sentence for a window.
    static func accessibilityDescription(_ window: LightWindow) -> String {
        switch window.assessment {
        case .scored(let s):
            String(localized: "\(name(window.kind)), Light Index \(s.value), \(name(s.band)), \(name(s.confidence))",
                   comment: "VoiceOver: window, score, band, confidence")
        case .noForecast(let reason):
            String(localized: "\(name(window.kind)), no forecast. \(noForecastReason(reason))",
                   comment: "VoiceOver: window with no forecast and why")
        }
    }

    // MARK: No forecast

    /// Short label shown in place of a score.
    static let noForecast = String(localized: "No forecast", comment: "Shown instead of a score when there is no forecast")

    /// Why there is no score, in one honest sentence.
    static func noForecastReason(_ reason: ForecastUnavailableReason) -> String {
        switch reason {
        case .weatherServiceNotEnabled:
            String(localized: "Weather isn't enabled for this build of Iter, so only sun and moon times are shown.",
                   comment: "No forecast reason: WeatherKit not provisioned")
        case .serviceFailed:
            String(localized: "Couldn't reach Apple Weather. Sun and moon times are still exact.",
                   comment: "No forecast reason: network or service failure")
        case .beyondHorizon:
            String(localized: "Too far ahead for a forecast. Planned on sun angle and season until about ten days out.",
                   comment: "No forecast reason: beyond the forecast horizon")
        case .inThePast:
            String(localized: "This window has passed.", comment: "No forecast reason: window already over")
        case .notLoaded:
            String(localized: "Forecast not loaded yet.", comment: "No forecast reason: not loaded")
        }
    }

    /// One-word reason for compact places (rows, pins).
    static func noForecastShort(_ reason: ForecastUnavailableReason) -> String {
        switch reason {
        case .weatherServiceNotEnabled: String(localized: "Weather off", comment: "Compact no-forecast reason")
        case .serviceFailed: String(localized: "Offline", comment: "Compact no-forecast reason")
        case .beyondHorizon: String(localized: "Too far ahead", comment: "Compact no-forecast reason")
        case .inThePast: String(localized: "Passed", comment: "Compact no-forecast reason")
        case .notLoaded: String(localized: "Loading", comment: "Compact no-forecast reason")
        }
    }

    // MARK: Contributors (the "why")

    static func title(_ factor: LightContributor.Factor) -> String {
        switch factor {
        case .lowCloud: String(localized: "Low cloud", comment: "Light factor")
        case .midHighCloud: String(localized: "Mid and high cloud", comment: "Light factor")
        case .totalCloud: String(localized: "Cloud cover", comment: "Light factor")
        case .clearSky: String(localized: "Clear sky", comment: "Light factor")
        case .precipitation: String(localized: "Rain", comment: "Light factor")
        case .visibility: String(localized: "Visibility", comment: "Light factor")
        case .moonlight: String(localized: "Moonlight", comment: "Light factor")
        case .darkSky: String(localized: "Dark sky", comment: "Light factor")
        case .wind: String(localized: "Wind", comment: "Light factor")
        case .sunAlignment: String(localized: "Sun direction", comment: "Light factor")
        }
    }

    /// The measured value, formatted for the factor's unit.
    static func value(_ c: LightContributor) -> String {
        switch c.factor {
        case .lowCloud, .midHighCloud, .totalCloud, .clearSky, .precipitation, .moonlight, .darkSky:
            c.value.formatted(.percent.precision(.fractionLength(0)))
        case .visibility:
            Measurement(value: c.value, unit: UnitLength.meters)
                .formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0))))
        case .wind:
            Measurement(value: c.value, unit: UnitSpeed.kilometersPerHour)
                .formatted(.measurement(width: .abbreviated, usage: .general, numberFormatStyle: .number.precision(.fractionLength(0))))
        case .sunAlignment:
            Measurement(value: c.value, unit: UnitAngle.degrees)
                .formatted(.measurement(width: .narrow, numberFormatStyle: .number.precision(.fractionLength(0))))
        }
    }

    /// One plain sentence about what the factor does to this window.
    static func sentence(_ c: LightContributor, kind: LightWindowKind) -> String {
        switch (c.factor, c.effect) {
        case (.lowCloud, .hurts): String(localized: "Low cloud can block the sun at the horizon.", comment: "Light reason")
        case (.lowCloud, _): String(localized: "Little low cloud: the horizon should be open.", comment: "Light reason")
        case (.midHighCloud, .helps): String(localized: "Mid and high cloud catches colour.", comment: "Light reason")
        case (.midHighCloud, .hurts): String(localized: "A thick upper deck mutes the colour.", comment: "Light reason")
        case (.midHighCloud, .neutral): String(localized: "Some upper cloud, little effect.", comment: "Light reason")
        case (.totalCloud, .helps): String(localized: "Cloud cover suits this window.", comment: "Light reason")
        case (.totalCloud, .hurts): String(localized: "Heavy cloud cover.", comment: "Light reason")
        case (.totalCloud, .neutral): String(localized: "Cloud layers unavailable; judged on total cover.", comment: "Light reason")
        case (.clearSky, _):
            kind == .night
                ? String(localized: "Clear sky for stars.", comment: "Light reason at night")
                : String(localized: "Bare sky: clean light, flat colour.", comment: "Light reason for a cloudless golden hour")
        case (.precipitation, .hurts): String(localized: "Rain is likely.", comment: "Light reason")
        case (.precipitation, _): String(localized: "Little chance of rain.", comment: "Light reason")
        case (.visibility, .hurts): String(localized: "Haze or fog cuts visibility.", comment: "Light reason")
        case (.visibility, _): String(localized: "Good visibility.", comment: "Light reason")
        case (.moonlight, _): String(localized: "A bright moon is up and washes out stars.", comment: "Light reason")
        case (.darkSky, _): String(localized: "Moon down or thin: a dark sky.", comment: "Light reason")
        case (.wind, .hurts): String(localized: "Strong wind: tripods and reflections suffer.", comment: "Light reason")
        case (.wind, _): String(localized: "Light wind.", comment: "Light reason")
        case (.sunAlignment, .helps): String(localized: "The sun lines up with the classic view.", comment: "Light reason")
        case (.sunAlignment, _): String(localized: "The sun is off-axis from the classic view.", comment: "Light reason")
        }
    }

    // MARK: Provenance

    static func name(_ origin: SpotOrigin) -> String {
        switch origin {
        case .curated: String(localized: "Curated", comment: "Spot provenance")
        case .user: String(localized: "Added by you", comment: "Spot provenance")
        case .appleMaps: String(localized: "Apple Maps", comment: "Spot provenance")
        case .scout: String(localized: "Scout", comment: "Spot provenance: found by the Apple Intelligence scout")
        }
    }

    static func name(_ category: SpotCategory) -> String {
        switch category {
        case .landscape: String(localized: "Landscape", comment: "Spot category")
        case .astro: String(localized: "Astro", comment: "Spot category")
        case .architecture: String(localized: "Architecture", comment: "Spot category")
        case .street: String(localized: "Street", comment: "Spot category")
        case .coast: String(localized: "Coast", comment: "Spot category")
        case .wildlife: String(localized: "Wildlife", comment: "Spot category")
        case .desert: String(localized: "Desert", comment: "Spot category")
        case .waterfall: String(localized: "Waterfall", comment: "Spot category")
        case .forest: String(localized: "Forest", comment: "Spot category")
        case .urban: String(localized: "Urban", comment: "Spot category")
        }
    }

    static func symbol(_ category: SpotCategory) -> String {
        switch category {
        case .landscape: "mountain.2"
        case .astro: "sparkles"
        case .architecture: "building.columns"
        case .street: "figure.walk"
        case .coast: "water.waves"
        case .wildlife: "pawprint"
        case .desert: "sun.dust"
        case .waterfall: "drop"
        case .forest: "tree"
        case .urban: "building.2"
        }
    }
}
