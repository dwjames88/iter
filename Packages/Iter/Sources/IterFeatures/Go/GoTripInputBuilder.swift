import Foundation
import IterAstro
import IterGo
import IterModel
import IterPlan
import IterSky

/// Builds what the engine takes: the trip, where it starts, each light stop's session window and the planned legs.
public enum GoTripInputBuilder {
    /// The astronomy-backed light engine the app uses.
    public static func defaultLightEngine() -> LightEngine { LightEngine(ephemeris: Astronomy()) }

    /// Windows come from `Scheduler().sessionWindows(for:engine:)`. `start` is the trip's start place, if it has one
    /// (see `startPlace(for:in:)`).
    public static func make(trip: Trip, start: Place? = nil, engine: LightEngine, plannedLegs: [LegKey: Leg] = [:]) -> GoTripInput {
        GoTripInput(trip: trip, start: start, windows: Scheduler().sessionWindows(for: trip, engine: engine), plannedLegs: plannedLegs)
    }

    /// The trip's start place, found by `startPlaceID` among `places`.
    public static func startPlace(for trip: Trip, in places: [Place]) -> Place? {
        trip.startPlaceID.flatMap { id in places.first { $0.id == id } }
    }
}
