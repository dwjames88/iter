import Foundation
import IterModel
import IterPlan
import IterConditions

extension GoLeaveStatus {
    public init(_ status: LiveStatus) {
        switch status {
        case .early: self = .early
        case .leaveSoon: self = .leaveSoon
        case .leaveNow: self = .leaveNow
        case .late: self = .late
        case .missed: self = .missed
        case .atStop: self = .atStop
        case .unscheduled: self = .unscheduled
        }
    }
}

extension GoETASource {
    public init(_ source: ETASource) {
        switch source {
        case .live: self = .live
        case .planned: self = .planned
        case .offlineEstimate: self = .offlineEstimate
        }
    }
}

extension LiveStop {
    /// An Evening Before transfer whose plan has you set off earlier than the hard leave-by: when to suggest driving tonight.
    public var eveningSuggestedDeparture: Date? {
        guard transfer == .eveningBefore, let plannedDeparture, let leaveBy, plannedDeparture < leaveBy else { return nil }
        return plannedDeparture
    }
}

/// Facts about the live ETA the schedule does not carry.
public struct GoETAFacts: Hashable, Sendable {
    /// When the live ETA was fetched; nil with no live ETA held.
    public var fetchedAt: Date?
    public var meters: Double?
    /// The refresher's last request failed for lack of a connection.
    public var isOffline: Bool
    /// How often the ETA is refreshed right now, seconds (for the stale rule: 2x this).
    public var cadence: TimeInterval

    public init(fetchedAt: Date? = nil, meters: Double? = nil, isOffline: Bool = false, cadence: TimeInterval = 180) {
        self.fetchedAt = fetchedAt
        self.meters = meters
        self.isOffline = isOffline
        self.cadence = cadence
    }
}

public struct GoSnapshotInput: Sendable {
    public var now: Date
    public var trip: Trip
    public var run: TripRun?
    public var live: LiveSchedule?
    public var windows: SessionWindows
    public var conditions: GoConditionsState
    public var eta: GoETAFacts
    public var lastFix: LocationFix?
    public var power: PowerState
    public var nextRefreshAt: Date?

    public init(now: Date, trip: Trip, run: TripRun?, live: LiveSchedule?, windows: SessionWindows = [:], conditions: GoConditionsState = GoConditionsState(),
                eta: GoETAFacts = GoETAFacts(), lastFix: LocationFix? = nil, power: PowerState = .normal, nextRefreshAt: Date? = nil) {
        self.now = now
        self.trip = trip
        self.run = run
        self.live = live
        self.windows = windows
        self.conditions = conditions
        self.eta = eta
        self.lastFix = lastFix
        self.power = power
        self.nextRefreshAt = nextRefreshAt
    }
}

/// Builds the one value every Go surface renders. Pure.
public enum GoSnapshotBuilder {
    /// Location is stale after this long without a fix while driving.
    public static let locationStaleAfter: TimeInterval = 5 * 60

