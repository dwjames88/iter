import Foundation
import Testing
import IterCore
@testable import IterLight

private let scheduler = TripScheduler(engine: LightEngine(ephemeris: FixedEphemeris()))

private func stop(_ id: String, day: Int, _ session: LightWindowKind, lat: Double = 40, lon: Double = -110, walk: Int? = 10, buffer: Int = 20) -> TripStopPlan {
    TripStopPlan(spot: makeSpot(id, lat: lat, lon: lon, walk: walk), dayIndex: day, session: session, setUpBufferMinutes: buffer)
}

private func trip(_ stops: [TripStopPlan], days: Int = 2) -> TripPlan {
    TripPlan(name: "t", startDay: testDay, dayCount: days, stops: stops)
}

private func leg(_ a: TripStopPlan, _ b: TripStopPlan, minutes: Double) -> (LegKey, DriveLeg) {
    (LegKey(a.id, b.id), DriveLeg(from: a.spot.coordinate, to: b.spot.coordinate, seconds: minutes * 60, meters: 50_000, isEstimate: false))
}

@Suite struct Schedule {
    @Test func leaveByArithmetic() {
        // Sunrise at 06:12 (golden morning start), buffer 20, walk 12, drive 75 -> leave 04:25.
        let a = stop("a", day: 0, .night)
        let b = stop("b", day: 1, .goldenMorning, walk: 12)
        let t = trip([a, b])
        let s = scheduler.schedule(t, legs: [leg(a, b, minutes: 75)].reduce(into: [:]) { $0[$1.0] = $1.1 })
        let sb = s.schedule(for: b.id)!
        let day1 = testDay.adding(days: 1)
        #expect(sb.window?.start == FixedEphemeris.at(day1, 6.2))
        #expect(sb.setUpBy == FixedEphemeris.at(day1, 6.2).addingTimeInterval(-20 * 60))
        #expect(sb.arriveBy == sb.setUpBy!.addingTimeInterval(-12 * 60))
        #expect(sb.leaveBy == FixedEphemeris.at(day1, 4.0 + 25.0 / 60))
        #expect(sb.walkInKnown)
        #expect(sb.issues.isEmpty)
        #expect(sb.legFromPrevious?.seconds == 4500)
        // The first stop has no drive.
        #expect(s.schedule(for: a.id)!.leaveBy == nil)
        #expect(s.issueCount == 0)
    }

    @Test func unknownWalkIn() {
        let a = stop("a", day: 0, .goldenEvening, walk: nil)
        let s = scheduler.schedule(trip([a]), legs: [:]).schedule(for: a.id)!
        #expect(!s.walkInKnown)
        #expect(s.arriveBy == s.setUpBy)
        #expect(s.setUpBy != nil)
    }

    @Test func driveThatDoesNotFit() {
        // Golden evening ends 18:20. Blue evening starts 18:20; set up 18:00, walk 0, drive 30 min -> leave 17:30.
        let a = stop("a", day: 0, .goldenEvening)
        let b = stop("b", day: 0, .blueEvening, walk: 0)
        let legs = Dictionary(uniqueKeysWithValues: [leg(a, b, minutes: 30)])
        let sb = scheduler.schedule(trip([a, b]), legs: legs).schedule(for: b.id)!
        let freeAt = FixedEphemeris.at(testDay, 18.333)
        #expect(sb.leaveBy == freeAt.addingTimeInterval(-20 * 60 - 30 * 60))
        #expect(sb.issues == [.driveDoesNotFit(shortBySeconds: 50 * 60)])
    }

    @Test func outOfOrder() {
        let a = stop("a", day: 0, .night)
        let b = stop("b", day: 0, .goldenMorning)
        let legs = Dictionary(uniqueKeysWithValues: [leg(a, b, minutes: 30)])
        let s = scheduler.schedule(trip([a, b]), legs: legs)
        let sb = s.schedule(for: b.id)!
        #expect(sb.issues.contains(.outOfOrder))
        #expect(sb.issues.contains { if case .driveDoesNotFit = $0 { true } else { false } })
        #expect(s.schedule(for: a.id)!.issues.isEmpty)
    }

