import Foundation
import Testing
import IterGo
import IterModel
import IterPlan

private typealias F = RunFixture
private func h(_ x: Double) -> Date { RunFixture.h(x) }

@Suite struct RunStartTests {
    @Test func defaultStartIsTheFirstStopArmed() {
        let rig = RunRig()
        #expect(rig.run.phase == .armed)
        #expect(rig.run.targetStopID == rig.fx.s1.id)
        #expect(rig.run.startedAt == h(0))
        #expect(rig.run.visits.count == 5)
        #expect(rig.run.visits.values.allSatisfy { $0.status == .pending })
        #expect(rig.run.progress == TripProgress(visited: [], skipped: [], currentStopID: rig.fx.s1.id, atCurrentStop: false))
    }

    @Test func midTripStartSkipsEarlierStopsWithNoDates() {
        let rig = RunRig(at: RunFixture().s2)
        #expect(rig.visit(rig.fx.s1) == StopVisit(stopID: rig.fx.s1.id, status: .skipped))
        #expect(rig.run.targetStopID == rig.fx.s2.id)
        #expect(rig.run.progress.skipped == [rig.fx.s1.id])
        #expect(rig.visit(rig.fx.hotel).status == .pending)
    }

    @Test func dayThreeStartSkipsTheFirstTwoDays() {
        let a = Stop(place: RunFixture.place("A", east: 1000), dayIndex: 0, session: .goldenMorning)
        let b = Stop(place: RunFixture.place("B", east: 2000), dayIndex: 1, session: .goldenMorning)
        let c1 = Stop(place: RunFixture.place("C1", east: 3000), dayIndex: 2, session: .goldenMorning)
        let c2 = Stop(place: RunFixture.place("C2", east: 4000), dayIndex: 2, session: .goldenEvening)
        // Array order is not day order: the start must follow day-major order.
        let trip = Trip(name: "t", startDay: LocalDay(year: 2027, month: 1, day: 1), dayCount: 3, stops: [c1, a, c2, b])
        let run = TripRun.start(trip: trip, runID: UUID(), at: c1.id, now: h(0), alreadyThere: false)
        #expect(run.visits[a.id]?.status == .skipped)
        #expect(run.visits[b.id]?.status == .skipped)
        #expect(run.visits[c1.id]?.status == .pending)
        #expect(run.visits[c2.id]?.status == .pending)
        #expect(run.targetStopID == c1.id)
    }

    @Test func alreadyThereStartsAtTheStop() {
        let rig = RunRig(at: RunFixture().s2, alreadyThere: true, now: h(16.5))
        #expect(rig.run.phase == .atStop)
        #expect(rig.visit(rig.fx.s2).status == .arrived)
        #expect(rig.visit(rig.fx.s2).arrivedAt == h(16.5))
        #expect(rig.run.progress.atCurrentStop)
    }

    @Test func unknownStopFallsBackToTheFirst() {
        let run = TripRun.start(trip: RunFixture().trip, runID: UUID(), at: UUID(), now: h(0), alreadyThere: false)
        #expect(run.targetStopID == RunFixture().s1.id)
    }
}

@Suite struct RunArmedTests {
    @Test func leaveNowDepartsAndFreezesThePlannedTimes() {
        var rig = RunRig()
        let live = rig.fx.live(rig.run, at: h(8))
        let out = rig.send(.user(.leaveNow), at: h(8))
        #expect(rig.run.phase == .driving)
        #expect(out.count == 1)
        let t = out[0]
        #expect(t.from == .armed && t.to == .driving && t.cause == .user && !t.automatic && t.undoExpiresAt == nil)
        #expect(t.stopID == rig.fx.s1.id)
        let v = rig.visit(rig.fx.s1)
        #expect(v.status == .enRoute)
        #expect(v.departedForAt == h(8))
        #expect(v.plannedLeaveBy == live.next!.leaveBy)
        #expect(v.plannedArrival == live.next!.projectedArrival)
        #expect(t.visitChanges == [v])
        // Later schedules move; the frozen times do not.
        _ = rig.send(.tick, at: h(9.5))
        _ = rig.fix(RunFixture.offset(rig.fx.home.coordinate, east: 5000), speed: 20, at: h(9.5))
        #expect(rig.visit(rig.fx.s1).plannedLeaveBy == live.next!.leaveBy)
        #expect(rig.visit(rig.fx.s1).plannedArrival == live.next!.projectedArrival)
    }

