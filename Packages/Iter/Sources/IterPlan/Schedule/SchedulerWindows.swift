import Foundation
import IterModel
import IterSky

extension Scheduler {
    /// The span of each light stop's chosen session on its own day at its own place (absent when the sun does not produce it).
    /// These are the sun-geometry windows (`LightEngine.sessionWindow`), not the terrain-adjusted `effectiveSpan`: the schedule
    /// plans to be set up when the light starts. Lodging and waypoint stops get none.
    /// Every scheduling pass needs these; a caller that already has the day's light passes windows in instead of redoing the
    /// astronomy.
    public func sessionWindows(for trip: Trip, engine: LightEngine) -> SessionWindows {
        var out: SessionWindows = [:]
        for stop in trip.stops where stop.kind == .light {
            if let span = engine.sessionWindow(for: stop.place, kind: stop.session, on: trip.day(stop.dayIndex)) {
                out[stop.id] = span
            }
        }
        return out
    }
}
