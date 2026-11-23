import Foundation
import Testing
import IterGo
import IterModel
import IterPlan
@testable import IterFeatures

@MainActor
@Suite("GoModel route path")
struct GoModelRouteTests {
    private func info(_ stop: Stop, number: Int) -> GoStopInfo {
        GoStopInfo(id: stop.id, number: number, name: stop.place.name, kind: stop.kind, dayIndex: stop.dayIndex, coordinate: stop.place.coordinate,
                   timeZoneIdentifier: "UTC")
    }

    /// Legs with a bend in the middle of each, so the path is not just the stops.
    private func input() -> (GoTripInput, GoWorld, [String: Coordinate]) {
        let w = GoWorld()
        let home = w.home.coordinate, s1 = w.stops[0].place.coordinate, s2 = w.stops[1].place.coordinate
        let a = goOffset(east: 6_000), b = goOffset(east: 13_000), m = goOffset(east: 30_000)
        var i = w.input
        i.plannedLegs[LegKey(w.home.id, w.stops[0].id)]?.path = [home, a, b, s1]
        i.plannedLegs[LegKey(w.stops[0].id, w.stops[1].id)]?.path = [s1, m, s2]
        return (i, w, ["home": home, "a": a, "b": b, "s1": s1, "m": m, "s2": s2])
    }

    private func snapshot(_ w: GoWorld, phase: GoPhase, current: Int? = nil, next: Int?, here: Coordinate? = nil, schedule: Bool = false) -> GoSnapshot {
        let nextInfo = next.map { info(w.stops[$0], number: $0 + 1) }
        return GoSnapshot(generatedAt: goT0, tripID: w.trip.id, tripName: "t", runID: UUID(), phase: phase, current: current.map { info(w.stops[$0], number: $0 + 1) },
                          next: nextInfo, schedule: schedule ? next.map { n in w.stops[n...].enumerated().map { GoScheduleItem(stop: info($1, number: n + $0 + 1)) } } : nil,
                          here: here)
    }

    @Test func armedRunFollowsEveryPlannedLegFromTheStart() {
        let (i, w, p) = input()
        let path = GoModel.routePath(snapshot: snapshot(w, phase: .armed, next: 0), input: i)
        #expect(path == [p["home"]!, p["a"]!, p["b"]!, p["s1"]!, p["m"]!, p["s2"]!])
    }

    @Test func drivingStartsAtYourPositionOnTheLeg() {
        let (i, w, p) = input()
        let here = goOffset(east: 12_500)
        let path = GoModel.routePath(snapshot: snapshot(w, phase: .driving, next: 0, here: here, schedule: true), input: i)
        #expect(path == [here, p["b"]!, p["s1"]!, p["m"]!, p["s2"]!])
    }

    @Test func atAStopOnlyTheRemainingLegsRemain() {
        let (i, w, p) = input()
        let path = GoModel.routePath(snapshot: snapshot(w, phase: .atStop, current: 0, next: 1, schedule: true), input: i)
        #expect(path == [p["s1"]!, p["m"]!, p["s2"]!])
    }

    @Test func aLegWithoutAPathFallsBackToAStraightSegment() {
        var (i, w, p) = input()
        i.plannedLegs[LegKey(w.stops[0].id, w.stops[1].id)] = nil
        let path = GoModel.routePath(snapshot: snapshot(w, phase: .armed, next: 0), input: i)
        #expect(path == [p["home"]!, p["a"]!, p["b"]!, p["s1"]!, p["s2"]!])
        i.plannedLegs = [:]
        #expect(GoModel.routePath(snapshot: snapshot(w, phase: .armed, next: 0), input: i) == [p["home"]!, p["s1"]!, p["s2"]!])
    }

    @Test func noNextStopMeansNoPath() {
        let (i, w, _) = input()
        #expect(GoModel.routePath(snapshot: snapshot(w, phase: .finished, next: nil), input: i).isEmpty)
    }

    @Test func theModelExposesThePathWhileRunningOnly() async throws {
        let rig = try GoRig()
        let model = rig.model()
        #expect(model.routePath.isEmpty)
        await model.start(rig.world.input)
        let path = model.routePath
        #expect(path.first == rig.world.home.coordinate && path.last == rig.world.stops[1].place.coordinate)
        await model.end()
        #expect(model.routePath.isEmpty)
        model.stop()
    }
}