    @Test func timeDepartsAtLeaveBy() {
        var rig = RunRig()
        let lb = rig.leaveBy(of: rig.fx.s1)
        #expect(rig.send(.tick, at: lb.addingTimeInterval(-1)).isEmpty)
        let out = rig.send(.tick, at: lb)
        #expect(out.count == 1)
        #expect(out[0].cause == .time && out[0].automatic && out[0].to == .driving)
        #expect(out[0].undoExpiresAt == lb.addingTimeInterval(120))
        #expect(rig.run.pendingUndo?.expiresAt == lb.addingTimeInterval(120))
        #expect(rig.run.undoExpiry == lb.addingTimeInterval(120))
        #expect(rig.visit(rig.fx.s1).plannedLeaveBy == lb)
    }

    @Test func motionNeedsDistanceAndSpeedOrTwoFixes() {
        var rig = RunRig()
        // Close to home: nothing.
        #expect(rig.fix(RunFixture.offset(rig.fx.home.coordinate, east: 400), speed: 20, at: h(8)).isEmpty)
        // Far but slow: the first is not enough, the second consecutive one is.
        #expect(rig.fix(RunFixture.offset(rig.fx.home.coordinate, east: 700), speed: 1, at: h(8.01)).isEmpty)
        let out = rig.fix(RunFixture.offset(rig.fx.home.coordinate, east: 800), speed: 1, at: h(8.02))
        #expect(out.count == 1 && out[0].cause == .motion && out[0].automatic && out[0].to == .driving)
    }

    @Test func fastFarFixDepartsAtOnce() {
        var rig = RunRig()
        let out = rig.fix(RunFixture.offset(rig.fx.home.coordinate, east: 700), speed: 8, at: h(8))
        #expect(out.count == 1 && out[0].cause == .motion)
        #expect(rig.run.phase == .driving)
    }

    @Test func aNearFixBreaksTheTwoFixStreak() {
        var rig = RunRig()
        #expect(rig.fix(RunFixture.offset(rig.fx.home.coordinate, east: 700), speed: 1, at: h(8)).isEmpty)
        #expect(rig.fix(RunFixture.offset(rig.fx.home.coordinate, east: 100), speed: 1, at: h(8.01)).isEmpty)
        #expect(rig.fix(RunFixture.offset(rig.fx.home.coordinate, east: 700), speed: 1, at: h(8.02)).isEmpty)
        #expect(rig.run.phase == .armed)
    }

    @Test func motionWithoutAStartUsesTheFirstFixAsOrigin() {
        var rig = RunRig()
        rig.hasStart = false
        let first = RunFixture.offset(rig.fx.home.coordinate, east: 30_000)
        #expect(rig.fix(first, speed: 10, at: h(8)).isEmpty)   // the origin itself
        #expect(rig.fix(RunFixture.offset(first, east: 300), speed: 10, at: h(8.01)).isEmpty)
        let out = rig.fix(RunFixture.offset(first, east: 900), speed: 10, at: h(8.02))
        #expect(out.count == 1 && out[0].cause == .motion)
    }

    @Test func unusableFixesNeverCount() {
        var rig = RunRig()
        #expect(rig.fix(RunFixture.offset(rig.fx.home.coordinate, east: 900), acc: 250, speed: 20, at: h(8)).isEmpty)
        #expect(rig.fix(RunFixture.offset(rig.fx.home.coordinate, east: 900), acc: -1, speed: 20, at: h(8.01)).isEmpty)
        #expect(rig.run.phase == .armed)
    }

    @Test func arrivedFromArmedGoesStraightToTheStop() {
        var rig = RunRig()
        let out = rig.send(.user(.arrived), at: h(9))
        #expect(rig.run.phase == .atStop && out.count == 1 && out[0].stopID == rig.fx.s1.id)
        #expect(rig.visit(rig.fx.s1).status == .arrived)
        #expect(rig.visit(rig.fx.s1).arrivedAt == h(9))
    }
}

