import Foundation
import Testing
import IterModel
@testable import IterPlan

// The first 23 tests are the old SchedulerTests ported onto Trip / Stop / Leg and supplied windows.

@Suite struct Schedule {
    @Test func leaveByArithmetic() {
        // Sunrise at 06:12 (golden morning start), buffer 20, walk 12, drive 75 -> leave 04:25.
        let a = stop("a", day: 0, .night)
        let b = stop("b", day: 1, .goldenMorning, walk: 12)
        let t = makeTrip([a, b])
        let s = schedule(t, legs: legs(leg(a, b, minutes: 75)))
        let sb = s.schedule(for: b.id)!
        let day1 = testDay.adding(days: 1)
        #expect(sb.window?.start == StandardDay.at(day1, 6.2))
        #expect(sb.setUpBy == StandardDay.at(day1, 6.2).addingTimeInterval(-20 * 60))
        #expect(sb.arriveBy == sb.setUpBy!.addingTimeInterval(-12 * 60))
        #expect(sb.leaveBy == StandardDay.at(day1, 4.0 + 25.0 / 60))
        #expect(sb.walkInKnown)
        #expect(sb.issues.isEmpty)
        #expect(sb.legFromPrevious?.seconds == 4500)
        // The first stop has no drive (no start place).
        #expect(s.schedule(for: a.id)!.leaveBy == nil)
        #expect(s.issueCount == 0)
    }

    @Test func unknownWalkIn() {
        let a = stop("a", day: 0, .goldenEvening, walk: nil)
        let s = schedule(makeTrip([a])).schedule(for: a.id)!
        #expect(!s.walkInKnown)
        #expect(s.arriveBy == s.setUpBy)
        #expect(s.setUpBy != nil)
    }

    @Test func driveThatDoesNotFit() {
        // Golden evening ends 18:20. Blue evening starts 18:20; set up 18:00, walk 0, drive 30 min -> leave 17:30.
        let a = stop("a", day: 0, .goldenEvening)
        let b = stop("b", day: 0, .blueEvening, walk: 0)
        let sb = schedule(makeTrip([a, b]), legs: legs(leg(a, b, minutes: 30))).schedule(for: b.id)!
        let freeAt = StandardDay.at(testDay, 18.333)
        #expect(sb.leaveBy == freeAt.addingTimeInterval(-20 * 60 - 30 * 60))
        #expect(sb.issues == [.driveDoesNotFit(shortBySeconds: 50 * 60)])
    }

    @Test func outOfOrder() {
        let a = stop("a", day: 0, .night)
        let b = stop("b", day: 0, .goldenMorning)
        let s = schedule(makeTrip([a, b]), legs: legs(leg(a, b, minutes: 30)))
        let sb = s.schedule(for: b.id)!
        #expect(sb.issues.contains(.outOfOrder))
        #expect(sb.issues.contains { if case .driveDoesNotFit = $0 { true } else { false } })
        #expect(s.schedule(for: a.id)!.issues.isEmpty)
    }

    @Test func crossDayDriveIsChecked() {
        let a = stop("a", day: 0, .night)                    // free at 23:10
        let b = stop("b", day: 1, .goldenMorning, walk: 0)   // arrive by 05:52
        let fits = schedule(makeTrip([a, b]), legs: legs(leg(a, b, minutes: 300)))
        #expect(fits.schedule(for: b.id)!.issues.isEmpty)
        let long = schedule(makeTrip([a, b]), legs: legs(leg(a, b, minutes: 7 * 60)))
        let sb = long.schedule(for: b.id)!
        let freeAt = StandardDay.at(testDay, 20.167).addingTimeInterval(3 * 3600)
        let expected = freeAt.timeIntervalSince(sb.leaveBy!)
        #expect(expected > 0)
        #expect(sb.issues == [.driveDoesNotFit(shortBySeconds: expected)])
        #expect(sb.leaveBy! < freeAt)
    }

    @Test func missingLegIsEstimated() {
        let a = stop("a", day: 0, .goldenMorning, lat: 40, lon: -110)
        let b = stop("b", day: 0, .goldenEvening, lat: 40.2, lon: -110)
        let t = makeTrip([a, b])
        let s = schedule(t).schedule(for: b.id)!
        #expect(s.issues == [.driveEstimated])
        #expect(s.legFromPrevious?.isEstimate == true)
        #expect(s.leaveBy != nil)
        // An estimated issue does not count as a conflict.
        #expect(schedule(t).issueCount == 0)
    }

    @Test func missingWindow() {
        let a = stop("a", day: 0, .goldenEvening)
        let t = makeTrip([a])
        let s = schedule(t, windows: [:]).schedule(for: a.id)!
        #expect(s.window == nil && s.setUpBy == nil && s.arriveBy == nil && s.leaveBy == nil)
        #expect(s.issues == [.windowMissing])
    }

    @Test func tripOrderIsDayMajor() {
        let a = stop("a", day: 1, .goldenMorning)
        let b = stop("b", day: 0, .goldenEvening)
        let s = schedule(makeTrip([a, b]))
        #expect(s.stops.map(\.stopID) == [b.id, a.id])
    }
}

