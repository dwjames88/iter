import Foundation
import Testing
import IterModel
@testable import IterPlan

/// One day: a start place, three light stops (sunrise, sunset, night) and a hotel.
private struct Day {
    var home = makePlace("home", lat: 40, lon: -110.5)
    var s1 = stop("Arch", day: 0, .goldenMorning, lat: 40, lon: -110)          // window 06:12-07:00, set up 05:52, arrive 05:42
    var s2 = stop("Mesa", day: 0, .goldenEvening, lat: 40.5, lon: -110)        // window 17:30-18:20, arrive 17:00
    var s3 = stop("Dark", day: 0, .night, lat: 40.5, lon: -109.5)              // window 20:10-23:10, arrive 19:40
    var hotel = stop("Hotel", day: 0, .goldenEvening, lat: 40.5, lon: -109.5, kind: .lodging)
    var trip: Trip
    var windows: SessionWindows
    var planned: [LegKey: Leg]

    init() {
        trip = makeTrip([s1, s2, s3, hotel], days: 1, start: home)
        windows = standardWindows(trip)
        planned = legs(startLeg(home, s1, minutes: 60), leg(s1, s2, minutes: 90), leg(s2, s3, minutes: 20), leg(s3, hotel, minutes: 15))
    }

    func live(now: Date, origin: Coordinate? = nil, etas: [UUID: ETA] = [:], progress: TripProgress = TripProgress()) -> LiveSchedule {
        LiveSchedule.make(trip: trip, start: home, windows: windows, plannedLegs: planned, progress: progress, now: now, origin: origin, liveETAs: etas)
    }

    func alarms(_ live: LiveSchedule, now: Date) -> [PlannedAlarm] { AlarmPlan.make(live: live, trip: trip, now: now) }
}

private func at(_ hour: Double) -> Date { StandardDay.at(testDay, hour) }
private func minutes(_ m: Double) -> TimeInterval { m * 60 }
private func eta(_ m: Double, from now: Date) -> ETA { ETA(seconds: m * 60, arrival: now.addingTimeInterval(m * 60), departing: now) }

@Suite struct LiveScheduleTests {
    @Test func marginIsFiveMinutesPlusTenPercent() {
        #expect(LiveSchedule.safetyMargin(forDriveSeconds: 3600) == 660)
        #expect(LiveSchedule.safetyMargin(forDriveSeconds: 0) == 300)
    }

    @Test func nextStopLeaveByUsesTheLiveETAAndTheMargin() {
        let d = Day()
        let now = at(3.5)
        let live = d.live(now: now, origin: d.home.coordinate, etas: [d.s1.id: eta(60, from: now)])
        let next = live.next!
        #expect(next.stopID == d.s1.id)
        #expect(next.etaSource == .live)
        #expect(next.driveSeconds == 3600)
        #expect(next.safetyMargin == 660)
        #expect(next.arriveBy == at(6.2).addingTimeInterval(-minutes(30)))            // 20 min buffer + 10 min walk
        #expect(next.leaveBy == next.arriveBy!.addingTimeInterval(-3600 - 660))
        guard case .early = next.status else { Issue.record("expected early, got \(next.status)"); return }
        #expect(live.remaining.map(\.stopID) == [d.s2.id, d.s3.id, d.hotel.id])
        #expect(!live.finished)
    }

    @Test func statusMovesFromEarlyToLeaveSoonToLeaveNow() {
        let d = Day()
        let leaveBy = at(6.2).addingTimeInterval(-minutes(30) - 3600 - 660)    // 04:31 for a 60 minute drive
        func status(_ now: Date) -> LiveStatus {
            d.live(now: now, origin: d.home.coordinate, etas: [d.s1.id: eta(60, from: now)]).next!.status
        }
        #expect(status(leaveBy.addingTimeInterval(-minutes(16))) == .early(untilLeaveBy: minutes(16)))
        #expect(status(leaveBy.addingTimeInterval(-minutes(15))) == .leaveSoon(untilLeaveBy: minutes(15)))
        #expect(status(leaveBy.addingTimeInterval(-minutes(1))) == .leaveSoon(untilLeaveBy: minutes(1)))
        #expect(status(leaveBy) == .leaveNow)
        #expect(status(leaveBy.addingTimeInterval(minutes(2))) == .leaveNow)
    }

