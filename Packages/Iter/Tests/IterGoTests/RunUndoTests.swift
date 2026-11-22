import Foundation
import Testing
import IterGo
import IterModel
import IterPlan

private func h(_ x: Double) -> Date { RunFixture.h(x) }

/// The run with its suppressions cleared, to compare a restored run with the one before the transition.
private func bare(_ run: TripRun) -> TripRun {
    var r = run
    r.suppressions = []
    return r
}

@Suite struct RunUndoTests {
    @Test func timeDepartureUndoRestoresExactlyAndSuppressesTimeForTheRestOfTheRun() {
        var rig = RunRig()
        let before = rig.run
        let lb = rig.leaveBy(of: rig.fx.s1)
        rig.send(.tick, at: lb)
        let out = rig.send(.user(.notYet), at: lb.addingTimeInterval(60))
        #expect(out.count == 1 && out[0].cause == .user && !out[0].automatic && out[0].from == .driving && out[0].to == .armed)
        #expect(out[0].visitChanges == [before.visits[rig.fx.s1.id]!])
        #expect(bare(rig.run) == before)
        #expect(rig.run.pendingUndo == nil)
        #expect(rig.run.suppressions.count == 1)
        // Time never fires again for that stop...
        #expect(rig.send(.tick, at: lb.addingTimeInterval(3600)).isEmpty)
        #expect(rig.send(.tick, at: h(30)).isEmpty)
        // ... but motion still can.
        let motion = rig.fix(RunFixture.offset(rig.fx.home.coordinate, east: 900), speed: 10, at: lb.addingTimeInterval(4000))
        #expect(motion.first?.cause == .motion)
    }

    @Test func motionUndoSuppressesUntilTheFixIsBackNearTheOrigin() {
        var rig = RunRig()
        let before = rig.run
        let far = RunFixture.offset(rig.fx.home.coordinate, east: 900)
        rig.fix(far, speed: 10, at: h(8))
        #expect(rig.send(.user(.notYet), at: h(8.01)).count == 1)
        #expect(bare(rig.run) == before)
        #expect(rig.fix(far, speed: 10, at: h(8.02)).isEmpty)
        #expect(rig.fix(far, speed: 10, at: h(8.03)).isEmpty)
        #expect(rig.fix(RunFixture.offset(rig.fx.home.coordinate, east: 100), speed: 10, at: h(8.04)).isEmpty)
        #expect(rig.run.suppressions.isEmpty)
        #expect(rig.fix(far, speed: 10, at: h(8.05)).first?.cause == .motion)
    }

    @Test func enterUndoSuppressesUntilAFixIsOutside() {
        var rig = RunRig.driving(to: RunFixture().s1)
        let before = rig.run
        let enter = rig.fix(near: rig.fx.s1, east: 50, speed: 0.5, at: h(9))
        #expect(enter.count == 1)
        rig.send(.user(.notYet), at: h(9.01))
        #expect(bare(rig.run) == before)
        #expect(rig.fix(near: rig.fx.s1, east: 50, speed: 0.5, at: h(9.02)).isEmpty)
        #expect(rig.fix(near: rig.fx.s1, east: 60, speed: 0.5, at: h(9.2)).isEmpty)
        #expect(rig.fix(near: rig.fx.s1, east: 600, speed: 0.5, at: h(9.3)).isEmpty)
        #expect(rig.run.suppressions.isEmpty)
        #expect(rig.fix(near: rig.fx.s1, east: 50, speed: 0.5, at: h(9.4)).count == 1)
    }

