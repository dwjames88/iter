import Foundation
import IterModel

/// The backward schedule ("leave by 4:25") and light-first ordering suggestions. Pure: geometry and arithmetic only, no
/// clock, no I/O, no weather. Session windows and drive legs come in as values.
public struct Scheduler: Sendable {
    public init() {}

    // MARK: Schedule

    /// Stops in trip order (day-major, array order within a day). For each stop:
    ///
    /// **Light stops** (`kind == .light`)
    /// - window = its session window; absent gives `.windowMissing` and nil times (a `fixedArrival` on such a stop is still
    ///   honoured as `arriveBy`).
    /// - setUpBy = window start − set-up buffer; arriveBy = setUpBy − walk-in (equal to setUpBy when the walk-in is unknown).
    ///   A `fixedArrival`, when set, overrides `arriveBy` (the user said when they will be there); `setUpBy` is unchanged.
    /// - departAt = window start + dwell when dwell > 0, else the window end (you shoot through it).
    ///
    /// **Lodging and waypoints**: no light window, so no `.windowMissing`.
    /// - arriveBy = `fixedArrival` on the stop's own day in the stop's own time zone when set (a constraint).
    ///   Otherwise it is an estimate, the previous stop's `departAt` plus the drive, not a constraint, and `leaveBy` is
    ///   the previous stop's `departAt`. With no previous stop or no known departure, both are nil.
    /// - departAt = arrival + dwell. A lodging with dwell 0 is "overnight": `departAt` is nil, and the next stop is free
    ///   whenever its own leave-by says.
    ///
    /// **Drives**
    /// - leaveBy = arriveBy − drive (supplied leg, else a straight-line estimate marked `.driveEstimated`).
    /// - The previous stop frees you at its `departAt`. Leaving earlier gives `.driveDoesNotFit`. Checked across days too, so
    ///   an overnight drive is verified rather than assumed. A nil `departAt` (overnight lodging, missing window) is not checked.
    /// - **Start place**: the trip's first stop gets its drive from `start` (leg key `start.id → first.id`), `fromStart = true`,
    ///   and a leaveBy. With no start place its leaveBy is nil. The start is never checked for fit: you leave when you like.
    /// - For a stop whose previous stop is on an earlier day, the trip's transfer timing into that day applies. Morning is
    ///   as above. `.eveningBefore`: leaveBy = the previous stop's `departAt` (nil when unknown), and the drive does not fit
    ///   only when leaveBy + drive is after this stop's arriveBy. If the previous stop is an overnight lodging the evening
    ///   option has no meaning (you are already asleep there), so the morning rule applies.
    /// - `.outOfOrder` when, on the same day, this window starts before the previous stop's window.
    public func schedule(trip: Trip, start: Place?, windows: SessionWindows, legs: [LegKey: Leg]) -> TripSchedule {
        run(stops: Self.ordered(trip.stops), trip: trip, start: start, windows: windows, legs: legs)
    }

    static func ordered(_ stops: [Stop]) -> [Stop] {
        stops.enumerated().sorted { a, b in
            a.element.dayIndex != b.element.dayIndex ? a.element.dayIndex < b.element.dayIndex : a.offset < b.offset
        }.map(\.element)
    }

