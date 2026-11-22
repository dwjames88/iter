import Foundation
import IterModel
import IterPlan
import IterSky

/// What the row mapping needs beyond the layout.
struct BuildRowContext {
    struct StopScores: Equatable {
        var scores: [LightWindowKind: Int] = [:]
        /// A better forecast is still loading.
        var improving = false
    }

    var trip: Trip
    var scores: [UUID: StopScores]
    /// The pair each stop's incoming drive is asked for as.
    var pairFor: [UUID: LegKey]
    var states: [LegKey: DriveLegState]
    var basis: [LegKey: DriveBasis]
}

/// Pure mapping from the plan's layout (IterPlan) to the builder's plain values. No clock, no store, no I/O.
enum BuildRowFactory {
    static func rows(layout: TripDayLayout, context: BuildRowContext) -> [BuildRow] {
        TripBuilderRow.make(layout).map { row in
            BuildRow(id: row.id, day: row.day, kind: kind(of: row, layout: layout, context: context), position: row.position)
        }
    }

    private static func kind(of row: TripBuilderRow, layout: TripDayLayout, context: BuildRowContext) -> BuildRow.Kind {
        switch row.kind {
        case .dayHeader(let group): .dayHeader(dayHeader(group, context: context))
        case .suggestion(let s): .suggestion(BuildSuggestion(dayIndex: s.dayIndex, order: s.order, issuesBefore: s.issuesBefore,
                                                              issuesAfter: s.issuesAfter))
        case .conflicts(let n): .conflicts(n)
        case .stop(let entry): .stop(stop(entry, context: context))
        case .drive(let item): .drive(drive(item, context: context))
        case .footer(let day, let overnight): .footer(day: day, overnight: overnight.map(overnight(_:)))
        case .transfer(let item, let night):
            .transfer(BuildTransfer(day: row.day, drive: item.map { drive($0, context: context) },
                                    timing: context.trip.transferTiming(intoDay: row.day), canChooseTiming: row.day > 0,
                                    overnight: night.map(overnight(_:))))
        }
    }

    static func overnight(_ boundary: OvernightBoundary) -> BuildOvernight {
        BuildOvernight(afterDay: boundary.afterDay, place: boundary.place, coordinate: boundary.coordinate)
    }

    // MARK: Days

    static func best(of group: TripDayGroup, context: BuildRowContext) -> BuildBestWindow? {
        var best: BuildBestWindow?
        var first: BuildBestWindow?
        for entry in group.stops where entry.stop.kind == .light {
            guard let window = entry.sessionWindow else { continue }
            let score = context.scores[entry.id]?.scores[entry.stop.session]
            let candidate = BuildBestWindow(stopID: entry.id, kind: window.kind, score: score, start: window.span.start,
                                            end: window.span.end, timeZone: entry.stop.place.timeZone)
            if first == nil { first = candidate }
            if let score, score > (best?.score ?? -1) { best = candidate }
        }
        return best ?? first
    }

    static func dayHeader(_ group: TripDayGroup, context: BuildRowContext) -> BuildDayHeader {
        BuildDayHeader(index: group.index, date: group.date, sunrise: group.sunrise, sunset: group.sunset, timeZone: group.timeZone,
                       stopCount: group.stopCount, drivingSeconds: group.drivingSeconds, hasEstimatedDrive: group.hasEstimatedDrive,
                       conflictCount: group.conflictCount, best: best(of: group, context: context))
    }

    static func dayItems(layout: TripDayLayout, context: BuildRowContext) -> [BuildDayItem] {
        layout.groups.map { group in
            let best = best(of: group, context: context)
            return BuildDayItem(index: group.index, date: group.date, stopCount: group.stopCount,
                                primarySession: best?.kind ?? group.stops.first?.stop.session, bestScore: best?.score,
                                hasConflict: group.hasConflict)
        }
    }

    // MARK: Stops

    static func stop(_ entry: TripStopEntry, context: BuildRowContext) -> BuildStop {
        let stop = entry.stop
        let schedule = entry.schedule
        let scores = context.scores[stop.id] ?? .init()
        let options = entry.windows.map { window in
            BuildWindowOption(kind: window.kind, start: window.span.start, end: window.span.end, score: scores.scores[window.kind])
        }
        let isLight = stop.kind == .light
        return BuildStop(
            id: stop.id, placeID: stop.place.id, number: entry.number, name: stop.place.name, locality: stop.place.locality,
            coordinate: stop.place.coordinate, kind: stop.kind, session: stop.session, timeZone: stop.place.timeZone,
            time: isLight ? (schedule?.setUpBy ?? schedule?.arriveBy) : schedule?.arriveBy,
            timeLabel: isLight ? .setUp : .arrive,
            parkAt: isLight ? schedule?.arriveBy : nil,
            walkInMinutes: stop.place.walkInMinutes, setUpBufferMinutes: stop.setUpBufferMinutes, dwellMinutes: stop.dwellMinutes,
            shootUntil: schedule?.departAt, fixedArrival: stop.fixedArrival, options: options,
            score: isLight ? scores.scores[stop.session] : nil, scoreIsImproving: isLight && scores.improving,
            note: stop.note,
            // A drive that does not fit is shown on the drive row, not twice.
            issues: entry.conflicts.compactMap { issue in
                if case .driveDoesNotFit = issue { return nil }
                return BuildIssue(issue)
            })
    }

    // MARK: Drives

    static func drive(_ item: TripDriveItem, context: BuildRowContext) -> BuildDrive {
        let pair = context.pairFor[item.toStopID]
        let state = pair.flatMap { context.states[$0] } ?? .loading
        var basis: DriveBasis?
        if item.leg != nil { basis = pair.flatMap { context.basis[$0] } ?? .estimate }
        if item.isEstimate { basis = .estimate }
        return BuildDrive(toStopID: item.toStopID, fromName: item.fromName, fromLocality: item.fromLocality, fromStart: item.fromStart,
                          state: state, seconds: item.leg?.seconds, meters: item.leg?.meters, isEstimate: item.isEstimate,
                          basis: basis, leaveBy: item.leaveBy, leaveZone: item.leaveZone,
                          issue: item.shortBySeconds.map { .driveDoesNotFit(shortBySeconds: $0) }, note: item.note,
                          transferTiming: item.transferTiming)
    }
}
