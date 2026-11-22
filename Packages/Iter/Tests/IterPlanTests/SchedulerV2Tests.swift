import Foundation
import Testing
import IterModel
@testable import IterPlan

@Suite struct StartPlace {
    @Test func firstStopLeavesFromTheStartPlaceWithASuppliedLeg() {
        let home = makePlace("home", lat: 39.5, lon: -110)
        let a = stop("a", day: 0, .goldenMorning, walk: 12)
        let t = makeTrip([a], start: home)
        let s = schedule(t, start: home, legs: legs(startLeg(home, a, minutes: 50))).schedule(for: a.id)!
        #expect(s.fromStart)
        #expect(s.legFromPrevious?.seconds == 3000)
        #expect(s.leaveBy == s.arriveBy!.addingTimeInterval(-3000))
        #expect(s.issues.isEmpty)
    }

    @Test func aMissingStartLegIsEstimatedAndSaysSo() {
        let home = makePlace("home", lat: 39.5, lon: -110)
        let a = stop("a", day: 0, .goldenMorning)
        let s = schedule(makeTrip([a], start: home), start: home).schedule(for: a.id)!
        #expect(s.fromStart)
        #expect(s.issues == [.driveEstimated])
        let estimate = Leg.estimate(from: home.coordinate, to: a.place.coordinate)
        #expect(s.legFromPrevious == estimate)
        #expect(s.leaveBy == s.arriveBy!.addingTimeInterval(-estimate.seconds))
    }

    @Test func noStartPlaceMeansNoLeaveByOnTheFirstStop() {
        let a = stop("a", day: 0, .goldenMorning)
        let s = schedule(makeTrip([a])).schedule(for: a.id)!
        #expect(!s.fromStart && s.leaveBy == nil && s.legFromPrevious == nil)
    }

    @Test func onlyTheTripsFirstStopComesFromTheStart() {
        let home = makePlace("home")
        let a = stop("a", day: 0, .goldenMorning)
        let b = stop("b", day: 0, .goldenEvening, lat: 40.1)
        let s = schedule(makeTrip([a, b], start: home), start: home)
        #expect(s.schedule(for: a.id)!.fromStart)
        #expect(!s.schedule(for: b.id)!.fromStart)
    }

    @Test func legPairsIncludeTheStartPair() {
        let home = makePlace("home")
        let sunset = stop("sunset", day: 0, .goldenEvening)
        let sunrise = stop("sunrise", day: 0, .goldenMorning, lat: 40.3)
        let t = makeTrip([sunset, sunrise], days: 1, start: home)
        let pairs = scheduler.legPairsNeeded(for: t, start: home, windows: standardWindows(t))
        #expect(pairs == [LegKey(home.id, sunset.id), LegKey(sunset.id, sunrise.id), LegKey(home.id, sunrise.id), LegKey(sunrise.id, sunset.id)])
    }
}

@Suite struct Dwell {
    @Test func aLightStopWithDwellFreesYouAtStartPlusDwell() {
        let a = stop("a", day: 0, .goldenEvening, dwell: 30)
        let s = schedule(makeTrip([a])).schedule(for: a.id)!
        #expect(s.departAt == s.window!.start.addingTimeInterval(30 * 60))
        let until = stop("u", day: 0, .goldenEvening)
        let u = schedule(makeTrip([until])).schedule(for: until.id)!
        #expect(u.departAt == u.window!.end)
    }

    @Test func dwellChangesWhetherTheNextDriveFits() {
        // b is set up for 18:20 with no buffer and no walk; a 15 minute drive means leaving by 18:05.
        let shortStay = stop("a", day: 0, .goldenEvening, dwell: 30)   // free at 18:00
        let b = stop("b", day: 0, .blueEvening, walk: 0, buffer: 0)
        let fits = schedule(makeTrip([shortStay, b]), legs: legs(leg(shortStay, b, minutes: 15))).schedule(for: b.id)!
        #expect(fits.issues.isEmpty)
        #expect(fits.leaveBy == StandardDay.at(testDay, 18.333).addingTimeInterval(-15 * 60))

        let untilEnd = stop("a", day: 0, .goldenEvening)               // free at 18:20
        let doesNotFit = schedule(makeTrip([untilEnd, b]), legs: legs(leg(untilEnd, b, minutes: 15))).schedule(for: b.id)!
        #expect(doesNotFit.issues == [.driveDoesNotFit(shortBySeconds: 15 * 60)])
    }
}

