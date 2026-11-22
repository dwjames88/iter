import Foundation
import Testing
import IterCore
import IterAstro
import IterLight
import IterData
@testable import IterFeatures

/// Which day, and whose clock, each stop of a trip is scored and scheduled against.
@MainActor
@Suite struct TripForecastDayTests {
    private func spans(_ h: TripHarness, _ stop: TripStopPlan, _ plan: TripPlan) -> [LightWindowKind: TimeSpan] {
        Dictionary(h.scheduler.engine.windows(for: stop.spot, on: plan.day(stop.dayIndex)).map { ($0.kind, $0.span) }, uniquingKeysWith: { a, _ in a })
    }

    @Test func eachStopIsLitForItsOwnDayAtItsOwnSpot() async {
        let h = TripHarness()
        let trip = h.store.createTrip(name: "Zones", startDay: TripHarness.start, dayCount: 3)
        h.store.addStop(h.spot("tunnel-view"), to: trip, day: 0, session: .goldenEvening)       // Pacific
        h.store.addStop(h.spot("mesa-arch"), to: trip, day: 1, session: .goldenMorning)         // Mountain
        h.store.addStop(h.spot("horseshoe-bend"), to: trip, day: 2, session: .goldenEvening)    // Arizona
        let model = h.model(for: trip)
        await model.waitForLegs()
        let plan = model.plan!

        for entry in model.days.flatMap(\.stops) {
            let expected = spans(h, entry.stop, plan)
            #expect(entry.windows.map(\.span) == h.scheduler.engine.windows(for: entry.stop.spot, on: plan.day(entry.stop.dayIndex)).map(\.span))
            #expect(entry.sessionWindow?.span == expected[entry.stop.session], "\(entry.stop.spot.name) is scored for day \(entry.stop.dayIndex)")
            #expect(entry.schedule?.window == expected[entry.stop.session], "and scheduled against the same window")
        }
        // The day's sun times are read at the day's first stop, in that stop's zone.
        #expect(model.days[0].timeZoneIdentifier == "America/Los_Angeles")
        #expect(model.days[1].timeZoneIdentifier == "America/Denver")
        #expect(model.days[2].timeZoneIdentifier == "America/Phoenix")
        // The same spot on consecutive days gets consecutive days' light, not one day repeated.
        let sameSpot = h.store.createTrip(name: "Same", startDay: TripHarness.start, dayCount: 2)
        h.store.addStop(h.spot("mesa-arch"), to: sameSpot, day: 0, session: .goldenMorning)
        h.store.addStop(h.spot("mesa-arch"), to: sameSpot, day: 1, session: .goldenMorning)
        let two = h.model(for: sameSpot)
        let starts = two.days.flatMap(\.stops).compactMap { $0.sessionWindow?.span.start }
        #expect(starts.count == 2 && starts[0] != starts[1])
        #expect(starts[1].timeIntervalSince(starts[0]) > 23.9 * 3600 && starts[1].timeIntervalSince(starts[0]) < 24.1 * 3600)
    }

    @Test func aDaylightSavingChangeDuringTheTripKeepsTheSunContinuous() async {
        let h = TripHarness()
        // US clocks go back at 2 am on 2026-11-01; Arizona's never change.
        let start = LocalDay(year: 2026, month: 10, day: 31)
        let trip = h.store.createTrip(name: "DST", startDay: start, dayCount: 3)
        for (day, id) in [(0, "mesa-arch"), (1, "mesa-arch"), (2, "mesa-arch")] {
            h.store.addStop(h.spot(id), to: trip, day: day, session: .goldenMorning)
        }
        let model = h.model(for: trip)
        let starts = model.days.flatMap(\.stops).compactMap { $0.sessionWindow?.span.start }
        #expect(starts.count == 3)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TripHarness.denver
        let minutes = starts.map { calendar.component(.hour, from: $0) * 60 + calendar.component(.minute, from: $0) }
        // The sun is continuous: consecutive golden mornings are 24 h apart (give or take its drift), whatever the clocks do.
        #expect(abs(starts[1].timeIntervalSince(starts[0]) - 24 * 3600) < 600)
        #expect(abs(starts[2].timeIntervalSince(starts[1]) - 24 * 3600) < 600)
        // The wall clock steps back an hour with the change (7:xx MDT on the 31st, 6:xx MST on the 1st) and then settles.
        #expect(abs(minutes[1] - minutes[0] + 60) < 6)
        #expect(abs(minutes[2] - minutes[1]) < 6)
    }

    @Test func aLegIntoAnotherZoneIsScheduledOnTheSameClock() async {
        let h = TripHarness()
        let trip = h.store.createTrip(name: "Cross", startDay: TripHarness.start, dayCount: 2)
        h.store.addStop(h.spot("tunnel-view"), to: trip, day: 0, session: .goldenEvening)   // Pacific
        h.store.addStop(h.spot("mesa-arch"), to: trip, day: 1, session: .goldenMorning)     // Mountain
        let model = h.model(for: trip, drives: FakeDrives(minutes: 600))
        await model.waitForLegs()
        let second = model.days[1].stops[0]
        let schedule = second.schedule!
        #expect(schedule.leaveBy == schedule.arriveBy!.addingTimeInterval(-600 * 60), "absolute times, whatever each end's zone")
        let drive = model.layout.groups[1].items.compactMap { item -> TripDriveItem? in
            if case .driveIn(let drive) = item { drive } else { nil }
        }.first
        #expect(drive?.leaveZone.identifier == "America/Los_Angeles", "leave-by is read on the clock of the place you leave")
        #expect(second.isOvernightFromPrevious)
    }

    @Test func aTripBeyondTheForecastGetsPersistenceNotNoForecast() async {
        let h = TripHarness()
        let trip = h.store.createTrip(name: "Far", startDay: TripHarness.start, dayCount: 10)
        let mesa = h.spot("mesa-arch")
        h.store.addStop(mesa, to: trip, day: 0, session: .goldenMorning)
        h.store.addStop(mesa, to: trip, day: 9, session: .goldenMorning)
        // Two days of hourly weather from the clock's "now" (6 October 10:00 Denver).
        let from = LocalDay(year: 2026, month: 10, day: 6).at(hour: 10, in: TripHarness.denver)
        let hours = (0..<48).map { i in
            HourlyConditions(date: from.addingTimeInterval(Double(i) * 3600), cloudCover: 0.3, cloudLow: 0.1, cloudMid: 0.2, cloudHigh: 0.3,
                             precipitationChance: 0.0, visibilityMeters: 20_000, windSpeedKph: 5, temperatureC: 12, humidity: 0.5,
                             symbolName: "sun.max", condition: "clear")
        }
        h.forecasts.seed(Forecast(coordinate: mesa.coordinate, hours: hours, days: [], fetchedAt: from, source: .appleWeather), for: mesa.coordinate)
        let model = h.model(for: trip)
        let near = model.days[0].stops[0].sessionWindow
        let far = model.days[9].stops[0].sessionWindow
        #expect(near?.assessment.lightScore != nil, "inside the forecast it is scored")
        let score = far?.assessment.lightScore
        #expect(score != nil, "beyond the horizon it is still scored (persistence), never 'No forecast'")
        #expect(score?.confidence == .low)
    }
}
