import Foundation
import IterModel
import IterAstro

// The Sky Index vocabulary. Everything here is a Sendable value type with no user-facing strings: the UI phrases the
// factors, notes, flags and causes (docs/rebuild/BLUEPRINT.md §8).

// MARK: - Bands and confidence

/// Named bands for a 0-100 score. The colour carries the band; the word is in the legend and the VoiceOver label.
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

    /// The scores 0 to 100 that fall in this band, found by asking `init(score:)`, so the thresholds stay in one place.
    public var scoreRange: ClosedRange<Int> {
        let scores = (0...100).filter { LightBand(score: $0) == self }
        guard let low = scores.first, let high = scores.last else { return 0...0 }
        return low...high
    }

    public static func < (a: LightBand, b: LightBand) -> Bool { a.rawValue < b.rawValue }
}

/// How far to trust a score. Falls with lead time, missing inputs, staleness and disagreeing sources.
public enum Confidence: String, Codable, CaseIterable, Comparable, Hashable, Sendable {
    case low, medium, high

    private var rank: Int { switch self { case .low: 0; case .medium: 1; case .high: 2 } }
    public static func < (a: Confidence, b: Confidence) -> Bool { a.rank < b.rank }
}

/// Cloud cover by height, fractions 0...1.
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

// MARK: - Inputs, notes, flags, causes

/// One input slot of the Sky Index. An input that is absent drops its factor, lowers confidence and produces a
/// `SkyNote.missing(_)`; it is never replaced by a silent default.
public enum SkyInput: String, Codable, CaseIterable, Hashable, Sendable {
    case cloudLayers, cloudTotal, precipitation, visibility
    /// Aerosol optical depth at 550 nm (`aod550`). Absent means neither this nor `smoke` was available.
    case aerosol
    /// Near-surface smoke, micrograms per cubic metre (`smokeUgm3`).
    case smoke
    case humidity, wind, horizon, moon, galacticCentre, aurora
    /// Bortle class. No source exists today, so it is always absent unless the caller supplies it.
    case lightPollution
    /// Astronomical seeing, arcseconds. No source exists today.
    case seeing
}

/// An input the score used, with where it came from and how old that source's data is.
public struct SkyInputUse: Codable, Hashable, Sendable {
    public var input: SkyInput
    /// The source of the field; nil for computed inputs (moon, galactic centre, horizon from the place).
    public var source: SourceID?
    /// Seconds since the source's data was fetched, at the `now` the score was computed for; nil for computed inputs.
    public var age: TimeInterval?

    public init(input: SkyInput, source: SourceID? = nil, age: TimeInterval? = nil) {
        self.input = input
        self.source = source
        self.age = age
    }
}

/// Something worth saying beside the score.
public enum SkyNote: Codable, Hashable, Sendable {
    /// An input was absent; its factor was dropped.
    case missing(SkyInput)
    /// Beyond the forecast: the last forecast day's weather was carried forward (confidence is low).
    case persistence
    /// No precipitation chance: rain was judged from the forecast amount (the contributor's value is mm per hour).
    case precipitationFromAmount
    /// The forecast is older than its time-to-live. Never presented as fresh.
    case stale(age: TimeInterval)
    /// Another source's total cloud differs from the primary by more than 0.30 over the window. Both are fractions 0...1.
    case sourceSpread(low: Double, high: Double)
    /// The terrain horizon cuts the golden window short (evening) or starts it late (morning) by this many seconds.
    case terrainEndsWindowEarly(by: TimeInterval)
    /// The night transparency figure was estimated from aerosol, humidity and high cloud, not measured.
    case transparencyFromProxy
    /// The raw score fell below 0 and was raised to 0.
    case clampedLow
    /// The raw score rose above 100 and was lowered to 100.
    case clampedHigh

    /// Stable display order and de-duplication key.
    var sortKey: Int {
        switch self {
        case .persistence: 0
        case .stale: 1
        case .missing(let input): 10 + (SkyInput.allCases.firstIndex(of: input) ?? 0)
        case .precipitationFromAmount: 40
        case .sourceSpread: 41
        case .terrainEndsWindowEarly: 42
        case .transparencyFromProxy: 43
        case .clampedLow: 50
        case .clampedHigh: 51
        }
    }
}