    private func run(stops: [Stop], trip: Trip, start: Place?, windows: SessionWindows, legs: [LegKey: Leg]) -> TripSchedule {
        var result: [StopSchedule] = []
        var previous: (stop: Stop, window: TimeSpan?, departAt: Date?)?
        for stop in stops {
            let window = stop.kind == .light ? windows[stop.id] : nil
            var issues: [ScheduleIssue] = []
            var leaveBy: Date?
            var leg: Leg?
            var fromStart = false
            var timing: TransferTiming?
            let times = Self.timing(for: stop, trip: trip, window: window)
            var arriveBy = times.arriveBy
            if stop.kind == .light, window == nil { issues.append(.windowMissing) }

            if let previous {
                leg = legs[LegKey(previous.stop.id, stop.id)] ?? Leg.estimate(from: previous.stop.place.coordinate, to: stop.place.coordinate)
                if stop.dayIndex > previous.stop.dayIndex { timing = trip.transferTiming(intoDay: stop.dayIndex) }
            } else if let start {
                leg = legs[LegKey(start.id, stop.id)] ?? Leg.estimate(from: start.coordinate, to: stop.place.coordinate)
                fromStart = true
            }
            if leg?.isEstimate == true { issues.append(.driveEstimated) }

            if let leg {
                let freeAt = previous?.departAt
                let overnightLodging = previous.map { $0.stop.kind == .lodging && $0.departAt == nil } ?? false
                if let constraint = times.constraint {
                    if timing == .eveningBefore, !overnightLodging {
                        // The drive starts when the previous stop frees you; it must be done by this stop's arrival.
                        if let freeAt {
                            leaveBy = freeAt
                            let done = freeAt.addingTimeInterval(leg.seconds)
                            if done > constraint { issues.append(.driveDoesNotFit(shortBySeconds: done.timeIntervalSince(constraint))) }
                        }
                    } else {
                        leaveBy = constraint.addingTimeInterval(-leg.seconds)
                        if let freeAt, leaveBy! < freeAt {
                            issues.append(.driveDoesNotFit(shortBySeconds: freeAt.timeIntervalSince(leaveBy!)))
                        }
                    }
                } else if stop.kind != .light, let freeAt {
                    // A flexible stop: you go when the previous stop frees you, and arrive after the drive. An estimate only.
                    leaveBy = freeAt
                    arriveBy = freeAt.addingTimeInterval(leg.seconds)
                }
            }
            if let previous, let window, let prevWindow = previous.window,
               previous.stop.dayIndex == stop.dayIndex, window.start < prevWindow.start {
                issues.append(.outOfOrder)
            }

            let departAt = Self.departAt(for: stop, window: window, arrival: arriveBy)
            result.append(StopSchedule(stopID: stop.id, kind: stop.kind, window: window, setUpBy: times.setUpBy, arriveBy: arriveBy,
                                       leaveBy: leaveBy, departAt: departAt, legFromPrevious: leg, fromStart: fromStart,
                                       walkInKnown: stop.place.walkInMinutes != nil, issues: issues, transferTiming: timing))
            previous = (stop, window, departAt)
        }
        return TripSchedule(stops: result)
    }

    // MARK: Per-stop arithmetic (shared with the live schedule)

    struct StopTiming {
        var setUpBy: Date?
        var arriveBy: Date?
        /// The instant you are bound to be there by, if any: `arriveBy` when it came from a window or a fixed arrival.
        var constraint: Date? { arriveBy }
    }

    static func timing(for stop: Stop, trip: Trip, window: TimeSpan?) -> StopTiming {
        var out = StopTiming()
        if stop.kind == .light, let window {
            out.setUpBy = window.start.addingTimeInterval(-TimeInterval(stop.setUpBufferMinutes) * 60)
            out.arriveBy = out.setUpBy!.addingTimeInterval(-TimeInterval(stop.place.walkInMinutes ?? 0) * 60)
        }
        if let fixed = stop.fixedArrival {
            out.arriveBy = fixedInstant(fixed, day: trip.day(stop.dayIndex), in: stop.place.timeZone)
        }
        return out
    }

    /// When you are free to leave `stop`. See `schedule(trip:start:windows:legs:)`.
    static func departAt(for stop: Stop, window: TimeSpan?, arrival: Date?) -> Date? {
        let dwell = TimeInterval(max(0, stop.dwellMinutes)) * 60
        switch stop.kind {
        case .light:
            guard let window else { return nil }
            return dwell > 0 ? window.start.addingTimeInterval(dwell) : window.end
        case .lodging:
            guard let arrival, dwell > 0 else { return nil }
            return arrival.addingTimeInterval(dwell)
        case .waypoint:
            return arrival?.addingTimeInterval(dwell)
        }
    }

    /// The instant of a wall-clock time on a day in a zone. A time that does not exist there (the hour skipped when clocks
    /// spring forward, e.g. 02:30 on 2027-03-14 in America/Denver) resolves to the next valid instant: the first moment after
    /// the gap (03:00). A time that happens twice (clocks falling back) resolves to its first occurrence.
    public static func fixedInstant(_ time: LocalTime, day: LocalDay, in zone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let components = DateComponents(year: day.year, month: day.month, day: day.day, hour: time.hour, minute: time.minute)
        let direct = calendar.date(from: components)!
        let back = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: direct)
        if back.day == day.day, back.hour == time.hour, back.minute == time.minute { return direct }
        // In a gap: Foundation shifted by the gap length. Ask for the next time that exists instead.
        let before = day.start(in: zone).addingTimeInterval(-1)
        let next = calendar.nextDate(after: before, matching: DateComponents(hour: time.hour, minute: time.minute),
                                     matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
        return next ?? direct
    }

