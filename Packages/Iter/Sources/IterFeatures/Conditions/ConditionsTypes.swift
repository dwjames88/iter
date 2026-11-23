import Foundation
import IterModel
import IterSources
import IterSky
import IterAstro
import IterConditions

// The values the Conditions screen draws. All `Equatable`; none is a number standing in for missing data.

/// What the screen can honestly say about the data it has.
public enum ConditionsStatus: Equatable, Sendable {
    /// Nothing yet. No score, no placeholder number.
    case loading
    /// The day is over; no forecast is fetched for it.
    case pastDay
    /// The first usable answer (one fast MET Norway request); better sources are still on their way.
    case quick
    /// Every forecast source has answered for the near term; long range or other parts are still coming.
    case nearTerm
    /// Nothing is loading any more.
    case complete
    /// The forecast is older than its time to live. Shown with its age, never as fresh.
    case stale(age: TimeInterval)
    /// No network: the last good forecast, with when it was fetched.
    case offline(lastGood: Date?, age: TimeInterval?)
    /// No forecast source covers this place.
    case outOfCoverage
    /// No forecast could be had, with the reasons the data layer gave.
    case unavailable([NoDataReason])

    /// True while more data is expected (quick or near-term tiers).
    public var isImproving: Bool { self == .quick || self == .nearTerm }
}

/// The one score on the header chip: the place's intent window, or the best window left on the day.
public struct HeadlineScore: Equatable, Sendable {
    public var kind: LightWindowKind
    public var value: Int
    public var band: LightBand
    public var confidence: Confidence
    /// 0...1, for fading.
    public var confidenceValue: Double
    public var range: ClosedRange<Int>
    public var tier: ForecastTier
    public var isStale: Bool
}

/// One window of the selected day with everything the "why" sheet needs.
public struct WindowDetail: Equatable, Identifiable, Sendable {
    public var kind: LightWindowKind
    public var id: LightWindowKind { kind }
    public var span: TimeSpan
    /// After the terrain skyline, when it changes the window.
    public var effectiveSpan: TimeSpan?
    public var score: Int?
    public var band: LightBand?
    public var confidence: Confidence?
    public var confidenceValue: Double?
    public var range: ClosedRange<Int>?
    public var causes: [ConfidenceCause]
    /// Per-factor reasons, strongest effect first (the "why" bars).
    public var contributors: [LightContributor]
    public var notes: [SkyNote]
    public var flags: [SkyFlag]
    /// Why there is no score (the window is over, beyond the forecast, no forecast); nil when scored.
    public var unavailable: SkyUnavailable?
    public var isStale: Bool
    public var source: SourceID?
    /// Seconds the terrain cuts off (evening) or delays (morning); nil when the skyline changes nothing.
    public var terrainLostSeconds: TimeInterval?

    /// The window end a photographer should plan to: the skyline's, when it cuts the window short.
    public var effectiveEnd: Date { (effectiveSpan ?? span).end }
}

public struct SunSample: Equatable, Sendable {
    public var time: Date
    /// Degrees above the horizon (negative below).
    public var altitude: Double
}

public struct CloudHour: Equatable, Sendable {
    public var time: Date
    public var low: Double?
    public var mid: Double?
    public var high: Double?
    public var total: Double?
}

public struct WindowSpan: Equatable, Identifiable, Sendable {
    public var kind: LightWindowKind
    public var id: LightWindowKind { kind }
    public var span: TimeSpan
    public var effectiveSpan: TimeSpan?
    public var score: Int?
}

/// Sun altitude over the day, cloud layers by hour and the window spans, for the light timeline.
public struct LightTimeline: Equatable, Sendable {
    public var dayStart: Date
    public var dayEnd: Date
    public var sun: [SunSample]
    /// Empty until a forecast arrives; never zero-filled.
    public var clouds: [CloudHour]
    public var windows: [WindowSpan]
    public var sunrise: Date?
    public var sunset: Date?
}

/// A day in the outlook with the day's best window.
public struct OutlookRow: Equatable, Identifiable, Sendable {
    public enum Load: Equatable, Sendable { case loading, ready, unavailable }
    public var day: LocalDay
    public var id: String { day.iso }
    public var isToday: Bool
    public var isSelected: Bool
    public var load: Load
    public var bestKind: LightWindowKind?
    public var score: Int?
    public var band: LightBand?
    public var confidence: Confidence?
    public var confidenceValue: Double?
    /// 0.35...1: low confidence fades the row; no score is 0.35.
    public var opacity: Double
}

/// The best window over the coming days.
public struct WhenToGo: Equatable, Sendable {
    public var day: LocalDay
    public var kind: LightWindowKind
    public var score: Int
    public var band: LightBand
    public var confidence: Confidence
    /// True while some days of the outlook have not answered yet.
    public var isProvisional: Bool
}