@Suite struct RunDrivingTests {
    @Test func userArrivedMarksArrival() {
        var rig = RunRig.driving(to: RunFixture().s1)
        let out = rig.send(.user(.arrived), at: h(9.5))
        #expect(rig.run.phase == .atStop)
        #expect(out[0].from == .driving && out[0].to == .atStop && out[0].cause == .user)
        #expect(rig.visit(rig.fx.s1).status == .arrived)
        #expect(rig.visit(rig.fx.s1).arrivedAt == h(9.5))
        #expect(rig.visit(rig.fx.s1).departedForAt == h(8))
    }

    @Test func slowInsideFixEntersAtOnce() {
        var rig = RunRig.driving(to: RunFixture().s1)
        let out = rig.fix(near: rig.fx.s1, east: 100, speed: 1, at: h(9))
        #expect(out.count == 1 && out[0].cause == .geofence && out[0].automatic && out[0].to == .atStop)
        #expect(rig.visit(rig.fx.s1).status == .arrived)
        #expect(rig.visit(rig.fx.s1).arrivedAt == h(9))
    }

    @Test func twoInsideFixesTwentySecondsApartEnter() {
        var rig = RunRig.driving(to: RunFixture().s1)
        #expect(rig.fix(near: rig.fx.s1, east: 100, speed: 9, at: h(9)).isEmpty)
        #expect(rig.fix(near: rig.fx.s1, east: 100, speed: 9, at: h(9).addingTimeInterval(19)).isEmpty)
        let out = rig.fix(near: rig.fx.s1, east: 100, speed: 9, at: h(9).addingTimeInterval(20))
        #expect(out.count == 1 && out[0].to == .atStop)
    }

    @Test func unknownSpeedNeedsTheTwoFixRule() {
        var rig = RunRig.driving(to: RunFixture().s1)
        #expect(rig.fix(near: rig.fx.s1, east: 100, at: h(9)).isEmpty)
        #expect(rig.fix(near: rig.fx.s1, east: 100, at: h(9).addingTimeInterval(25)).count == 1)
    }

    @Test func radiusAndAccuracyRules() {
        var rig = RunRig.driving(to: RunFixture().s1)
        // 190 m with a 20 m accuracy: 150 + 20 = 170 < 190, outside.
        #expect(rig.fix(near: rig.fx.s1, east: 190, acc: 20, speed: 0.5, at: h(9)).isEmpty)
        // Accuracy slack is capped at 50 m: 210 m with 150 m accuracy is still outside.
        #expect(rig.fix(near: rig.fx.s1, east: 210, acc: 150, speed: 0.5, at: h(9.01)).isEmpty)
        // 190 m with a 50 m accuracy: 150 + 50 = 200 >= 190, inside.
        #expect(rig.fix(near: rig.fx.s1, east: 190, acc: 50, speed: 0.5, at: h(9.02)).count == 1)
    }

    @Test func fixesWorseThanTwoHundredMetresNeverCount() {
        var rig = RunRig.driving(to: RunFixture().s1)
        #expect(rig.fix(near: rig.fx.s1, east: 0, acc: 201, speed: 0, at: h(9)).isEmpty)
        #expect(rig.fix(near: rig.fx.s1, east: 0, acc: 201, speed: 0, at: h(9.01)).isEmpty)
        #expect(rig.run.phase == .driving)
    }

    @Test func radiusDependsOnTheStopKind() {
        #expect(GeofencePolicy.enterRadius(for: .light) == 150)
        #expect(GeofencePolicy.enterRadius(for: .waypoint) == 200)
        #expect(GeofencePolicy.enterRadius(for: .lodging) == 300)
        #expect(GeofencePolicy.exitRadius(for: .light) == 400)
        var lodging = RunRig.driving(to: RunFixture().hotel)
        #expect(lodging.fix(near: lodging.fx.hotel, east: 280, speed: 0.5, at: h(9)).count == 1)
        var waypoint = RunRig.driving(to: RunFixture().way)
        #expect(waypoint.fix(near: waypoint.fx.way, east: 220, speed: 0.5, at: h(9)).isEmpty)
        #expect(waypoint.fix(near: waypoint.fx.way, east: 180, speed: 0.5, at: h(9.01)).count == 1)
    }

