import Foundation
import IterModel
import IterAstro
import IterSky
@testable import IterPlan

/// The old TripHarness without the store and the view model: a trip, its legs, the real sun, and the pure builders.
struct TripHarness {
    static let start = LocalDay(year: 2026, month: 10, day: 7)
    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    let engine = LightEngine(ephemeris: Astronomy())
    let mesa = makeBuilderPlace("Mesa Arch", "Canyonlands National Park, UT", 38.3872, -109.8663, "America/Denver", walk: 10)
    let delicate = makeBuilderPlace("Delicate Arch", "Arches National Park, UT", 38.7436, -109.4993, "America/Denver", walk: 45)
    let horseshoe = makeBuilderPlace("Horseshoe Bend", "Page, AZ", 36.8791, -111.5104, "America/Phoenix", walk: 15)
    let home = makeBuilderPlace("Home", "Moab, UT", 38.5733, -109.5498, "America/Denver", walk: nil)

    /// Two days: day 0 Mesa Arch (sunrise) then Delicate Arch (sunset); day 1 Horseshoe Bend (sunset).
    func makeTrip(start: Place? = nil) -> Trip {
        Trip(name: "Test", startDay: Self.start, dayCount: 2, stops: [
            Stop(place: mesa, dayIndex: 0, session: .goldenMorning),
            Stop(place: delicate, dayIndex: 0, session: .goldenEvening),
            Stop(place: horseshoe, dayIndex: 1, session: .goldenEvening),
        ], startPlaceID: start?.id)
    }

    func trip(days: Int, _ stops: [(Place, Int, LightWindowKind)]) -> Trip {
        Trip(name: "Test", startDay: Self.start, dayCount: days,
             stops: stops.map { Stop(place: $0.0, dayIndex: $0.1, session: $0.2) })
    }

    struct Built {
        var trip: Trip
        var schedule: TripSchedule
        var suggestions: [OrderingSuggestion]
        var days: [TripDay]
        var layout: TripDayLayout
    }

    /// `drives`: a fixed time for every drive (the old FakeDrives, 60 minutes), or nil for no routes (everything estimated).
    func build(_ trip: Trip, start: Place? = nil, driveMinutes: Double? = 60) -> Built {
        let scheduler = Scheduler()
        let windows = scheduler.sessionWindows(for: trip, engine: engine)
        var legs: [LegKey: Leg] = [:]
        if let driveMinutes {
            let all = Dictionary(uniqueKeysWithValues: trip.stops.map { ($0.id, $0.place) })
            for key in scheduler.legPairsNeeded(for: trip, start: start, windows: windows) {
                let from = all[key.from] ?? start!
                let to = all[key.to]!
                legs[key] = Leg(from: from.coordinate, to: to.coordinate, seconds: driveMinutes * 60, meters: 80_000, isEstimate: false,
                                path: [from.coordinate, to.coordinate])
            }
        }
        let schedule = scheduler.schedule(trip: trip, start: start, windows: windows, legs: legs)
        let suggestions = scheduler.suggestOrdering(trip: trip, start: start, windows: windows, legs: legs)
        let days = TripDays.make(trip: trip, start: start, schedule: schedule, lights: lights(for: trip))
        return Built(trip: trip, schedule: schedule, suggestions: suggestions, days: days,
                     layout: TripDayLayout.make(days: days, suggestions: suggestions))
    }

    func lights(for trip: Trip) -> [UUID: DayLight] {
        Dictionary(uniqueKeysWithValues: trip.stops.map {
            ($0.id, engine.dayLight(for: $0.place, on: trip.day($0.dayIndex), inputs: nil, now: Self.now))
        })
    }
}

func makeBuilderPlace(_ name: String, _ locality: String, _ lat: Double, _ lon: Double, _ zone: String, walk: Int?) -> Place {
    Place(name: name, locality: locality, coordinate: Coordinate(latitude: lat, longitude: lon), timeZoneIdentifier: zone,
          category: .landscape, walkInMinutes: walk, origin: .curated)
}

func scored(_ value: Int) -> LightAssessment {
    .scored(SkyScore(value: value, band: LightBand(score: value), confidence: .high, confidenceValue: 0.9, range: value...value,
                     contributors: [], forecastFetchedAt: Date(timeIntervalSince1970: 0), leadHours: 12, age: 0, isStale: false))
}
