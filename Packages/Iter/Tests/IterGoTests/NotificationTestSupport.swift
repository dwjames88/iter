import Foundation
import IterModel
import IterPlan

/// PlannedAlarm has no public initializer (IterPlan builds it), so tests decode one.
func makeAlarm(_ stop: UUID, _ kind: AlarmKind, at: Date, leaveBy: Date, name: String = "Mesa Arch", drive: TimeInterval = 2880,
               windowStart: Date? = nil) -> PlannedAlarm {
    struct Wire: Encodable {
        var id: String, kind: AlarmKind, fireAt: Date, stopID: UUID, stopName: String, leaveBy: Date, driveSeconds: TimeInterval
        var windowKind: LightWindowKind, windowStart: Date?, includesNavigateAction: Bool
    }
    let wire = Wire(id: AlarmPlan.id(for: stop, kind: kind), kind: kind, fireAt: at, stopID: stop, stopName: name, leaveBy: leaveBy, driveSeconds: drive,
                    windowKind: .goldenEvening, windowStart: windowStart ?? leaveBy.addingTimeInterval(3000), includesNavigateAction: kind == .leaveNow)
    // swiftlint:disable:next force_try
    return try! JSONDecoder().decode(PlannedAlarm.self, from: JSONEncoder().encode(wire))
}
