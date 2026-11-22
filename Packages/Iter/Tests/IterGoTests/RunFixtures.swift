import Foundation
import IterGo
import IterModel
import IterPlan

/// A small trip on a straight east-west line from home, and a harness that feeds the state machine the way the engine does.
struct RunFixture {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    static func h(_ hours: Double) -> Date { t0.addingTimeInterval(hours * 3600) }

    static let origin = Coordinate(latitude: 40, longitude: -110)
    /// A point `east` metres from `from` (and `north` metres north).
    static func offset(_ from: Coordinate, east: Double = 0, north: Double = 0) -> Coordinate {
        Coordinate(latitude: from.latitude + north / 111_195, longitude: from.longitude + east / (111_195 * cos(from.latitude * .pi / 180)))
    }

    static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }

    static func place(_ name: String, east: Double) -> Place {
        Place(name: name, coordinate: offset(origin, east: east), timeZoneIdentifier: "UTC", category: .landscape, origin: .user)
    }

    let home = RunFixture.place("Home", east: 0)
    let s1: Stop       // light, day 0, 10:00-11:00
    let s2: Stop       // light, day 0, 17:00-18:00
    let hotel: Stop    // overnight lodging, day 0
    let s3: Stop       // light, day 1, 06:00-07:00
    let way: Stop      // waypoint, day 1, 30 min dwell
    let trip: Trip
    let windows: SessionWindows

    init() {
        s1 = Stop(id: RunFixture.id(1), place: RunFixture.place("S1", east: 20_000), dayIndex: 0, session: .goldenMorning)
        s2 = Stop(id: RunFixture.id(2), place: RunFixture.place("S2", east: 40_000), dayIndex: 0, session: .goldenEvening)
        hotel = Stop(id: RunFixture.id(3), place: RunFixture.place("Hotel", east: 41_000), dayIndex: 0, session: .goldenEvening, kind: .lodging)
        s3 = Stop(id: RunFixture.id(4), place: RunFixture.place("S3", east: 80_000), dayIndex: 1, session: .goldenMorning)
        way = Stop(id: RunFixture.id(5), place: RunFixture.place("Way", east: 100_000), dayIndex: 1, session: .goldenMorning, dwellMinutes: 30, kind: .waypoint)
        trip = Trip(id: RunFixture.id(100), name: "Run", startDay: LocalDay(year: 2027, month: 1, day: 1), dayCount: 2, stops: [s1, s2, hotel, s3, way],
                    startPlaceID: home.id)
        windows = [
            s1.id: TimeSpan(start: RunFixture.h(10), end: RunFixture.h(11)),
            s2.id: TimeSpan(start: RunFixture.h(17), end: RunFixture.h(18)),
            s3.id: TimeSpan(start: RunFixture.h(30), end: RunFixture.h(31)),
        ]
    }

    func live(_ run: TripRun, at now: Date) -> LiveSchedule {
        LiveSchedule.make(trip: trip, start: home, windows: windows, plannedLegs: [:], progress: run.progress, now: now, origin: nil, liveETAs: [:])
    }

    func fix(_ c: Coordinate, acc: Double = 5, speed: Double? = nil, at t: Date) -> LocationFix {
        LocationFix(coordinate: c, accuracyM: acc, speedMs: speed, timestamp: t)
    }
}

struct RunRig {
    var fx = RunFixture()
    var run: TripRun
    var hasStart = true

    init(at stop: Stop? = nil, alreadyThere: Bool = false, now: Date = RunFixture.h(0)) {
        let fx = RunFixture()
        self.fx = fx
        run = TripRun.start(trip: fx.trip, runID: UUID(), at: stop?.id, now: now, alreadyThere: alreadyThere)
    }

    /// Armed, or at a stop, or driving to it.
    static func driving(to stop: Stop, now: Date = RunFixture.h(8)) -> RunRig {
        var rig = RunRig(at: stop, now: now)
        rig.send(.user(.leaveNow), at: now)
        return rig
    }

    func context(at now: Date) -> RunContext {
        RunContext(trip: fx.trip, live: fx.live(run, at: now), now: now, startCoordinate: hasStart ? fx.home.coordinate : nil)
    }

    @discardableResult
    mutating func send(_ event: RunEvent, at now: Date) -> [RunTransition] {
        run.handle(event, context: context(at: now))
    }

    @discardableResult
    mutating func fix(_ c: Coordinate, acc: Double = 5, speed: Double? = nil, at now: Date) -> [RunTransition] {
        send(.location(fx.fix(c, acc: acc, speed: speed, at: now)), at: now)
    }

    /// A fix `east` metres east of the stop.
    @discardableResult
    mutating func fix(near stop: Stop, east: Double, acc: Double = 5, speed: Double? = nil, at now: Date) -> [RunTransition] {
        fix(RunFixture.offset(stop.place.coordinate, east: east), acc: acc, speed: speed, at: now)
    }

    func leaveBy(of stop: Stop) -> Date { fx.live(run, at: RunFixture.h(0)).upcoming.first { $0.stopID == stop.id }!.leaveBy! }
    func visit(_ stop: Stop) -> StopVisit { run.visits[stop.id]! }
}
