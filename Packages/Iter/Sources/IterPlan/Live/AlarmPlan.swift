import Foundation
import IterModel

/// Which alarm.
public enum AlarmKind: String, Codable, Hashable, Sendable {
    /// 15 minutes before leave-by: "Leave in 15 minutes for Mesa Arch".
    case leaveSoon
    /// At leave-by, with a Navigate action.
    case leaveNow
}

/// One notification the Go layer should have scheduled: pure data, no `UNNotificationRequest`.
public struct PlannedAlarm: Codable, Hashable, Sendable, Identifiable {
    /// Stable: "<stopID>-leaveSoon" / "<stopID>-leaveNow". A re-plan with a new ETA yields the same ids with new times, so
    /// scheduling by id replaces the old request instead of duplicating it.
    public var id: String
    public var kind: AlarmKind
    public var fireAt: Date
    public var stopID: UUID
    public var stopName: String
    /// The leave-by this alarm counts down to (never earlier than `earliestDeparture`).
    public var leaveBy: Date
    public var driveSeconds: TimeInterval
    public var windowKind: LightWindowKind
    public var windowStart: Date?
    /// True for `.leaveNow`: the notification offers a Navigate action.
    public var includesNavigateAction: Bool
}

public enum AlarmPlan {
    public static func id(for stopID: UUID, kind: AlarmKind) -> String { "\(stopID.uuidString)-\(kind.rawValue)" }

    /// The alarms for the stops still to come.
    ///
    /// - Each upcoming stop that has a leave-by and is not already late, missed or unscheduled gets at most two: leave-soon at
    ///   leave-by − 15 min and leave-now at leave-by. The leave-by is pushed back to when the previous stop frees you
    ///   (`earliestDeparture`) so an alarm never rings while you are still shooting the stop before.
    /// - **Alarms in the past are not emitted, and nothing fires immediately.** Trip mode shows `.leaveNow` and `.late` in the app
    ///   (and the Live Activity) as soon as the status changes; replanning every minute must not re-fire a delivered alarm, and an
    ///   immediate fire would. (If `now` is past leave-soon but before leave-now, only leave-now is emitted.)
    /// - Skipped and visited stops have no alarms: they are absent from `live`.
    /// - Output order: trip order, leave-soon before leave-now.
    public static func make(live: LiveSchedule, trip: Trip, now: Date) -> [PlannedAlarm] {
        var out: [PlannedAlarm] = []
        let stops = Dictionary(trip.stops.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for item in live.upcoming {
            guard let stop = stops[item.stopID], var leaveBy = item.leaveBy else { continue }
            switch item.status {
            case .late, .missed, .atStop, .unscheduled: continue
            case .early, .leaveSoon, .leaveNow: break
            }
            if let earliest = item.earliestDeparture, earliest > leaveBy { leaveBy = earliest }
            let soon = leaveBy.addingTimeInterval(-LiveSchedule.leaveSoonLead)
            func alarm(_ kind: AlarmKind, at date: Date) -> PlannedAlarm {
                PlannedAlarm(id: id(for: stop.id, kind: kind), kind: kind, fireAt: date, stopID: stop.id, stopName: stop.place.name,
                             leaveBy: leaveBy, driveSeconds: item.driveSeconds, windowKind: stop.session, windowStart: item.window?.start,
                             includesNavigateAction: kind == .leaveNow)
            }
            if soon > now { out.append(alarm(.leaveSoon, at: soon)) }
            if leaveBy > now { out.append(alarm(.leaveNow, at: leaveBy)) }
        }
        return out
    }
}