@Suite struct LodgingAndWaypoints {
    @Test func aLodgingHasNoWindowIssueAndIsOvernight() {
        let a = stop("a", day: 0, .goldenEvening)
        let hotel = stop("hotel", day: 0, .goldenEvening, lat: 40.2, kind: .lodging)
        let b = stop("b", day: 1, .goldenMorning, lat: 40.4, walk: 0)
        let t = makeTrip([a, hotel, b])
        let s = schedule(t, legs: legs(leg(a, hotel, minutes: 20), leg(hotel, b, minutes: 45)))
        let sh = s.schedule(for: hotel.id)!
        #expect(sh.kind == .lodging)
        #expect(sh.window == nil && sh.setUpBy == nil)
        #expect(!sh.issues.contains(.windowMissing))
        // Estimated arrival: free of the previous stop at its window end, plus the drive. Not a constraint.
        #expect(sh.leaveBy == s.schedule(for: a.id)!.departAt)
        #expect(sh.arriveBy == s.schedule(for: a.id)!.departAt!.addingTimeInterval(20 * 60))
        #expect(sh.departAt == nil)
        // The next morning's first stop leaves from the hotel, with no fit check against the sleeping stop.
        let sb = s.schedule(for: b.id)!
        let driveSeconds: TimeInterval = 45 * 60
        #expect(sb.legFromPrevious?.seconds == driveSeconds)
        #expect(sb.leaveBy == sb.arriveBy!.addingTimeInterval(-45 * 60))
        #expect(sb.issues.isEmpty)
        #expect(s.issueCount == 0)
    }

    @Test func aLodgingWithDwellFreesYouAfterIt() {
        let hotel = stop("hotel", day: 0, .goldenEvening, kind: .lodging, dwell: 90, fixed: "15:00")
        let s = schedule(makeTrip([hotel])).schedule(for: hotel.id)!
        #expect(s.arriveBy == StandardDay.at(testDay, 15))
        #expect(s.departAt == StandardDay.at(testDay, 16.5))
    }

    @Test func aLodgingAfterAnEveningBeforeTransferUsesTheMorningRule() {
        let hotel = stop("hotel", day: 0, .goldenEvening, kind: .lodging)
        let b = stop("b", day: 1, .goldenMorning, walk: 0)
        let s = schedule(makeTrip([hotel, b], timings: [1: .eveningBefore]), legs: legs(leg(hotel, b, minutes: 60))).schedule(for: b.id)!
        #expect(s.transferTiming == .eveningBefore)
        #expect(s.leaveBy == s.arriveBy!.addingTimeInterval(-3600))
        #expect(s.issues.isEmpty)
    }

    @Test func aWaypointWithAFixedArrivalIsAConstraint() {
        let a = stop("a", day: 0, .goldenEvening, walk: 0)
        let lunch = stop("lunch", day: 1, .goldenMorning, lat: 40.5, kind: .waypoint, dwell: 45, fixed: "12:30")
        let s = schedule(makeTrip([a, lunch]), legs: legs(leg(a, lunch, minutes: 240)))
        let sl = s.schedule(for: lunch.id)!
        let noon = StandardDay.at(testDay.adding(days: 1), 12.5)
        #expect(sl.window == nil && !sl.issues.contains(.windowMissing))
        #expect(sl.arriveBy == noon)
        #expect(sl.leaveBy == noon.addingTimeInterval(-240 * 60))
        #expect(sl.departAt == noon.addingTimeInterval(45 * 60))
        #expect(sl.issues.isEmpty)
    }

    @Test func aWaypointWithoutAFixedTimeFollowsThePreviousStop() {
        let a = stop("a", day: 0, .goldenMorning)
        let w = stop("w", day: 0, .goldenMorning, lat: 40.1, kind: .waypoint, dwell: 10)
        let s = schedule(makeTrip([a, w]), legs: legs(leg(a, w, minutes: 30))).schedule(for: w.id)!
        let free = StandardDay.window(.goldenMorning, on: testDay).end
        #expect(s.leaveBy == free)
        #expect(s.arriveBy == free.addingTimeInterval(30 * 60))
        #expect(s.departAt == free.addingTimeInterval(40 * 60))
        // A waypoint with dwell 0 passes straight through.
        let pass = stop("p", day: 0, .goldenMorning, kind: .waypoint)
        let sp = schedule(makeTrip([a, pass]), legs: legs(leg(a, pass, minutes: 30))).schedule(for: pass.id)!
        #expect(sp.departAt == sp.arriveBy)
    }