    @Test func exitUndoRestoresTheStopAndSuppressesUntilAFixIsInsideTheExitRadius() {
        var rig = RunRig(at: RunFixture().s1, alreadyThere: true, now: h(9.6))
        let before = rig.run
        rig.fix(near: rig.fx.s1, east: 600, at: h(10))
        let exit = rig.fix(near: rig.fx.s1, east: 600, at: h(10).addingTimeInterval(40))
        #expect(exit.first?.to == .driving)
        let out = rig.send(.user(.notYet), at: h(10).addingTimeInterval(70))
        #expect(out.first?.to == .atStop)
        #expect(Set(out[0].visitChanges.map(\.stopID)) == [rig.fx.s1.id, rig.fx.s2.id])
        #expect(bare(rig.run) == before)
        // Still outside: suppressed, however long.
        for i in 0..<5 { #expect(rig.fix(near: rig.fx.s1, east: 700, at: h(11 + Double(i) * 0.1)).isEmpty) }
        // A fix inside the exit radius re-arms the trigger.
        #expect(rig.fix(near: rig.fx.s1, east: 100, at: h(12)).isEmpty)
        #expect(rig.run.suppressions.isEmpty)
        #expect(rig.fix(near: rig.fx.s1, east: 700, at: h(12.1)).isEmpty)
        #expect(rig.fix(near: rig.fx.s1, east: 700, at: h(12.1).addingTimeInterval(40)).first?.to == .driving)
    }

    @Test func stopEndByTimeUndoSuppressesThatTimeTriggerForTheRestOfTheRun() {
        var rig = RunRig(at: RunFixture().s1, alreadyThere: true, now: h(9.6))
        let before = rig.run
        rig.send(.tick, at: h(11))
        #expect(rig.run.phase == .betweenStops)
        rig.send(.user(.notYet), at: h(11.01))
        #expect(bare(rig.run) == before)
        #expect(rig.send(.tick, at: h(11.5)).isEmpty)
        #expect(rig.send(.tick, at: h(20)).isEmpty)
        #expect(rig.send(.user(.doneHere), at: h(20)).count == 1)
    }

    @Test func overnightLodgingTimeUndoWorks() {
        var rig = RunRig(at: RunFixture().hotel, alreadyThere: true, now: h(19))
        let before = rig.run
        let lb = rig.fx.live(rig.run, at: h(26)).next!.leaveBy!
        rig.send(.tick, at: lb)
        #expect(rig.run.phase == .driving)
        rig.send(.user(.notYet), at: lb.addingTimeInterval(10))
        #expect(bare(rig.run) == before)
        #expect(rig.send(.tick, at: lb.addingTimeInterval(600)).isEmpty)
    }

    @Test func undoWorksUpToButNotAtExpiry() {
        var rig = RunRig()
        let lb = rig.leaveBy(of: rig.fx.s1)
        rig.send(.tick, at: lb)
        #expect(rig.run.undoExpiry(at: lb.addingTimeInterval(119)) == lb.addingTimeInterval(120))
        #expect(rig.run.undoExpiry(at: lb.addingTimeInterval(120)) == nil)
        let late = rig.send(.user(.notYet), at: lb.addingTimeInterval(120))
        #expect(late.isEmpty)
        #expect(rig.run.phase == .driving)
        #expect(rig.run.pendingUndo == nil)
        #expect(rig.run.suppressions.isEmpty)
    }

    @Test func notYetAfterExpiryDoesNothingEvenAfterAnotherEvent() {
        var rig = RunRig()
        let lb = rig.leaveBy(of: rig.fx.s1)
        rig.send(.tick, at: lb)
        rig.send(.tick, at: lb.addingTimeInterval(500))
        #expect(rig.run.pendingUndo == nil)
        #expect(rig.send(.user(.notYet), at: lb.addingTimeInterval(501)).isEmpty)
    }

    @Test func aUserActionClearsThePendingUndo() {
        var rig = RunRig()
        let lb = rig.leaveBy(of: rig.fx.s1)
        rig.send(.tick, at: lb)
        #expect(rig.run.pendingUndo != nil)
        rig.send(.user(.arrived), at: lb.addingTimeInterval(10))
        #expect(rig.run.pendingUndo == nil)
        #expect(rig.send(.user(.notYet), at: lb.addingTimeInterval(20)).isEmpty)
        #expect(rig.run.phase == .atStop)
    }

    @Test func aNoOpUserActionKeepsThePendingUndo() {
        var rig = RunRig()
        let lb = rig.leaveBy(of: rig.fx.s1)
        rig.send(.tick, at: lb)
        #expect(rig.send(.user(.doneHere), at: lb.addingTimeInterval(5)).isEmpty)
        #expect(rig.run.pendingUndo != nil)
        #expect(rig.send(.user(.notYet), at: lb.addingTimeInterval(10)).count == 1)
    }

    @Test func notYetWithNothingToUndoIsEmpty() {
        var rig = RunRig()
        #expect(rig.send(.user(.notYet), at: h(8)).isEmpty)
        rig.send(.user(.leaveNow), at: h(8))
        #expect(rig.send(.user(.notYet), at: h(8.01)).isEmpty)   // a user transition has no undo
        #expect(rig.run.phase == .driving)
    }

    @Test func undoingTheAutomaticFinishRestoresTheStop() {
        var rig = RunRig(at: RunFixture().way, alreadyThere: true, now: h(40))
        let before = rig.run
        rig.send(.tick, at: h(40).addingTimeInterval(1800))
        #expect(rig.run.phase == .finished)
        let out = rig.send(.user(.notYet), at: h(40).addingTimeInterval(1830))
        #expect(out.count == 1)
        #expect(bare(rig.run) == before)
        #expect(rig.run.endedAt == nil)
    }
}

@Suite struct RunJitterTests {
    /// Feeds a trace of (east metres from `stop`, seconds) and counts transitions.
    private func run(_ rig: inout RunRig, around stop: Stop, trace: [(Double, Double)], speed: Double? = 5) -> [RunTransition] {
        var all: [RunTransition] = []
        let base = h(9)
        for (east, t) in trace { all += rig.fix(near: stop, east: east, speed: speed, at: base.addingTimeInterval(t)) }
        return all
    }