    @Test func crossDayDriveIsChecked() {
        let a = stop("a", day: 0, .night)         // free at 23:10
        let b = stop("b", day: 1, .goldenMorning, walk: 0)   // arrive by 05:52
        let fits = scheduler.schedule(trip([a, b]), legs: Dictionary(uniqueKeysWithValues: [leg(a, b, minutes: 300)]))
        #expect(fits.schedule(for: b.id)!.issues.isEmpty)
        // 7 h overnight: leave 22:52, 18 minutes... compute exactly.
        let long = scheduler.schedule(trip([a, b]), legs: Dictionary(uniqueKeysWithValues: [leg(a, b, minutes: 7 * 60)]))
        let sb = long.schedule(for: b.id)!
        let freeAt = FixedEphemeris.at(testDay, 20.167).addingTimeInterval(3 * 3600)
        let expected = freeAt.timeIntervalSince(sb.leaveBy!)
        #expect(expected > 0)
        #expect(sb.issues == [.driveDoesNotFit(shortBySeconds: expected)])
        #expect(sb.leaveBy! < freeAt)
    }

    @Test func missingLegIsEstimated() {
        let a = stop("a", day: 0, .goldenMorning, lat: 40, lon: -110)
        let b = stop("b", day: 0, .goldenEvening, lat: 40.2, lon: -110)
        let s = scheduler.schedule(trip([a, b]), legs: [:]).schedule(for: b.id)!
        #expect(s.issues == [.driveEstimated])
        #expect(s.legFromPrevious?.isEstimate == true)
        #expect(s.leaveBy != nil)
        // An estimated issue does not count as a conflict.
        #expect(scheduler.schedule(trip([a, b]), legs: [:]).issueCount == 0)
    }

    @Test func missingWindow() {
        var eph = FixedEphemeris()
        eph.sun = { d in SunEvents(day: d, kind: .polarDay, solarNoon: FixedEphemeris.at(d, 12)) }
        let sch = TripScheduler(engine: LightEngine(ephemeris: eph))
        let a = stop("a", day: 0, .goldenEvening)
        let s = sch.schedule(trip([a]), legs: [:]).schedule(for: a.id)!
        #expect(s.window == nil && s.setUpBy == nil && s.arriveBy == nil && s.leaveBy == nil)
        #expect(s.issues == [.windowMissing])
    }

    @Test func tripOrderIsDayMajor() {
        let a = stop("a", day: 1, .goldenMorning)
        let b = stop("b", day: 0, .goldenEvening)
        let s = scheduler.schedule(trip([a, b]), legs: [:])
        #expect(s.stops.map(\.stopID) == [b.id, a.id])
    }
}

@Suite struct Ordering {
    @Test func sunsetBeforeSunriseGetsASuggestion() {
        let sunset = stop("sunset", day: 0, .goldenEvening, lat: 40, lon: -110)
        let sunrise = stop("sunrise", day: 0, .goldenMorning, lat: 40.3, lon: -110)
        let t = trip([sunset, sunrise], days: 1)
        let legs = [leg(sunset, sunrise, minutes: 40), leg(sunrise, sunset, minutes: 40)].reduce(into: [LegKey: DriveLeg]()) { $0[$1.0] = $1.1 }
        let suggestions = scheduler.suggestOrdering(t, legs: legs)
        #expect(suggestions.count == 1)
        let s = suggestions[0]
        #expect(s.dayIndex == 0)
        #expect(s.order == [sunrise.id, sunset.id])
        #expect(s.issuesBefore > s.issuesAfter)
        #expect(s.issuesAfter == 0)
        // Estimates work when legs are missing.
        #expect(scheduler.suggestOrdering(t, legs: [:]).count == 1)
        // The trip itself is untouched.
        #expect(t.stops.map(\.id) == [sunset.id, sunrise.id])
    }

    @Test func alreadyGoodDayGetsNone() {
        let sunrise = stop("sunrise", day: 0, .goldenMorning)
        let sunset = stop("sunset", day: 0, .goldenEvening, lat: 40.3)
        #expect(scheduler.suggestOrdering(trip([sunrise, sunset], days: 1), legs: [:]).isEmpty)
        #expect(scheduler.suggestOrdering(trip([sunrise], days: 1), legs: [:]).isEmpty)
        #expect(scheduler.suggestOrdering(trip([], days: 1), legs: [:]).isEmpty)
    }

    @Test func otherDaysAreNotRearranged() {
        let a = stop("a", day: 0, .goldenMorning)
        let b = stop("b", day: 1, .goldenEvening)
        let c = stop("c", day: 1, .goldenMorning, lat: 40.2)
        let suggestions = scheduler.suggestOrdering(trip([a, b, c]), legs: [:])
        #expect(suggestions.map(\.dayIndex) == [1])
        #expect(suggestions[0].order == [c.id, b.id])
    }