    @Test func lateIsMeasuredAgainstArriveByAndSetUpBy() {
        let d = Day()
        let now = at(5.0)     // 60 minute drive: arrive 06:00; arriveBy 05:42, setUpBy 05:52
        let next = d.live(now: now, origin: d.home.coordinate, etas: [d.s1.id: eta(60, from: now)]).next!
        #expect(next.status == .late(by: minutes(18), arrivesAfterSetUpBy: minutes(8)))
        #expect(next.projectedArrival == at(6.0))
        // Arriving between arriveBy and setUpBy (the walk-in) is still "leave now", not late.
        let n2 = at(4.7)      // arrive 05:42 + 10 min = 05:52 = setUpBy exactly
        let ok = d.live(now: n2, origin: d.home.coordinate, etas: [d.s1.id: eta(60, from: n2)]).next!
        #expect(ok.status == .leaveNow)
    }

    @Test func missedWhenEvenLeavingNowArrivesAfterTheWindowEnds() {
        let d = Day()
        let now = at(7.5)
        let live = d.live(now: now, origin: d.home.coordinate, etas: [d.s1.id: eta(60, from: now)])
        #expect(live.next!.status == .missed)
        #expect(live.next!.alternative?.stopID == d.s2.id)
    }

    @Test func lateOffersTheNextBestReachableStop() {
        let d = Day()
        let now = at(5.0)
        let live = d.live(now: now, origin: d.home.coordinate, etas: [d.s1.id: eta(60, from: now)])
        let alt = live.next!.alternative!
        #expect(alt.stopID == d.s2.id)
        #expect(alt.etaSource == .offlineEstimate)
        #expect(alt.window == d.windows[d.s2.id])
        #expect(alt.projectedArrival == now.addingTimeInterval(alt.driveSeconds))
        #expect(alt.makesSetUp)
        // On time: no alternative.
        let early = at(3.5)
        #expect(d.live(now: early, origin: d.home.coordinate, etas: [d.s1.id: eta(60, from: early)]).next!.alternative == nil)
    }

    @Test func noAlternativeWhenNothingElseIsReachable() {
        let d = Day()
        let now = at(23.5)      // after every window
        let live = d.live(now: now, origin: d.home.coordinate, progress: TripProgress(visited: [d.s1.id]))
        #expect(live.next?.stopID == d.s2.id)
        #expect(live.next?.status == .missed)
        #expect(live.next?.alternative?.stopID == nil)
    }

    @Test func aStopYouAreAtIsCurrentAndTheNextIsTheOneAfterIt() {
        let d = Day()
        let progress = TripProgress(currentStopID: d.s1.id, atCurrentStop: true)
        let live = d.live(now: at(6.5), origin: d.s1.place.coordinate, progress: progress)
        #expect(live.current == d.s1.id)
        #expect(live.currentStop?.status == .atStop)
        #expect(live.next?.stopID == d.s2.id)
        #expect(live.remaining.map(\.stopID) == [d.s3.id, d.hotel.id])
        // Marking it visited moves on with no current.
        let done = d.live(now: at(7.1), origin: d.s1.place.coordinate, progress: TripProgress(visited: [d.s1.id]))
        #expect(done.current == nil && done.next?.stopID == d.s2.id)
    }

    @Test func skippingAStopSchedulesTheFollowingOneFromWhereYouAre() {
        let d = Day()
        let now = at(12)
        let here = Coordinate(latitude: 40.2, longitude: -110)
        let progress = TripProgress(visited: [d.s1.id], skipped: [d.s2.id])
        let live = d.live(now: now, origin: here, etas: [d.s3.id: eta(30, from: now)], progress: progress)
        #expect(live.next?.stopID == d.s3.id)
        #expect(live.next?.etaSource == .live)
        #expect(live.next?.driveSeconds == 1800)
        #expect(live.next?.leaveBy == live.next!.arriveBy!.addingTimeInterval(-1800 - 480))
        #expect(live.remaining.map(\.stopID) == [d.hotel.id])
        #expect(!live.upcoming.map(\.stopID).contains(d.s2.id))
        // Without a live ETA it is a straight line from here, not the planned Mesa -> Dark leg.
        let offline = d.live(now: now, origin: here, progress: progress)
        #expect(offline.next?.etaSource == .offlineEstimate)
        #expect(offline.next?.driveSeconds == Leg.estimate(from: here, to: d.s3.place.coordinate).seconds)
        // With no position either, the planned leg from the last non-skipped stop (Arch -> Dark, estimated: none was planned).
        let planned = d.live(now: now, progress: progress)
        #expect(planned.next?.etaSource == .planned)
        #expect(planned.next?.driveSeconds == Leg.estimate(from: d.s1.place.coordinate, to: d.s3.place.coordinate).seconds)
    }

