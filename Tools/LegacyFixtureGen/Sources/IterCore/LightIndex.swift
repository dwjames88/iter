import Foundation

/// A scored shooting window. The single object that every view (badge, timeline band, arc marker, hourly tint,
/// trip stop) draws, so they always agree.
public struct LightWindow: Codable, Hashable, Sendable, Identifiable {
    public var kind: LightWindowKind
    public var span: TimeSpan
    public var assessment: LightAssessment

    public var id: LightWindowKind { kind }

    public init(kind: LightWindowKind, span: TimeSpan, assessment: LightAssessment) {
        self.kind = kind
        self.span = span
        self.assessment = assessment
    }

    public var score: Int? { assessment.score }
}

/// Either a real score with its confidence and reasons, or an explicit "no forecast".
/// There is no placeholder number: unknown is never shown as a score.
public enum LightAssessment: Codable, Hashable, Sendable {
    case scored(LightScore)
    case noForecast(ForecastUnavailableReason)

    public var score: Int? {
        if case .scored(let s) = self { return s.value }
        return nil
    }

    public var lightScore: LightScore? {
        if case .scored(let s) = self { return s }
        return nil
    }
}

public struct LightScore: Codable, Hashable, Sendable {
    /// 0–100.
    public var value: Int
    public var band: LightBand
    public var confidence: Confidence
    /// Plausible spread given the lead time, e.g. 55...75 for day 5. Equal bounds when confidence is high.
    public var range: ClosedRange<Int>
    /// Inputs, strongest effect first.
    public var contributors: [LightContributor]
    public var source: ForecastSource
    /// When the forecast behind this score was fetched.
    public var forecastFetchedAt: Date
    /// Hours between the fetch and the window's middle.
    public var leadHours: Double
    /// The provider's model ("GFS") when it names one, so the score can say "Windy · GFS".
    public var model: String?
    /// What the provider could not supply for this window; each is phrased beside the reasons and lowers confidence where noted.
    public var notes: [ScoreNote]

    public init(value: Int, band: LightBand, confidence: Confidence, range: ClosedRange<Int>, contributors: [LightContributor],
                source: ForecastSource, forecastFetchedAt: Date, leadHours: Double, model: String? = nil, notes: [ScoreNote] = []) {
        self.model = model
        self.notes = notes
        self.value = value
        self.band = band
        self.confidence = confidence
        self.range = range
        self.contributors = contributors
        self.source = source
        self.forecastFetchedAt = forecastFetchedAt
        self.leadHours = leadHours
    }
}

/// Every window of one local day at one spot, plus the sun events they were built from.
public struct DayLight: Codable, Hashable, Sendable {
    public var day: LocalDay
    public var coordinate: Coordinate
    public var timeZoneIdentifier: String
    public var sun: SunEvents
    public var moon: MoonEvents
    /// Moon phase at local midnight starting the night window (or noon if there is none).
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
