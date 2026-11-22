import Foundation
import IterModel

/// Where the traveller is in the trip: what is done, what was skipped, and which stop they are at or heading to.
public struct TripProgress: Codable, Hashable, Sendable {
    public var visited: Set<UUID>
    public var skipped: Set<UUID>
    /// The stop you are at (when `atCurrentStop`), or the one you have chosen to head to.
    public var currentStopID: UUID?
    /// True while you are at `currentStopID`. That stop is then "current" and the next stop is the one after it.
    public var atCurrentStop: Bool

    public init(visited: Set<UUID> = [], skipped: Set<UUID> = [], currentStopID: UUID? = nil, atCurrentStop: Bool = false) {
        self.visited = visited
        self.skipped = skipped
        self.currentStopID = currentStopID
        self.atCurrentStop = atCurrentStop
    }
}

/// How a stop's drive time was obtained.
public enum ETASource: String, Codable, Hashable, Sendable {
    /// A live, traffic-aware ETA from where you are.
    case live
    /// The leg planned in the builder (or an honest estimate between the planned stops): no route from here was available.
    case planned
    /// No route available: a straight line from where you are, × 1.3 at 70 km/h (`Leg.estimate`). Shown labelled as such.
    case offlineEstimate
}

/// Where a stop stands against the clock.
public enum LiveStatus: Codable, Hashable, Sendable {
    /// More than 15 minutes before `leaveBy`.
    case early(untilLeaveBy: TimeInterval)
    /// Within 15 minutes of `leaveBy` (not yet there).
    case leaveSoon(untilLeaveBy: TimeInterval)
    /// `leaveBy` has arrived and you can still make set-up by leaving now (so this lasts until you would be late).
    case leaveNow
    /// Leaving now (or, for a later stop, when the chain frees you) you arrive after `setUpBy`.
    /// `by` = projected arrival minus `arriveBy`; `arrivesAfterSetUpBy` = projected arrival minus `setUpBy`.
    case late(by: TimeInterval, arrivesAfterSetUpBy: TimeInterval)
    /// You are there.
    case atStop
    /// Even leaving now you arrive after the window ends.
    case missed
    /// No time binds this stop (a lodging or waypoint with no fixed arrival, or a light stop with no window).
    case unscheduled
}

/// The next-best stop to head for when the next one is late or missed.
public struct LiveAlternative: Codable, Hashable, Sendable {
    public var stopID: UUID
    public var window: TimeSpan
    public var driveSeconds: TimeInterval
    public var etaSource: ETASource
    /// Arrival if you leave now.
    public var projectedArrival: Date
    /// Whether you would still make set-up (arrive by `setUpBy`) leaving now.
    public var makesSetUp: Bool
}

/// One upcoming stop as trip mode shows it.
public struct LiveStop: Codable, Hashable, Sendable, Identifiable {
    public var stopID: UUID
    public var kind: StopKind
    public var window: TimeSpan?
    /// For a stop with no light window this equals `arriveBy`.
    public var setUpBy: Date?
    public var arriveBy: Date?
    /// arriveBy − drive − safety margin. nil when no time binds the stop.
    public var leaveBy: Date?
    public var driveSeconds: TimeInterval
    public var etaSource: ETASource
    /// 5 minutes + 10 % of the drive, applied to every stop (live, offline and planned).
    public var safetyMargin: TimeInterval
    public var status: LiveStatus
    /// When you would arrive leaving at the later of now, `leaveBy` and `earliestDeparture`.
    public var projectedArrival: Date?
    /// When the chain frees you to leave for this stop: the previous remaining stop's projected departure. nil for the
    /// next stop (you decide) and when the previous stop leaves you free.
    public var earliestDeparture: Date?
    /// When you expect to be free to leave this stop; the chain for the stops after it starts here.
    public var projectedDeparture: Date?
    /// Set on the next stop only, when it is late or missed.
    public var alternative: LiveAlternative?
    /// How the trip moves into this stop's day, set when the previous non-skipped stop in trip order is on an earlier day (nil on
    /// same-day stops and for the first stop). After an overnight lodging the evening option has no meaning, so this is `.morning`.
    public var transfer: TransferTiming?
    /// For an `.eveningBefore` transfer only: when the plan has you set off (the previous stop's departure from its window).
    /// `leaveBy` and `status` stay the hard latest departure for the morning arrival; this is when to suggest driving that evening.
    public var plannedDeparture: Date?

