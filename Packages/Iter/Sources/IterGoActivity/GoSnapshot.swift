import Foundation
import IterModel

// The single value the Go screen, the Live Activity and the widgets render (BLUEPRINT §5.2, §10.5). It lives here, not in
// IterGo, because the widget extension links only IterModel, IterUI and IterGoActivity and reads this value from the App
// Group; it never opens the store. Everything is plain data: no IterSky or IterPlan types, so band, confidence and trend
// are mirrored as small raw-value enums (`GoBand`, `GoConfidence`, `GoTrend`) whose raw values match IterSky's.

/// Where the run is.
public enum GoPhase: String, Codable, Hashable, Sendable, CaseIterable {
    /// No run.
    case idle
    /// Started, before the first departure.
    case armed
    /// On the road to `next`.
    case driving
    /// At `current`.
    case atStop
    /// Done with one stop, waiting to leave for the next (including overnight).
    case betweenStops
    /// The user paused trip mode: no automatic transitions, no alerts.
    case paused
    /// Last stop done or "End trip".
    case finished
}

/// Mirrors IterSky's `LightBand` (raw values equal its case names).
public enum GoBand: String, Codable, Hashable, Sendable, CaseIterable {
    case poor, fair, good, great, epic
}

/// Mirrors IterSky's `Confidence`.
public enum GoConfidence: String, Codable, Hashable, Sendable, CaseIterable {
    case low, medium, high
}

/// Mirrors IterSky's `LiveTrend`.
public enum GoTrend: String, Codable, Hashable, Sendable, CaseIterable {
    case rising, steady, falling, unknown
}

/// Mirrors IterPlan's `LiveStatus`, flattened.
public enum GoLeaveStatus: String, Codable, Hashable, Sendable, CaseIterable {
    case early, leaveSoon, leaveNow, late, missed, atStop, unscheduled
}

/// How a drive time was obtained. Mirrors IterPlan's `ETASource`.
public enum GoETASource: String, Codable, Hashable, Sendable, CaseIterable {
    /// A live, traffic-aware ETA from where you are.
    case live
    /// The leg planned in the builder.
    case planned
    /// No network: the planned leg scaled by progress along it, or a straight line. Labelled "offline estimate".
    case offlineEstimate
}

/// One stop as Go shows it.
public struct GoStopInfo: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// 1-based position in the trip.
    public var number: Int
    public var name: String
    public var locality: String?
    public var kind: StopKind
    public var dayIndex: Int
    public var coordinate: Coordinate
    /// The stop's own zone: every time about it is shown in this zone (D13).
    public var timeZoneIdentifier: String
    public var windowKind: LightWindowKind?
    public var windowStart: Date?
    public var windowEnd: Date?
    public var setUpBy: Date?
    public var arriveBy: Date?

    public init(id: UUID, number: Int, name: String, locality: String? = nil, kind: StopKind, dayIndex: Int, coordinate: Coordinate,
                timeZoneIdentifier: String, windowKind: LightWindowKind? = nil, windowStart: Date? = nil, windowEnd: Date? = nil,
                setUpBy: Date? = nil, arriveBy: Date? = nil) {
        self.id = id
        self.number = number
        self.name = name
        self.locality = locality
        self.kind = kind
        self.dayIndex = dayIndex
        self.coordinate = coordinate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.windowKind = windowKind
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.setUpBy = setUpBy
        self.arriveBy = arriveBy
    }
}

/// When to leave for `next`, and how that stands against the clock.
public struct GoLeaveInfo: Codable, Hashable, Sendable {
    /// The latest departure that still makes set-up. nil when no time binds the next stop.
    public var leaveBy: Date?
    public var status: GoLeaveStatus
    /// Late: projected arrival minus set-up-by, seconds (positive).
    public var lateBySeconds: TimeInterval?
    /// When the chain (or the current stop's window) frees you, if later than now.
    public var earliestDeparture: Date?
    /// An Evening Before transfer: when the plan has you set off (the previous stop's session end), earlier than `leaveBy`,
    /// which stays the hard latest departure for the morning arrival. "Drive to X tonight".
    public var suggestedDeparture: Date?

