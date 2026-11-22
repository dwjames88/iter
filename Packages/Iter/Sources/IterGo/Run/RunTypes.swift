import Foundation
import IterGoActivity
import IterModel
import IterPlan

// The value types of the trip run (BLUEPRINT §10.1, §5.2). Pure data: the state machine is in RunEngine.swift and the
// persistence boundary in RunPersistence.swift. Nothing here reads the clock.

/// Progress through one stop. Raw values equal `StoredVisitStatus` in IterStore.
public enum VisitStatus: String, Codable, Hashable, Sendable, CaseIterable {
    case pending, enRoute, arrived, done, skipped
}

/// One stop's visit: what happened and the leave/arrival times frozen at departure.
public struct StopVisit: Codable, Hashable, Sendable {
    public var stopID: UUID
    public var status: VisitStatus
    public var departedForAt: Date?
    public var arrivedAt: Date?
    public var leftAt: Date?
    public var plannedLeaveBy: Date?
    public var plannedArrival: Date?

    public init(stopID: UUID, status: VisitStatus = .pending, departedForAt: Date? = nil, arrivedAt: Date? = nil,
                leftAt: Date? = nil, plannedLeaveBy: Date? = nil, plannedArrival: Date? = nil) {
        self.stopID = stopID
        self.status = status
        self.departedForAt = departedForAt
        self.arrivedAt = arrivedAt
        self.leftAt = leftAt
        self.plannedLeaveBy = plannedLeaveBy
        self.plannedArrival = plannedArrival
    }
}

/// Why a transition happened.
public enum RunCause: String, Codable, Hashable, Sendable, CaseIterable {
    case user, geofence, time, motion
}

/// The numbers behind the automatic rules (BLUEPRINT §10.1).
public enum GeofencePolicy {
    /// Entry radius by stop kind: light 150 m, waypoint 200 m, lodging 300 m.
    public static func enterRadius(for kind: StopKind) -> Double {
        switch kind {
        case .light: 150
        case .waypoint: 200
        case .lodging: 300
        }
    }
    /// Exit hysteresis: you have left once you are this far beyond the entry radius.
    public static let exitMargin: Double = 250
    public static func exitRadius(for kind: StopKind) -> Double { enterRadius(for: kind) + exitMargin }
    /// Fixes worse than this never count.
    public static let maxAccuracyM: Double = 200
    /// Accuracy widens the entry radius by at most this much.
    public static let accuracySlackCapM: Double = 50
    /// Two inside fixes must be this far apart (seconds) to enter.
    public static let enterDwellSeconds: TimeInterval = 20
    /// One inside fix slower than this (m/s) enters at once.
    public static let enterSlowSpeed: Double = 2
    /// Two outside fixes must be this far apart (seconds) to exit.
    public static let exitDwellSeconds: TimeInterval = 30
    /// Motion departure: farther than this from the origin (metres) ...
    public static let motionDistanceM: Double = 500
    /// ... at faster than this (m/s), or on two consecutive such fixes.
    public static let motionSpeed: Double = 3
    /// How long "Not yet" works after an automatic transition (D12).
    public static let undoWindow: TimeInterval = 120
}

/// The part of a run "Not yet" restores.
public struct RunSnapshot: Codable, Hashable, Sendable {
    public var phase: GoPhase
    public var pausedFrom: GoPhase?
    public var startedAt: Date?
    public var endedAt: Date?
    public var targetStopID: UUID?
    public var visits: [UUID: StopVisit]
}

/// The way back from an automatic transition: the complete prior state, until `expiresAt`.
public struct PendingUndo: Codable, Hashable, Sendable {
    public var prior: RunSnapshot
    public var cause: RunCause
    public var stopID: UUID?
    public var from: GoPhase
    public var to: GoPhase
    public var expiresAt: Date
}

/// An automatic trigger the user refused with "Not yet".
public struct RunSuppression: Codable, Hashable, Sendable {
    public var stopID: UUID?
    public var from: GoPhase
    public var to: GoPhase
    public var cause: RunCause
    /// True for time triggers: suppressed for the rest of the run. Otherwise until the trigger has been false once.
    public var restOfRun: Bool
}

/// Fix bookkeeping between calls. Not persisted: a relaunch starts counting again.
struct RunTracker: Codable, Hashable, Sendable {
    var insideSince: Date?
    var outsideSince: Date?
    var farCount = 0
    var anchor: Coordinate?
}

public enum RunUserAction: Hashable, Sendable {
    case leaveNow
    /// "I'm here".
    case arrived
    case doneHere
    /// nil = the next stop (the target, or the one after the stop you are at).
    case skip(UUID?)
    /// Undo the last automatic transition.
    case notYet
    case pause
    case resume
    case end
}

