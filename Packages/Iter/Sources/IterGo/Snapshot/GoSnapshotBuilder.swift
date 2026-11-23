import Foundation
import IterModel
import IterPlan
import IterConditions
import IterSources

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

/// Which stop the conditions are about. Usually the next stop; while you are at a light stop whose window has not ended (plus a
/// short grace), the stop you are standing at.
public enum ConditionsSubject {
    /// How long after its window ends the current stop stays the subject.
    public static let windowGrace: TimeInterval = 5 * 60

    public static func isCurrent(phase: GoPhase, kind: StopKind?, windowEnd: Date?, now: Date) -> Bool {
        guard phase == .atStop, kind == .light, let windowEnd else { return false }
        return now < windowEnd.addingTimeInterval(windowGrace)
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
        let currentStop = stop(live?.currentStop?.stopID)
        let atCurrent = ConditionsSubject.isCurrent(phase: phase, kind: currentStop?.kind, windowEnd: currentInfo?.windowEnd, now: i.now)
        let subjectStop = atCurrent ? currentStop : nextStop
        let subjectInfo = atCurrent ? currentInfo : nextInfo
        let nextID = subjectStop?.id
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

        // Phase 9 detail fields.
        let sameStop = subjectStop.map { c.nextLive?.placeID == $0.place.id } ?? false
        let hours = sameStop ? Self.hours(c.nextLive?.strip ?? [], window: subjectInfo.flatMap { w in w.windowStart.flatMap { s in w.windowEnd.map { TimeSpan(start: s, end: $0) } } }) : nil
        let schedule = phase == .finished ? nil : (live?.upcoming.compactMap { l in
            stop(l.stopID).map { GoScheduleItem(stop: info($0, l), leaveBy: l.leaveBy, arrival: l.projectedArrival, status: GoLeaveStatus(l.status)) }
        }).flatMap { $0.isEmpty ? nil : $0 }
        let details = nextID == nil ? nil : Self.sourceDetails(conditions: c, sameStop: sameStop, drive: drive, etaStale: etaStale, hasAlerts: !c.alerts.isEmpty)

        return GoSnapshot(generatedAt: i.now, tripID: i.trip.id, tripName: i.trip.name, runID: run.id, phase: phase, current: currentInfo,
                          next: nextInfo, remainingCount: live?.remaining.count ?? 0, leave: leave, drive: drive, stay: stayInfo,
                          alternative: alternative, sky: nextID == nil ? nil : sky, weather: nextID == nil ? [] : weather,
                          alerts: nextID == nil ? [] : c.alerts, freshness: freshness, undo: undo, sources: Array(sources.prefix(5)),
                          hours: hours, sourceDetails: details, schedule: schedule, here: i.lastFix?.coordinate,
                          summary: phase == .finished ? Self.summary(i, run: run, ordered: ordered) : nil)
    }

    // MARK: Phase 9 detail fields

    /// The next stop's strip as `GoHourInfo`, at most six hours; nil when there is none.
    static func hours(_ strip: [LiveStripHour], window: TimeSpan?) -> [GoHourInfo]? {
        let out = strip.prefix(6).map { h -> GoHourInfo in
            let basis: GoHourInfo.Basis
            switch h.basis {
            case .observation: basis = .observation
            case .nowcast: basis = .nowcast
            case .forecast: basis = .forecast
            }
            let inWindow = window.map { h.time < $0.end && h.time.addingTimeInterval(3600) > $0.start } ?? false
            let c = h.conditions
            return GoHourInfo(time: h.time, basis: basis, cloudTotal: c.cloudTotal, precipChance: c.precipChance, tempC: c.tempC, windMs: c.windMs,
                              visibilityKm: c.visibilityKm, isInWindow: inWindow)
        }
        return out.isEmpty ? nil : Array(out)
    }

    /// The word for what a forecast field supplies.
    static func role(of field: HourlyField) -> String {
        switch field {
        case .cloudTotal, .cloudLow, .cloudMid, .cloudHigh, .cloudBaseM: "Cloud"
        case .precipChance, .precipMm: "Precipitation"
        case .visibilityKm: "Visibility"
        case .tempC, .dewpointC, .rhPercent: "Temperature"
        case .windMs, .gustMs, .windDirDeg: "Wind"
        case .aod550, .smokeUgm3, .pm25: "Smoke and air quality"
        }
    }