    public init(leaveBy: Date?, status: GoLeaveStatus, lateBySeconds: TimeInterval? = nil, earliestDeparture: Date? = nil,
                suggestedDeparture: Date? = nil) {
        self.leaveBy = leaveBy
        self.status = status
        self.lateBySeconds = lateBySeconds
        self.earliestDeparture = earliestDeparture
        self.suggestedDeparture = suggestedDeparture
    }
}

/// The drive to `next`.
public struct GoDriveInfo: Codable, Hashable, Sendable {
    /// Projected arrival (leaving now while driving; leaving at leave-by otherwise).
    public var arrival: Date?
    public var driveSeconds: TimeInterval
    public var driveMeters: Double?
    public var source: GoETASource
    /// When the drive time was computed (the ETA's fetch time, or the estimate's time).
    public var asOf: Date

    public init(arrival: Date?, driveSeconds: TimeInterval, driveMeters: Double?, source: GoETASource, asOf: Date) {
        self.arrival = arrival
        self.driveSeconds = driveSeconds
        self.driveMeters = driveMeters
        self.source = source
        self.asOf = asOf
    }
}

/// While at a stop: the real cost of staying, so a photographer mid-shoot can decide without being nagged.
/// "Shoot until 18:52 as planned" or "Leave by 18:40 to make blue hour at X (12 min before this window ends)".
public struct GoStayInfo: Codable, Hashable, Sendable {
    /// When the plan has you leaving this stop (window end, or start + dwell).
    public var plannedDeparture: Date?
    /// The next stop's leave-by: the latest you can stay and still make its set-up.
    public var latestDeparture: Date?
    /// How much earlier than planned you must leave to make the next stop (positive), or nil when the plan fits.
    public var cutsShortBySeconds: TimeInterval?
    /// The next stop's name and window, for the sentence.
    public var nextStopName: String?
    public var nextWindowKind: LightWindowKind?

    public init(plannedDeparture: Date?, latestDeparture: Date?, cutsShortBySeconds: TimeInterval?, nextStopName: String?,
                nextWindowKind: LightWindowKind?) {
        self.plannedDeparture = plannedDeparture
        self.latestDeparture = latestDeparture
        self.cutsShortBySeconds = cutsShortBySeconds
        self.nextStopName = nextStopName
        self.nextWindowKind = nextWindowKind
    }
}

/// The next-best stop when `next` is late or missed.
public struct GoAlternativeInfo: Codable, Hashable, Sendable {
    public var stopID: UUID
    public var name: String
    public var windowKind: LightWindowKind?
    public var windowStart: Date
    public var projectedArrival: Date
    public var makesSetUp: Bool

    public init(stopID: UUID, name: String, windowKind: LightWindowKind?, windowStart: Date, projectedArrival: Date, makesSetUp: Bool) {
        self.stopID = stopID
        self.name = name
        self.windowKind = windowKind
        self.windowStart = windowStart
        self.projectedArrival = projectedArrival
        self.makesSetUp = makesSetUp
    }
}

/// The sky for the window Go is heading into.
public struct GoSkyInfo: Codable, Hashable, Sendable {
    /// What the numbers rest on.
    public enum Basis: String, Codable, Hashable, Sendable {
        /// Live Sky Index: an observation is blended in.
        case blended
        /// Live Sky Index with no usable observation: nowcast and forecast only.
        case forecastOnly
        /// Live Sky Index from an observation alone (no forecast).
        case observationOnly
        /// No window within the live horizon: the next window's Forecast Sky Index, with its trend across refreshes.
        case nextWindowForecast
        /// Nothing at all.
        case noData
    }

