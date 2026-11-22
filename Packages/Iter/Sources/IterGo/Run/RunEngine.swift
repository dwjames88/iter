import Foundation
import IterGoActivity
import IterModel
import IterPlan

// The run state machine (BLUEPRINT §10.1, D12). Pure: time arrives in `RunContext.now` and in fix timestamps.

extension TripRun {
    /// Starts a run. Stops before `stopID` (trip order) are marked skipped with no dates. `stopID` nil = the first stop.
    public static func start(trip: Trip, runID: UUID, at stopID: UUID?, now: Date, alreadyThere: Bool) -> TripRun {
        let ordered = RunOrder.ordered(trip.stops)
        var run = TripRun(id: runID, tripID: trip.id, phase: .armed, startedAt: now)
        guard !ordered.isEmpty else {
            run.phase = .finished
            run.endedAt = now
            return run
        }
        let index = stopID.flatMap { id in ordered.firstIndex { $0.id == id } } ?? 0
        for (i, stop) in ordered.enumerated() {
            run.visits[stop.id] = StopVisit(stopID: stop.id, status: i < index ? .skipped : .pending)
        }
        let target = ordered[index].id
        run.targetStopID = target
        if alreadyThere {
            run.phase = .atStop
            run.visits[target]?.status = .arrived
            run.visits[target]?.arrivedAt = now
        }
        return run
    }

    /// Applies one event. Returns the transitions it caused (usually zero or one), each with the visits it changed.
    public mutating func handle(_ event: RunEvent, context: RunContext) -> [RunTransition] {
        if let undo = pendingUndo, context.now >= undo.expiresAt { pendingUndo = nil }
        guard phase != .idle else { return [] }
        // A finished run takes only "Not yet", to undo an automatic finish.
        if phase == .finished {
            guard case .user(.notYet) = event else { return [] }
            return undo(context)
        }
        switch event {
        case .user(let action):
            let before = pendingUndo
            let out = handleUser(action, context)
            if out.isEmpty { pendingUndo = before }
            return out
        case .tick:
            return phase == .paused ? [] : handleTick(context)
        case .location(let fix):
            return phase == .paused ? [] : handleLocation(fix, context)
        }
    }

    // MARK: Shared helpers

    private func snapshot() -> RunSnapshot {
        RunSnapshot(phase: phase, pausedFrom: pausedFrom, startedAt: startedAt, endedAt: endedAt, targetStopID: targetStopID, visits: visits)
    }

    /// The first stop in trip order that is still to do (pending or being driven to).
    private func nextPendingID(_ trip: Trip) -> UUID? {
        RunOrder.ordered(trip.stops).first { status(of: $0.id) == .pending || status(of: $0.id) == .enRoute }?.id
    }

    private func stop(_ id: UUID?, in trip: Trip) -> Stop? {
        id.flatMap { id in trip.stops.first { $0.id == id } }
    }

    private mutating func edit(_ id: UUID, _ changes: inout [StopVisit], _ body: (inout StopVisit) -> Void) {
        var visit = visits[id] ?? StopVisit(stopID: id)
        body(&visit)
        visits[id] = visit
        if let i = changes.firstIndex(where: { $0.stopID == id }) { changes[i] = visit } else { changes.append(visit) }
    }

    /// Heading for `id`: enRoute, and the leave-by and arrival frozen from the live schedule at this moment.
    private mutating func beginDrive(to id: UUID, live: LiveSchedule, now: Date, _ changes: inout [StopVisit]) {
        let liveStop = live.upcoming.first { $0.stopID == id }
        edit(id, &changes) {
            $0.status = .enRoute
            $0.departedForAt = now
            if let liveStop {
                $0.plannedLeaveBy = liveStop.leaveBy
                $0.plannedArrival = liveStop.projectedArrival
            }
        }
        targetStopID = id
        phase = .driving
    }

    private mutating func markDone(_ id: UUID?, now: Date, _ changes: inout [StopVisit]) {
        guard let id else { return }
        edit(id, &changes) { $0.status = .done; $0.leftAt = now }
    }

    private mutating func finish(now: Date) {
        phase = .finished
        pausedFrom = nil
        endedAt = now
        targetStopID = nil
    }

    /// The current stop is closed: wait for the next one, or finish when nothing is left.
    private mutating func settleAfterClosing(_ trip: Trip, now: Date) {
        if let next = nextPendingID(trip) {
            targetStopID = next
            phase = .betweenStops
        } else {
            finish(now: now)
        }
    }

