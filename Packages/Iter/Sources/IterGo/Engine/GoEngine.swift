import Foundation
import IterGoActivity
import IterModel
import IterPlan
import IterSources

/// One conditions loop run, for the request budget.
public struct ConditionsFetchRecord: Hashable, Sendable {
    public var at: Date
    public var items: [ConditionsItem]
    public var requestCount: Int
}

/// The trip-mode engine: runs the parts (run state machine, live location, ETA refresher, conditions loop, notification
/// planner, Live Activity, snapshot) together (BLUEPRINT §10).
///
/// **One step** (shared by `tick`, `ingest`, `perform`, `foreground`, `backgroundRefresh` and the completion of in-flight work):
/// 1. compute the live schedule from the run's progress (origin = last usable fix; live ETA if fresh, offline estimate if not);
/// 2. feed the event to `TripRun.handle`; persist its transitions; recompute the schedule if one happened;
/// 3. apply `LocationPolicy.mode` to the location, only when it changed;
/// 4. ask the `ETARefresher` (scheduled, or forced; a route request on a deviation of over 1 km while driving);
/// 5. start the `ConditionsLoop` if anything is due (single flight, in a task; its completion runs another step);
/// 6. build the snapshot, plan and sync notifications (alarms, Evening Before, conditions notices, automatic arrival),
///    publish the snapshot, apply the Live Activity, persist `GoEngineState`, and ask for the next background refresh.
///
/// **ETA freshness rule.** A held live ETA feeds the schedule when it is for the next stop and
/// - not driving: younger than max(15 min, 2 x the current refresh cadence) and the fix is within 2 km of where it was asked;
/// - driving: younger than 15 min, and the fix is not farther from the stop than where it was asked (+2 km). It is rescaled by
///   progress: seconds x (distance now to the stop / distance when asked), capped at 1, so a stopped car keeps its ETA and a
///   moving one counts down. Without it the planned leg scaled along its route line (`OfflineETA`) stands in, labelled
///   "offline estimate"; with no live ETA at all and no network trouble while waiting, the planned leg is used.
@MainActor
public final class GoEngine {
    public static let liveETAMaxAge: TimeInterval = 15 * 60
    public static let liveETAMaxMoveM: Double = 2_000
    public static let stationaryAfter: TimeInterval = 5 * 60
    public static let stationaryDistanceM: Double = 50
    public static let stationarySpeed: Double = 1
    public static let drivingTickInterval: TimeInterval = 60
    public static let idleTickInterval: TimeInterval = 5 * 60

    public private(set) var run: TripRun?
    public private(set) var snapshot: GoSnapshot
    /// Every snapshot as it is published.
    public let snapshots: AsyncStream<GoSnapshot>
    public var onSnapshot: (@MainActor (GoSnapshot) -> Void)?

    // Instrumentation (read-only, for tests).
    public var etaRequestLog: [ETARequestRecord] { refresher.requestLog }
    public var maxETAInFlight: Int { refresher.maxConcurrentObserved }
    public private(set) var conditionsFetchLog: [ConditionsFetchRecord] = []
    public private(set) var stepCount = 0
    public var liveETA: GoLiveETA? { lastETA }
    /// While the ETA refresher is backing off after a rate limit, when it may ask again.
    public var etaBackoffUntil: Date? { refresher.backoffUntil }

    private let deps: GoEngineDependencies
    private let refresher: ETARefresher
    private let loop: ConditionsLoop
    private let publisher: SnapshotPublisher
    private let coordinator: LiveActivityCoordinator
    private var sync: NotificationSync
    private let continuation: AsyncStream<GoSnapshot>.Continuation