public enum RunEvent: Sendable {
    case location(LocationFix)
    /// Time passed.
    case tick
    case user(RunUserAction)
}

/// What the engine supplies on each call.
public struct RunContext: Sendable {
    public var trip: Trip
    /// Computed by the engine from the run's `progress` and `now`.
    public var live: LiveSchedule
    public var now: Date
    public var startCoordinate: Coordinate?
    public var lastFix: LocationFix?

    public init(trip: Trip, live: LiveSchedule, now: Date, startCoordinate: Coordinate? = nil, lastFix: LocationFix? = nil) {
        self.trip = trip
        self.live = live
        self.now = now
        self.startCoordinate = startCoordinate
        self.lastFix = lastFix
    }
}

/// One change of phase (or, for a skip of a later stop, of visits only) with exactly what to persist.
public struct RunTransition: Hashable, Sendable {
    public var from: GoPhase
    public var to: GoPhase
    public var stopID: UUID?
    public var cause: RunCause
    public var automatic: Bool
    /// When "Not yet" stops working; nil for a user action.
    public var undoExpiresAt: Date?
    /// The after-values of the visits this transition changed.
    public var visitChanges: [StopVisit]
}

/// One trip run.
public struct TripRun: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var tripID: UUID
    public var phase: GoPhase
    /// Set while `phase == .paused`.
    public var pausedFrom: GoPhase?
    public var startedAt: Date?
    public var endedAt: Date?
    /// The stop you are at or heading to.
    public var targetStopID: UUID?
    public var visits: [UUID: StopVisit]
    public var pendingUndo: PendingUndo?
    public var suppressions: [RunSuppression]
    var tracker = RunTracker()

    public init(id: UUID, tripID: UUID, phase: GoPhase = .armed, pausedFrom: GoPhase? = nil, startedAt: Date? = nil,
                endedAt: Date? = nil, targetStopID: UUID? = nil, visits: [UUID: StopVisit] = [:], pendingUndo: PendingUndo? = nil,
                suppressions: [RunSuppression] = []) {
        self.id = id
        self.tripID = tripID
        self.phase = phase
        self.pausedFrom = pausedFrom
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.targetStopID = targetStopID
        self.visits = visits
        self.pendingUndo = pendingUndo
        self.suppressions = suppressions
    }

    /// The fix tracker is transient and does not take part in equality.
    public static func == (a: TripRun, b: TripRun) -> Bool {
        a.id == b.id && a.tripID == b.tripID && a.phase == b.phase && a.pausedFrom == b.pausedFrom && a.startedAt == b.startedAt
            && a.endedAt == b.endedAt && a.targetStopID == b.targetStopID && a.visits == b.visits && a.pendingUndo == b.pendingUndo
            && a.suppressions == b.suppressions
    }

    /// The phase the run is really in: `pausedFrom` while paused.
    public var activePhase: GoPhase { phase == .paused ? (pausedFrom ?? TripRun.derivePhase(visits: visits)) : phase }

    /// For `LiveSchedule.make`.
    public var progress: TripProgress {
        TripProgress(visited: Set(visits.values.filter { $0.status == .done }.map(\.stopID)),
                     skipped: Set(visits.values.filter { $0.status == .skipped }.map(\.stopID)),
                     currentStopID: targetStopID, atCurrentStop: activePhase == .atStop)
    }

    /// When "Not yet" stops working, if it still works at `now`.
    public func undoExpiry(at now: Date) -> Date? {
        guard let undo = pendingUndo, now < undo.expiresAt else { return nil }
        return undo.expiresAt
    }

    /// The raw expiry of the pending undo, for the UI to count down to.
    public var undoExpiry: Date? { pendingUndo?.expiresAt }

    public func status(of stopID: UUID) -> VisitStatus { visits[stopID]?.status ?? .pending }

    /// Phase derived from visits alone, for restore.
    static func derivePhase(visits: [UUID: StopVisit]) -> GoPhase {
        if visits.values.contains(where: { $0.status == .enRoute }) { return .driving }
        if visits.values.contains(where: { $0.status == .arrived }) { return .atStop }
        return .betweenStops
    }
}

/// Trip order: day-major, array order within a day (the same as `Scheduler.ordered`, which is internal to IterPlan).
enum RunOrder {
    static func ordered(_ stops: [Stop]) -> [Stop] {
        stops.enumerated().sorted { a, b in
            a.element.dayIndex != b.element.dayIndex ? a.element.dayIndex < b.element.dayIndex : a.offset < b.offset
        }.map(\.element)
    }
}