public struct HourRow: Equatable, Identifiable, Sendable {
    public var time: Date
    public var id: Date { time }
    public var tempC: Double?
    public var cloudTotal: Double?
    public var cloudLow: Double?
    public var cloudMid: Double?
    public var cloudHigh: Double?
    public var precipChance: Double?
    public var precipMm: Double?
    public var windMs: Double?
    public var gustMs: Double?
    public var windDirDeg: Double?
    public var rhPercent: Double?
    public var visibilityKm: Double?
    public var smokeUgm3: Double?
}

/// The nearest report from an airfield or station.
public struct StationObservation: Equatable, Sendable {
    public var stationID: String?
    public var stationName: String?
    public var distanceKm: Double?
    public var observedAt: Date
    public var ageSeconds: TimeInterval
    public var isMilitary: Bool
    /// "Military-origin (US Air Force) via NOAA Aviation Weather Center" when the data says so; "Government (NOAA)" etc.
    public var originLabel: String
    public var flightCategory: String?
    public var weather: [String]
    public var conditions: HourlyConditions
    public var rawMETAR: String?
    /// True when the age is older than 90 minutes (the Live Sky Index gives it no weight past that).
    public var isOld: Bool
}

public struct AlertRow: Equatable, Identifiable, Sendable {
    public var id: String
    public var event: String
    public var headline: String?
    public var severity: WeatherAlert.Severity
    public var onset: Date?
    public var ends: Date?
    public var sender: String?
    public var url: URL?
}

public struct SmokeInfo: Equatable, Sendable {
    /// The HMS analysis density at the place, when it answered.
    public var density: SmokeAnalysis.Density?
    public var nearSurfaceMaxUgm3: Double?
    public var nearSurfaceSource: SourceID?
    public var opticalDepthMax: Double?
    /// Why a part is missing, in plain words.
    public var notes: [String]
    public var isEmpty: Bool { density == nil && nearSurfaceMaxUgm3 == nil && opticalDepthMax == nil }
}

public struct AuroraInfo: Equatable, Sendable {
    public var probabilityPercent: Double?
    public var peakKp: Double?
    public var kp: [AuroraOutlook.KpStep]
    public var isStale: Bool
    public var sourceLabel: String?
}

public struct HorizonInfo: Equatable, Sendable {
    public enum Load: Equatable, Sendable { case known, loading, unavailable }
    public var load: Load
    public var profile: HorizonProfile?
    public var tallestDegrees: Double?
    /// Windows the skyline shortens: the natural span, the span after the skyline, and what it costs.
    public var shortened: [Shortened]

    public struct Shortened: Equatable, Sendable {
        public var kind: LightWindowKind
        public var natural: TimeSpan
        public var effective: TimeSpan
        public var lostSeconds: TimeInterval
    }
}

/// Another source's cloud forecast and how far it disagrees.
public struct ComparisonInfo: Equatable, Sendable {
    public var sourceName: String
    /// Largest difference in total cloud (0...1) over the hours both have.
    public var maxCloudDifference: Double?
    /// True when the difference passes 0.30, the line where confidence drops.
    public var disagrees: Bool
    public var fetchedAt: Date
}

/// Something the Sky Index could use that nobody supplies (light pollution and seeing have no source today).
public struct GapRow: Equatable, Identifiable, Sendable {
    public var subject: GapSubject
    public var id: GapSubject { subject }
    public var title: String
    /// Plain reasons ("No source provides it yet"), never a number.
    public var reasons: [String]
}

public struct EventPoint: Equatable, Sendable {
    public var time: Date
    /// Compass bearing 0...360 at that instant.
    public var azimuth: Double
}

public struct MilkyWayInfo: Equatable, Sendable {
    /// True when the galactic core is up in astronomical dark during the night window.
    public var isVisible: Bool
    public var peakAltitude: Double
    public var peakAzimuth: Double
    public var peakTime: Date
    public var coreUpInDark: TimeSpan?
    /// The part of it with the moon down.
    public var bestWindow: TimeSpan?
}

/// The day's fixed sun and moon facts for the compass.
public struct CompassDay: Equatable, Sendable {
    public var sunrise: EventPoint?
    public var sunset: EventPoint?
    public var solarNoon: Date
    public var moonrise: EventPoint?
    public var moonset: EventPoint?
    public var moonIllumination: Double
    public var moonPhaseName: MoonPhase.Name
    public var milkyWay: MilkyWayInfo?
}

/// Where the sun, the moon and the galactic core are at the scrubbed time.
public struct CompassReadout: Equatable, Sendable {
    public var time: Date
    public var sun: SkyPosition
    public var moon: SkyPosition
    public var milkyWayCore: SkyPosition
    public var sunIsUp: Bool { sun.altitude > 0 }
    public var moonIsUp: Bool { moon.altitude > 0 }
    /// Core above 10 degrees with the sun below -18: the Milky Way is photographable.
    public var coreIsInDark: Bool { milkyWayCore.altitude >= 10 && sun.altitude < -18 }
}

public enum LiveLoad: Equatable, Sendable {
    case idle, loading, ready
}