    private var input: GoTripInput?
    private var lastFix: LocationFix?
    private var lastETA: GoLiveETA?
    private var routePath: [Coordinate] = []
    private var pendingOrigin: Coordinate?
    private var lastRequest: (stopID: UUID, at: Date)?
    private var processedOutcome: ETAOutcome?
    private var conditionsTask: Task<Void, Never>?
    private var pendingChanges: [ConditionsChange] = []
    private var appliedMode: LocationMode?
    private var armedAnchor: Coordinate?
    private var stationaryAnchor: LocationFix?
    private var stationarySince: Date?
    private var lastBackground: Date?
    private var backgroundCancelled = false
    private var quiescentDone: GoPhase?
    private var stopped = false
    private var loopTasks: [Task<Void, Never>] = []

    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private enum OutputMode { case always, onChange }

    public init(_ dependencies: GoEngineDependencies) {
        deps = dependencies
        refresher = ETARefresher(routing: dependencies.routing, clock: dependencies.clock)
        loop = ConditionsLoop(provider: dependencies.conditions, clock: dependencies.clock)
        publisher = SnapshotPublisher(store: dependencies.snapshotStore, reloader: dependencies.widgetReloader)
        coordinator = LiveActivityCoordinator(controller: dependencies.activity)
        sync = NotificationSync(scheduler: dependencies.notifications)
        snapshot = .idle(at: dependencies.clock.now)
        (snapshots, continuation) = AsyncStream.makeStream(of: GoSnapshot.self, bufferingPolicy: .bufferingNewest(1))
    }

    // MARK: Public API

    /// Starts a run, builds the trip's pack once, and applies everything.
    public func start(_ input: GoTripInput, at stopID: UUID?, alreadyThere: Bool) async {
        await serialized {
            self.input = input
            self.stopped = false
            let now = deps.clock.now
            let run = TripRun.start(trip: input.trip, runID: UUID(), at: stopID, now: now, alreadyThere: alreadyThere)
            self.run = run
            resetTransient()
            deps.persistence.save(run.persisted)
            deps.persistence.record(run, transitions: [])
            sync = NotificationSync(scheduler: deps.notifications)
            if deps.location.authorization == .whenInUse { deps.location.requestAlways() }
            _ = await loop.refreshPack(trip: input.trip)
            await step(.tick, startWork: true, force: false, outputs: .always)
        }
    }

    /// Relaunch: picks the trip's unfinished run back up. Nothing is re-fired: the restored ledger knows what went out.
    public func restore(_ input: GoTripInput) async -> Bool {
        await serialized {
            guard let persisted = deps.persistence.activeRun(tripID: input.trip.id) else { return false }
            self.input = input
            self.stopped = false
            let now = deps.clock.now
            let sidecar = deps.persistence.loadSidecar(runID: persisted.id)
            run = TripRun.restore(from: persisted, sidecar: sidecar, now: now)
            resetTransient()
            let saved = deps.engineState.load(runID: persisted.id)
            sync = NotificationSync(scheduler: deps.notifications, ledger: saved?.ledger ?? NotificationLedger())
            if let saved {
                loop.restore(saved.conditions)
                lastETA = saved.lastETA
                lastFix = saved.lastFix
                routePath = saved.routePath
            }
            await step(.tick, startWork: true, force: false, outputs: .always)
            return true
        }
    }

    public func perform(_ action: RunUserAction) async {
        await serialized { await step(.user(action), startWork: true, force: false, outputs: .always) }
    }

    public func ingest(_ event: LocationEvent) async {
        await serialized {
            switch event {
            case .fix(let fix):
                noteFix(fix)
                await step(.location(fix), startWork: true, force: false, outputs: .onChange)
            case .regionEntered(let id):
                // The OS says you are inside the arrival region while the phone was locked: treat it as a slow fix at the stop.
                if id == LocationPolicy.arrivalRegionID, let run, run.phase == .driving, let stop = stop(run.targetStopID) {
                    let fix = LocationFix(coordinate: stop.place.coordinate, accuracyM: 50, speedMs: 0, timestamp: deps.clock.now)
                    noteFix(fix)
                    await step(.location(fix), startWork: true, force: false, outputs: .always)
                } else {
                    await step(.tick, startWork: true, force: false, outputs: .always)
                }
            case .regionExited, .authorizationChanged:
                await step(.tick, startWork: true, force: false, outputs: .always)
            case .error:
                break
            }
        }
    }