    public var stopID: UUID?
    public var windowKind: LightWindowKind?
    public var windowStart: Date?
    public var windowEnd: Date?
    /// The Live Sky Index (nil when the basis is `.nextWindowForecast` or `.noData`).
    public var liveScore: Int?
    /// The Forecast Sky Index for the same window.
    public var forecastScore: Int?
    /// Band of the score shown (live when present, else forecast).
    public var band: GoBand?
    public var confidence: GoConfidence
    /// The live trend over the next hour (nowcast); for `.nextWindowForecast`, how the forecast score moved since the last refresh.
    public var trend: GoTrend
    public var basis: Basis
    /// Time of the freshest input.
    public var asOf: Date?
    /// "No live data", "Forecast only, no recent observation", "Forecast from 06:29, offline".
    public var notice: String?
    public var isStale: Bool

    public init(stopID: UUID?, windowKind: LightWindowKind?, windowStart: Date?, windowEnd: Date?, liveScore: Int?, forecastScore: Int?,
                band: GoBand?, confidence: GoConfidence, trend: GoTrend, basis: Basis, asOf: Date?, notice: String?, isStale: Bool) {
        self.stopID = stopID
        self.windowKind = windowKind
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.liveScore = liveScore
        self.forecastScore = forecastScore
        self.band = band
        self.confidence = confidence
        self.trend = trend
        self.basis = basis
        self.asOf = asOf
        self.notice = notice
        self.isStale = isStale
    }

    /// The number to show: live when there is one, else the forecast.
    public var displayScore: Int? { liveScore ?? forecastScore }
}

/// Current weather at one place: the nearest observation, or the current forecast hour (labelled).
public struct GoWeatherInfo: Codable, Hashable, Sendable {
    public enum Basis: String, Codable, Hashable, Sendable { case observation, forecast }
    /// Where this is: your position or a stop.
    public enum Subject: Codable, Hashable, Sendable {
        case here
        case stop(UUID)
    }

    public var subject: Subject
    public var basis: Basis
    public var tempC: Double?
    /// 0...1.
    public var cloudTotal: Double?
    public var visibilityKm: Double?
    /// 0...1.
    public var precipChance: Double?
    public var windMs: Double?
    public var stationName: String?
    public var stationDistanceKm: Double?
    public var asOf: Date

    public init(subject: Subject, basis: Basis, tempC: Double?, cloudTotal: Double?, visibilityKm: Double?, precipChance: Double?,
                windMs: Double?, stationName: String?, stationDistanceKm: Double?, asOf: Date) {
        self.subject = subject
        self.basis = basis
        self.tempC = tempC
        self.cloudTotal = cloudTotal
        self.visibilityKm = visibilityKm
        self.precipChance = precipChance
        self.windMs = windMs
        self.stationName = stationName
        self.stationDistanceKm = stationDistanceKm
        self.asOf = asOf
    }
}

/// An official alert in force at the next stop.
public struct GoAlertInfo: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var event: String
    public var headline: String?
    /// The source's severity word ("Severe", "Moderate").
    public var severity: String
    public var ends: Date?

    public init(id: String, event: String, headline: String?, severity: String, ends: Date?) {
        self.id = id
        self.event = event
        self.headline = headline
        self.severity = severity
        self.ends = ends
    }
}

/// How old everything is, and what is stale or offline. The Lock Screen shows `generatedAt`'s age, because without push the
/// snapshot is only as fresh as the last time the app ran.
public struct GoFreshness: Codable, Hashable, Sendable {
    public var locationAsOf: Date?
    public var etaAsOf: Date?
    public var conditionsAsOf: Date?
    public var packBuiltAt: Date?
    /// The last network request failed for lack of a connection.
    public var isOffline: Bool
    public var etaIsStale: Bool
    public var conditionsAreStale: Bool
    public var locationIsStale: Bool
    /// Low Power Mode or battery under 20 %: refresh intervals are stretched (§10.6). The card says so.
    public var isPowerSaving: Bool
    /// When the app next expects to refresh while running; the Live Activity's stale date is this + 15 min.
    public var nextRefreshAt: Date?