    @Test func withNoRouteTheOfflineEstimateIsLabelled() {
        let d = Day()
        let origin = Coordinate(latitude: 40.1, longitude: -110.2)
        let live = d.live(now: at(3), origin: origin)
        #expect(live.next?.etaSource == .offlineEstimate)
        #expect(live.next?.driveSeconds == Leg.estimate(from: origin, to: d.s1.place.coordinate).seconds)
        // No origin at all: the planned leg from the start place.
        let planned = d.live(now: at(3))
        #expect(planned.next?.etaSource == .planned)
        #expect(planned.next?.driveSeconds == 3600)
        #expect(planned.remaining.allSatisfy { $0.etaSource == .planned })
    }

    @Test func laterStopsChainFromThePreviousStopsDeparture() {
        let d = Day()
        let live = d.live(now: at(3), origin: d.home.coordinate)
        let s2 = live.remaining[0]
        #expect(s2.stopID == d.s2.id && s2.etaSource == .planned && s2.driveSeconds == 5400)
        #expect(s2.earliestDeparture == d.windows[d.s1.id]!.end)
        #expect(s2.leaveBy == s2.arriveBy!.addingTimeInterval(-5400 - 840))        // the margin applies to planned legs too
        // The hotel is flexible: nothing binds it.
        let hotel = live.remaining.last!
        #expect(hotel.stopID == d.hotel.id && hotel.status == .unscheduled && hotel.leaveBy == nil)
    }

    @Test func aChainThatDoesNotFitIsLate() {
        var d = Day()
        // Arch -> Mesa takes 11 hours: freed at 07:00, arrives 18:00, after Mesa's set-up (17:10).
        d.planned = legs(leg(d.s1, d.s2, minutes: 11 * 60))
        let s2 = d.live(now: at(3), origin: d.home.coordinate).remaining[0]
        guard case .late(let by, let afterSetUp) = s2.status else { Issue.record("expected late, got \(s2.status)"); return }
        #expect(by > afterSetUp && afterSetUp > 0)
    }

    @Test func allVisitedIsFinished() {
        let d = Day()
        let progress = TripProgress(visited: Set(d.trip.stops.map(\.id)))
        let live = d.live(now: at(23.5), origin: d.hotel.place.coordinate, progress: progress)
        #expect(live.finished && live.next == nil && live.remaining.isEmpty && live.current == nil)
        #expect(d.alarms(live, now: at(23.5)).isEmpty)
        // Skipped counts as done too.
        let mixed = TripProgress(visited: [d.s1.id, d.s2.id], skipped: [d.s3.id, d.hotel.id])
        #expect(d.live(now: at(23.5), progress: mixed).finished)
        // An empty trip is finished.
        let empty = LiveSchedule.make(trip: makeTrip([], days: 1), start: nil, windows: [:], plannedLegs: [:], progress: TripProgress(),
                                      now: at(1), origin: nil, liveETAs: [:])
        #expect(empty.finished)
    }

    @Test func aLightStopWithNoWindowIsUnscheduled() {
        var d = Day()
        d.windows[d.s2.id] = nil
        let s2 = d.live(now: at(3), origin: d.home.coordinate).remaining[0]
        #expect(s2.stopID == d.s2.id && s2.status == .unscheduled && s2.leaveBy == nil)
    }