    /// Time passed.
    public func tick() async {
        await serialized { await step(.tick, startWork: true, force: false, outputs: .always) }
    }

    /// The app came to the foreground: a forced ETA refresh (still one in flight, 30 s spacing).
    public func foreground() async {
        await serialized { await step(.tick, startWork: true, force: true, outputs: .always) }
    }

    /// A background refresh task: conditions, ETA, notifications, activity, snapshot; then asks for the next refresh. Best effort:
    /// iOS decides whether and when the task runs.
    public func backgroundRefresh() async {
        await serialized { await step(.tick, startWork: true, force: true, outputs: .always) }
        await settle()
        await serialized { await step(.tick, startWork: false, force: false, outputs: .always) }
    }

    /// Ends observation without ending the run: stops the loop, in-flight work and the location.
    public func stop() {
        stopped = true
        for t in loopTasks { t.cancel() }
        loopTasks = []
        refresher.cancel()
        conditionsTask?.cancel()
        deps.location.apply(.off)
        appliedMode = .off
    }

    /// Waits for in-flight ETA and conditions work, and for the steps their results trigger. For tests.
    public func settle() async {
        for _ in 0..<10 {
            await refresher.settle()
            if let outcome = refresher.latest { await handleOutcome(outcome) }
            if let t = conditionsTask { await t.value }
            if !refresher.isInFlight && conditionsTask == nil { break }
        }
    }

    /// The production loop: location events and ETA outcomes as they come, and a tick at each wake (see `nextWake`). Returns when
    /// the run ends, `stop()` is called or the task is cancelled. Not used by tests.
    public func runLoop() async {
        let events = deps.location.events
        let outcomes = refresher.outcomes
        let locationTask = Task { @MainActor [weak self] in
            for await event in events { await self?.ingest(event) }
        }
        let outcomeTask = Task { @MainActor [weak self] in
            for await outcome in outcomes { await self?.handleOutcome(outcome) }
        }
        loopTasks = [locationTask, outcomeTask]
        defer {
            locationTask.cancel()
            outcomeTask.cancel()
        }
        while !Task.isCancelled, !stopped, let run, run.phase != .finished {
            let wait = max(1, nextWake().timeIntervalSince(deps.clock.now))
            try? await deps.clock.sleep(for: .seconds(wait))
            if Task.isCancelled || stopped { break }
            await tick()
        }
    }

    /// The next time the loop should wake: the earliest of the ETA due, conditions due, next leave-soon and leave-by, the current
    /// window end, the undo expiry, and 60 s while driving (5 min otherwise).
    public func nextWake() -> Date {
        let now = deps.clock.now
        guard let run else { return now.addingTimeInterval(Self.idleTickInterval) }
        let live = makeLive(run, now: now)
        var c: [Date] = [now.addingTimeInterval(run.phase == .driving ? Self.drivingTickInterval : Self.idleTickInterval)]
        if let d = etaDue(run: run, live: live, now: now) { c.append(d) }
        if let d = loop.state.nextDueAt { c.append(d) }
        if let lb = live.next?.leaveBy {
            c.append(lb.addingTimeInterval(-LiveSchedule.leaveSoonLead))
            c.append(lb)
        }
        if let end = live.currentStop?.projectedDeparture { c.append(end) }
        if let u = run.undoExpiry { c.append(u) }
        return max(now.addingTimeInterval(1), c.filter { $0 > now }.min() ?? now.addingTimeInterval(1))
    }

    // MARK: Serialisation

