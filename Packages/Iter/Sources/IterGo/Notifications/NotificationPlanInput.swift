import Foundation
import IterModel
import IterPlan

/// What the planner needs to know about the stop Go is heading to (or about to head to).
public struct NotificationStopFacts: Hashable, Sendable {
    public var stopID: UUID
    public var name: String
    public var status: GoLeaveStatus
    public var leaveBy: Date?
    public var lateBySeconds: TimeInterval?
    public var windowKind: LightWindowKind?
    public var windowStart: Date?
    public var driveSeconds: TimeInterval?
    public var alternativeName: String?
    /// Every time in the text is shown in the stop's own zone (D13).
    public var timeZone: TimeZone
    /// Projected arrival and set-up-by, for "arrive 18:12, set-up 18:04".
    public var projectedArrival: Date?
    public var setUpBy: Date?

    public init(stopID: UUID, name: String, status: GoLeaveStatus, leaveBy: Date? = nil, lateBySeconds: TimeInterval? = nil,
                windowKind: LightWindowKind? = nil, windowStart: Date? = nil, driveSeconds: TimeInterval? = nil,
                alternativeName: String? = nil, timeZone: TimeZone, projectedArrival: Date? = nil, setUpBy: Date? = nil) {
        self.stopID = stopID
        self.name = name
        self.status = status
        self.leaveBy = leaveBy
        self.lateBySeconds = lateBySeconds
        self.windowKind = windowKind
        self.windowStart = windowStart
        self.driveSeconds = driveSeconds
        self.alternativeName = alternativeName
        self.timeZone = timeZone
        self.projectedArrival = projectedArrival
        self.setUpBy = setUpBy
    }
}

/// A conditions change the engine decided is worth telling the user (ConditionsAlertPolicy already applied the +-15 / band rule).
public struct ConditionsAlertNotice: Hashable, Sendable {
    public var stopID: UUID
    public var stopName: String
    public var windowKind: LightWindowKind?
    public var previous: Int
    public var current: Int
    public var reason: ConditionsAlert.Reason
    /// "high cloud moving in".
    public var cause: String?

    public init(stopID: UUID, stopName: String, windowKind: LightWindowKind?, previous: Int, current: Int,
                reason: ConditionsAlert.Reason = .scoreMoved, cause: String? = nil) {
        self.stopID = stopID
        self.stopName = stopName
        self.windowKind = windowKind
        self.previous = previous
        self.current = current
        self.reason = reason
        self.cause = cause
    }
}

/// An automatic arrival that can still be undone.
public struct ArrivalNotice: Hashable, Sendable {
    public var stopID: UUID
    public var stopName: String
    public var undoExpiresAt: Date?

    public init(stopID: UUID, stopName: String, undoExpiresAt: Date? = nil) {
        self.stopID = stopID
        self.stopName = stopName
        self.undoExpiresAt = undoExpiresAt
    }
}

/// Plain data the engine fills for each planning pass.
public struct NotificationPlanInput: Sendable {
    public var now: Date
    public var tripID: UUID
    public var tripName: String
    public var phase: GoPhase
    /// `AlarmPlan.make` output: future alarms for all upcoming stops.
    public var alarms: [PlannedAlarm]
    public var nextStop: NotificationStopFacts?
    /// The stay verdict while at a stop.
    public var stay: GoStayInfo?
    /// The stop Go is at, while at one.
    public var currentStopID: UUID?
    /// The stop being driven to, while driving.
    public var targetStopID: UUID?
    public var conditionsAlerts: [ConditionsAlertNotice]
    public var arrival: ArrivalNotice?
    /// Zones for alarm text (alarms carry no zone); the next stop's own zone is the fallback, then UTC.
    public var timeZones: [UUID: TimeZone]

    public init(now: Date, tripID: UUID, tripName: String, phase: GoPhase, alarms: [PlannedAlarm] = [], nextStop: NotificationStopFacts? = nil,
                stay: GoStayInfo? = nil, currentStopID: UUID? = nil, targetStopID: UUID? = nil,
                conditionsAlerts: [ConditionsAlertNotice] = [], arrival: ArrivalNotice? = nil, timeZones: [UUID: TimeZone] = [:]) {
        self.now = now
        self.tripID = tripID
        self.tripName = tripName
        self.phase = phase
        self.alarms = alarms
        self.nextStop = nextStop
        self.stay = stay
        self.currentStopID = currentStopID
        self.targetStopID = targetStopID
        self.conditionsAlerts = conditionsAlerts
        self.arrival = arrival
        self.timeZones = timeZones
    }
}

/// What is scheduled and what was delivered. Codable so the engine can persist it with the run.
public struct NotificationLedger: Codable, Hashable, Sendable {
    public struct Scheduled: Codable, Hashable, Sendable {
        public var fireAt: Date
        public var contentHash: String
        public init(fireAt: Date, contentHash: String) {
            self.fireAt = fireAt
            self.contentHash = contentHash
        }
    }

    public var scheduled: [String: Scheduled]
    /// id -> when it went out (or was due, for scheduled ones that have since fired).
    public var delivered: [String: Date]
    /// stop id string -> last conditions notification.
    public var conditionsLast: [String: Date]
    public var lastImmediateAt: Date?

    public init(scheduled: [String: Scheduled] = [:], delivered: [String: Date] = [:], conditionsLast: [String: Date] = [:],
                lastImmediateAt: Date? = nil) {
        self.scheduled = scheduled
        self.delivered = delivered
        self.conditionsLast = conditionsLast
        self.lastImmediateAt = lastImmediateAt
    }

    /// A scheduled request whose time has passed has fired (the app may have been suspended): it counts as delivered.
    mutating func settle(now: Date) {
        for (id, entry) in scheduled where entry.fireAt <= now {
            delivered[id] = entry.fireAt
            scheduled[id] = nil
        }
    }
}

/// The planner's answer.
public struct NotificationPlan: Hashable, Sendable {
    /// The complete desired set of future requests.
    public var pending: [GoNotificationRequest]
    /// To deliver now: at most one (the quiet rule).
    public var immediate: [GoNotificationRequest]
    /// The ledger once this plan is applied.
    public var ledger: NotificationLedger
    /// Idle, paused or finished: the sync clears every pending request.
    public var removeAll: Bool
}