    @Test func onlyTheTargetStopCounts() {
        var rig = RunRig.driving(to: RunFixture().s1)
        #expect(rig.fix(near: rig.fx.s2, east: 0, speed: 0, at: h(9)).isEmpty)
        #expect(rig.run.phase == .driving)
    }

    @Test func timeAndMotionDoNothingWhileDriving() {
        var rig = RunRig.driving(to: RunFixture().s1)
        #expect(rig.send(.tick, at: h(30)).isEmpty)
        #expect(rig.fix(RunFixture.offset(rig.fx.home.coordinate, east: 9000), speed: 30, at: h(9)).isEmpty)
    }
}

@Suite struct RunAtStopTests {
    @Test func doneHereMovesOnAndTargetsTheNextStop() {
        var rig = RunRig(at: RunFixture().s1, alreadyThere: true, now: h(9.6))
        let out = rig.send(.user(.doneHere), at: h(10.5))
        #expect(rig.run.phase == .betweenStops)
        #expect(out[0].from == .atStop && out[0].to == .betweenStops && out[0].cause == .user)
        #expect(rig.visit(rig.fx.s1).status == .done)
        #expect(rig.visit(rig.fx.s1).leftAt == h(10.5))
        #expect(rig.visit(rig.fx.s1).arrivedAt == h(9.6))
        #expect(rig.run.targetStopID == rig.fx.s2.id)
        #expect(rig.run.progress.visited == [rig.fx.s1.id])
        #expect(!rig.run.progress.atCurrentStop)
    }

    @Test func windowEndEndsTheStopByTime() {
        var rig = RunRig(at: RunFixture().s1, alreadyThere: true, now: h(9.6))
        #expect(rig.send(.tick, at: h(10.99)).isEmpty)
        let out = rig.send(.tick, at: h(11))
        #expect(out.count == 1 && out[0].cause == .time && out[0].automatic && out[0].to == .betweenStops)
        #expect(rig.visit(rig.fx.s1).status == .done)
        #expect(rig.visit(rig.fx.s1).leftAt == h(11))
    }

    @Test func dwellEndsAWaypoint() {
        var rig = RunRig(at: RunFixture().way, alreadyThere: true, now: h(40))
        // IterPlan gives a waypoint with no fixed arrival no departure; the run uses arrival + dwell.
        #expect(rig.fx.live(rig.run, at: h(40)).currentStop!.projectedDeparture == nil)
        let departure = h(40).addingTimeInterval(1800)
        #expect(rig.send(.tick, at: departure.addingTimeInterval(-1)).isEmpty)
        // It is the last stop, so the run finishes.
        let out = rig.send(.tick, at: departure)
        #expect(out.count == 1 && out[0].to == .finished)
        #expect(rig.run.endedAt == departure)
    }

    @Test func overnightLodgingNeverEndsByTimeButNextLeaveByTakesYouOn() {
        var rig = RunRig(at: RunFixture().hotel, alreadyThere: true, now: h(19))
        #expect(rig.fx.live(rig.run, at: h(19)).currentStop!.projectedDeparture == nil)
        #expect(rig.send(.tick, at: h(26)).isEmpty)
        let lb = rig.fx.live(rig.run, at: h(26)).next!.leaveBy!
        #expect(rig.send(.tick, at: lb.addingTimeInterval(-1)).isEmpty)
        let out = rig.send(.tick, at: lb)
        #expect(out.count == 1 && out[0].cause == .time && out[0].automatic && out[0].from == .atStop && out[0].to == .driving)
        #expect(out[0].stopID == rig.fx.s3.id)
        #expect(rig.visit(rig.fx.hotel).status == .done)
        #expect(rig.visit(rig.fx.s3).status == .enRoute)
        #expect(rig.visit(rig.fx.s3).plannedLeaveBy == lb)
        #expect(Set(out[0].visitChanges.map(\.stopID)) == [rig.fx.hotel.id, rig.fx.s3.id])
    }