@Suite struct Ordering {
    @Test func sunsetBeforeSunriseGetsASuggestion() {
        let sunset = stop("sunset", day: 0, .goldenEvening, lat: 40, lon: -110)
        let sunrise = stop("sunrise", day: 0, .goldenMorning, lat: 40.3, lon: -110)
        let t = makeTrip([sunset, sunrise], days: 1)
        let l = legs(leg(sunset, sunrise, minutes: 40), leg(sunrise, sunset, minutes: 40))
        let w = standardWindows(t)
        let suggestions = scheduler.suggestOrdering(trip: t, start: nil, windows: w, legs: l)
        #expect(suggestions.count == 1)
        let s = suggestions[0]
        #expect(s.dayIndex == 0)
        #expect(s.order == [sunrise.id, sunset.id])
        #expect(s.issuesBefore > s.issuesAfter)
        #expect(s.issuesAfter == 0)
        // Estimates work when legs are missing.
        #expect(scheduler.suggestOrdering(trip: t, start: nil, windows: w, legs: [:]).count == 1)
        // The trip itself is untouched.
        #expect(t.stops.map(\.id) == [sunset.id, sunrise.id])
    }

    @Test func alreadyGoodDayGetsNone() {
        let sunrise = stop("sunrise", day: 0, .goldenMorning)
        let sunset = stop("sunset", day: 0, .goldenEvening, lat: 40.3)
        func suggest(_ t: Trip) -> [OrderingSuggestion] { scheduler.suggestOrdering(trip: t, start: nil, windows: standardWindows(t), legs: [:]) }
        #expect(suggest(makeTrip([sunrise, sunset], days: 1)).isEmpty)
        #expect(suggest(makeTrip([sunrise], days: 1)).isEmpty)
        #expect(suggest(makeTrip([], days: 1)).isEmpty)
    }

    @Test func otherDaysAreNotRearranged() {
        let a = stop("a", day: 0, .goldenMorning)
        let b = stop("b", day: 1, .goldenEvening)
        let c = stop("c", day: 1, .goldenMorning, lat: 40.2)
        let t = makeTrip([a, b, c])
        let suggestions = scheduler.suggestOrdering(trip: t, start: nil, windows: standardWindows(t), legs: [:])
        #expect(suggestions.map(\.dayIndex) == [1])
        #expect(suggestions[0].order == [c.id, b.id])
    }

    @Test func legPairsCoverCurrentAndSuggested() {
        let sunset = stop("sunset", day: 0, .goldenEvening)
        let sunrise = stop("sunrise", day: 0, .goldenMorning, lat: 40.3)
        let bad = makeTrip([sunset, sunrise], days: 1)
        #expect(scheduler.legPairsNeeded(for: bad, start: nil, windows: standardWindows(bad))
                == [LegKey(sunset.id, sunrise.id), LegKey(sunrise.id, sunset.id)])
        let good = makeTrip([sunrise, sunset], days: 1)
        #expect(scheduler.legPairsNeeded(for: good, start: nil, windows: standardWindows(good)) == [LegKey(sunrise.id, sunset.id)])
    }

    @Test func legKeyCodable() throws {
        let k = LegKey(UUID(), UUID())
        let data = try JSONEncoder().encode(k)
        #expect(try JSONDecoder().decode(LegKey.self, from: data) == k)
    }
}

@Suite struct SchedulerEdges {
    @Test func emptyTripsAndEmptyDaysNeedNothing() {
        let empty = makeTrip([], days: 3)
        #expect(schedule(empty).stops.isEmpty)
        #expect(scheduler.suggestOrdering(trip: empty, start: nil, windows: [:], legs: [:]).isEmpty)
        #expect(scheduler.legPairsNeeded(for: empty, start: nil, windows: [:]).isEmpty)
        // An empty middle day: the drive is from the last stop before it, over the empty day, to the next one.
        let a = stop("a", day: 0, .goldenEvening)
        let c = stop("c", day: 2, .goldenMorning)
        let t = makeTrip([a, c], days: 3)
        #expect(scheduler.legPairsNeeded(for: t, start: nil, windows: standardWindows(t)) == [LegKey(a.id, c.id)])
        #expect(schedule(t).schedule(for: c.id)?.legFromPrevious != nil)
    }

    @Test func singleStopDaysHaveNothingToReorder() {
        let t = makeTrip([stop("a", day: 0, .goldenEvening), stop("b", day: 1, .goldenMorning)])
        #expect(scheduler.suggestOrdering(trip: t, start: nil, windows: standardWindows(t), legs: [:]).isEmpty)
        #expect(scheduler.legPairsNeeded(for: t, start: nil, windows: standardWindows(t)).count == 1)
    }