    @Test func aFixedArrivalWaypointIsLiveToo() {
        let d = Day()
        let lunch = stop("Lunch", day: 0, .goldenMorning, lat: 40.1, kind: .waypoint, dwell: 30, fixed: "12:00")
        var t = d.trip
        t.stops.insert(lunch, at: 1)
        let now = at(8)
        let live = LiveSchedule.make(trip: t, start: d.home, windows: d.windows, plannedLegs: d.planned,
                                     progress: TripProgress(visited: [d.s1.id]), now: now, origin: d.s1.place.coordinate,
                                     liveETAs: [lunch.id: eta(40, from: now)])
        let next = live.next!
        #expect(next.stopID == lunch.id)
        #expect(next.arriveBy == at(12) && next.setUpBy == at(12))
        #expect(next.leaveBy == at(12).addingTimeInterval(-2400 - (300 + 240)))
        #expect(next.projectedDeparture == at(12.5))
    }
}

@Suite struct AlarmPlanTests {
    @Test func leaveSoonAndLeaveNowForTheNextStop() {
        let d = Day()
        let now = at(3.5)
        let live = d.live(now: now, origin: d.home.coordinate, etas: [d.s1.id: eta(60, from: now)])
        let alarms = d.alarms(live, now: now)
        let leaveBy = live.next!.leaveBy!
        let soon = alarms.first { $0.id == "\(d.s1.id.uuidString)-leaveSoon" }!
        let go = alarms.first { $0.id == "\(d.s1.id.uuidString)-leaveNow" }!
        #expect(soon.fireAt == leaveBy.addingTimeInterval(-900) && soon.kind == .leaveSoon && !soon.includesNavigateAction)
        #expect(go.fireAt == leaveBy && go.kind == .leaveNow && go.includesNavigateAction)
        #expect(go.stopName == "Arch" && go.windowKind == .goldenMorning && go.windowStart == d.windows[d.s1.id]!.start)
        #expect(go.driveSeconds == 3600 && go.leaveBy == leaveBy)
        // Three light stops, two alarms each; the hotel is flexible and has none.
        #expect(alarms.count == 6)
        #expect(Set(alarms.map(\.id)).count == 6)
        #expect(!alarms.contains { $0.stopID == d.hotel.id })
    }

    @Test func aReplanKeepsTheIdsAndChangesTheTimes() {
        let d = Day()
        let n1 = at(3.5)
        let first = d.alarms(d.live(now: n1, origin: d.home.coordinate, etas: [d.s1.id: eta(60, from: n1)]), now: n1)
        let n2 = at(3.6)
        let second = d.alarms(d.live(now: n2, origin: d.home.coordinate, etas: [d.s1.id: eta(90, from: n2)]), now: n2)
        #expect(first.map(\.id) == second.map(\.id))
        let a = first.first { $0.kind == .leaveNow && $0.stopID == d.s1.id }!
        let b = second.first { $0.kind == .leaveNow && $0.stopID == d.s1.id }!
        // 30 more minutes of drive and 3 more minutes of margin.
        #expect(a.fireAt.timeIntervalSince(b.fireAt) == minutes(33))
        // Later stops' alarms do not move: they do not depend on the next stop's ETA.
        let a2 = first.first { $0.id == "\(d.s2.id.uuidString)-leaveNow" }!
        let b2 = second.first { $0.id == "\(d.s2.id.uuidString)-leaveNow" }!
        #expect(a2.fireAt == b2.fireAt)
    }

    @Test func alarmsInThePastAreNotEmitted() {
        let d = Day()
        let leaveBy = at(6.2).addingTimeInterval(-minutes(30) - 3600 - 660)
        // Between leave-soon and leave-now: only leave-now.
        let n1 = leaveBy.addingTimeInterval(-minutes(5))
        let soonOnly = d.alarms(d.live(now: n1, origin: d.home.coordinate, etas: [d.s1.id: eta(60, from: n1)]), now: n1)
        #expect(soonOnly.filter { $0.stopID == d.s1.id }.map(\.kind) == [.leaveNow])
        // After leave-now: nothing for that stop (the app shows the status).
        let n2 = leaveBy.addingTimeInterval(minutes(1))
        let none = d.alarms(d.live(now: n2, origin: d.home.coordinate, etas: [d.s1.id: eta(60, from: n2)]), now: n2)
        #expect(none.filter { $0.stopID == d.s1.id }.isEmpty)
        #expect(none.contains { $0.stopID == d.s2.id })
    }