    @Test func aFixedArrivalOnALightStopOverridesArriveBy() {
        let a = stop("a", day: 0, .goldenMorning, fixed: "05:30")
        let s = schedule(makeTrip([a])).schedule(for: a.id)!
        #expect(s.arriveBy == StandardDay.at(testDay, 5.5))
        #expect(s.setUpBy == s.window!.start.addingTimeInterval(-20 * 60))
    }

    @Test func aFixedArrivalThatCannotBeReachedDoesNotFit() {
        let a = stop("a", day: 0, .goldenEvening)
        let lunch = stop("lunch", day: 0, .goldenEvening, kind: .waypoint, fixed: "18:00")
        // Free at 18:20, the drive is 30 minutes, due 18:00: leave by 17:30, 50 minutes short.
        let sl = schedule(makeTrip([a, lunch]), legs: legs(leg(a, lunch, minutes: 30))).schedule(for: lunch.id)!
        #expect(sl.issues.count == 1)
        if case .driveDoesNotFit(let short) = sl.issues[0] { #expect(abs(short - 50 * 60) < 2) } else { Issue.record("expected driveDoesNotFit") }
    }

    @Test func lightFirstOrderingUsesFixedTimes() {
        let sunset = stop("sunset", day: 0, .goldenEvening)
        let coffee = stop("coffee", day: 0, .goldenEvening, lat: 40.05, kind: .waypoint, fixed: "05:00")
        let rest = stop("rest", day: 0, .goldenEvening, lat: 40.1, kind: .waypoint)
        let sunrise = stop("sunrise", day: 0, .goldenMorning, lat: 40.2)
        let t = makeTrip([sunset, rest, sunrise, coffee], days: 1)
        let suggestions = scheduler.suggestOrdering(trip: t, start: nil, windows: standardWindows(t), legs: [:])
        #expect(suggestions.count == 1)
        // Fixed 05:00, sunrise window 06:12, sunset window 17:30, then the stop with no time, last.
        #expect(suggestions[0].order == [coffee.id, sunrise.id, sunset.id, rest.id])
    }
}

@Suite struct FixedTimesAndZones {
    @Test func aFixedTimeInASpringForwardGapResolvesToTheNextValidInstant() {
        // Clocks in Denver jump from 02:00 to 03:00 on 2027-03-14: 02:30 does not exist.
        let gapDay = LocalDay(year: 2027, month: 3, day: 14)
        let resolved = Scheduler.fixedInstant(LocalTime(hour: 2, minute: 30), day: gapDay, in: denver)
        #expect(resolved == gapDay.at(hour: 3, minute: 0, in: denver))
        #expect(resolved.timeIntervalSince(gapDay.start(in: denver)) == 2 * 3600)   // only two real hours since midnight
        // Either side of the gap is untouched.
        #expect(Scheduler.fixedInstant(LocalTime(hour: 1, minute: 59), day: gapDay, in: denver) == gapDay.at(hour: 1, minute: 59, in: denver))
        #expect(Scheduler.fixedInstant(LocalTime(hour: 3, minute: 0), day: gapDay, in: denver) == resolved)
        // The next day is an ordinary 24 h later.
        let after = Scheduler.fixedInstant(LocalTime(hour: 2, minute: 30), day: gapDay.adding(days: 1), in: denver)
        #expect(after == gapDay.adding(days: 1).at(hour: 2, minute: 30, in: denver))
    }

    @Test func aFallBackTimeResolvesToItsFirstOccurrence() {
        let fallDay = LocalDay(year: 2026, month: 11, day: 1)   // 01:00-02:00 happens twice in Denver
        let t = Scheduler.fixedInstant(LocalTime(hour: 1, minute: 30), day: fallDay, in: denver)
        #expect(t.timeIntervalSince(fallDay.start(in: denver)) == 1.5 * 3600)
    }

    @Test func aScheduledStopInTheGapUsesTheResolvedInstant() {
        let gapDay = LocalDay(year: 2027, month: 3, day: 14)
        var stop = stop("w", day: 0, .goldenMorning, kind: .waypoint, dwell: 60, fixed: "02:30", zone: "America/Denver")
        stop.place.timeZoneIdentifier = "America/Denver"
        let t = Trip(name: "gap", startDay: gapDay, dayCount: 1, stops: [stop])
        let s = scheduler.schedule(trip: t, start: nil, windows: [:], legs: [:]).schedule(for: stop.id)!
        #expect(s.arriveBy == gapDay.at(hour: 3, minute: 0, in: denver))
        #expect(s.departAt == gapDay.at(hour: 4, minute: 0, in: denver))
    }