    public init(locationAsOf: Date? = nil, etaAsOf: Date? = nil, conditionsAsOf: Date? = nil, packBuiltAt: Date? = nil, isOffline: Bool = false,
                etaIsStale: Bool = false, conditionsAreStale: Bool = false, locationIsStale: Bool = false, isPowerSaving: Bool = false,
                nextRefreshAt: Date? = nil) {
        self.locationAsOf = locationAsOf
        self.etaAsOf = etaAsOf
        self.conditionsAsOf = conditionsAsOf
        self.packBuiltAt = packBuiltAt
        self.isOffline = isOffline
        self.etaIsStale = etaIsStale
        self.conditionsAreStale = conditionsAreStale
        self.locationIsStale = locationIsStale
        self.isPowerSaving = isPowerSaving
        self.nextRefreshAt = nextRefreshAt
    }
}

/// An automatic transition the user can still undo ("Not yet"), D12.
public struct GoUndoInfo: Codable, Hashable, Sendable {
    /// What happened, as data: the phase it moved to and the stop concerned.
    public var toPhase: GoPhase
    public var stopID: UUID?
    public var stopName: String?
    public var expiresAt: Date

    public init(toPhase: GoPhase, stopID: UUID?, stopName: String?, expiresAt: Date) {
        self.toPhase = toPhase
        self.stopID = stopID
        self.stopName = stopName
        self.expiresAt = expiresAt
    }
}

/// Everything Go shows, as one value.
public struct GoSnapshot: Codable, Hashable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    /// When this snapshot was built. The widget shows its age.
    public var generatedAt: Date
    public var tripID: UUID?
    public var tripName: String
    public var runID: UUID?
    public var phase: GoPhase
    /// The stop you are at.
    public var current: GoStopInfo?
    /// The stop you are heading to, or will head to next.
    public var next: GoStopInfo?
    /// Stops after `next` still to do.
    public var remainingCount: Int
    public var leave: GoLeaveInfo?
    public var drive: GoDriveInfo?
    public var stay: GoStayInfo?
    public var alternative: GoAlternativeInfo?
    public var sky: GoSkyInfo?
    /// Weather where you are (first) and at the next stop.
    public var weather: [GoWeatherInfo]
    public var alerts: [GoAlertInfo]
    public var freshness: GoFreshness
    public var undo: GoUndoInfo?
    /// Short names of the sources behind the numbers, for the quiet source line (D5).
    public var sources: [String]

    public init(version: Int = GoSnapshot.currentVersion, generatedAt: Date, tripID: UUID?, tripName: String, runID: UUID?, phase: GoPhase,
                current: GoStopInfo? = nil, next: GoStopInfo? = nil, remainingCount: Int = 0, leave: GoLeaveInfo? = nil,
                drive: GoDriveInfo? = nil, stay: GoStayInfo? = nil, alternative: GoAlternativeInfo? = nil, sky: GoSkyInfo? = nil,
                weather: [GoWeatherInfo] = [], alerts: [GoAlertInfo] = [], freshness: GoFreshness = GoFreshness(),
                undo: GoUndoInfo? = nil, sources: [String] = []) {
        self.version = version
        self.generatedAt = generatedAt
        self.tripID = tripID
        self.tripName = tripName
        self.runID = runID
        self.phase = phase
        self.current = current
        self.next = next
        self.remainingCount = remainingCount
        self.leave = leave
        self.drive = drive
        self.stay = stay
        self.alternative = alternative
        self.sky = sky
        self.weather = weather
        self.alerts = alerts
        self.freshness = freshness
        self.undo = undo
        self.sources = sources
    }

    /// No run.
    public static func idle(at date: Date) -> GoSnapshot {
        GoSnapshot(generatedAt: date, tripID: nil, tripName: "", runID: nil, phase: .idle)
    }
}