    public var id: UUID { stopID }
}

/// The trade-off of staying at the current stop: its planned departure against the latest the next stop allows.
public struct StayCost: Codable, Hashable, Sendable {
    public var currentStopID: UUID
    public var nextStopID: UUID
    /// The current stop's projected departure (window end, or start + dwell); nil for an overnight lodging.
    public var plannedDeparture: Date?
    /// The next stop's leave-by.
    public var latestDeparture: Date?
    /// `plannedDeparture` minus `latestDeparture` when positive: how much of the current stop you give up to make the next. Else nil.
    public var cutsShortBy: TimeInterval?
    public var conflicts: Bool { cutsShortBy != nil }

    public init(currentStopID: UUID, nextStopID: UUID, plannedDeparture: Date?, latestDeparture: Date?, cutsShortBy: TimeInterval?) {
        self.currentStopID = currentStopID
        self.nextStopID = nextStopID
        self.plannedDeparture = plannedDeparture
        self.latestDeparture = latestDeparture
        self.cutsShortBy = cutsShortBy
    }
}

/// The live view of the rest of the trip, recomputed whenever the clock, the position or an ETA changes. Pure.
public struct LiveSchedule: Codable, Hashable, Sendable {
    public var now: Date
    /// The stop you are at, if `progress.atCurrentStop`.
    public var current: UUID?
    public var currentStop: LiveStop?
    /// The first stop that is neither visited, skipped nor current.
    public var next: LiveStop?
    /// The stops after `next`, in trip order. Does not include `next`.
    public var remaining: [LiveStop]
    /// Nothing left to do: no stop is waiting and you are not at one.
    public var finished: Bool
    /// While at a stop with another to come: what leaving on time for the next costs the current one. Nil otherwise.
    public var stay: StayCost?

    /// `next` followed by `remaining`.
    public var upcoming: [LiveStop] { (next.map { [$0] } ?? []) + remaining }

    /// 5 minutes + 10 % of the drive (blueprint §10.2).
    public static func safetyMargin(forDriveSeconds seconds: TimeInterval) -> TimeInterval { 300 + 0.1 * max(0, seconds) }

    /// `leaveSoon` begins this long before `leaveBy` (blueprint D9).
    public static let leaveSoonLead: TimeInterval = 15 * 60