    @Test func lateAndMissedStopsHaveNoAlarmsAndVisitedOnesNeither() {
        let d = Day()
        let late = at(5.0)
        let l1 = d.alarms(d.live(now: late, origin: d.home.coordinate, etas: [d.s1.id: eta(60, from: late)]), now: late)
        #expect(!l1.contains { $0.stopID == d.s1.id })
        let missed = at(7.5)
        let l2 = d.alarms(d.live(now: missed, origin: d.home.coordinate, etas: [d.s1.id: eta(60, from: missed)]), now: missed)
        #expect(!l2.contains { $0.stopID == d.s1.id } && l2.contains { $0.stopID == d.s2.id })
        let skip = at(12)
        let l3 = d.alarms(d.live(now: skip, origin: d.home.coordinate, progress: TripProgress(visited: [d.s1.id], skipped: [d.s2.id])), now: skip)
        #expect(Set(l3.map(\.stopID)) == [d.s3.id])
    }

    @Test func anAlarmNeverRingsWhileYouAreStillAtThePreviousStop() {
        var d = Day()
        // Arch frees you at 07:00. Mesa's drive is 10 hours: leave-by lands before that.
        d.planned = legs(leg(d.s1, d.s2, minutes: 10 * 60 + 5))
        let now = at(3)
        let live = d.live(now: now, origin: d.home.coordinate)
        let s2 = live.remaining[0]
        #expect(s2.leaveBy! < d.windows[d.s1.id]!.end)
        // Pushed back to when Arch frees you (07:00), and not late: arriving 17:05 is before Mesa's set-up at 17:10.
        #expect(s2.status == .leaveSoon(untilLeaveBy: s2.leaveBy!.timeIntervalSince(now)) || s2.status == .early(untilLeaveBy: s2.leaveBy!.timeIntervalSince(now)))
        let alarms = d.alarms(live, now: now).filter { $0.stopID == d.s2.id }
        #expect(alarms.map(\.kind) == [.leaveSoon, .leaveNow])
        #expect(alarms[1].fireAt == d.windows[d.s1.id]!.end)
        #expect(alarms[1].leaveBy == d.windows[d.s1.id]!.end)
    }
}