    @Test func legPairsCoverCurrentAndSuggested() {
        let sunset = stop("sunset", day: 0, .goldenEvening)
        let sunrise = stop("sunrise", day: 0, .goldenMorning, lat: 40.3)
        let pairs = scheduler.legPairsNeeded(for: trip([sunset, sunrise], days: 1))
        #expect(pairs == [LegKey(sunset.id, sunrise.id), LegKey(sunrise.id, sunset.id)])
        let good = scheduler.legPairsNeeded(for: trip([sunrise, sunset], days: 1))
        #expect(good == [LegKey(sunrise.id, sunset.id)])
    }

    @Test func legKeyCodable() throws {
        let k = LegKey(UUID(), UUID())
        let data = try JSONEncoder().encode(k)
        #expect(try JSONDecoder().decode(LegKey.self, from: data) == k)
    }
}

@Suite struct SchedulerWindows {
    @Test func suppliedWindowsGiveTheSameResultsAsComputingThem() {
        let a = stop("a", day: 0, .goldenEvening)
        let b = stop("b", day: 0, .goldenMorning)
        let c = stop("c", day: 1, .goldenMorning, lat: 41, lon: -111)
        let t = trip([a, b, c])
        let windows = scheduler.sessionWindows(for: t)
        #expect(windows.count == 3)
        let legs = Dictionary(uniqueKeysWithValues: [leg(a, b, minutes: 30), leg(b, c, minutes: 90)])
        #expect(scheduler.schedule(t, legs: legs, windows: windows) == scheduler.schedule(t, legs: legs))
        #expect(scheduler.suggestOrdering(t, legs: legs, windows: windows) == scheduler.suggestOrdering(t, legs: legs))
        #expect(scheduler.legPairsNeeded(for: t, windows: windows) == scheduler.legPairsNeeded(for: t))
    }
}

@Suite struct SchedulerEdges {
    @Test func emptyTripsAndEmptyDaysNeedNothing() {
        let empty = trip([], days: 3)
        #expect(scheduler.schedule(empty, legs: [:]).stops.isEmpty)
        #expect(scheduler.suggestOrdering(empty, legs: [:]).isEmpty)
        #expect(scheduler.legPairsNeeded(for: empty).isEmpty)
        // An empty middle day: the drive is from the last stop before it, over the empty day, to the next one.
        let a = stop("a", day: 0, .goldenEvening)
        let c = stop("c", day: 2, .goldenMorning)
        let t = trip([a, c], days: 3)
        #expect(scheduler.legPairsNeeded(for: t) == [LegKey(a.id, c.id)])
        #expect(scheduler.schedule(t, legs: [:]).schedule(for: c.id)?.legFromPrevious != nil)
    }

    @Test func singleStopDaysHaveNothingToReorder() {
        let t = trip([stop("a", day: 0, .goldenEvening), stop("b", day: 1, .goldenMorning)])
        #expect(scheduler.suggestOrdering(t, legs: [:]).isEmpty)
        #expect(scheduler.legPairsNeeded(for: t).count == 1)
    }

    @Test func aStopAfterAPolarNightStopHasNoDriveToFit() {
        // Polar night on day 0 only: its session has no window, so the next day's stop has nothing to be free after.
        var eph = FixedEphemeris()
        eph.sun = { d in
            d == testDay ? SunEvents(day: d, kind: .polarNight, solarNoon: FixedEphemeris.at(d, 12)) : FixedEphemeris.standardDay(d)
        }
        let sch = TripScheduler(engine: LightEngine(ephemeris: eph))
        let a = stop("a", day: 0, .goldenMorning)
        let b = stop("b", day: 1, .goldenMorning)
        let s = sch.schedule(trip([a, b]), legs: [leg(a, b, minutes: 600)].reduce(into: [:]) { $0[$1.0] = $1.1 })
        #expect(s.schedule(for: a.id)?.issues == [.windowMissing])
        #expect(s.schedule(for: b.id)?.issues.isEmpty == true)
        #expect(s.schedule(for: b.id)?.leaveBy != nil)
    }

    @Test func stopsWithoutAWindowSortLastInALightFirstOrder() {
        var eph = FixedEphemeris()
        eph.sun = { d in
            d == testDay ? SunEvents(day: d, kind: .polarNight, solarNoon: FixedEphemeris.at(d, 12)) : FixedEphemeris.standardDay(d)
        }
        let sch = TripScheduler(engine: LightEngine(ephemeris: eph))
        let dark = stop("dark", day: 0, .goldenMorning)
        let evening = stop("evening", day: 0, .goldenEvening)
        // Both have no window on a polar-night day, so their order is kept (stable) and nothing is suggested.
        #expect(sch.suggestOrdering(trip([dark, evening], days: 1), legs: [:]).isEmpty)
    }
}