    /// Builds the live schedule.
    ///
    /// - `windows`, `plannedLegs`, `start`: as for `Scheduler.schedule`.
    /// - `origin`: where you are now (nil when unknown). `liveETAs[stopID]` is a live ETA from `origin` to that stop; the caller
    ///   may supply it for any stops it asked about.
    /// - `offlineETAs[stopID]`: an ETA computed without a network (see `OfflineETA`), used when there is no live one.
    ///
    /// Drive time for the **next** stop: its live ETA if present (`.live`); else its offline ETA (`.offlineEstimate`); else, with
    /// no route but a known origin, a straight-line estimate from the origin (`.offlineEstimate`); else the planned leg into it from the previous non-skipped stop (the start
    /// place for the first stop; `.planned`). A skipped stop disappears from the chain, so the stop after it is driven from
    /// where you are, not from the skipped stop. Later stops use their planned leg from the previous remaining stop (`.planned`,
    /// an estimate if none was planned) and chain from that stop's projected departure.
    ///
    /// While at a stop, the next stop's leave-by and status stay truthful (the latest departure that still makes set-up). The
    /// trade-off is exposed as `stay`. When leaving at the current stop's planned departure still makes the next stop
    /// (no conflict) and that is later than now, it becomes the next stop's `earliestDeparture`; on a conflict it stays nil.
    ///
    /// Every stop's leave-by = arriveBy − drive − margin. The margin is applied to planned legs too, so a stop's leave-by does not
    /// jump when it becomes the next stop and a live ETA replaces the planned one.
    public static func make(trip: Trip, start: Place?, windows: SessionWindows, plannedLegs: [LegKey: Leg], progress: TripProgress,
                            now: Date, origin: Coordinate?, liveETAs: [UUID: ETA], offlineETAs: [UUID: ETA] = [:]) -> LiveSchedule {
        let ordered = Scheduler.ordered(trip.stops)
        let active = ordered.filter { !progress.visited.contains($0.id) && !progress.skipped.contains($0.id) }
        var currentStop: Stop?
        var upcoming = active
        if progress.atCurrentStop, let id = progress.currentStopID, let stop = active.first(where: { $0.id == id }) {
            currentStop = stop
            upcoming = active.filter { $0.id != id }
        }

        func window(_ stop: Stop) -> TimeSpan? { stop.kind == .light ? windows[stop.id] : nil }

        var currentLive: LiveStop?
        if let currentStop {
            let w = window(currentStop)
            let times = Scheduler.timing(for: currentStop, trip: trip, window: w)
            let depart = Scheduler.departAt(for: currentStop, window: w, arrival: times.arriveBy)
            currentLive = LiveStop(stopID: currentStop.id, kind: currentStop.kind, window: w, setUpBy: times.setUpBy ?? times.arriveBy,
                                   arriveBy: times.arriveBy, leaveBy: nil, driveSeconds: 0, etaSource: .planned, safetyMargin: 0,
                                   status: .atStop, projectedArrival: nil, earliestDeparture: nil, projectedDeparture: depart, alternative: nil)
        }

        var live: [LiveStop] = []
        // The previous non-skipped stop in trip order, for planned legs.
        func plannedLeg(into stop: Stop, from previous: Stop?) -> Leg? {
            if let previous {
                return plannedLegs[LegKey(previous.id, stop.id)] ?? Leg.estimate(from: previous.place.coordinate, to: stop.place.coordinate)
            }
            if let start {
                return plannedLegs[LegKey(start.id, stop.id)] ?? Leg.estimate(from: start.coordinate, to: stop.place.coordinate)
            }
            return nil
        }

        var previousRemaining: Stop?
        var previousDeparture: Date?
        for (index, stop) in upcoming.enumerated() {
            let w = window(stop)
            let times = Scheduler.timing(for: stop, trip: trip, window: w)
            let isNext = index == 0

            // Drive time and its source.
            var drive: TimeInterval
            var source: ETASource
            var previousForPlan: Stop?
            if isNext {
                previousForPlan = ordered.last { candidate in
                    candidate.id != stop.id && ordered.firstIndex(of: candidate)! < ordered.firstIndex(of: stop)!
                        && !progress.skipped.contains(candidate.id)
                }
            } else {
                previousForPlan = previousRemaining
            }
            if isNext, let eta = liveETAs[stop.id] {
                drive = eta.seconds
                source = .live
            } else if isNext, let eta = offlineETAs[stop.id] {
                drive = eta.seconds
                source = .offlineEstimate
            } else if isNext, let origin {
                drive = Leg.estimate(from: origin, to: stop.place.coordinate).seconds
                source = .offlineEstimate
            } else {
                drive = plannedLeg(into: stop, from: previousForPlan)?.seconds ?? 0
                source = .planned
            }
            let margin = safetyMargin(forDriveSeconds: drive)
            let setUpBy = times.setUpBy ?? times.arriveBy
            var earliest: Date? = isNext ? nil : previousDeparture
            if isNext, let planned = currentLive?.projectedDeparture, planned > now {
                // Leaving when the shoot ends, but only when that still makes this stop.
                let latest = times.arriveBy.map { $0.addingTimeInterval(-drive - margin) }
                if latest.map({ $0 >= planned }) ?? true { earliest = planned }
            }
            let previousStop = ordered.last { $0.id != stop.id && ordered.firstIndex(of: $0)! < ordered.firstIndex(of: stop)! && !progress.skipped.contains($0.id) }
            var transfer: TransferTiming?
            var plannedDeparture: Date?
            if let previousStop, previousStop.dayIndex < stop.dayIndex {
                let prevWindow = window(previousStop)
                let prevTimes = Scheduler.timing(for: previousStop, trip: trip, window: prevWindow)
                let prevDepart = Scheduler.departAt(for: previousStop, window: prevWindow, arrival: prevTimes.arriveBy)
                let overnight = previousStop.kind == .lodging && prevDepart == nil
                let timing = trip.transferTiming(intoDay: stop.dayIndex)
                transfer = overnight ? .morning : timing
                if transfer == .eveningBefore { plannedDeparture = prevDepart }
            }

            var leaveBy: Date?
            var projectedArrival: Date?
            var status: LiveStatus = .unscheduled
            if let arriveBy = times.arriveBy, let setUpBy {
                let lb = arriveBy.addingTimeInterval(-drive - margin)
                leaveBy = lb
                let departing = max(now, lb, earliest ?? now)
                let arrival = departing.addingTimeInterval(drive)
                projectedArrival = arrival
                if let w, arrival > w.end {
                    status = .missed
                } else if arrival > setUpBy {
                    status = .late(by: arrival.timeIntervalSince(arriveBy), arrivesAfterSetUpBy: arrival.timeIntervalSince(setUpBy))
                } else if now >= lb {
                    status = .leaveNow
                } else if lb.timeIntervalSince(now) <= leaveSoonLead {
                    status = .leaveSoon(untilLeaveBy: lb.timeIntervalSince(now))
                } else {
                    status = .early(untilLeaveBy: lb.timeIntervalSince(now))
                }
            } else if stop.kind != .light, let base = earliest ?? (isNext ? now : nil) {
                // Flexible: go when free; arrival is only an estimate.
                projectedArrival = max(base, now).addingTimeInterval(drive)
            }

            let arrivalForDeparture = times.arriveBy ?? projectedArrival
            var departure = Scheduler.departAt(for: stop, window: w, arrival: arrivalForDeparture)
            if let departure0 = departure, let projectedArrival, projectedArrival > departure0 { departure = projectedArrival }

            live.append(LiveStop(stopID: stop.id, kind: stop.kind, window: w, setUpBy: setUpBy, arriveBy: times.arriveBy, leaveBy: leaveBy,
                                 driveSeconds: drive, etaSource: source, safetyMargin: margin, status: status,
                                 projectedArrival: projectedArrival, earliestDeparture: earliest, projectedDeparture: departure,
                                 alternative: nil, transfer: transfer, plannedDeparture: plannedDeparture))
            previousRemaining = stop
            previousDeparture = departure
        }

        // The next-best stop when the next one is late or missed.
        if let first = live.first {
            switch first.status {
            case .late, .missed:
                live[0].alternative = alternative(after: first, upcoming: Array(upcoming.dropFirst()), windows: windows, now: now, origin: origin,
                                                  liveETAs: liveETAs, offlineETAs: offlineETAs, plannedFrom: upcoming[0], plannedLegs: plannedLegs, trip: trip)
            default: break
            }
        }

        var stay: StayCost?
        if let currentLive, let first = live.first {
            let planned = currentLive.projectedDeparture
            var cuts: TimeInterval?
            if let planned, let latest = first.leaveBy, planned > latest { cuts = planned.timeIntervalSince(latest) }
            stay = StayCost(currentStopID: currentLive.stopID, nextStopID: first.stopID, plannedDeparture: planned,
                            latestDeparture: first.leaveBy, cutsShortBy: cuts)
        }

        return LiveSchedule(now: now, current: currentStop?.id, currentStop: currentLive, next: live.first,
                            remaining: Array(live.dropFirst()), finished: currentStop == nil && live.isEmpty, stay: stay)
    }