    private func serialized<T>(_ body: () async -> T) async -> T {
        if busy {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in waiters.append(c) }
        } else {
            busy = true
        }
        let result = await body()
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
        return result
    }

    private func resetTransient() {
        lastFix = nil
        lastETA = nil
        routePath = []
        pendingOrigin = nil
        lastRequest = nil
        processedOutcome = nil
        pendingChanges = []
        appliedMode = nil
        armedAnchor = nil
        stationaryAnchor = nil
        stationarySince = nil
        lastBackground = nil
        backgroundCancelled = false
        quiescentDone = nil
        loop.restore(GoConditionsState())
        refresher.cancel()
    }

    // MARK: The step

    private func step(_ event: RunEvent, startWork: Bool, force: Bool, outputs mode: OutputMode) async {
        guard var run = self.run, let input else { return }
        stepCount += 1
        let now = deps.clock.now
        let power = deps.power.current()
        var live = makeLive(run, now: now)
        let ctx = RunContext(trip: input.trip, live: live, now: now, startCoordinate: input.start?.coordinate, lastFix: lastFix)
        let transitions = run.handle(event, context: ctx)
        self.run = run
        if !transitions.isEmpty {
            deps.persistence.record(run, transitions: transitions)
            live = makeLive(run, now: now)
            quiescentDone = nil
        }
        let phase = run.phase
        let quiescent = phase == .finished || phase == .paused || phase == .idle
        if !quiescent { quiescentDone = nil }

        applyLocationMode(run: run, live: live, now: now, power: power)
        if quiescent {
            refresher.cancel()
        } else if startWork {
            requestETA(run: run, live: live, now: now, power: power, force: force)
            startConditions(run: run, live: live, now: now, power: power)
        }

        guard mode == .always || !transitions.isEmpty else { return }
        if quiescent, quiescentDone == phase, transitions.isEmpty { return }
        await publish(run: run, live: live, now: now, power: power)
        if quiescent { quiescentDone = phase }
    }

    // MARK: Live schedule

    private func stop(_ id: UUID?) -> Stop? { id.flatMap { id in input?.trip.stops.first { $0.id == id } } }

    private var usableFix: LocationFix? { lastFix.flatMap { $0.isUsable() ? $0 : nil } }

    private func makeLive(_ run: TripRun, now: Date) -> LiveSchedule {
        guard let input else {
            let empty = Trip(name: "", startDay: LocalDay(now, in: TimeZone(identifier: "UTC") ?? .current), dayCount: 1)
            return LiveSchedule.make(trip: empty, start: nil, windows: [:], plannedLegs: [:], progress: TripProgress(), now: now, origin: nil, liveETAs: [:])
        }
        func make(_ origin: Coordinate?, _ live: [UUID: ETA], _ offline: [UUID: ETA]) -> LiveSchedule {
            LiveSchedule.make(trip: input.trip, start: input.start, windows: input.windows, plannedLegs: input.plannedLegs, progress: run.progress,
                              now: now, origin: origin, liveETAs: live, offlineETAs: offline)
        }
        let base = make(nil, [:], [:])
        guard let next = base.next, let target = stop(next.stopID) else { return base }
        let fix = usableFix
        if let eta = freshLiveETA(for: target, run: run, fix: fix, now: now) {
            return make(fix?.coordinate, [target.id: eta], [:])
        }
        if let fix, refresher.isOffline || run.phase == .driving {
            let leg = plannedLeg(into: target.id, run: run)
            let (eta, _) = OfflineETA.eta(from: fix.coordinate, to: target.place.coordinate, plannedLeg: leg, now: now)
            return make(fix.coordinate, [:], [target.id: eta])
        }
        return base
    }

    private func freshLiveETA(for target: Stop, run: TripRun, fix: LocationFix?, now: Date) -> ETA? {
        guard let held = lastETA, held.stopID == target.id else { return nil }
        let age = now.timeIntervalSince(held.fetchedAt)
        guard age >= 0 else { return nil }
        if run.phase == .driving {
            guard age < Self.liveETAMaxAge else { return nil }
            guard let fix else {
                let s = max(0, held.eta.seconds - age)
                return ETA(seconds: s, arrival: now.addingTimeInterval(s), departing: now)
            }
            let d0 = held.origin.distance(to: target.place.coordinate)
            let d1 = fix.coordinate.distance(to: target.place.coordinate)
            guard d1 <= d0 + Self.liveETAMaxMoveM else { return nil }
            let ratio = d0 > 200 ? min(1, d1 / d0) : 1
            let s = held.eta.seconds * ratio
            return ETA(seconds: s, arrival: now.addingTimeInterval(s), departing: now)
        }
        let maxAge = max(Self.liveETAMaxAge, 2 * etaCadence(run: run, leaveBy: nil, power: deps.power.current()))
        guard age < maxAge else { return nil }
        if let fix, fix.coordinate.distance(to: held.origin) > Self.liveETAMaxMoveM { return nil }
        return held.eta
    }

    private func plannedLeg(into id: UUID, run: TripRun) -> Leg? {
        guard let input else { return nil }
        let ordered = RunOrder.ordered(input.trip.stops)
        guard let i = ordered.firstIndex(where: { $0.id == id }) else { return nil }
        let previous = ordered[..<i].last { run.status(of: $0.id) != .skipped }
        let fromID = previous?.id ?? input.start?.id
        if let fromID, let leg = input.plannedLegs[LegKey(fromID, id)] { return leg }
        return input.plannedLegs.first { $0.key.to == id }?.value
    }

    // MARK: Location

    private func noteFix(_ fix: LocationFix) {
        guard fix.isUsable() else { return }
        if let last = lastFix, fix.timestamp < last.timestamp { return }
        lastFix = fix
        let slow = fix.speedMs.map { $0 < Self.stationarySpeed } ?? false
        if let anchor = stationaryAnchor {
            let near = fix.coordinate.distance(to: anchor.coordinate) < Self.stationaryDistanceM
            if !(slow || near) {
                stationaryAnchor = fix
                stationarySince = fix.timestamp
            }
        } else {
            stationaryAnchor = fix
            stationarySince = fix.timestamp
        }
    }

    /// Slow or parked for 5 min.
    private func isStationary(now: Date) -> Bool {
        guard let since = stationarySince, let last = lastFix else { return false }
        return last.timestamp.timeIntervalSince(since) >= Self.stationaryAfter
            || (now.timeIntervalSince(since) >= Self.stationaryAfter && now.timeIntervalSince(last.timestamp) < Self.stationaryAfter
                && (last.speedMs ?? 0) < Self.stationarySpeed)
    }

    private func applyLocationMode(run: TripRun, live: LiveSchedule, now: Date, power: PowerState) {
        guard let input else { return }
        let phase = run.phase
        var coordinate: Coordinate?
        var watched: (id: String, coordinate: Coordinate, radius: Double)?
        switch phase {
        case .armed:
            if armedAnchor == nil { armedAnchor = input.start?.coordinate ?? lastFix?.coordinate }
            coordinate = armedAnchor
        case .betweenStops:
            let last = run.visits.values.filter { $0.status == .done && $0.leftAt != nil }.max { $0.leftAt! < $1.leftAt! }
            coordinate = stop(last?.stopID)?.place.coordinate ?? lastFix?.coordinate ?? input.start?.coordinate
        case .driving, .atStop:
            if let s = stop(run.targetStopID) { watched = (s.id.uuidString, s.place.coordinate, GeofencePolicy.enterRadius(for: s.kind)) }
        default: break
        }
        let mode = LocationPolicy.mode(phase: phase, untilLeaveBy: live.next?.leaveBy.map { $0.timeIntervalSince(now) },
                                       startOrCurrentCoordinate: coordinate, nextStop: watched, power: power)
        if mode != appliedMode {
            deps.location.apply(mode)
            appliedMode = mode
        }
    }

    // MARK: ETA

    private func etaCadence(run: TripRun, leaveBy: Date?, power: PowerState) -> TimeInterval {
        let now = deps.clock.now
        if run.phase == .driving {
            if power.isSaving { return ETARefreshPolicy.Cadence.drivingPowerSaving }
            return isStationary(now: now) ? ETARefreshPolicy.Cadence.drivingStationary : ETARefreshPolicy.Cadence.driving
        }
        return ETARefreshPolicy.leaveByInterval(untilLeaveBy: leaveBy.map { $0.timeIntervalSince(now) }, power: power)
    }

    /// Where an ETA is asked from: the last usable fix; while armed with none, the start place.
    private func etaOrigin(run: TripRun, now: Date) -> LocationFix? {
        if let fix = usableFix { return fix }
        if run.phase == .armed, let start = input?.start { return LocationFix(coordinate: start.coordinate, accuracyM: 100, timestamp: now) }
        return nil
    }

    private func etaDue(run: TripRun, live: LiveSchedule, now: Date) -> Date? {
        guard let next = live.next else { return nil }
        let moved = (refresher.requestLog.isEmpty ? nil : usableFix.flatMap { f in pendingOrigin.map { f.coordinate.distance(to: $0) } }) ?? 0
        return ETARefreshPolicy.nextRefresh(lastRequestAt: refresher.requestLog.last?.startedAt, now: now, phase: run.phase,
                                            untilLeaveBy: next.leaveBy.map { $0.timeIntervalSince(now) }, remainingDriveSeconds: next.driveSeconds,
                                            movedSinceLastRequestM: moved, isStationary: isStationary(now: now), power: deps.power.current(),
                                            backoffUntil: refresher.backoffUntil)
    }

    private func requestETA(run: TripRun, live: LiveSchedule, now: Date, power: PowerState, force: Bool) {
        guard let next = live.next, let target = stop(next.stopID) else {
            refresher.cancel()
            return
        }
        guard let origin = etaOrigin(run: run, now: now) else { return }
        let dest = (id: target.id, coordinate: target.place.coordinate)
        let context = ETARefreshContext(phase: run.phase, leaveBy: next.leaveBy, remainingDriveSeconds: next.driveSeconds,
                                        isStationary: isStationary(now: now), power: power)
        let before = refresher.requestLog.count
        // While driving the cadence alone decides: the policy's "moved 2 km" trigger would fire every ~80 s at highway speed (45
        // requests an hour measured), and progress is already counted by rescaling the ETA. A deviation asks for a route below.
        var started = false
        var gated = false
        if run.phase == .driving, !force, let last = lastRequest, last.stopID == target.id {
            gated = now.timeIntervalSince(last.at) < etaCadence(run: run, leaveBy: next.leaveBy, power: power)
        }
        if !gated {
            started = force ? refresher.forceRefresh(from: origin, to: dest, context: context)
                            : refresher.refreshIfDue(from: origin, to: dest, context: context)
        }
        if !started, run.phase == .driving, let fix = usableFix {
            let path = routePath.isEmpty ? (plannedLeg(into: target.id, run: run)?.path ?? []) : routePath
            if RouteDeviation.needsReroute(fix: fix, path: path) {
                started = refresher.requestRoute(from: fix, to: dest, context: context)
            }
        }
        _ = started
        if refresher.requestLog.count > before {
            pendingOrigin = origin.coordinate
            lastRequest = (target.id, now)
        }
    }

    private func handleOutcome(_ outcome: ETAOutcome) async {
        guard outcome != processedOutcome else { return }
        processedOutcome = outcome
        switch outcome.result {
        case .eta(let eta):
            lastETA = GoLiveETA(stopID: outcome.stopID, eta: eta, fetchedAt: outcome.requestedAt, origin: pendingOrigin ?? usableFix?.coordinate ?? Coordinate(latitude: 0, longitude: 0))
        case .route(let route):
            let eta = ETA(seconds: route.seconds, arrival: outcome.departing.addingTimeInterval(route.seconds), departing: outcome.departing)
            lastETA = GoLiveETA(stopID: outcome.stopID, eta: eta, fetchedAt: outcome.requestedAt, origin: pendingOrigin ?? usableFix?.coordinate ?? Coordinate(latitude: 0, longitude: 0),
                                meters: route.meters)
            if !route.path.isEmpty { routePath = route.path }
        case .failed(.cancelled):
            return
        case .failed:
            break
        }
        await serialized { await step(.tick, startWork: false, force: false, outputs: .always) }
    }

    // MARK: Conditions

    private func startConditions(run: TripRun, live: LiveSchedule, now: Date, power: PowerState) {
        guard conditionsTask == nil, let input, ConditionsCadence.isActive(run.phase) else { return }
        let nextStop = stop(live.next?.stopID)
        let today = nextStop.map { n in live.upcoming.compactMap { stop($0.stopID) }.filter { $0.dayIndex == n.dayIndex } } ?? []
        let fix = usableFix
        let due = ConditionsCadence.due(now: now, phase: run.phase, power: power, memory: loop.state.memory.cadence, nextStopID: nextStop?.id,
                                        hasTodayStops: !today.isEmpty, fix: fix)
        let nextChanged = loop.state.memory.cadence.nextStopID != nextStop?.id
        guard !due.isEmpty || nextChanged else { return }
        let ctx = ConditionsContext(trip: input.trip, phase: run.phase, nextStop: nextStop, todayRemaining: today, fix: fix, power: power)
        conditionsTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let update = await self.loop.refreshIfDue(context: ctx)
            await self.conditionsFinished(update)
        }
    }

    private func conditionsFinished(_ update: ConditionsUpdate) async {
        conditionsTask = nil
        guard !update.skipped else { return }
        conditionsFetchLog.append(ConditionsFetchRecord(at: deps.clock.now, items: update.fetched, requestCount: update.requestCount))
        for change in update.state.changes where !pendingChanges.contains(where: { $0.stopID == change.stopID && $0.raisedAt == change.raisedAt }) {
            pendingChanges.append(change)
        }
        guard !stopped else { return }
        await serialized { await step(.tick, startWork: false, force: false, outputs: .always) }
    }

    // MARK: Outputs

    private func publish(run: TripRun, live: LiveSchedule, now: Date, power: PowerState) async {
        guard let input else { return }
        let phase = run.phase
        let conditions = loop.state
        let held = lastETA.flatMap { $0.stopID == live.next?.stopID ? $0 : nil }
        let cadence = etaCadence(run: run, leaveBy: live.next?.leaveBy, power: power)
        let nextRefresh = [etaDue(run: run, live: live, now: now), conditions.nextDueAt].compactMap { $0 }.min()
        let facts = GoETAFacts(fetchedAt: held?.fetchedAt, meters: held?.meters, isOffline: refresher.isOffline, cadence: cadence)
        let snap = GoSnapshotBuilder.build(GoSnapshotInput(
            now: now, trip: input.trip, run: run, live: live, windows: input.windows, conditions: conditions, eta: facts,
            lastFix: lastFix, power: power, nextRefreshAt: (phase == .finished || phase == .paused) ? nil : nextRefresh))

        // Notifications.
        let plan = notificationInput(run: run, live: live, snap: snap, now: now)
        await sync.sync(plan)
        let ledger = await sync.ledger
        pendingChanges.removeAll { c in
            (ledger.conditionsLast[c.stopID.uuidString].map { $0 >= c.raisedAt } ?? false) || now.timeIntervalSince(c.raisedAt) > 30 * 60
        }

        snapshot = snap
        publisher.publish(snap)
        await coordinator.apply(snapshot: snap, power: power, now: now)
        onSnapshot?(snap)
        continuation.yield(snap)

        if phase == .finished {
            deps.engineState.clear(runID: run.id)
        } else {
            deps.engineState.save(GoEngineState(ledger: ledger, conditions: conditions, lastETA: lastETA, lastFix: lastFix, routePath: routePath),
                                  runID: run.id)
        }
        scheduleBackground(run: run, live: live, now: now)
    }

    private func scheduleBackground(run: TripRun, live: LiveSchedule, now: Date) {
        let wants = run.phase == .armed || run.phase == .betweenStops || run.phase == .atStop
        guard wants, let when = GoBackground.nextRefresh(now: now, leaveBy: live.next?.leaveBy) else {
            if !backgroundCancelled {
                deps.background.cancel()
                backgroundCancelled = true
                lastBackground = nil
            }
            return
        }
        if let last = lastBackground, last > now, when >= last.addingTimeInterval(-600) { return }
        deps.background.scheduleRefresh(earliest: when)
        lastBackground = when
        backgroundCancelled = false
    }

    // MARK: Notifications input

    private func notificationInput(run: TripRun, live: LiveSchedule, snap: GoSnapshot, now: Date) -> NotificationPlanInput {
        guard let input else { return NotificationPlanInput(now: now, tripID: UUID(), tripName: "", phase: .idle) }
        let trip = input.trip
        var alarms = AlarmPlan.make(live: live, trip: trip, now: now)
        // Evening Before: a stop whose plan has you set off tonight rings at the evening departure, not at the morning leave-by.
        for next in live.upcoming {
            guard let tonight = next.eveningSuggestedDeparture, let target = stop(next.stopID),
                  alarms.contains(where: { $0.stopID == next.stopID }) else { continue }
            alarms.removeAll { $0.stopID == next.stopID }
            let name = "\(target.place.name) tonight"
            func alarm(_ kind: AlarmKind, _ at: Date) -> PlannedAlarm {
                PlannedAlarm(id: AlarmPlan.id(for: next.stopID, kind: kind), kind: kind, fireAt: at, stopID: next.stopID, stopName: name,
                             leaveBy: tonight, driveSeconds: next.driveSeconds, windowKind: target.session, windowStart: next.window?.start,
                             includesNavigateAction: kind == .leaveNow)
            }
            var tonightAlarms: [PlannedAlarm] = []
            let soon = tonight.addingTimeInterval(-LiveSchedule.leaveSoonLead)
            if soon > now { tonightAlarms.append(alarm(.leaveSoon, soon)) }
            if tonight > now { tonightAlarms.append(alarm(.leaveNow, tonight)) }
            alarms = tonightAlarms + alarms
        }

        var facts: NotificationStopFacts?
        if let next = live.next, let target = stop(next.stopID), let leave = snap.leave {
            facts = NotificationStopFacts(stopID: next.stopID, name: target.place.name, status: leave.status, leaveBy: next.leaveBy,
                                          lateBySeconds: leave.lateBySeconds, windowKind: target.kind == .light ? target.session : nil,
                                          windowStart: next.window?.start, driveSeconds: next.driveSeconds,
                                          alternativeName: snap.alternative?.name, timeZone: target.place.timeZone,
                                          projectedArrival: next.projectedArrival, setUpBy: next.setUpBy)
        }
        var zones: [UUID: TimeZone] = [:]
        for s in live.upcoming { if let st = stop(s.stopID) { zones[st.id] = st.place.timeZone } }

        var arrival: ArrivalNotice?
        if let undo = run.pendingUndo, undo.to == .atStop, undo.cause == .geofence, now < undo.expiresAt, let id = undo.stopID,
           let s = stop(id) {
            arrival = ArrivalNotice(stopID: id, stopName: s.place.name, undoExpiresAt: undo.expiresAt)
        }
        let notices = pendingChanges.map {
            ConditionsAlertNotice(stopID: $0.stopID, stopName: $0.stopName, windowKind: $0.windowKind, previous: $0.previous, current: $0.current,
                                  reason: $0.reason == .scoreMoved ? .scoreMoved : .bandChanged, cause: $0.cause)
        }
        // An automatic departure by the clock is not the traveller leaving: while its "Not yet" window is open the plan still reads
        // the phase before it, so a leave-by that traffic pushed into the past still gets its one "Leave now".
        var phase = run.phase
        if phase == .driving, let undo = run.pendingUndo, undo.cause == .time, undo.to == .driving, now < undo.expiresAt,
           undo.from == .armed || undo.from == .betweenStops {
            phase = undo.from
        }
        return NotificationPlanInput(now: now, tripID: trip.id, tripName: trip.name, phase: phase, alarms: alarms, nextStop: facts, stay: snap.stay,
                                     currentStopID: phase == .atStop ? run.targetStopID : nil,
                                     targetStopID: phase == .driving ? run.targetStopID : nil, conditionsAlerts: notices, arrival: arrival,
                                     timeZones: zones)
    }
}
