import Foundation
import IterGo
import IterGoActivity
import IterModel
import IterPlan
import IterSky
import IterSources
import IterConditions

// The whole-trip simulation harness: every external part is a fake, time is a ManualClock, the traveller is a list of
// timestamped fixes. The harness steps virtual time in 30 s steps (fixes due by then, then tick, then settle) and records
// what the engine did.

/// 2027-01-15 00:00 UTC.
let simT0 = Date(timeIntervalSince1970: 1_799_971_200)
func simH(_ hours: Double) -> Date { simT0.addingTimeInterval(hours * 3600) }
let simUTC = TimeZone(identifier: "UTC")!

// MARK: World

struct SimStopSpec {
    var name: String
    var eastKm: Double
    var kind: StopKind = .light
    var session: LightWindowKind = .goldenEvening
    var day: Int = 0
    /// Window in hours since `simT0` (light stops).
    var window: (Double, Double)?
    var dwell: Int = 0
    var fixedArrival: LocalTime?
}

struct SimWorld {
    var home: Place
    var stops: [Stop]
    var trip: Trip
    var windows: SessionWindows
    var plannedLegs: [LegKey: Leg]

    static let speed = 25.0   // m/s

    static func place(_ name: String, eastKm: Double) -> Place {
        Place(name: name, coordinate: RunFixture.offset(RunFixture.origin, east: eastKm * 1000), timeZoneIdentifier: "UTC", category: .landscape, origin: .user)
    }

    init(_ specs: [SimStopSpec], transfers: [Int: TransferTiming] = [:], dayCount: Int = 1, name: String = "Sim trip") {
        home = SimWorld.place("Home", eastKm: 0)
        var stops: [Stop] = []
        var windows: SessionWindows = [:]
        for (i, s) in specs.enumerated() {
            let stop = Stop(id: RunFixture.id(i + 1), place: SimWorld.place(s.name, eastKm: s.eastKm), dayIndex: s.day, session: s.session,
                            dwellMinutes: s.dwell, fixedArrival: s.fixedArrival, kind: s.kind)
            stops.append(stop)
            if let w = s.window { windows[stop.id] = TimeSpan(start: simH(w.0), end: simH(w.1)) }
        }
        self.stops = stops
        self.windows = windows
        trip = Trip(id: RunFixture.id(100), name: name, startDay: LocalDay(year: 2027, month: 1, day: 15), dayCount: dayCount, stops: stops,
                    transferTimings: transfers, startPlaceID: home.id)
        var legs: [LegKey: Leg] = [:]
        var previous: (id: UUID, coordinate: Coordinate) = (home.id, home.coordinate)
        for s in stops {
            legs[LegKey(previous.id, s.id)] = SimWorld.leg(previous.coordinate, s.place.coordinate)
            previous = (s.id, s.place.coordinate)
        }
        plannedLegs = legs
    }

    static func driveSeconds(_ a: Coordinate, _ b: Coordinate) -> TimeInterval { a.distance(to: b) * 1.3 / speed }

    static func leg(_ a: Coordinate, _ b: Coordinate) -> Leg {
        Leg(from: a, to: b, seconds: driveSeconds(a, b), meters: a.distance(to: b) * 1.3, isEstimate: false, path: [a, b])
    }

    var input: GoTripInput { GoTripInput(trip: trip, start: home, windows: windows, plannedLegs: plannedLegs) }
    func stop(_ i: Int) -> Stop { stops[i] }

    /// Fixes driving `from` to `to` starting at `start`, then parked there for `park` seconds (so the geofence enters).
    static func drive(from: Coordinate, to: Coordinate, start: Date, park: TimeInterval = 120, speed: Double = SimWorld.speed,
                      jitterM: Double = 0, seed: UInt64 = 1) -> [LocationFix] {
        let moving = LocationTrace.fixes(along: [from, to], speedMs: speed, interval: 10, start: start, accuracyM: 5, jitterM: jitterM, seed: seed)
        guard let end = moving.last else { return [] }
        return moving + LocationTrace.stationary(at: to, duration: park, interval: 10, start: end.timestamp.addingTimeInterval(10))
    }
}

// MARK: Fakes

