import Foundation
import IterModel
@testable import IterPlan

let utc = TimeZone(identifier: "UTC")!
let denver = TimeZone(identifier: "America/Denver")!
let newYork = TimeZone(identifier: "America/New_York")!
let testDay = LocalDay(year: 2026, month: 10, day: 12)

/// The old tests' fixed sun: the same times every day (hours after local midnight in UTC): sunrise 06:12, sunset 18:20,
/// golden morning to 07:00, golden evening from 17:30, night from 20:10 for three hours.
enum StandardDay {
    static func at(_ day: LocalDay, _ hour: Double) -> Date {
        day.start(in: utc).addingTimeInterval(hour * 3600)
    }

    static func window(_ kind: LightWindowKind, on day: LocalDay) -> TimeSpan {
        switch kind {
        case .blueMorning: TimeSpan(start: at(day, 5.67), end: at(day, 6.2))
        case .goldenMorning: TimeSpan(start: at(day, 6.2), end: at(day, 7.0))
        case .goldenEvening: TimeSpan(start: at(day, 17.5), end: at(day, 18.333))
        case .blueEvening: TimeSpan(start: at(day, 18.333), end: at(day, 18.833))
        case .night: TimeSpan(start: at(day, 20.167), end: at(day, 20.167 + 3))
        }
    }
}

func makePlace(_ name: String = "place", lat: Double = 40, lon: Double = -110, walk: Int? = 10, zone: String = "UTC") -> Place {
    Place(name: name, coordinate: Coordinate(latitude: lat, longitude: lon), timeZoneIdentifier: zone, category: .landscape,
          walkInMinutes: walk, origin: .user)
}

func stop(_ name: String, day: Int, _ session: LightWindowKind, lat: Double = 40, lon: Double = -110, walk: Int? = 10,
          buffer: Int = 20, kind: StopKind = .light, dwell: Int = 0, fixed: String? = nil, zone: String = "UTC") -> Stop {
    Stop(place: makePlace(name, lat: lat, lon: lon, walk: walk, zone: zone), dayIndex: day, session: session,
         setUpBufferMinutes: buffer, dwellMinutes: dwell, fixedArrival: fixed.flatMap { LocalTime(iso: $0) }, kind: kind)
}

func makeTrip(_ stops: [Stop], days: Int = 2, timings: [Int: TransferTiming] = [:], start: Place? = nil) -> Trip {
    Trip(name: "t", startDay: testDay, dayCount: days, stops: stops, transferTimings: timings, startPlaceID: start?.id)
}

/// The standard-day window of every light stop's session on its day, minus `omit` (stops whose window the sun does not produce).
func standardWindows(_ trip: Trip, omit: Set<UUID> = []) -> SessionWindows {
    var out: SessionWindows = [:]
    for stop in trip.stops where stop.kind == .light && !omit.contains(stop.id) {
        out[stop.id] = StandardDay.window(stop.session, on: trip.day(stop.dayIndex))
    }
    return out
}

func leg(_ a: Stop, _ b: Stop, minutes: Double) -> (LegKey, Leg) {
    (LegKey(a.id, b.id), Leg(from: a.place.coordinate, to: b.place.coordinate, seconds: minutes * 60, meters: 50_000, isEstimate: false))
}

func legs(_ pairs: (LegKey, Leg)...) -> [LegKey: Leg] { Dictionary(uniqueKeysWithValues: pairs) }

func startLeg(_ start: Place, _ b: Stop, minutes: Double) -> (LegKey, Leg) {
    (LegKey(start.id, b.id), Leg(from: start.coordinate, to: b.place.coordinate, seconds: minutes * 60, meters: 50_000, isEstimate: false))
}

/// Deterministic generator (SplitMix64). Never the system generator in tests.
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

let scheduler = Scheduler()

func schedule(_ trip: Trip, start: Place? = nil, windows: SessionWindows? = nil, legs: [LegKey: Leg] = [:]) -> TripSchedule {
    scheduler.schedule(trip: trip, start: start, windows: windows ?? standardWindows(trip), legs: legs)
}
