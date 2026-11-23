import Foundation
import IterModel

/// Realistic sample snapshots for every state Go draws: the widget placeholder, SwiftUI previews and the snapshot renders
/// of the Go screens, the Live Activity and the widgets all use these, so every surface is checked against the same data.
/// A Moab, Utah evening (America/Denver). Times are relative to the `now` passed in.
public enum GoSample: String, CaseIterable, Sendable {
    /// No run.
    case idle
    /// Started; first departure hours away (countdown).
    case armedEarly
    /// Leave-by within 15 minutes.
    case leaveSoon
    /// Leave-by is now.
    case leaveNow
    /// Driving, arriving before set-up ("arrive 17:42 · 28 min before sunset").
    case drivingOnTime
    /// Driving, late for set-up, with the next-best stop offered.
    case drivingLate
    /// Driving, the window will be over on arrival, with the next-best stop offered.
    case drivingMissed
    /// At a stop, shooting: live sky blended with an observation, the window running, the plan fits.
    case atStopShooting
    /// At a stop, staying costs the next stop ("Leave by 18:40 to make blue hour at X").
    case atStopStayCost
    /// Just arrived automatically (geofence): "Not yet" undo for 2 minutes.
    case arrivedUndo
    /// Done with one stop, the next leave-by later today.
    case betweenStops
    /// Done for the day; the next stop is tomorrow morning (Evening Before suggestion).
    case betweenOvernight
    /// The user paused trip mode.
    case paused
    /// The run is over: a short summary.
    case finished
    /// No network: offline-estimate ETA, last good conditions with their ages, "No live data".
    case offline
    /// The app has not run for hours: every value old, the snapshot's age shown.
    case stale
    /// An official alert in force at the next stop.
    case alert
    /// Low Power Mode: refresh intervals stretched, the card says so.
    case powerSaving
    /// No window within the live horizon: the next window's forecast score with its trend.
    case nextWindowForecast

    /// The sample at `now`.
    public func snapshot(now: Date) -> GoSnapshot {
        // Filled in by the samples worker; every case must return a realistic, distinct snapshot.
        .idle(at: now)
    }
}
