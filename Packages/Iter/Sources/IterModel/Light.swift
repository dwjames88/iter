import Foundation

// Raw values are stored (SwiftData, .iter files). Never rename a case's raw value.

/// The five shooting windows of a day. Every score, band, stop session and timeline highlight refers to one of these.
/// Definitions (sun altitude, refraction-corrected): blue hour = civil twilight (-6° to the horizon);
/// golden hour = horizon to +6°; night = from astronomical dusk (-18°) for three hours, or to astronomical dawn if sooner.
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

/// What a place is known for, from curated data or the user.
public enum BestLight: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case sunrise
    case sunset
    case blueHour
    case night
    case midday
    case overcast

    public var id: String { rawValue }

    /// The intent a place with this "best at" defaults to, if any.
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
