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
    /// For cloud factors when the provider separates layers: the window's mean low, mid and high cloud,
    /// so the reason can name them ("high cloud 60%, low cloud 10%"). nil when the provider gives total cloud only.
    public var layers: CloudLayers?

    public var id: Factor { factor }

    public init(factor: Factor, effect: Effect, points: Int, value: Double, layers: CloudLayers? = nil) {
        self.factor = factor
        self.effect = effect
        self.points = points
        self.value = value
        self.layers = layers
    }
}

/// Cloud cover by height, fractions 0–1.
public struct CloudLayers: Codable, Hashable, Sendable {
    public var low: Double
    public var mid: Double
    public var high: Double

    public init(low: Double, mid: Double, high: Double) {
        self.low = low
        self.mid = mid
        self.high = high
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
    /// The chosen provider needs an API key and none is set (Settings ▸ Weather, Keychain, or ITER_*_KEY).
    case missingAPIKey(ForecastSource)
    /// The provider refused the key (HTTP 401/403, or the subscription does not include the product).
    case keyRejected(ForecastSource)
    /// Iter's own daily call cap for the provider was reached (it protects the free allowance), or the provider said 429.
    case dailyLimitReached(ForecastSource)
    /// The key is a testing key whose data is not a real forecast (Windy's free tier returns data for random places).
    case testingKey(ForecastSource)
    /// A named provider failed (network, server, unreadable response). `detail` is for logs and Settings, not for rows.
    case providerFailed(ForecastSource, detail: String)
    /// The Mac could not reach the provider (no connection, DNS or timeout).
    case offline(ForecastSource)
}

/// Where a forecast came from. Sample data is always labelled on screen; every other source is named wherever a
/// forecast or score appears, with the attribution its licence requires.
public enum ForecastSource: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case appleWeather
    case openWeather
    case windy
    case sample

    public var id: String { rawValue }

    /// The real providers a user can choose in Settings ▸ Weather (sample data stays behind the Debug menu).
    public static let selectable: [ForecastSource] = [.appleWeather, .openWeather, .windy]

    /// Whether the provider needs an API key from the user.
    public var needsAPIKey: Bool { self == .openWeather || self == .windy }
}

/// Something the provider could not supply for a scored window, which the Light Index reports beside its reasons
/// and folds into its confidence.
public enum ScoreNote: String, Codable, CaseIterable, Hashable, Sendable {
    /// No cloud by height: the score used total cloud only (confidence drops one step).
    case noCloudLayers
    /// Beyond the provider's hourly range: the window was scored from a daily summary (confidence is low).
    case dailySummaryOnly
    /// Beyond the provider's forecast: the last forecast day's weather is carried forward (confidence is lowest).
    case persistence
    /// The model steps every three hours; Iter interpolated to hours (high confidence needs 24 h lead, not 36).
    case threeHourlySteps
    /// No precipitation probability: rain was judged from the forecast amount.
    case precipitationFromAmount
    /// No visibility from this provider or model; visibility was left out of the score.
    case noVisibility
}