/// Informational facts about the window. They are not score terms.
public enum SkyFlag: Codable, Hashable, Sendable {
    /// Dewpoint spread at most 2 C (or humidity at least 95%) with wind under 3 m/s on a morning window: mist in the valleys.
    case fogPossible
    /// Aurora is plausible: probability at least 10%, or Kp at or above the place's latitude threshold.
    case aurora(probability: Double?, kp: Double?)
    /// The galactic core is up in astronomical dark during the night window. `best` is the stretch with the moon down, if any.
    case milkyWayCore(best: TimeSpan?, peakAltitude: Double)
    /// Sustained wind above 8 m/s or gusts above 12 m/s: expect vibration on long exposures.
    case longExposureWind
}

/// Why confidence is not at its ceiling.
public enum ConfidenceCause: Codable, Hashable, Sendable {
    /// The window's middle is this many hours after the forecast run (only when over 36).
    case leadTime(hours: Double)
    case missingPrimary(SkyInput)
    case missingSecondary(SkyInput)
    case stale(age: TimeInterval)
    case sourceSpread
    case persistence
}

// MARK: - Contributors

/// One input to a window's score. Structured so the UI can phrase it; the domain never produces user-facing strings.
public struct LightContributor: Codable, Hashable, Sendable, Identifiable {
    public enum Factor: String, Codable, CaseIterable, Hashable, Sendable {
        case lowCloud          // value: fraction 0...1
        case midHighCloud      // value: fraction 0...1 (the larger of mid and high)
        case totalCloud        // value: fraction 0...1 (used when the layers are unavailable, and for the overcast ceiling)
        case clearSky          // value: total cloud fraction 0...1; "bare sky, clean but flat"
        case precipitation     // value: chance 0...1 (mm per hour when judged from amount)
        case visibility        // value: kilometres
        case moonlight         // value: illuminated fraction 0...1 while the moon is up
        case darkSky           // value: illuminated fraction 0...1 (moon down or thin)
        case wind              // value: m/s, the larger of sustained wind and gusts / 1.5
        case aerosol           // value: aerosol optical depth at 550 nm, or smoke in micrograms per cubic metre when AOD was absent
        case fog               // value: dewpoint spread in C. Reserved: fog is a flag, not a score term, so this is not emitted today.
        case humidity          // value: percent (night only)
        case terrain           // value: golden windows, fraction 0...1 of the window the skyline takes; blue windows, skyline elevation in degrees toward the sun
        case milkyWay          // value: peak altitude of the galactic core over the window, degrees
        case transparency      // value: proxy 0...1. Reserved: today the proxy is `SkyScore.transparency`, not a term.
        case lightPollution    // value: Bortle class 1...9
        case seeing            // value: arcseconds
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
    /// For cloud factors when the source separates layers: the window's mean low, mid and high cloud.
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

// MARK: - The score

public struct SkyScore: Codable, Hashable, Sendable {
    /// 0...100, after clamping.
    public var value: Int
    public var band: LightBand
    public var confidence: Confidence
    /// The continuous value behind `confidence`, 0...1.
    public var confidenceValue: Double
    public var confidenceCauses: [ConfidenceCause]
    /// Plausible spread given the confidence (0 / 8 / 15 points), clamped to 0...100.
    public var range: ClosedRange<Int>
    /// Strongest effect first. With the baseline of 60 they sum to the raw score; `value` is that raw score clamped
    /// to 0...100 (see `SkyNote.clampedLow` and `.clampedHigh`).
    public var contributors: [LightContributor]
    public var notes: [SkyNote]
    public var flags: [SkyFlag]
    public var inputs: [SkyInputUse]
    /// Night only: atmospheric transparency 0...1 estimated from aerosol, humidity and high cloud; nil when not computable.
    public var transparency: Double?
    /// The source of the primary forecast.
    public var source: SourceID?
    /// The model run time when known.
    public var forecastIssuedAt: Date?
    public var forecastFetchedAt: Date
    /// Hours between the model run (else the fetch) and the window's middle.
    public var leadHours: Double
    /// `now` minus `forecastFetchedAt`, seconds.
    public var age: TimeInterval
    public var isStale: Bool
    /// The model ("GFS") when the provenance names one.
    public var model: String?