/// A fake router with a scripted traffic function, an offline switch, optional suspension and call counting.
final class SimRouting: RoutingProvider, @unchecked Sendable {
    enum Mode: Sendable { case ok, offline, rateLimited }

    let descriptor = SourceCatalogue.appleDirections
    private let lock = NSLock()
    private let clock: ManualClock
    private var _traffic: @Sendable (Coordinate, Coordinate, Date) -> TimeInterval = { a, b, _ in SimWorld.driveSeconds(a, b) }
    private var _mode = Mode.ok
    private var _hold = false
    private var held: [UUID: CheckedContinuation<Void, any Error>] = [:]
    private var running = 0
    private(set) var maxRunning = 0
    private(set) var etaCalls = 0
    private(set) var routeCalls = 0
    private(set) var callTimes: [Date] = []
    private(set) var callOutcomes: [(at: Date, ok: Bool)] = []

    init(clock: ManualClock) { self.clock = clock }

    func setTraffic(_ f: @escaping @Sendable (Coordinate, Coordinate, Date) -> TimeInterval) { lock.withLock { _traffic = f } }
    func setMode(_ m: Mode) { lock.withLock { _mode = m } }
    func setOffline(_ v: Bool) { setMode(v ? .offline : .ok) }
    /// While held, requests suspend until `release()` (or until cancelled).
    func setHold(_ v: Bool) { lock.withLock { _hold = v } }
    var heldCount: Int { lock.withLock { held.count } }
    var calls: Int { lock.withLock { etaCalls + routeCalls } }
    func release() {
        let all = lock.withLock { () -> [CheckedContinuation<Void, any Error>] in
            _hold = false
            defer { held = [:] }
            return Array(held.values)
        }
        for c in all { c.resume() }
    }

    private func begin(isRoute: Bool, from: Coordinate, to: Coordinate, departing: Date) async throws -> TimeInterval {
        let (mode, hold, traffic) = lock.withLock { () -> (Mode, Bool, @Sendable (Coordinate, Coordinate, Date) -> TimeInterval) in
            if isRoute { routeCalls += 1 } else { etaCalls += 1 }
            callTimes.append(clock.now)
            running += 1
            maxRunning = max(maxRunning, running)
            return (_mode, _hold, _traffic)
        }
        defer { lock.withLock { running -= 1 } }
        if hold {
            let id = UUID()
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
                    lock.withLock { held[id] = c }
                }
            } onCancel: {
                let c = lock.withLock { held.removeValue(forKey: id) }
                c?.resume(throwing: CancellationError())
            }
        }
        switch mode {
        case .ok:
            lock.withLock { callOutcomes.append((clock.now, true)) }
            return traffic(from, to, departing)
        case .offline:
            lock.withLock { callOutcomes.append((clock.now, false)) }
            throw SourceError.offline
        case .rateLimited:
            lock.withLock { callOutcomes.append((clock.now, false)) }
            throw SourceError.rateLimited(retryAfter: nil)
        }
    }

    func route(from: Coordinate, to: Coordinate, departing: Date?) async throws -> Route {
        let s = try await begin(isRoute: true, from: from, to: to, departing: departing ?? clock.now)
        return Route(path: [from, to], seconds: s, meters: from.distance(to: to) * 1.3, departing: departing, isTrafficAware: true)
    }

    func eta(from: Coordinate, to: Coordinate, departing: Date) async throws -> ETA {
        let s = try await begin(isRoute: false, from: from, to: to, departing: departing)
        return ETA(seconds: s, arrival: departing.addingTimeInterval(s), departing: departing)
    }
}

/// A number the test changes while the router is asking (traffic factor).
final class SimKnob: @unchecked Sendable {
    private let lock = NSLock()
    private var v: Double
    init(_ v: Double = 1) { self.v = v }
    var value: Double { get { lock.withLock { v } } set { lock.withLock { v = newValue } } }
}

/// Scripted conditions: a score per place over time, observation present or absent, an offline switch.
final class SimConditions: TripConditionsProviding, @unchecked Sendable {
    private let lock = NSLock()
    private let clock: ManualClock
    private var _score: @Sendable (UUID, Date) -> Int? = { _, _ in 60 }
    private var _observation = true
    private var _offline = false
    private var windows: [UUID: TimeSpan] = [:]
    private var _packBuilt: [UUID: Date] = [:]
    private(set) var liveCalls: [(at: Date, place: UUID)] = []
    private(set) var reportCalls: [(at: Date, place: UUID)] = []
    private(set) var packCalls: [Date] = []