    @Test func fixedTimesAreReadInEachStopsOwnZoneOnOneDay() {
        let east = stop("east", day: 0, .goldenMorning, kind: .waypoint, fixed: "09:00", zone: "America/New_York")
        let west = stop("west", day: 0, .goldenMorning, lat: 39, lon: -105, kind: .waypoint, fixed: "09:00", zone: "America/Denver")
        let t = makeTrip([east, west], days: 1)
        let s = scheduler.schedule(trip: t, start: nil, windows: [:], legs: legs(leg(east, west, minutes: 10)))
        let e = s.schedule(for: east.id)!, w = s.schedule(for: west.id)!
        #expect(e.arriveBy == testDay.at(hour: 9, in: newYork))
        #expect(w.arriveBy == testDay.at(hour: 9, in: denver))
        // 09:00 in Denver is two hours after 09:00 in New York, so the Denver stop is bound later, and its drive fits.
        #expect(w.arriveBy!.timeIntervalSince(e.arriveBy!) == 2 * 3600)
        #expect(w.issues.isEmpty)
    }

    @Test func aStopInTheEarlierZoneAfterOneInTheLaterZoneChecksRealElapsedTime() {
        // Denver 09:00 then New York 09:00: New York is bound two hours EARLIER in real time, so it cannot fit.
        let west = stop("west", day: 0, .goldenMorning, lat: 39, lon: -105, kind: .waypoint, dwell: 5, fixed: "09:00", zone: "America/Denver")
        let east = stop("east", day: 0, .goldenMorning, kind: .waypoint, fixed: "09:00", zone: "America/New_York")
        let t = makeTrip([west, east], days: 1)
        let sEast = scheduler.schedule(trip: t, start: nil, windows: [:], legs: legs(leg(west, east, minutes: 10))).schedule(for: east.id)!
        #expect(sEast.shortBySeconds != nil)
        let expectedShort: TimeInterval = 2 * 3600 + 5 * 60 + 10 * 60
        #expect(abs(sEast.shortBySeconds! - expectedShort) < 1)
    }
}

@Suite struct ScheduleProperties {
    private func drives(seed: UInt64, count: Int) -> [Double] {
        var rng = SeededRNG(seed: seed)
        return (0..<count).map { _ in Double.random(in: 1...900, using: &rng) * 60 }.sorted()
    }

    private func leg(seconds: Double, a: Stop, b: Stop) -> [LegKey: Leg] {
        [LegKey(a.id, b.id): Leg(from: a.place.coordinate, to: b.place.coordinate, seconds: seconds, meters: 1, isEstimate: false)]
    }

    @Test func leaveByNeverGetsLaterAndShortByNeverShrinksAsTheDriveGrows() {
        for (timing, sameDay) in [(TransferTiming.morning, true), (.morning, false), (.eveningBefore, false)] {
            for seed in [1, 2, 3] as [UInt64] {
                let a = stop("a", day: 0, .goldenEvening)
                let b = stop("b", day: sameDay ? 0 : 1, sameDay ? .blueEvening : .goldenMorning, walk: 0)
                let t = makeTrip([a, b], timings: [1: timing])
                var lastLeave: Date?
                var lastShort: TimeInterval = 0
                for seconds in drives(seed: seed, count: 200) {
                    let sb = schedule(t, legs: leg(seconds: seconds, a: a, b: b)).schedule(for: b.id)!
                    if timing == .eveningBefore && !sameDay {
                        // The evening drive leaves when the previous stop frees you, whatever the drive.
                        #expect(sb.leaveBy == StandardDay.window(.goldenEvening, on: testDay).end)
                    } else if let lastLeave {
                        #expect(sb.leaveBy! <= lastLeave)
                    }
                    let short = sb.shortBySeconds ?? 0
                    #expect(short >= lastShort)
                    lastLeave = sb.leaveBy
                    lastShort = short
                }
            }
        }
    }

    @Test func aStartPlacesLeaveByNeverGetsLaterAsTheDriveGrows() {
        let home = makePlace("home")
        let a = stop("a", day: 0, .goldenMorning)
        let t = makeTrip([a], start: home)
        var last: Date?
        for seconds in drives(seed: 9, count: 200) {
            let l = [LegKey(home.id, a.id): Leg(from: home.coordinate, to: a.place.coordinate, seconds: seconds, meters: 1, isEstimate: false)]
            let s = schedule(t, start: home, legs: l).schedule(for: a.id)!
            if let last { #expect(s.leaveBy! <= last) }
            last = s.leaveBy
        }
    }
}