@Suite struct ScriptedDay {
    /// The whole day with a fake clock. Each step re-plans from scratch, as trip mode does.
    @Test func theDayFromDawnToTheHotel() {
        let d = Day()
        func id(_ stop: Stop, _ kind: AlarmKind) -> String { "\(stop.id.uuidString)-\(kind.rawValue)" }
        let s1LeaveBy = at(6.2).addingTimeInterval(-minutes(30))        // arriveBy 05:42, before the drive

        // (1) 03:30, on time. 60 minute drive: leave by 04:31.
        var now = at(3.5)
        var live = d.live(now: now, origin: d.home.coordinate, etas: [d.s1.id: eta(60, from: now)])
        guard case .early(let until) = live.next!.status else { Issue.record("step 1 should be early"); return }
        #expect(until == minutes(61))
        var alarms = d.alarms(live, now: now)
        let ids = alarms.map(\.id)
        #expect(ids == [id(d.s1, .leaveSoon), id(d.s1, .leaveNow), id(d.s2, .leaveSoon), id(d.s2, .leaveNow), id(d.s3, .leaveSoon), id(d.s3, .leaveNow)])
        var leaveNow = alarms.first { $0.id == id(d.s1, .leaveNow) }!
        #expect(leaveNow.fireAt == s1LeaveBy.addingTimeInterval(-3600 - 660))
        #expect(alarms.first { $0.id == id(d.s1, .leaveSoon) }!.fireAt == leaveNow.fireAt.addingTimeInterval(-900))

        // (2) 03:36, traffic: the ETA grows to 90 minutes. Leave-by moves 33 minutes earlier; same ids, new times.
        now = at(3.6)
        live = d.live(now: now, origin: d.home.coordinate, etas: [d.s1.id: eta(90, from: now)])
        alarms = d.alarms(live, now: now)
        #expect(alarms.map(\.id) == ids)
        let moved = alarms.first { $0.id == id(d.s1, .leaveNow) }!
        #expect(moved.fireAt == leaveNow.fireAt.addingTimeInterval(-minutes(33)))
        #expect(moved.driveSeconds == 5400)
        leaveNow = moved

        // (2b) 03:50: leave-soon has passed, leave-now has not: only leave-now remains for Arch.
        now = at(3.9)
        live = d.live(now: now, origin: d.home.coordinate, etas: [d.s1.id: eta(90, from: now)])
        if case .leaveSoon = live.next!.status {} else { Issue.record("step 2b should be leaveSoon, got \(live.next!.status)") }
        #expect(d.alarms(live, now: now).filter { $0.stopID == d.s1.id }.map(\.id) == [id(d.s1, .leaveNow)])

        // (3) Running late: still at home at 05:10 with an hour to go.
        now = at(5 + 10.0 / 60)
        live = d.live(now: now, origin: d.home.coordinate, etas: [d.s1.id: eta(60, from: now)])
        guard case .late(_, let afterSetUp) = live.next!.status else { Issue.record("step 3 should be late"); return }
        #expect(afterSetUp > 0)
        #expect(live.next!.alternative?.stopID == d.s2.id)
        #expect(!d.alarms(live, now: now).contains { $0.stopID == d.s1.id })

        // (3b) 07:30: the sunrise window is over.
        now = at(7.5)
        live = d.live(now: now, origin: d.home.coordinate, etas: [d.s1.id: eta(60, from: now)])
        #expect(live.next!.status == .missed)
        #expect(live.next!.alternative?.stopID == d.s2.id)

        // (4) Skip Mesa (stop 2) after shooting Arch: Dark is scheduled from where you are.
        now = at(15)
        let here = Coordinate(latitude: 40.4, longitude: -109.9)
        let progress = TripProgress(visited: [d.s1.id], skipped: [d.s2.id])
        live = d.live(now: now, origin: here, etas: [d.s3.id: eta(25, from: now)], progress: progress)
        #expect(live.next?.stopID == d.s3.id && live.next?.etaSource == .live && live.next?.driveSeconds == 1500)
        alarms = d.alarms(live, now: now)
        #expect(alarms.map(\.id) == [id(d.s3, .leaveSoon), id(d.s3, .leaveNow)])
        #expect(alarms[1].fireAt == live.next!.arriveBy!.addingTimeInterval(-1500 - 450))

        // (5) No live ETA, no route: an offline estimate, labelled.
        live = d.live(now: now, origin: here, progress: progress)
        #expect(live.next?.etaSource == .offlineEstimate)
        #expect(live.next?.driveSeconds == Leg.estimate(from: here, to: d.s3.place.coordinate).seconds)
        #expect(d.alarms(live, now: now).count == 2)

        // (6) Everything done.
        now = at(23.4)
        live = d.live(now: now, origin: d.hotel.place.coordinate, progress: TripProgress(visited: Set(d.trip.stops.map(\.id))))
        #expect(live.finished)
        #expect(d.alarms(live, now: now).isEmpty)
    }
}

@Suite struct LiveProperties {
    @Test func liveLeaveByNeverGetsLaterAsTheETAGrows() {
        let d = Day()
        var rng = SeededRNG(seed: 42)
        let etas = (0..<300).map { _ in Double.random(in: 1...600, using: &rng) * 60 }.sorted()
        let now = at(2)
        var last: Date?
        for seconds in etas {
            let live = d.live(now: now, origin: d.home.coordinate,
                              etas: [d.s1.id: ETA(seconds: seconds, arrival: now.addingTimeInterval(seconds), departing: now)])
            let leaveBy = live.next!.leaveBy!
            if let last { #expect(leaveBy <= last) }
            last = leaveBy
        }
    }

    @Test func theMarginGrowsWithTheETAToo() {
        var last = 0.0
        for seconds in stride(from: 0.0, through: 36_000, by: 600) {
            let margin = LiveSchedule.safetyMargin(forDriveSeconds: seconds)
            #expect(margin >= last)
            last = margin
        }
    }
}

@Suite struct ConditionsAlerts {
    private let stop = UUID()
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func aFifteenPointMoveAlerts() {
        #expect(ConditionsAlertPolicy.evaluate(stopID: stop, previous: 60, current: 75, lastAlertAt: nil, now: t0))
        #expect(ConditionsAlertPolicy.evaluate(stopID: stop, previous: 80, current: 65, lastAlertAt: nil, now: t0))
        // 14 points inside one band does not (60 -> 73 are both "good").
        #expect(!ConditionsAlertPolicy.evaluate(stopID: stop, previous: 59, current: 72, lastAlertAt: nil, now: t0))
    }