    init(clock: ManualClock, world: SimWorld) {
        self.clock = clock
        for s in world.stops { if let w = world.windows[s.id] { windows[s.place.id] = w } }
    }

    func setScore(_ f: @escaping @Sendable (UUID, Date) -> Int?) { lock.withLock { _score = f } }
    func setObservation(_ v: Bool) { lock.withLock { _observation = v } }
    func setOffline(_ v: Bool) { lock.withLock { _offline = v } }
    var totalCalls: Int { lock.withLock { liveCalls.count + reportCalls.count + packCalls.count } }

    private func window(_ kind: LightWindowKind, score: Int?, span: TimeSpan, at: Date) -> LightWindow {
        guard let score else { return LightWindow(kind: kind, span: span, assessment: .unavailable(.beyondHorizon)) }
        let s = SkyScore(value: score, band: LightBand(score: score), confidence: .medium, confidenceValue: 0.5, range: 0...100, contributors: [],
                         forecastFetchedAt: at, leadHours: 4, age: 0, isStale: false)
        return LightWindow(kind: kind, span: span, assessment: .scored(s))
    }

    func live(for place: Place, target: LightWindowKind?, priority: ConditionsPriority) async -> LiveConditions {
        let now = clock.now
        let (score, obs, offline, span) = lock.withLock { () -> (Int?, Bool, Bool, TimeSpan?) in
            liveCalls.append((now, place.id))
            return (_score(place.id, now), _observation, _offline, windows[place.id])
        }
        let reading = LiveSkyReading(kind: target, window: score == nil ? nil : span, score: score, band: score.map { LightBand(score: $0) },
                                     forecastScore: score, trend: .steady, state: score == nil ? .noData : (obs ? .blended : .forecastOnly),
                                     age: obs ? 300 : nil, confidence: .high, isStale: false)
        let hour = HourlyConditions(time: now, cloudTotal: 0.3, cloudHigh: 0.1)
        let current = obs && !offline ? CurrentObservation(conditions: hour, stationName: "Test station", distanceKm: 8, age: 300,
                                                           provenance: cProvenance(at: now)) : nil
        return LiveConditions(placeID: place.id, generatedAt: now, reading: reading, current: current, currentForecastHour: current == nil ? hour : nil,
                              strip: [], notice: nil, nowcast: offline ? .none([.offline(lastGood: nil)]) : .none([]), observations: .none([]),
                              forecastTier: .complete, forecastOfflineNote: nil)
    }

    func report(for place: Place, day: LocalDay, priority: ConditionsPriority) async -> SkyReport {
        let now = clock.now
        let (score, offline, span) = lock.withLock { () -> (Int?, Bool, TimeSpan) in
            reportCalls.append((now, place.id))
            return (_score(place.id, now), _offline, windows[place.id] ?? TimeSpan(start: now, end: now.addingTimeInterval(3600)))
        }
        return cReport(place, windows: LightWindowKind.allCases.map { window($0, score: score, span: span, at: now) },
                       offlineNote: offline ? "Forecast from earlier, offline" : nil, generatedAt: now)
    }

    func buildTripPack(for trip: Trip) async throws -> Date {
        let now = clock.now
        lock.withLock { packCalls.append(now); _packBuilt[trip.id] = now }
        return now
    }

    func packBuiltAt(tripID: UUID) async -> Date? { lock.withLock { _packBuilt[tripID] } }
}

final class SimPower: PowerMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private var state: PowerState
    init(_ s: PowerState = .normal) { state = s }
    func set(_ s: PowerState) { lock.withLock { state = s } }
    func current() -> PowerState { lock.withLock { state } }
}

// MARK: Harness

struct SimNotificationEvent {
    var at: Date
    var call: FakeNotificationScheduler.Call
}

struct SimFired {
    var at: Date
    var request: GoNotificationRequest
    var immediate: Bool
}