    public static func build(_ i: GoSnapshotInput) -> GoSnapshot {
        guard let run = i.run, run.phase != .idle else { return .idle(at: i.now) }
        let ordered = RunOrder.ordered(i.trip.stops)
        let phase = run.phase
        let live = i.live

        func info(_ stop: Stop, _ liveStop: LiveStop?) -> GoStopInfo {
            let w = i.windows[stop.id]
            return GoStopInfo(id: stop.id, number: (ordered.firstIndex { $0.id == stop.id } ?? 0) + 1, name: stop.place.name,
                              locality: stop.place.locality.isEmpty ? nil : stop.place.locality, kind: stop.kind, dayIndex: stop.dayIndex,
                              coordinate: stop.place.coordinate, timeZoneIdentifier: stop.place.timeZoneIdentifier,
                              windowKind: stop.kind == .light ? stop.session : nil, windowStart: (liveStop?.window ?? w)?.start,
                              windowEnd: (liveStop?.window ?? w)?.end, setUpBy: liveStop?.setUpBy, arriveBy: liveStop?.arriveBy)
        }
        func stop(_ id: UUID?) -> Stop? { id.flatMap { id in i.trip.stops.first { $0.id == id } } }

        let currentInfo = live?.currentStop.flatMap { l in stop(l.stopID).map { info($0, l) } }
        let nextLive = live?.next
        let nextStop = stop(nextLive?.stopID)
        let nextInfo = nextLive.flatMap { l in nextStop.map { info($0, l) } }

        var leave: GoLeaveInfo?
        var drive: GoDriveInfo?
        var alternative: GoAlternativeInfo?
        if let l = nextLive {
            var late: TimeInterval?
            switch l.status {
            case .late(_, let after): late = after
            case .missed:
                if let arrival = l.projectedArrival, let setUp = l.setUpBy { late = max(0, arrival.timeIntervalSince(setUp)) }
            default: break
            }
            let earliest = l.earliestDeparture.flatMap { $0 > i.now ? $0 : nil }
            leave = GoLeaveInfo(leaveBy: l.leaveBy, status: GoLeaveStatus(l.status), lateBySeconds: late, earliestDeparture: earliest,
                                suggestedDeparture: l.eveningSuggestedDeparture)
            let source = GoETASource(l.etaSource)
            let asOf: Date
            switch source {
            case .live: asOf = i.eta.fetchedAt ?? i.now
            case .offlineEstimate: asOf = i.now
            case .planned: asOf = run.startedAt ?? i.now
            }
            // Driving: you are leaving now. Otherwise the schedule's arrival (leaving at the later of now and leave-by).
            let arrival = phase == .driving ? i.now.addingTimeInterval(l.driveSeconds) : l.projectedArrival
            drive = GoDriveInfo(arrival: arrival, driveSeconds: l.driveSeconds, driveMeters: source == .live ? i.eta.meters : nil,
                                source: source, asOf: asOf)
            if let alt = l.alternative, let altStop = stop(alt.stopID) {
                alternative = GoAlternativeInfo(stopID: alt.stopID, name: altStop.place.name, windowKind: altStop.session, windowStart: alt.window.start,
                                                projectedArrival: alt.projectedArrival, makesSetUp: alt.makesSetUp)
            }
        }

        var stayInfo: GoStayInfo?
        if let s = live?.stay, live?.currentStop != nil {
            stayInfo = GoStayInfo(plannedDeparture: s.plannedDeparture, latestDeparture: s.latestDeparture, cutsShortBySeconds: s.cutsShortBy,
                                  nextStopName: nextStop?.place.name, nextWindowKind: nextStop.flatMap { $0.kind == .light ? $0.session : nil })
        }

        // Conditions: only what is about the stop shown.
        let c = i.conditions
        let nextID = nextStop?.id
        let sky = c.sky.flatMap { $0.stopID == nextID ? $0 : nil }
        let weather = c.weather.filter { w in
            switch w.subject { case .here: true; case .stop(let id): id == nextID }
        }

        let active = phase != .finished && phase != .paused
        let etaStale: Bool = {
            guard active, nextLive != nil else { return false }
            guard let at = i.eta.fetchedAt else { return true }
            return i.now.timeIntervalSince(at) > 2 * i.eta.cadence
        }()
        let locationStale = phase == .driving && (i.lastFix.map { i.now.timeIntervalSince($0.timestamp) > locationStaleAfter } ?? true)
        let freshness = GoFreshness(locationAsOf: i.lastFix?.timestamp, etaAsOf: i.eta.fetchedAt, conditionsAsOf: c.conditionsAsOf,
                                    packBuiltAt: c.packBuiltAt, isOffline: i.eta.isOffline || c.isOffline, etaIsStale: etaStale,
                                    conditionsAreStale: active && c.isStale, locationIsStale: locationStale, isPowerSaving: i.power.isSaving,
                                    nextRefreshAt: i.nextRefreshAt)

        var undo: GoUndoInfo?
        if let expiry = run.undoExpiry(at: i.now), let pending = run.pendingUndo {
            undo = GoUndoInfo(toPhase: pending.to, stopID: pending.stopID, stopName: stop(pending.stopID)?.place.name, expiresAt: expiry)
        }

        var sources: [String] = []
        func add(_ s: String) { if !s.isEmpty, !sources.contains(s) { sources.append(s) } }
        if drive?.source == .live { add("Apple Maps") }
        for line in c.nextReport?.provenanceLines ?? [] { add(line.label) }
        if let station = c.nextLive?.current?.stationName { add(station) }

        return GoSnapshot(generatedAt: i.now, tripID: i.trip.id, tripName: i.trip.name, runID: run.id, phase: phase, current: currentInfo,
                          next: nextInfo, remainingCount: live?.remaining.count ?? 0, leave: leave, drive: drive, stay: stayInfo,
                          alternative: alternative, sky: nextID == nil ? nil : sky, weather: nextID == nil ? [] : weather,
                          alerts: nextID == nil ? [] : c.alerts, freshness: freshness, undo: undo, sources: Array(sources.prefix(5)))
    }
}