    @Test func leavingTheGeofenceGoesStraightToDriving() {
        var rig = RunRig(at: RunFixture().s1, alreadyThere: true, now: h(9.6))
        let next = rig.fx.live(rig.run, at: h(10)).next!
        // Inside the exit radius (400 m): nothing.
        #expect(rig.fix(near: rig.fx.s1, east: 390, at: h(10)).isEmpty)
        #expect(rig.fix(near: rig.fx.s1, east: 450, at: h(10.1)).isEmpty)
        let t = h(10.1).addingTimeInterval(29)
        #expect(rig.fix(near: rig.fx.s1, east: 460, at: t).isEmpty)
        let out = rig.fix(near: rig.fx.s1, east: 470, at: h(10.1).addingTimeInterval(31))
        #expect(out.count == 1)
        #expect(out[0].cause == .geofence && out[0].automatic && out[0].from == .atStop && out[0].to == .driving)
        #expect(out[0].stopID == rig.fx.s2.id)
        #expect(rig.visit(rig.fx.s1).status == .done)
        #expect(rig.visit(rig.fx.s2).status == .enRoute)
        #expect(rig.visit(rig.fx.s2).plannedLeaveBy == next.leaveBy)
        #expect(rig.run.targetStopID == rig.fx.s2.id)
    }

    @Test func aFixBackInsideResetsTheExitStreak() {
        var rig = RunRig(at: RunFixture().s1, alreadyThere: true, now: h(9.6))
        #expect(rig.fix(near: rig.fx.s1, east: 500, at: h(10)).isEmpty)
        #expect(rig.fix(near: rig.fx.s1, east: 100, at: h(10).addingTimeInterval(20)).isEmpty)
        #expect(rig.fix(near: rig.fx.s1, east: 500, at: h(10).addingTimeInterval(40)).isEmpty)
        #expect(rig.fix(near: rig.fx.s1, east: 500, at: h(10).addingTimeInterval(60)).isEmpty)
        #expect(rig.run.phase == .atStop)
    }

    @Test func leavingTheLastStopFinishes() {
        var rig = RunRig(at: RunFixture().way, alreadyThere: true, now: h(40))
        _ = rig.fix(near: rig.fx.way, east: 700, at: h(40.1))
        let out = rig.fix(near: rig.fx.way, east: 700, at: h(40.1).addingTimeInterval(40))
        #expect(out.count == 1 && out[0].to == .finished && out[0].cause == .geofence)
        #expect(rig.run.phase == .finished)
    }

    @Test func leaveNowFromAStopMarksItDone() {
        var rig = RunRig(at: RunFixture().s1, alreadyThere: true, now: h(9.6))
        let out = rig.send(.user(.leaveNow), at: h(10.2))
        #expect(out[0].to == .driving && rig.visit(rig.fx.s1).status == .done && rig.visit(rig.fx.s2).status == .enRoute)
    }
}

@Suite struct RunBetweenStopsTests {
    private func between() -> RunRig {
        var rig = RunRig(at: RunFixture().s1, alreadyThere: true, now: h(9.6))
        rig.send(.user(.doneHere), at: h(10.5))
        return rig
    }

    @Test func leaveNowDeparts() {
        var rig = between()
        let out = rig.send(.user(.leaveNow), at: h(12))
        #expect(rig.run.phase == .driving && out[0].stopID == rig.fx.s2.id && out[0].cause == .user)
        #expect(rig.visit(rig.fx.s2).departedForAt == h(12))
    }

    @Test func timeDepartsAtLeaveBy() {
        var rig = between()
        let lb = rig.fx.live(rig.run, at: h(10.5)).next!.leaveBy!
        #expect(rig.send(.tick, at: lb.addingTimeInterval(-1)).isEmpty)
        let out = rig.send(.tick, at: lb)
        #expect(out.count == 1 && out[0].cause == .time && out[0].automatic && out[0].to == .driving)
    }

    @Test func motionAwayFromTheLastStopDeparts() {
        var rig = between()
        #expect(rig.fix(near: rig.fx.s1, east: 300, speed: 10, at: h(11)).isEmpty)
        let out = rig.fix(near: rig.fx.s1, east: 800, speed: 10, at: h(11.01))
        #expect(out.count == 1 && out[0].cause == .motion && out[0].to == .driving)
    }