    public init(value: Int, band: LightBand, confidence: Confidence, confidenceValue: Double, confidenceCauses: [ConfidenceCause] = [],
                range: ClosedRange<Int>, contributors: [LightContributor], notes: [SkyNote] = [], flags: [SkyFlag] = [],
                inputs: [SkyInputUse] = [], transparency: Double? = nil, source: SourceID? = nil, forecastIssuedAt: Date? = nil,
                forecastFetchedAt: Date, leadHours: Double, age: TimeInterval, isStale: Bool, model: String? = nil) {
        self.value = value
        self.band = band
        self.confidence = confidence
        self.confidenceValue = confidenceValue
        self.confidenceCauses = confidenceCauses
        self.range = range
        self.contributors = contributors
        self.notes = notes
        self.flags = flags
        self.inputs = inputs
        self.transparency = transparency
        self.source = source
        self.forecastIssuedAt = forecastIssuedAt
        self.forecastFetchedAt = forecastFetchedAt
        self.leadHours = leadHours
        self.age = age
        self.isStale = isStale
        self.model = model
    }
}

/// Why there is no score. Each case has a specific, honest message in the UI. There is no placeholder number.
public enum SkyUnavailable: Codable, Hashable, Sendable {
    /// The window has already ended.
    case inThePast
    /// The forecast has no hours covering the window, or there are no hours at all.
    case beyondHorizon
    /// There is no usable forecast, with the reasons the data layer gave (an empty list is reported as `.notLoaded`).
    case noForecast([NoDataReason])
    /// No forecast has been requested yet (for example, still loading).
    case notLoaded
}

/// Either a real score or an explicit reason there is none.
public enum LightAssessment: Codable, Hashable, Sendable {
    case scored(SkyScore)
    case unavailable(SkyUnavailable)

    public var score: Int? {
        if case .scored(let s) = self { return s.value }
        return nil
    }

    public var skyScore: SkyScore? {
        if case .scored(let s) = self { return s }
        return nil
    }
}

// MARK: - Windows and days

/// A shooting window with its assessment. The single object every view draws, so they always agree.
public struct LightWindow: Codable, Hashable, Sendable, Identifiable {
    public var kind: LightWindowKind
    /// The window the sun geometry gives.
    public var span: TimeSpan
    /// The window after the terrain skyline, when a horizon is known and it changes the window (zero length when the
    /// skyline hides the sun for all of it); nil when there is no horizon or nothing changed.
    public var effectiveSpan: TimeSpan?
    public var assessment: LightAssessment

    public var id: LightWindowKind { kind }

    public init(kind: LightWindowKind, span: TimeSpan, effectiveSpan: TimeSpan? = nil, assessment: LightAssessment) {
        self.kind = kind
        self.span = span
        self.effectiveSpan = effectiveSpan
        self.assessment = assessment
    }

    public var score: Int? { assessment.score }
}

/// Every window of one local day at one place, plus the sun events they were built from.
public struct DayLight: Codable, Hashable, Sendable {
    public var day: LocalDay
    public var coordinate: Coordinate
    public var timeZoneIdentifier: String
    public var sun: SunEvents
    public var moon: MoonEvents
    /// Moon phase at the start of the night window (or local noon if there is none).
    public var moonPhase: MoonPhase
    /// In chronological order. Windows the sun does not produce that day (polar day or night) are absent.
    public var windows: [LightWindow]

    public init(day: LocalDay, coordinate: Coordinate, timeZoneIdentifier: String, sun: SunEvents, moon: MoonEvents,
                moonPhase: MoonPhase, windows: [LightWindow]) {
        self.day = day
        self.coordinate = coordinate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.sun = sun
        self.moon = moon
        self.moonPhase = moonPhase
        self.windows = windows
    }

    public var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .gmt }

    public func window(_ kind: LightWindowKind) -> LightWindow? { windows.first { $0.kind == kind } }

    /// The window that answers `intent`. For blue hour, the better scored of the two (evening on ties);
    /// if neither is scored, the evening one. Never crosses intents: night cannot answer sunset.
    public func headline(for intent: LightIntent) -> LightWindow? {
        let candidates = intent.windows.compactMap { window($0) }
        guard !candidates.isEmpty else { return nil }
        return candidates.max { a, b in (a.score ?? -1) < (b.score ?? -1) } ?? candidates.first
    }
}