    @Test func alternatingAroundTheEnterBoundaryNeverEnters() {
        var rig = RunRig.driving(to: RunFixture().s1)
        // 150 m radius, 5 m accuracy: inside <= 155 m. Alternate 140 / 170 every 10 s.
        let trace = (0..<60).map { (i: Int) in (i.isMultiple(of: 2) ? 140.0 : 170.0, Double(i) * 10) }
        #expect(run(&rig, around: rig.fx.s1, trace: trace).isEmpty)
    }

    @Test func hoveringJustInsideTheEnterBoundaryEntersExactlyOnce() {
        var rig = RunRig.driving(to: RunFixture().s1)
        let trace = (0..<60).map { (i: Int) in (150.0 + Double(i % 3) * 2, Double(i) * 5) }   // 150-154 m, all inside
        let out = run(&rig, around: rig.fx.s1, trace: trace)
        #expect(out.count == 1 && out[0].to == .atStop)
        #expect(rig.run.phase == .atStop)
    }

    @Test func jitterAfterEnteringAcrossTheEnterBoundaryNeverLeaves() {
        var rig = RunRig.driving(to: RunFixture().s1)
        rig.fix(near: rig.fx.s1, east: 100, speed: 0.5, at: h(9))
        let trace = (0..<80).map { (i: Int) in (i.isMultiple(of: 2) ? 120.0 : 200.0, Double(i) * 7) }
        #expect(run(&rig, around: rig.fx.s1, trace: trace).isEmpty)
        #expect(rig.run.phase == .atStop)
    }

    @Test func alternatingAroundTheExitBoundaryNeverLeaves() {
        var rig = RunRig(at: RunFixture().s1, alreadyThere: true, now: h(8.9))
        // Exit radius 400 m: alternate 380 / 420 every 15 s: no two consecutive outside fixes.
        let trace = (0..<60).map { (i: Int) in (i.isMultiple(of: 2) ? 380.0 : 420.0, Double(i) * 15) }
        #expect(run(&rig, around: rig.fx.s1, trace: trace, speed: nil).isEmpty)
        #expect(rig.run.phase == .atStop)
    }

    @Test func hoveringJustOutsideTheExitBoundaryLeavesExactlyOnce() {
        var rig = RunRig(at: RunFixture().s1, alreadyThere: true, now: h(8.9))
        let trace = (0..<60).map { (i: Int) in (405.0 + Double(i % 3) * 3, Double(i) * 5) }
        let out = run(&rig, around: rig.fx.s1, trace: trace, speed: nil)
        #expect(out.count == 1 && out[0].to == .driving)
        #expect(rig.run.targetStopID == rig.fx.s2.id)
    }

    @Test func aThreeFixWobbleAroundExitStillSingleTransitionAfterUndo() {
        var rig = RunRig(at: RunFixture().s1, alreadyThere: true, now: h(8.9))
        rig.fix(near: rig.fx.s1, east: 410, at: h(9))
        #expect(rig.fix(near: rig.fx.s1, east: 410, at: h(9).addingTimeInterval(35)).count == 1)
        rig.send(.user(.notYet), at: h(9).addingTimeInterval(36))
        let trace = (0..<40).map { (i: Int) in (i.isMultiple(of: 2) ? 395.0 : 415.0, 40 + Double(i) * 10) }
        #expect(run(&rig, around: rig.fx.s1, trace: trace, speed: nil).isEmpty)
        #expect(rig.run.phase == .atStop)
    }
}