@MainActor
final class SimHarness {
    let world: SimWorld
    let clock: ManualClock
    let routing: SimRouting
    let conditions: SimConditions
    let location: ScriptedLocation
    let notifications = FakeNotificationScheduler()
    let activity: FakeLiveActivityController
    let store = InMemorySnapshotStore()
    let reloader = FakeWidgetReloader()
    let persistence = InMemoryRunPersistence()
    let engineState = InMemoryEngineStateStore()
    let background = FakeBackgroundScheduler()
    let power = SimPower()
    private(set) var engine: GoEngine

    private(set) var snapshots: [GoSnapshot] = []
    private(set) var notificationLog: [SimNotificationEvent] = []
    private(set) var fired: [SimFired] = []
    private var loggedCalls = 0
    private var firedKeys = Set<String>()
    private var loggedImmediates = 0
    /// (time, backoff-until) as the engine reported after each step.
    private(set) var backoffs: [(at: Date, until: Date)] = []
    var pendingFixes: [LocationFix] = []
    var step: TimeInterval = 30

    init(_ world: SimWorld, start: Date = simH(8)) {
        self.world = world
        clock = ManualClock(start)
        routing = SimRouting(clock: clock)
        conditions = SimConditions(clock: clock, world: world)
        location = ScriptedLocation(clock: clock, authorization: .whenInUse)
        let c = clock
        activity = FakeLiveActivityController(clock: { c.now })
        engine = GoEngine(SimHarness.deps(clock: clock, routing: routing, conditions: conditions, location: location, notifications: notifications,
                                           activity: activity, store: store, reloader: reloader, persistence: persistence, engineState: engineState,
                                           power: power, background: background))
        attach()
    }

    private static func deps(clock: ManualClock, routing: SimRouting, conditions: SimConditions, location: ScriptedLocation,
                             notifications: FakeNotificationScheduler, activity: FakeLiveActivityController, store: InMemorySnapshotStore,
                             reloader: FakeWidgetReloader, persistence: InMemoryRunPersistence, engineState: InMemoryEngineStateStore,
                             power: SimPower, background: FakeBackgroundScheduler) -> GoEngineDependencies {
        GoEngineDependencies(clock: clock, routing: routing, conditions: conditions, location: location, notifications: notifications,
                             activity: activity, snapshotStore: store, widgetReloader: reloader, persistence: persistence, engineState: engineState,
                             power: power, background: background)
    }

    private func attach() {
        engine.onSnapshot = { [weak self] s in self?.snapshots.append(s) }
    }

    /// A fresh engine on the same persistence, state store and notification centre (an app relaunch). The old engine is stopped.
    func relaunch() {
        engine.stop()
        engine = GoEngine(SimHarness.deps(clock: clock, routing: routing, conditions: conditions, location: location, notifications: notifications,
                                           activity: activity, store: store, reloader: reloader, persistence: persistence, engineState: engineState,
                                           power: power, background: background))
        attach()
    }

    // MARK: Driving the clock

    func start(at index: Int? = nil, alreadyThere: Bool = false) async {
        await engine.start(world.input, at: index.map { world.stops[$0].id }, alreadyThere: alreadyThere)
        await engine.settle()
        record()
    }

    func feed(_ fixes: [LocationFix]) {
        pendingFixes.append(contentsOf: fixes)
        pendingFixes.sort { $0.timestamp < $1.timestamp }
    }

    /// Notifications scheduled for a time that has now passed fire (the system does that, not the app).
    private func moveClock(to t: Date) {
        guard t > clock.now else { return }
        for (id, req) in notifications.pending.sorted(by: { ($0.value.fireAt ?? .distantPast, $0.key) < ($1.value.fireAt ?? .distantPast, $1.key) }) {
            guard let at = req.fireAt, at <= t else { continue }
            let key = "\(id)@\(at.timeIntervalSince1970)"
            if firedKeys.insert(key).inserted { fired.append(SimFired(at: at, request: req, immediate: false)) }
        }
        clock.set(t)
    }

    private func record() {
        if let b = engine.etaBackoffUntil, backoffs.last?.until != b { backoffs.append((clock.now, b)) }
        let calls = notifications.calls
        if calls.count > loggedCalls {
            for c in calls[loggedCalls...] { notificationLog.append(SimNotificationEvent(at: clock.now, call: c)) }
            loggedCalls = calls.count
        }
        let delivered = notifications.delivered
        if delivered.count > loggedImmediates {
            for r in delivered[loggedImmediates...] { fired.append(SimFired(at: clock.now, request: r, immediate: true)) }
            loggedImmediates = delivered.count
        }
    }