    // MARK: Ordering

    /// Light-first order for each day, as a suggestion only. For each day the stops are sorted by the time they are bound to:
    /// a stop with a `fixedArrival` by that time on its day; a light stop by its session window start; every other stop
    /// (a lodging or waypoint with no fixed time, a light stop with no window) after those, in its current order. Stable.
    /// A suggestion is returned only when the order differs and the whole trip then has strictly fewer issues
    /// (`.driveEstimated` is not counted). Missing legs use estimates.
    public func suggestOrdering(trip: Trip, start: Place?, windows: SessionWindows, legs: [LegKey: Leg]) -> [OrderingSuggestion] {
        let current = Self.ordered(trip.stops)
        let before = run(stops: current, trip: trip, start: start, windows: windows, legs: legs).issueCount
        var out: [OrderingSuggestion] = []
        for dayIndex in 0..<trip.dayCount {
            guard let candidate = lightFirst(current: current, trip: trip, dayIndex: dayIndex, windows: windows) else { continue }
            let after = run(stops: candidate.stops, trip: trip, start: start, windows: windows, legs: legs).issueCount
            if after < before {
                out.append(OrderingSuggestion(dayIndex: dayIndex, order: candidate.dayOrder.map(\.id), issuesBefore: before, issuesAfter: after))
            }
        }
        return out
    }

    /// Every consecutive pair of stops in the current order and in each day's light-first order, plus the start place's pair
    /// with each sequence's first stop, so the app knows which drives to fetch. Deduplicated, in first-seen order.
    public func legPairsNeeded(for trip: Trip, start: Place?, windows: SessionWindows) -> [LegKey] {
        let current = Self.ordered(trip.stops)
        var sequences = [current]
        for dayIndex in 0..<trip.dayCount {
            if let candidate = lightFirst(current: current, trip: trip, dayIndex: dayIndex, windows: windows) { sequences.append(candidate.stops) }
        }
        var seen = Set<LegKey>()
        var out: [LegKey] = []
        for seq in sequences {
            if let start, let first = seq.first {
                let key = LegKey(start.id, first.id)
                if seen.insert(key).inserted { out.append(key) }
            }
            for (a, b) in zip(seq, seq.dropFirst()) {
                let key = LegKey(a.id, b.id)
                if seen.insert(key).inserted { out.append(key) }
            }
        }
        return out
    }

    /// The trip's stops with one day re-sorted by bound time, or nil when that day's order would not change.
    private func lightFirst(current: [Stop], trip: Trip, dayIndex: Int, windows: SessionWindows) -> (stops: [Stop], dayOrder: [Stop])? {
        let day = current.filter { $0.dayIndex == dayIndex }
        guard day.count >= 2 else { return nil }
        let keys: [UUID: Date] = Dictionary(uniqueKeysWithValues: day.map { stop in
            if let fixed = stop.fixedArrival {
                return (stop.id, Self.fixedInstant(fixed, day: trip.day(stop.dayIndex), in: stop.place.timeZone))
            }
            if stop.kind == .light, let window = windows[stop.id] { return (stop.id, window.start) }
            return (stop.id, .distantFuture)
        })
        let sorted = day.enumerated().sorted { a, b in
            let sa = keys[a.element.id]!, sb = keys[b.element.id]!
            return sa != sb ? sa < sb : a.offset < b.offset
        }.map(\.element)
        guard sorted.map(\.id) != day.map(\.id) else { return nil }
        // Rebuild day-major with the re-sorted day in place.
        var stops: [Stop] = []
        var inserted = false
        for stop in current {
            if stop.dayIndex == dayIndex {
                if !inserted { stops.append(contentsOf: sorted); inserted = true }
            } else {
                stops.append(stop)
            }
        }
        return (stops, sorted)
    }
}