    @Test func aBandChangeAlertsEvenForASmallMove() {
        #expect(ConditionsAlertPolicy.evaluate(stopID: stop, previous: 57, current: 58, lastAlertAt: nil, now: t0))      // fair -> good
        #expect(ConditionsAlertPolicy.evaluate(stopID: stop, previous: 74, current: 73, lastAlertAt: nil, now: t0))      // great -> good
        #expect(ConditionsAlertPolicy.evaluate(stopID: stop, previous: 87, current: 88, lastAlertAt: nil, now: t0))      // great -> epic
        #expect(ConditionsAlertPolicy.evaluate(stopID: stop, previous: 40, current: 39, lastAlertAt: nil, now: t0))      // fair -> poor
        #expect(ConditionsAlertPolicy.evaluate(stopID: stop, previous: 58, current: 73, lastAlertAt: nil, now: t0))      // exactly 15
        #expect(!ConditionsAlertPolicy.evaluate(stopID: stop, previous: 58, current: 72, lastAlertAt: nil, now: t0))
    }

    @Test func quietForAnHourAfterAnAlert() {
        let recent = t0.addingTimeInterval(-3599)
        #expect(!ConditionsAlertPolicy.evaluate(stopID: stop, previous: 30, current: 90, lastAlertAt: recent, now: t0))
        #expect(ConditionsAlertPolicy.evaluate(stopID: stop, previous: 30, current: 90, lastAlertAt: t0.addingTimeInterval(-3600), now: t0))
    }

    @Test func noBaselineNoAlert() {
        #expect(!ConditionsAlertPolicy.evaluate(stopID: stop, previous: nil, current: 90, lastAlertAt: nil, now: t0))
    }

    @Test func theBandsAreIterSkys() {
        // < 40 poor, 40-57 fair, 58-73 good, 74-87 great, >= 88 epic.
        let edges: [(Int, Int)] = [(39, 40), (57, 58), (73, 74), (87, 88)]
        for (lo, hi) in edges {
            #expect(ConditionsAlertPolicy.evaluate(stopID: stop, previous: lo, current: hi, lastAlertAt: nil, now: t0))
        }
    }

    @Test func theStateObservesScoresAndRateLimits() throws {
        var state = ConditionsAlertState()
        let other = UUID()
        #expect(state.observe(stopID: stop, score: 60, now: t0) == nil)                  // first: baseline
        #expect(state.observe(stopID: stop, score: 66, now: t0.addingTimeInterval(60)) == nil)
        let alert = state.observe(stopID: stop, score: 80, now: t0.addingTimeInterval(120))
        #expect(alert?.previous == 60 && alert?.current == 80 && alert?.reason == .scoreMoved && alert?.improved == true)
        #expect(alert?.previousBand == .good && alert?.currentBand == .great)
        // Quiet for an hour, even for a big drop; the baseline stays at the alerted score.
        #expect(state.observe(stopID: stop, score: 40, now: t0.addingTimeInterval(1800)) == nil)
        let later = state.observe(stopID: stop, score: 40, now: t0.addingTimeInterval(120 + 3600))
        #expect(later?.previous == 80 && later?.current == 40)
        // Stops are independent.
        #expect(state.observe(stopID: other, score: 50, now: t0) == nil)
        #expect(state.observe(stopID: other, score: 58, now: t0.addingTimeInterval(10))?.reason == .bandChanged)
        // Persistable.
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(ConditionsAlertState.self, from: data) == state)
        state.forget(stopID: stop)
        #expect(state.entries[stop] == nil)
    }
}