    private mutating func commit(from: GoPhase, stopID: UUID?, cause: RunCause, now: Date, prior: RunSnapshot,
                                 _ changes: [StopVisit]) -> RunTransition {
        let automatic = cause != .user
        var expiry: Date?
        if automatic {
            let e = now.addingTimeInterval(GeofencePolicy.undoWindow)
            pendingUndo = PendingUndo(prior: prior, cause: cause, stopID: stopID, from: from, to: phase, expiresAt: e)
            expiry = e
        } else {
            pendingUndo = nil
        }
        tracker = RunTracker()
        return RunTransition(from: from, to: phase, stopID: stopID, cause: cause, automatic: automatic, undoExpiresAt: expiry,
                             visitChanges: changes)
    }

    private func isSuppressed(_ stopID: UUID?, from: GoPhase, to: GoPhase, cause: RunCause) -> Bool {
        suppressions.contains { $0.stopID == stopID && $0.from == from && $0.to == to && $0.cause == cause }
    }

    // MARK: User actions

    private mutating func handleUser(_ action: RunUserAction, _ context: RunContext) -> [RunTransition] {
        let now = context.now, trip = context.trip
        let prior = snapshot()
        let from = phase
        var changes: [StopVisit] = []

        if phase == .paused {
            switch action {
            case .resume:
                phase = pausedFrom ?? TripRun.derivePhase(visits: visits)
                pausedFrom = nil
                return [commit(from: from, stopID: targetStopID, cause: .user, now: now, prior: prior, changes)]
            case .end:
                break   // handled below
            case .notYet: return undo(context)
            default: return []
            }
        }

        switch action {
        case .notYet:
            return undo(context)

        case .pause:
            guard phase != .paused else { return [] }
            pausedFrom = phase
            phase = .paused
            return [commit(from: from, stopID: targetStopID, cause: .user, now: now, prior: prior, changes)]

        case .resume:
            return []

        case .end:
            let active = activePhase
            if active == .atStop { markDone(targetStopID, now: now, &changes) }
            let stopID = targetStopID
            finish(now: now)
            return [commit(from: from, stopID: stopID, cause: .user, now: now, prior: prior, changes)]

        case .leaveNow:
            switch phase {
            case .armed, .betweenStops:
                guard let next = nextPendingID(trip) else { return [] }
                beginDrive(to: next, live: context.live, now: now, &changes)
                return [commit(from: from, stopID: next, cause: .user, now: now, prior: prior, changes)]
            case .atStop:
                let current = targetStopID
                markDone(current, now: now, &changes)
                guard let next = nextPendingID(trip) else {
                    finish(now: now)
                    return [commit(from: from, stopID: current, cause: .user, now: now, prior: prior, changes)]
                }
                beginDrive(to: next, live: context.live, now: now, &changes)
                return [commit(from: from, stopID: next, cause: .user, now: now, prior: prior, changes)]
            default: return []
            }

        case .arrived:
            switch phase {
            case .driving, .armed, .betweenStops:
                guard let target = (phase == .driving ? targetStopID : nextPendingID(trip)) else { return [] }
                edit(target, &changes) { $0.status = .arrived; $0.arrivedAt = now }
                targetStopID = target
                phase = .atStop
                return [commit(from: from, stopID: target, cause: .user, now: now, prior: prior, changes)]
            default: return []
            }

        case .doneHere:
            guard phase == .atStop else { return [] }
            let current = targetStopID
            markDone(current, now: now, &changes)
            settleAfterClosing(trip, now: now)
            return [commit(from: from, stopID: current, cause: .user, now: now, prior: prior, changes)]

        case .skip(let requested):
            return skip(requested, context, prior: prior, from: from)
        }
    }

    private mutating func skip(_ requested: UUID?, _ context: RunContext, prior: RunSnapshot, from: GoPhase) -> [RunTransition] {
        let now = context.now, trip = context.trip
        let chosen = requested ?? nextPendingID(trip)
        guard let chosen, stop(chosen, in: trip) != nil else { return [] }
        let state = status(of: chosen)
        guard state == .pending || state == .enRoute || state == .arrived else { return [] }
        var changes: [StopVisit] = []
        let leaving = state == .arrived
        edit(chosen, &changes) {
            $0.status = .skipped
            if leaving { $0.leftAt = now }
        }
        if leaving {
            // Skipping the stop you are at: you are done with it.
            settleAfterClosing(trip, now: now)
        } else if chosen == targetStopID && phase != .atStop {
            if let next = nextPendingID(trip) {
                if phase == .driving {
                    beginDrive(to: next, live: context.live, now: now, &changes)
                } else {
                    targetStopID = next
                }
            } else {
                finish(now: now)
            }
        }
        return [commit(from: from, stopID: chosen, cause: .user, now: now, prior: prior, changes)]
    }