    /// Steps virtual time to `target`.
    func advance(to target: Date) async {
        while clock.now < target {
            let next = min(clock.now.addingTimeInterval(step), target)
            while let fix = pendingFixes.first, fix.timestamp <= next {
                pendingFixes.removeFirst()
                moveClock(to: fix.timestamp)
                await engine.ingest(.fix(fix))
                await engine.settle()
                record()
            }
            moveClock(to: next)
            await engine.tick()
            await engine.settle()
            record()
        }
    }

    func advance(by seconds: TimeInterval) async { await advance(to: clock.now.addingTimeInterval(seconds)) }

    /// A user action at the current time.
    func perform(_ action: RunUserAction) async {
        await engine.perform(action)
        await engine.settle()
        record()
    }

    // MARK: Queries

    var run: TripRun? { engine.run }
    var last: GoSnapshot { engine.snapshot }

    /// The phases the snapshots went through, consecutive repeats dropped.
    var phases: [GoPhase] {
        var out: [GoPhase] = []
        for s in snapshots where out.last != s.phase { out.append(s.phase) }
        return out
    }

    var added: [(at: Date, request: GoNotificationRequest)] {
        notificationLog.compactMap { if case .add(let r) = $0.call { ($0.at, r) } else { nil } }
    }
    func adds(_ kind: GoNotificationKind, stop: Int? = nil) -> [(at: Date, request: GoNotificationRequest)] {
        added.filter { $0.request.kind == kind && (stop == nil || $0.request.stopID == world.stops[stop!].id) }
    }
    func firedRequests(_ kind: GoNotificationKind, stop: Int? = nil) -> [SimFired] {
        fired.filter { $0.request.kind == kind && (stop == nil || $0.request.stopID == world.stops[stop!].id) }
    }
    var immediates: [SimFired] { fired.filter(\.immediate) }

    /// ETA requests (started, finished) with the phase the engine was in when each started.
    var etaRequests: [(start: Date, finish: Date?, phase: GoPhase?, kind: ETARequestKind)] {
        engine.etaRequestLog.map { r in
            let phase = snapshots.last { $0.generatedAt <= r.startedAt }?.phase
            return (r.startedAt, r.finishedAt, phase, r.kind)
        }
    }

    /// The most requests started in any window of `length` seconds, counting only requests whose phase is in `phases`.
    func maxETARequests(inWindow length: TimeInterval = 3600, phases: Set<GoPhase>? = nil) -> Int {
        let starts = etaRequests.filter { phases == nil || ($0.phase.map(phases!.contains) ?? false) }.map(\.start)
        var best = 0
        for (i, s) in starts.enumerated() {
            best = max(best, starts[i...].prefix { $0 < s.addingTimeInterval(length) }.count)
        }
        return best
    }

    /// Conditions fetch items in the busiest window of `length`.
    func maxConditionsItems(inWindow length: TimeInterval = 3600) -> Int {
        let entries = engine.conditionsFetchLog.flatMap { rec in rec.items.map { _ in rec.at } }.sorted()
        var best = 0
        for (i, s) in entries.enumerated() { best = max(best, entries[i...].prefix { $0 < s.addingTimeInterval(length) }.count) }
        return best
    }

    func snapshot(at date: Date) -> GoSnapshot? { snapshots.last { $0.generatedAt <= date } }
}

extension SimHarness {
    /// Debug aid: one line about where things stand.
    func dump(_ label: String) {
        let f = DateFormatter(); f.dateFormat = "d HH:mm:ss"; f.timeZone = simUTC
        func t(_ d: Date?) -> String { d.map { f.string(from: $0) } ?? "-" }
        let s = last
        print("DUMP \(label) @\(t(clock.now)) phase=\(s.phase) next=\(s.next?.name ?? "-") status=\(s.leave.map { "\($0.status)" } ?? "-") leaveBy=\(t(s.leave?.leaveBy)) drive=\(s.drive.map { "\(Int($0.driveSeconds))s \($0.source)" } ?? "-") imm=\(immediates.map { $0.request.kind.rawValue }) offline=\(s.freshness.isOffline)")
    }
}