    /// The first later light stop whose window is still reachable leaving now. Drive time from here: a live ETA if the caller
    /// supplied one for it, else a straight line from `origin` (`.offlineEstimate`), else the planned leg from the stop you
    /// were heading for.
    private static func alternative(after first: LiveStop, upcoming: [Stop], windows: SessionWindows, now: Date, origin: Coordinate?,
                                    liveETAs: [UUID: ETA], offlineETAs: [UUID: ETA], plannedFrom: Stop, plannedLegs: [LegKey: Leg], trip: Trip) -> LiveAlternative? {
        for stop in upcoming where stop.kind == .light {
            guard let window = windows[stop.id] else { continue }
            let drive: TimeInterval
            let source: ETASource
            if let eta = liveETAs[stop.id] {
                drive = eta.seconds
                source = .live
            } else if let eta = offlineETAs[stop.id] {
                drive = eta.seconds
                source = .offlineEstimate
            } else if let origin {
                drive = Leg.estimate(from: origin, to: stop.place.coordinate).seconds
                source = .offlineEstimate
            } else {
                drive = (plannedLegs[LegKey(plannedFrom.id, stop.id)] ?? Leg.estimate(from: plannedFrom.place.coordinate, to: stop.place.coordinate)).seconds
                source = .planned
            }
            let arrival = now.addingTimeInterval(drive)
            guard arrival <= window.end else { continue }
            let times = Scheduler.timing(for: stop, trip: trip, window: window)
            let setUpBy = times.setUpBy ?? window.start
            return LiveAlternative(stopID: stop.id, window: window, driveSeconds: drive, etaSource: source, projectedArrival: arrival,
                                   makesSetUp: arrival <= setUpBy)
        }
        return nil
    }
}