    private mutating func undo(_ context: RunContext) -> [RunTransition] {
        guard let pending = pendingUndo, context.now < pending.expiresAt else {
            pendingUndo = nil
            return []
        }
        let from = phase
        var changes: [StopVisit] = []
        for (id, visit) in pending.prior.visits where visits[id] != visit { changes.append(visit) }
        changes.sort { $0.stopID.uuidString < $1.stopID.uuidString }
        let p = pending.prior
        phase = p.phase
        pausedFrom = p.pausedFrom
        startedAt = p.startedAt
        endedAt = p.endedAt
        targetStopID = p.targetStopID
        visits = p.visits
        suppressions.append(RunSuppression(stopID: pending.stopID, from: pending.from, to: pending.to, cause: pending.cause,
                                           restOfRun: pending.cause == .time))
        pendingUndo = nil
        tracker = RunTracker()
        return [RunTransition(from: from, to: phase, stopID: pending.stopID, cause: .user, automatic: false, undoExpiresAt: nil,
                              visitChanges: changes)]
    }

    // MARK: Time

    private mutating func handleTick(_ context: RunContext) -> [RunTransition] {
        let now = context.now, trip = context.trip, live = context.live
        let prior = snapshot()
        let from = phase
        var changes: [StopVisit] = []
        switch phase {
        case .armed, .betweenStops:
            guard let next = live.next, let leaveBy = next.leaveBy, now >= leaveBy,
                  !isSuppressed(next.stopID, from: from, to: .driving, cause: .time) else { return [] }
            beginDrive(to: next.stopID, live: live, now: now, &changes)
            return [commit(from: from, stopID: next.stopID, cause: .time, now: now, prior: prior, changes)]
        case .atStop:
            guard let current = live.currentStop else { return [] }
            // IterPlan has no departure for a waypoint or lodging without a fixed arrival; fall back to when you arrived + dwell.
            var departure = current.projectedDeparture
            if departure == nil, current.kind != .light, let dwell = stop(current.stopID, in: trip)?.dwellMinutes, dwell > 0,
               let arrivedAt = visits[current.stopID]?.arrivedAt {
                departure = arrivedAt.addingTimeInterval(TimeInterval(dwell) * 60)
            }
            if let departure {
                guard now >= departure, !isSuppressed(current.stopID, from: from, to: .betweenStops, cause: .time) else { return [] }
                markDone(current.stopID, now: now, &changes)
                settleAfterClosing(trip, now: now)
                return [commit(from: from, stopID: current.stopID, cause: .time, now: now, prior: prior, changes)]
            }
            // Overnight lodging never ends by itself, but the next stop's leave-by takes you straight on.
            guard current.kind == .lodging, let next = live.next, let leaveBy = next.leaveBy, now >= leaveBy,
                  !isSuppressed(next.stopID, from: from, to: .driving, cause: .time) else { return [] }
            markDone(current.stopID, now: now, &changes)
            beginDrive(to: next.stopID, live: live, now: now, &changes)
            return [commit(from: from, stopID: next.stopID, cause: .time, now: now, prior: prior, changes)]
        default:
            return []
        }
    }

    // MARK: Location

    /// Where the last stop was: the finished stop with the latest `leftAt`.
    private func lastStopCoordinate(_ trip: Trip) -> Coordinate? {
        let last = visits.values.filter { $0.status == .done && $0.leftAt != nil }.max { $0.leftAt! < $1.leftAt! }
        return stop(last?.stopID, in: trip)?.place.coordinate
    }

    private func motionOrigin(_ context: RunContext) -> Coordinate? {
        phase == .betweenStops ? (lastStopCoordinate(context.trip) ?? context.startCoordinate) : context.startCoordinate
    }

    private static func isInside(_ fix: LocationFix, _ stop: Stop) -> Bool {
        fix.coordinate.distance(to: stop.place.coordinate)
            <= GeofencePolicy.enterRadius(for: stop.kind) + min(fix.accuracyM, GeofencePolicy.accuracySlackCapM)
    }

