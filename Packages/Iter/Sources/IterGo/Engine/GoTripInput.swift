import Foundation
import IterModel
import IterPlan

/// What the caller (the view model) gives the engine. The engine does no astronomy: `windows` are computed by the caller.
public struct GoTripInput: Sendable {
    public var trip: Trip
    public var start: Place?
    public var windows: SessionWindows
    public var plannedLegs: [LegKey: Leg]

    public init(trip: Trip, start: Place? = nil, windows: SessionWindows, plannedLegs: [LegKey: Leg] = [:]) {
        self.trip = trip
        self.start = start
        self.windows = windows
        self.plannedLegs = plannedLegs
    }
}