    @Test func userArrivedGoesToTheNextStop() {
        var rig = between()
        let out = rig.send(.user(.arrived), at: h(16))
        #expect(rig.run.phase == .atStop && out[0].stopID == rig.fx.s2.id)
    }
}

@Suite struct RunSkipTests {
    @Test func skippingTheTargetWhileArmedMovesTheTarget() {
        var rig = RunRig()
        let out = rig.send(.user(.skip(nil)), at: h(8))
        #expect(rig.run.phase == .armed && rig.run.targetStopID == rig.fx.s2.id)
        #expect(rig.visit(rig.fx.s1).status == .skipped)
        #expect(out[0].stopID == rig.fx.s1.id && out[0].from == .armed && out[0].to == .armed)
        #expect(rig.run.progress.skipped == [rig.fx.s1.id])
    }

    @Test func skippingTheTargetWhileDrivingKeepsDrivingToTheNewNext() {
        var rig = RunRig.driving(to: RunFixture().s1)
        let out = rig.send(.user(.skip(nil)), at: h(9))
        #expect(rig.run.phase == .driving && rig.run.targetStopID == rig.fx.s2.id)
        #expect(rig.visit(rig.fx.s1).status == .skipped)
        #expect(rig.visit(rig.fx.s1).departedForAt == h(8))
        #expect(rig.visit(rig.fx.s2).status == .enRoute)
        #expect(rig.visit(rig.fx.s2).departedForAt == h(9))
        #expect(rig.visit(rig.fx.s2).plannedLeaveBy != nil)
        #expect(Set(out[0].visitChanges.map(\.stopID)) == [rig.fx.s1.id, rig.fx.s2.id])
    }

    @Test func skippingTheStopYouAreAtGoesBetweenStops() {
        var rig = RunRig(at: RunFixture().s1, alreadyThere: true, now: h(9.6))
        let out = rig.send(.user(.skip(rig.fx.s1.id)), at: h(10))
        #expect(rig.run.phase == .betweenStops && out[0].from == .atStop && out[0].to == .betweenStops)
        #expect(rig.visit(rig.fx.s1).status == .skipped)
        #expect(rig.visit(rig.fx.s1).leftAt == h(10))
        #expect(rig.visit(rig.fx.s1).arrivedAt == h(9.6))
        #expect(rig.run.targetStopID == rig.fx.s2.id)
    }

    @Test func nilSkipWhileAtAStopSkipsTheNextStop() {
        var rig = RunRig(at: RunFixture().s1, alreadyThere: true, now: h(9.6))
        rig.send(.user(.skip(nil)), at: h(10))
        #expect(rig.run.phase == .atStop && rig.run.targetStopID == rig.fx.s1.id)
        #expect(rig.visit(rig.fx.s2).status == .skipped)
        #expect(rig.visit(rig.fx.s1).status == .arrived)
        #expect(rig.run.progress.skipped == [rig.fx.s2.id])
    }

    @Test func skippingWhileBetweenStopsMovesTheTarget() {
        var rig = RunRig(at: RunFixture().s1, alreadyThere: true, now: h(9.6))
        rig.send(.user(.doneHere), at: h(10.5))
        rig.send(.user(.skip(nil)), at: h(11))
        #expect(rig.run.phase == .betweenStops && rig.run.targetStopID == rig.fx.hotel.id)
    }

    @Test func skippingALaterStopLeavesThePhoneAlone() {
        var rig = RunRig.driving(to: RunFixture().s1)
        let out = rig.send(.user(.skip(rig.fx.s3.id)), at: h(9))
        #expect(rig.run.phase == .driving && rig.run.targetStopID == rig.fx.s1.id)
        #expect(out.count == 1 && out[0].from == .driving && out[0].to == .driving)
        #expect(rig.visit(rig.fx.s3).status == .skipped)
    }

    @Test func skippingEverythingFinishes() {
        var rig = RunRig(at: RunFixture().way)
        let out = rig.send(.user(.skip(nil)), at: h(9))
        #expect(rig.run.phase == .finished && out[0].to == .finished)
        #expect(rig.run.endedAt == h(9))
    }