    private static func isOutside(_ fix: LocationFix, _ stop: Stop) -> Bool {
        fix.coordinate.distance(to: stop.place.coordinate) > GeofencePolicy.exitRadius(for: stop.kind)
    }

    /// Drops "Not yet" suppressions whose trigger this fix shows to be false.
    private mutating func clearSuppressions(_ fix: LocationFix, _ context: RunContext) {
        let origin = motionOrigin(context) ?? tracker.anchor ?? fix.coordinate
        let current = phase
        let trip = context.trip
        let currentStop = stop(targetStopID, in: trip)
        let targets = Dictionary(uniqueKeysWithValues: suppressions.compactMap { s in stop(s.stopID, in: trip).map { (s.stopID!, $0) } })
        suppressions.removeAll { s in
            guard !s.restOfRun, s.from == current else { return false }
            switch (s.cause, current) {
            case (.geofence, .driving):
                guard let id = s.stopID, let target = targets[id] else { return false }
                return !TripRun.isInside(fix, target)
            case (.geofence, .atStop):
                guard let currentStop else { return false }
                return !TripRun.isOutside(fix, currentStop)
            case (.motion, _):
                return fix.coordinate.distance(to: origin) <= GeofencePolicy.motionDistanceM
            default:
                return false
            }
        }
    }

    private mutating func handleLocation(_ fix: LocationFix, _ context: RunContext) -> [RunTransition] {
        guard fix.isUsable(maxAccuracyM: GeofencePolicy.maxAccuracyM) else { return [] }
        clearSuppressions(fix, context)
        let now = context.now, trip = context.trip
        let prior = snapshot()
        let from = phase
        var changes: [StopVisit] = []

        switch phase {
        case .armed, .betweenStops:
            guard let next = nextPendingID(trip),
                  !isSuppressed(next, from: from, to: .driving, cause: .motion) else { return [] }
            let origin: Coordinate
            if let known = motionOrigin(context) {
                origin = known
            } else {
                if tracker.anchor == nil { tracker.anchor = fix.coordinate }
                origin = tracker.anchor!
            }
            guard fix.coordinate.distance(to: origin) > GeofencePolicy.motionDistanceM else {
                tracker.farCount = 0
                return []
            }
            tracker.farCount += 1
            guard (fix.speedMs ?? 0) > GeofencePolicy.motionSpeed || tracker.farCount >= 2 else { return [] }
            beginDrive(to: next, live: context.live, now: now, &changes)
            return [commit(from: from, stopID: next, cause: .motion, now: now, prior: prior, changes)]

        case .driving:
            guard let target = stop(targetStopID, in: trip),
                  !isSuppressed(target.id, from: from, to: .atStop, cause: .geofence) else { return [] }
            guard TripRun.isInside(fix, target) else {
                tracker.insideSince = nil
                return []
            }
            var enter = false
            if let speed = fix.speedMs, speed >= 0, speed < GeofencePolicy.enterSlowSpeed {
                enter = true
            } else if let since = tracker.insideSince {
                enter = fix.timestamp.timeIntervalSince(since) >= GeofencePolicy.enterDwellSeconds
            } else {
                tracker.insideSince = fix.timestamp
            }
            guard enter else { return [] }
            edit(target.id, &changes) { $0.status = .arrived; $0.arrivedAt = now }
            phase = .atStop
            return [commit(from: from, stopID: target.id, cause: .geofence, now: now, prior: prior, changes)]

        case .atStop:
            guard let current = stop(targetStopID, in: trip) else { return [] }
            let next = nextPendingID(trip)
            guard !isSuppressed(next, from: from, to: next == nil ? .finished : .driving, cause: .geofence) else { return [] }
            guard TripRun.isOutside(fix, current) else {
                tracker.outsideSince = nil
                return []
            }
            guard let since = tracker.outsideSince else {
                tracker.outsideSince = fix.timestamp
                return []
            }
            guard fix.timestamp.timeIntervalSince(since) >= GeofencePolicy.exitDwellSeconds else { return [] }
            markDone(current.id, now: now, &changes)
            if let next {
                beginDrive(to: next, live: context.live, now: now, &changes)
            } else {
                finish(now: now)
            }
            return [commit(from: from, stopID: next ?? current.id, cause: .geofence, now: now, prior: prior, changes)]

        default:
            return []
        }
    }
}
