import Foundation
import IterModel

// Phase 9 additions to GoSnapshot: the hour strip, sources with their origin tier, the remaining schedule and the
// finished-trip summary. Plain data, like the rest of the snapshot.

/// One hour of the next stop's short-range strip.
public struct GoHourInfo: Codable, Hashable, Sendable {
    public enum Basis: String, Codable, Hashable, Sendable { case observation, nowcast, forecast }

    public var time: Date
    public var basis: Basis
    /// 0...1.
    public var cloudTotal: Double?
    /// 0...1.
    public var precipChance: Double?
    public var tempC: Double?
    public var windMs: Double?
    public var visibilityKm: Double?
    /// The hour overlaps the next stop's light window (highlighted in the strip).
    public var isInWindow: Bool

    public init(time: Date, basis: Basis, cloudTotal: Double? = nil, precipChance: Double? = nil, tempC: Double? = nil,
                windMs: Double? = nil, visibilityKm: Double? = nil, isInWindow: Bool = false) {
        self.time = time
        self.basis = basis
        self.cloudTotal = cloudTotal
        self.precipChance = precipChance
        self.tempC = tempC
        self.windMs = windMs
        self.visibilityKm = visibilityKm
        self.isInWindow = isInWindow
    }
}

/// One source behind what Go shows, credited where the data is shown (military-origin marked honestly).
public struct GoSourceInfo: Codable, Hashable, Sendable {
    /// What it supplied, in words: "Cloud", "Observation", "Drive time", "Alerts".
    public var role: String
    /// The source's display name: "NOAA HRRR", "KCNY METAR", "Apple Maps".
    public var name: String
    public var tier: SourceTier
    /// Who made the data when that differs from the name ("US Air Force"), from `SourceOrigin.producer`.
    public var producer: String?
    /// Model run, observation or fetch time.
    public var asOf: Date?
    /// Station or grid-point distance.
    public var distanceKm: Double?
    public var isStale: Bool

    public init(role: String, name: String, tier: SourceTier, producer: String? = nil, asOf: Date? = nil, distanceKm: Double? = nil,
                isStale: Bool = false) {
        self.role = role
        self.name = name
        self.tier = tier
        self.producer = producer
        self.asOf = asOf
        self.distanceKm = distanceKm
        self.isStale = isStale
    }

    public var isMilitary: Bool { tier == .military }
}

/// One upcoming stop in the remaining schedule.
public struct GoScheduleItem: Codable, Hashable, Sendable, Identifiable {
    public var stop: GoStopInfo
    public var leaveBy: Date?
    public var arrival: Date?
    public var status: GoLeaveStatus?

    public init(stop: GoStopInfo, leaveBy: Date? = nil, arrival: Date? = nil, status: GoLeaveStatus? = nil) {
        self.stop = stop
        self.leaveBy = leaveBy
        self.arrival = arrival
        self.status = status
    }

    public var id: UUID { stop.id }
}

/// What happened on a finished run.
public struct GoTripSummary: Codable, Hashable, Sendable {
    public enum Outcome: String, Codable, Hashable, Sendable { case shot, skipped, missed }

    public struct Stop: Codable, Hashable, Sendable, Identifiable {
        public var id: UUID
        public var number: Int
        public var name: String
        public var windowKind: LightWindowKind?
        public var outcome: Outcome
        public var arrivedAt: Date?
        public var leftAt: Date?
        /// The last sky score Go held for the stop's window while there (nil when it never had one).
        public var score: Int?
        public var timeZoneIdentifier: String

        public init(id: UUID, number: Int, name: String, windowKind: LightWindowKind?, outcome: Outcome, arrivedAt: Date? = nil,
                    leftAt: Date? = nil, score: Int? = nil, timeZoneIdentifier: String) {
            self.id = id
            self.number = number
            self.name = name
            self.windowKind = windowKind
            self.outcome = outcome
            self.arrivedAt = arrivedAt
            self.leftAt = leftAt
            self.score = score
            self.timeZoneIdentifier = timeZoneIdentifier
        }
    }

    public var startedAt: Date?
    public var endedAt: Date?
    public var stops: [Stop]
    /// Metres driven, when known.
    public var drivenMeters: Double?

    public init(startedAt: Date?, endedAt: Date?, stops: [Stop], drivenMeters: Double? = nil) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.stops = stops
        self.drivenMeters = drivenMeters
    }
}