    @Test func aStopAfterAPolarNightStopHasNoDriveToFit() {
        // No window for `a` (polar night on day 0 only): the next day's stop has nothing to be free after.
        let a = stop("a", day: 0, .goldenMorning)
        let b = stop("b", day: 1, .goldenMorning)
        let t = makeTrip([a, b])
        let s = schedule(t, windows: standardWindows(t, omit: [a.id]), legs: legs(leg(a, b, minutes: 600)))
        #expect(s.schedule(for: a.id)?.issues == [.windowMissing])
        #expect(s.schedule(for: b.id)?.issues.isEmpty == true)
        #expect(s.schedule(for: b.id)?.leaveBy != nil)
    }

    @Test func stopsWithoutAWindowSortLastInALightFirstOrder() {
        let dark = stop("dark", day: 0, .goldenMorning)
        let evening = stop("evening", day: 0, .goldenEvening)
        let t = makeTrip([dark, evening], days: 1)
        // Neither has a window, so their order is kept (stable) and nothing is suggested.
        #expect(scheduler.suggestOrdering(trip: t, start: nil, windows: [:], legs: [:]).isEmpty)
    }
}

@Suite struct TransferTimingSchedule {
    @Test func eveningBeforeLeavesWhenThePreviousSessionEnds() {
        let a = stop("a", day: 0, .goldenEvening)
        let b = stop("b", day: 1, .goldenMorning, walk: 0)
        let s = schedule(makeTrip([a, b], timings: [1: .eveningBefore]), legs: legs(leg(a, b, minutes: 5 * 60)))
        let sa = s.schedule(for: a.id)!, sb = s.schedule(for: b.id)!
        #expect(sb.leaveBy == sa.window!.end)
        #expect(sb.transferTiming == .eveningBefore)
        #expect(sb.issues.isEmpty)
        #expect(sa.transferTiming == nil)
    }

    @Test func eveningBeforeDoesNotFitWhenTheDriveIsLongerThanTheGap() {
        let a = stop("a", day: 0, .goldenEvening)
        let b = stop("b", day: 1, .goldenMorning, walk: 0)
        let s = schedule(makeTrip([a, b], timings: [1: .eveningBefore]), legs: legs(leg(a, b, minutes: 13 * 60)))
        let sa = s.schedule(for: a.id)!, sb = s.schedule(for: b.id)!
        let short = sa.window!.end.addingTimeInterval(13 * 3600).timeIntervalSince(sb.arriveBy!)
        #expect(short > 0)
        #expect(sb.issues == [.driveDoesNotFit(shortBySeconds: short)])
        #expect(sb.leaveBy == sa.window!.end)
    }

    @Test func eveningBeforeWithAMissingPreviousWindowHasNoLeaveBy() {
        let a = stop("a", day: 0, .goldenEvening)
        let b = stop("b", day: 1, .goldenMorning, walk: 0)
        let t = makeTrip([a, b], timings: [1: .eveningBefore])
        let sb = schedule(t, windows: standardWindows(t, omit: [a.id]), legs: legs(leg(a, b, minutes: 60))).schedule(for: b.id)!
        #expect(sb.leaveBy == nil)
        #expect(!sb.issues.contains { if case .driveDoesNotFit = $0 { true } else { false } })
    }

    @Test func morningIsTheDefaultAndSameDayDrivesIgnoreTheTiming() {
        let a = stop("a", day: 0, .goldenMorning)
        let b = stop("b", day: 0, .goldenEvening, walk: 0)
        let c = stop("c", day: 1, .goldenMorning, walk: 0)
        let l = legs(leg(a, b, minutes: 20), leg(b, c, minutes: 60))
        let morning = schedule(makeTrip([a, b, c]), legs: l)
        let explicit = schedule(makeTrip([a, b, c], timings: [1: .morning]), legs: l)
        #expect(morning == explicit)
        let sc = morning.schedule(for: c.id)!
        #expect(sc.leaveBy == sc.arriveBy!.addingTimeInterval(-3600))
        #expect(sc.transferTiming == .morning)
        #expect(morning.schedule(for: b.id)!.transferTiming == nil)
        // A timing keyed to day 0 is harmless.
        #expect(makeTrip([a], timings: [0: .eveningBefore]).transferTiming(intoDay: 0) == .morning)
        let evening = schedule(makeTrip([a, b, c], timings: [1: .eveningBefore]), legs: l)
        #expect(evening.schedule(for: b.id) == morning.schedule(for: b.id))
    }

    @Test func orderingSuggestionsStayConsistentWithTheTiming() {
        let a = stop("a", day: 0, .goldenEvening)
        let b = stop("b", day: 1, .goldenMorning, walk: 0)
        let t = makeTrip([a, b], timings: [1: .eveningBefore])
        let l = legs(leg(a, b, minutes: 13 * 60))
        let w = standardWindows(t)
        #expect(schedule(t, legs: l).issueCount == 1)
        #expect(scheduler.suggestOrdering(trip: t, start: nil, windows: w, legs: l).isEmpty)
        #expect(scheduler.legPairsNeeded(for: t, start: nil, windows: w) == [LegKey(a.id, b.id)])
    }
}
