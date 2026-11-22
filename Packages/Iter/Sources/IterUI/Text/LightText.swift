import Foundation
import IterModel

/// Every user-facing phrase about light windows, intents and places. IterModel returns structured values; this is
/// where they become words, all through the String Catalog in this package's bundle.
public enum LightText {
    // MARK: Windows and intents

    /// The name printed beside every score: "Sunset · 38".
    public static func name(_ kind: LightWindowKind) -> String {
        switch kind {
        case .blueMorning: String(localized: "Morning Blue Hour", bundle: .module, comment: "Light window: civil twilight before sunrise")
        case .goldenMorning: String(localized: "Sunrise", bundle: .module, comment: "Light window: golden hour after sunrise")
        case .goldenEvening: String(localized: "Sunset", bundle: .module, comment: "Light window: golden hour before sunset")
        case .blueEvening: String(localized: "Evening Blue Hour", bundle: .module, comment: "Light window: civil twilight after sunset")
        case .night: String(localized: "Night", bundle: .module, comment: "Light window: astronomical night")
        }
    }

    /// Short form for tight places (map pins, day chips).
    public static func shortName(_ kind: LightWindowKind) -> String {
        switch kind {
        case .blueMorning: String(localized: "Blue AM", bundle: .module, comment: "Short light window name for pins")
        case .goldenMorning: String(localized: "Sunrise", bundle: .module, comment: "Short light window name for pins")
        case .goldenEvening: String(localized: "Sunset", bundle: .module, comment: "Short light window name for pins")
        case .blueEvening: String(localized: "Blue PM", bundle: .module, comment: "Short light window name for pins")
        case .night: String(localized: "Night", bundle: .module, comment: "Short light window name for pins")
        }
    }

    public static func name(_ intent: LightIntent) -> String {
        switch intent {
        case .sunrise: String(localized: "Sunrise", bundle: .module, comment: "Light intent")
        case .sunset: String(localized: "Sunset", bundle: .module, comment: "Light intent")
        case .blueHour: String(localized: "Blue Hour", bundle: .module, comment: "Light intent")
        case .night: String(localized: "Night", bundle: .module, comment: "Light intent")
        }
    }

    /// One symbol per window, fixed by the owner: the rising or setting sun is golden hour, the sun in haze is the
    /// blue hour before sunrise, the moon in haze is the blue hour after sunset, the starry moon is night.
    /// This is the one mapping; every window symbol in the app comes from here.
    public static func symbol(_ kind: LightWindowKind) -> String {
        switch kind {
        case .blueMorning: "sun.haze.fill"
        case .goldenMorning: "sunrise.fill"
        case .goldenEvening: "sunset.fill"
        case .blueEvening: "moon.haze.fill"
        case .night: "moon.stars.fill"
        }
    }

    /// An intent is a preference, not a time of day, so `.blueHour` cannot say morning or evening; it takes the
    /// evening symbol. Everything else routes through the window mapping.
    public static func symbol(_ intent: LightIntent) -> String {
        switch intent {
        case .sunrise: symbol(LightWindowKind.goldenMorning)
        case .sunset: symbol(LightWindowKind.goldenEvening)
        case .blueHour: symbol(LightWindowKind.blueEvening)
        case .night: symbol(LightWindowKind.night)
        }
    }

    public static func name(_ best: BestLight) -> String {
        switch best {
        case .sunrise: String(localized: "Sunrise", bundle: .module, comment: "Best light a spot is known for")
        case .sunset: String(localized: "Sunset", bundle: .module, comment: "Best light a spot is known for")
        case .blueHour: String(localized: "Blue Hour", bundle: .module, comment: "Best light a spot is known for")
        case .night: String(localized: "Night Sky", bundle: .module, comment: "Best light a spot is known for")
        case .midday: String(localized: "Midday", bundle: .module, comment: "Best light a spot is known for")
        case .overcast: String(localized: "Overcast", bundle: .module, comment: "Best light a spot is known for")
        }
    }

    // MARK: Scores

    /// "Sunset · 38", or just "Sunset" when there is no score. `score` is 0...100.
    public static func headline(_ kind: LightWindowKind, score: Int?, locale: Locale = .current) -> String {
        guard let score else { return name(kind) }
        let n = score.formatted(.number.locale(locale))
        return String(localized: "\(name(kind)) · \(n)", bundle: .module, locale: locale,
                      comment: "Window name and Light Index score, e.g. Sunset · 38")
    }

    /// "55–75" for a plausible range, nil when the range is a single value.
    public static func range(_ scores: ClosedRange<Int>, locale: Locale = .current) -> String? {
        guard scores.lowerBound != scores.upperBound else { return nil }
        let lo = scores.lowerBound.formatted(.number.locale(locale))
        let hi = scores.upperBound.formatted(.number.locale(locale))
        return String(localized: "\(lo)–\(hi)", bundle: .module, locale: locale, comment: "Plausible score range, e.g. 55–75")
    }

    /// The VoiceOver sentence for a window. `score` is 0...100, nil when there is no forecast.
    public static func accessibilityDescription(_ kind: LightWindowKind, score: Int?, locale: Locale = .current) -> String {
        guard let score else { return name(kind) }
        let n = score.formatted(.number.locale(locale))
        return String(localized: "\(name(kind)), Light Index \(n)", bundle: .module, locale: locale,
                      comment: "VoiceOver: window and score, e.g. Sunset, Light Index 38")
    }

    // MARK: Places

    public static func name(_ origin: PlaceOrigin) -> String {
        switch origin {
        case .curated: String(localized: "Curated", bundle: .module, comment: "Place provenance")
        case .user: String(localized: "Added by You", bundle: .module, comment: "Place provenance")
        case .appleMaps: String(localized: "Apple Maps", bundle: .module, comment: "Place provenance")
        case .scout: String(localized: "Scout", bundle: .module, comment: "Place provenance: found by Scout in Find")
        }
    }

    public static func name(_ category: PlaceCategory) -> String {
        switch category {
        case .landscape: String(localized: "Landscape", bundle: .module, comment: "Place category")
        case .astro: String(localized: "Astro", bundle: .module, comment: "Place category")
        case .architecture: String(localized: "Architecture", bundle: .module, comment: "Place category")
        case .street: String(localized: "Street", bundle: .module, comment: "Place category")
        case .coast: String(localized: "Coast", bundle: .module, comment: "Place category")
        case .wildlife: String(localized: "Wildlife", bundle: .module, comment: "Place category")
        case .desert: String(localized: "Desert", bundle: .module, comment: "Place category")
        case .waterfall: String(localized: "Waterfall", bundle: .module, comment: "Place category")
        case .forest: String(localized: "Forest", bundle: .module, comment: "Place category")
        case .urban: String(localized: "Urban", bundle: .module, comment: "Place category")
        }
    }

    public static func symbol(_ category: PlaceCategory) -> String {
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