    /// One entry per distinct source, best tier first (ties keep the order the sources were met).
    static func sourceDetails(conditions c: GoConditionsState, sameStop: Bool, drive: GoDriveInfo?, etaStale: Bool, hasAlerts: Bool) -> [GoSourceInfo]? {
        struct Entry { var source: SourceID; var name: String?; var roles: [String]; var tier: SourceTier?; var producer: String?; var asOf: Date?; var distanceKm: Double? }
        var entries: [Entry] = []
        func add(_ source: SourceID, role: String, name: String? = nil, provenance: Provenance?) {
            let origin = provenance?.origin ?? SourceCatalogue.descriptor(source)?.origin
            let asOf = provenance.map { $0.issuedAt ?? $0.fetchedAt }
            if let index = entries.firstIndex(where: { $0.source == source && $0.name == name }) {
                if !entries[index].roles.contains(role) { entries[index].roles.append(role) }
                if entries[index].asOf == nil { entries[index].asOf = asOf }
                if entries[index].distanceKm == nil { entries[index].distanceKm = provenance?.distanceKm }
            } else {
                entries.append(Entry(source: source, name: name, roles: [role], tier: origin?.tier ?? SourceCatalogue.descriptor(source)?.tier,
                                     producer: origin?.producer.isEmpty == false ? origin?.producer : nil, asOf: asOf, distanceKm: provenance?.distanceKm))
            }
        }
        if drive?.source == .live {
            entries.append(Entry(source: SourceID.appleDirections, name: "Apple Maps", roles: ["Drive time"],
                                 tier: SourceCatalogue.appleDirections.tier,
                                 producer: SourceCatalogue.appleDirections.origin.producer, asOf: drive?.asOf, distanceKm: nil))
        }
        if sameStop, let report = c.nextReport {
            for fp in report.fieldProvenance {
                add(fp.provenance.source, role: role(of: fp.field), provenance: fp.provenance)
                for other in fp.contributors where other != fp.provenance.source {
                    add(other, role: role(of: fp.field), provenance: nil)
                }
            }
        }
        if sameStop, let obs = c.nextLive?.current {
            let isMetar = obs.provenance.source == SourceID.aviationWeather
            let station = obs.stationName
            let name = station.map { isMetar ? "\($0) METAR" : $0 }
            add(obs.provenance.source, role: "Observation", name: name, provenance: obs.provenance)
            if let index = entries.lastIndex(where: { $0.source == obs.provenance.source && $0.name == name }), entries[index].distanceKm == nil {
                entries[index].distanceKm = obs.distanceKm
            }
        }
        if sameStop, hasAlerts, let alerts = c.nextReport?.alerts.provenance {
            add(alerts.source, role: "Alerts", provenance: alerts)
        }
        let out = entries.enumerated().map { offset, e -> (Int, SourceTier, GoSourceInfo) in
            let tier = e.tier ?? .openData
            let name = e.name ?? SourceCatalogue.descriptor(e.source)?.name ?? e.source.rawValue
            let isDrive = e.source == SourceID.appleDirections
            return (offset, tier, GoSourceInfo(role: e.roles.joined(separator: ", "), name: name, tier: tier, producer: e.producer, asOf: e.asOf,
                                               distanceKm: e.distanceKm, isStale: isDrive ? etaStale : c.isStale))
        }
        let sorted = out.sorted { ($0.1, $0.0) < ($1.1, $1.0) }.map(\.2)
        return sorted.isEmpty ? nil : sorted
    }

    /// What happened at each stop, in trip order. A stop's score is the last Forecast Sky Index the conditions loop kept for its
    /// window (`ConditionsMemory.trends`, recorded for the next stop only); nil when it never held one.
    static func summary(_ i: GoSnapshotInput, run: TripRun, ordered: [Stop]) -> GoTripSummary {
        let stops = ordered.enumerated().map { index, stop -> GoTripSummary.Stop in
            let visit = run.visits[stop.id]
            let outcome: GoTripSummary.Outcome
            switch visit?.status {
            case .done: outcome = .shot
            case .skipped: outcome = .skipped
            default: outcome = .missed
            }
            let score = stop.kind == .light ? i.conditions.memory.trends.samples(stopID: stop.id, kind: stop.session).last : nil
            return GoTripSummary.Stop(id: stop.id, number: index + 1, name: stop.place.name, windowKind: stop.kind == .light ? stop.session : nil,
                                      outcome: outcome, arrivedAt: visit?.arrivedAt, leftAt: visit?.leftAt, score: score,
                                      timeZoneIdentifier: stop.place.timeZoneIdentifier)
        }
        return GoTripSummary(startedAt: run.startedAt, endedAt: run.endedAt, stops: stops)
    }
}
