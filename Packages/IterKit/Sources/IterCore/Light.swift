import Foundation

// MARK: - What a photographer shoots

/// The five shooting windows of a day. Every score, band, stop session and timeline highlight refers to one of these.
/// Definitions (sun altitude, refraction-corrected): blue hour = civil twilight (−6° to the horizon);
/// golden hour = horizon to +6°; night = from astronomical dusk (−18°) for three hours, or to astronomical dawn if sooner.
public enum LightWindowKind: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case blueMorning
    case goldenMorning
    case goldenEvening
    case blueEvening
    case night

    public var id: String { rawValue }

    public var isMorning: Bool { self == .blueMorning || self == .goldenMorning }
    public var isEvening: Bool { self == .goldenEvening || self == .blueEvening }
    public var isGolden: Bool { self == .goldenMorning || self == .goldenEvening }
    public var isBlue: Bool { self == .blueMorning || self == .blueEvening }
    public var isDaytimeLight: Bool { self != .night }

    /// The intent this window belongs to.
    public var intent: LightIntent {
        switch self {
        case .goldenMorning: .sunrise
        case .goldenEvening: .sunset
        case .blueMorning, .blueEvening: .blueHour
        case .night: .night
        }
    }
}

/// What the user wants to shoot. The headline score on every surface is the score for the chosen intent,
/// always printed with the window it scores ("Sunset · 38"). A night window can never lift a daytime intent.
public enum LightIntent: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case sunrise
    case sunset
    case blueHour
    case night

    public var id: String { rawValue }

    /// The windows this intent may score. For blue hour the better of the two is used, and its name is shown.
    public var windows: [LightWindowKind] {
        switch self {
        case .sunrise: [.goldenMorning]
        case .sunset: [.goldenEvening]
        case .blueHour: [.blueEvening, .blueMorning]
        case .night: [.night]
        }
    }
}

/// What a spot is known for, from curated data or the user.
public enum BestLight: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case sunrise
    case sunset
    case blueHour
    case night
    case midday
    case overcast

    public var id: String { rawValue }

    /// The intent a spot with this "best at" defaults to, if any.
    public var intent: LightIntent? {
        switch self {
        case .sunrise: .sunrise
        case .sunset: .sunset
        case .blueHour: .blueHour
        case .night: .night
        case .midday, .overcast: nil
        }
    }
}

// MARK: - Bands, confidence, reasons

/// Named bands for a 0–100 score. The word is always shown beside the colour.
public enum LightBand: Int, Codable, CaseIterable, Comparable, Hashable, Sendable {
    case poor, fair, good, great, epic

    /// Thresholds live here and only here.
    public init(score: Int) {
        switch score {
        case 88...: self = .epic
        case 74..<88: self = .great
        case 58..<74: self = .good
        case 40..<58: self = .fair
        default: self = .poor
        }
    }

    public static func < (a: LightBand, b: LightBand) -> Bool { a.rawValue < b.rawValue }
}

/// How far to trust a score. Falls with lead time and with missing inputs.
public enum Confidence: String, Codable, CaseIterable, Comparable, Hashable, Sendable {
    case low, medium, high

    private var rank: Int { switch self { case .low: 0; case .medium: 1; case .high: 2 } }
    public static func < (a: Confidence, b: Confidence) -> Bool { a.rank < b.rank }
}

/// One input to a window's score. Structured so the UI (and the plain-language explainer) can phrase it;
/// the domain never produces user-facing strings.
public struct LightContributor: Codable, Hashable, Sendable, Identifiable {
    public enum Factor: String, Codable, CaseIterable, Hashable, Sendable {
        case lowCloud          // value: fraction 0–1
        case midHighCloud      // value: fraction 0–1 (the larger of mid and high)
        case totalCloud        // value: fraction 0–1 (used when the layers are unavailable)
        case clearSky          // value: total cloud fraction 0–1; "bare sky, clean but flat"
        case precipitation     // value: chance 0–1
        case visibility        // value: metres
        case moonlight         // value: illuminated fraction 0–1 while the moon is up
        case darkSky           // value: illuminated fraction 0–1 (moon down or thin)
        case wind              // value: km/h
        case sunAlignment      // value: degrees between the sun's azimuth and the spot's facing
    }

    public enum Effect: String, Codable, Hashable, Sendable {
        case helps, hurts, neutral
    }

    public var factor: Factor
    public var effect: Effect
    /// Signed effect on the score in points (for ordering and the "why" bars).
    public var points: Int
    /// The measured value, in the unit documented on `Factor`.
    public var value: Double

    public var id: Factor { factor }

    public init(factor: Factor, effect: Effect, points: Int, value: Double) {
        self.factor = factor
        self.effect = effect
        self.points = points
        self.value = value
    }
}

/// Why there is no score. Each case has a specific, honest message in the UI.
public enum ForecastUnavailableReason: Codable, Hashable, Sendable {
    /// WeatherKit is not provisioned for this build (no entitlement or the App ID lacks the capability).
    case weatherServiceNotEnabled
    /// The network or the weather service failed. `detail` is for logs, not for display.
    case serviceFailed(detail: String)
    /// The window is past the forecast horizon (about ten days); it is planned on sun geometry only.
    case beyondHorizon
    /// The window has already ended.
    case inThePast
    /// No forecast has been requested yet (for example, offline or still loading).
    case notLoaded
}

/// Where a forecast came from. Sample data is always labelled on screen.
public enum ForecastSource: String, Codable, Hashable, Sendable {
    case appleWeather
    case sample
}