    @Test func skippingTheLastRemainingStopWhileAtThePenultimateIsFine() {
        var rig = RunRig(at: RunFixture().s3, alreadyThere: true, now: h(29))
        rig.send(.user(.skip(nil)), at: h(29.5))   // way
        #expect(rig.run.phase == .atStop)
        rig.send(.user(.doneHere), at: h(30.5))
        #expect(rig.run.phase == .finished)
    }

    @Test func skippingAFinishedOrUnknownStopDoesNothing() {
        var rig = RunRig(at: RunFixture().s2)
        #expect(rig.send(.user(.skip(rig.fx.s1.id)), at: h(9)).isEmpty)   // already skipped
        #expect(rig.send(.user(.skip(UUID())), at: h(9)).isEmpty)
    }
}

@Suite struct RunFinishPauseTests {
    @Test func lastStopDoneFinishesTheRun() {
        var rig = RunRig(at: RunFixture().way, alreadyThere: true, now: h(40))
        let out = rig.send(.user(.doneHere), at: h(41))
        #expect(rig.run.phase == .finished && out[0].to == .finished)
        #expect(rig.run.endedAt == h(41))
        #expect(rig.visit(rig.fx.way).status == .done)
        #expect(rig.send(.tick, at: h(50)).isEmpty)
        #expect(rig.send(.user(.leaveNow), at: h(50)).isEmpty)
        #expect(rig.fix(near: rig.fx.way, east: 900, speed: 20, at: h(50)).isEmpty)
    }

    @Test func endFinishesFromAnyPhaseAndClosesTheCurrentStop() {
        var armed = RunRig()
        #expect(armed.send(.user(.end), at: h(8)).first?.to == .finished)
        #expect(armed.run.endedAt == h(8))
        var atStop = RunRig(at: RunFixture().s1, alreadyThere: true, now: h(9.6))
        atStop.send(.user(.end), at: h(10))
        #expect(atStop.run.phase == .finished)
        #expect(atStop.visit(atStop.fx.s1).status == .done && atStop.visit(atStop.fx.s1).leftAt == h(10))
        var driving = RunRig.driving(to: RunFixture().s1)
        driving.send(.user(.end), at: h(9))
        #expect(driving.run.phase == .finished && driving.visit(driving.fx.s1).status == .enRoute)
        var paused = RunRig()
        paused.send(.user(.pause), at: h(8))
        #expect(paused.send(.user(.end), at: h(8.5)).first?.to == .finished)
    }

    @Test func pauseBlocksAutomaticTransitionsAndResumeRestores() {
        var rig = RunRig()
        let lb = rig.leaveBy(of: rig.fx.s1)
        let out = rig.send(.user(.pause), at: h(8))
        #expect(rig.run.phase == .paused && rig.run.pausedFrom == .armed)
        #expect(out[0].from == .armed && out[0].to == .paused)
        #expect(rig.send(.tick, at: lb.addingTimeInterval(60)).isEmpty)
        #expect(rig.fix(RunFixture.offset(rig.fx.home.coordinate, east: 5000), speed: 30, at: lb).isEmpty)
        #expect(rig.send(.user(.leaveNow), at: lb).isEmpty)
        #expect(rig.run.phase == .paused)
        let back = rig.send(.user(.resume), at: lb.addingTimeInterval(120))
        #expect(rig.run.phase == .armed && rig.run.pausedFrom == nil && back[0].to == .armed)
        #expect(rig.send(.tick, at: lb.addingTimeInterval(130)).first?.to == .driving)
    }

    @Test func pausedRunReportsItsRealProgress() {
        var rig = RunRig(at: RunFixture().s1, alreadyThere: true, now: h(9.6))
        rig.send(.user(.pause), at: h(9.7))
        #expect(rig.run.activePhase == .atStop)
        #expect(rig.run.progress.atCurrentStop)
        rig.send(.user(.resume), at: h(9.8))
        #expect(rig.run.phase == .atStop)
    }

    @Test func resumeOutsideAPauseDoesNothing() {
        var rig = RunRig()
        #expect(rig.send(.user(.resume), at: h(8)).isEmpty)
    }
}
