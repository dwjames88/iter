import Foundation

/// When the live ETA should next be asked for (BLUEPRINT §10.2, §10.6). Pure.
///
/// Cadence (all constants are in `Cadence`):
/// - driving: every 3 min; power saving 10 min; stationary for over 5 min (fuel or food stop) 6 min (power saving
///   still 10); moved 2 km or more since the last request: due at once, but never sooner than 60 s after the last.
/// - armed / betweenStops / atStop, by time to leave-by: over 2 h every 60 min; 1 to 2 h every 15 min; 30 to 60 min
///   every 5 min; under 30 min every 3 min; at or past leave-by every 2 min. No leave-by known counts as over 2 h.
///   Power saving doubles the interval with a 10 min floor.
/// - paused / finished / idle: nil.
/// Never before `backoffUntil`.
public enum ETARefreshPolicy {
    public enum Cadence {
        public static let driving: TimeInterval = 3 * 60
        public static let drivingPowerSaving: TimeInterval = 10 * 60
        public static let drivingStationary: TimeInterval = 6 * 60
        /// "Stationary" for the engine: parked this long while the phase is driving.
        public static let stationaryAfter: TimeInterval = 5 * 60
        public static let movedDistanceM: Double = 2_000
        public static let movedMinSpacing: TimeInterval = 60

        public static let farAhead: TimeInterval = 60 * 60       // leave-by over 2 h away
        public static let twoHours: TimeInterval = 2 * 3600
        public static let oneHour: TimeInterval = 3600
        public static let halfHour: TimeInterval = 30 * 60
        public static let hourToTwo: TimeInterval = 15 * 60      // 1-2 h
        public static let halfToHour: TimeInterval = 5 * 60      // 30-60 min
        public static let underHalf: TimeInterval = 3 * 60       // under 30 min
        public static let pastLeaveBy: TimeInterval = 2 * 60     // at or after leave-by
        public static let savingFloor: TimeInterval = 10 * 60
    }

    /// The next time a request is due, or nil when none is needed now. A date in the past means due now. With no
    /// previous request the answer is `now` (or `backoffUntil` when later). `remainingDriveSeconds` is accepted so the
    /// engine can pass what it knows; it does not change the cadence today.
    public static func nextRefresh(lastRequestAt: Date?, now: Date, phase: GoPhase, untilLeaveBy: TimeInterval?,
                                   remainingDriveSeconds: TimeInterval?, movedSinceLastRequestM: Double, isStationary: Bool,
                                   power: PowerState, backoffUntil: Date?) -> Date? {
        let interval: TimeInterval
        var due: Date
        switch phase {
        case .idle, .paused, .finished:
            return nil
        case .driving:
            if power.isSaving { interval = Cadence.drivingPowerSaving }
            else if isStationary { interval = Cadence.drivingStationary }
            else { interval = Cadence.driving }
            if let last = lastRequestAt {
                due = movedSinceLastRequestM >= Cadence.movedDistanceM
                    ? last.addingTimeInterval(Cadence.movedMinSpacing)
                    : last.addingTimeInterval(interval)
            } else {
                due = now
            }
        case .armed, .betweenStops, .atStop:
            interval = leaveByInterval(untilLeaveBy: untilLeaveBy, power: power)
            due = lastRequestAt.map { $0.addingTimeInterval(interval) } ?? now
        }
        if let backoffUntil, backoffUntil > due { due = backoffUntil }
        return due
    }

    static func leaveByInterval(untilLeaveBy: TimeInterval?, power: PowerState) -> TimeInterval {
        let base: TimeInterval
        switch untilLeaveBy {
        case nil: base = Cadence.farAhead
        case let t? where t > Cadence.twoHours: base = Cadence.farAhead
        case let t? where t >= Cadence.oneHour: base = Cadence.hourToTwo
        case let t? where t >= Cadence.halfHour: base = Cadence.halfToHour
        case let t? where t > 0: base = Cadence.underHalf
        default: base = Cadence.pastLeaveBy
        }
        return power.isSaving ? max(base * 2, Cadence.savingFloor) : base
    }

    /// The departure to ask MapKit about: now while driving; otherwise the later of now and leave-by.
    public static func departureDate(now: Date, leaveBy: Date?, phase: GoPhase) -> Date {
        if phase == .driving { return now }
        return max(now, leaveBy ?? now)
    }
}
