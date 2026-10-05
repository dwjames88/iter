import Foundation
import IterCore

/// Identifies a drive between two stops by stop id.
public struct LegKey: Hashable, Sendable, Codable {
    public let from: UUID
    public let to: UUID

    public init(from: UUID, to: UUID) {
        self.from = from
        self.to = to
    }

    public init(_ from: UUID, _ to: UUID) {
        self.from = from
        self.to = to
    }
}

/// The backward schedule ("leave by 4:25") and light-first ordering suggestions. Geometry only: weather plays no part.
public struct TripScheduler: Sendable {
    public let engine: LightEngine

    public init(engine: LightEngine) {
        self.engine = engine
    }

    // MARK: Schedule

    /// Stops in trip order (day-major, array order within a day). For each stop:
    /// - window = its session window on its day; absent gives `.windowMissing` and nil times.
    /// - setUpBy = window start − set-up buffer; arriveBy = setUpBy − walk-in (equal to setUpBy when the walk-in is unknown).
    /// - leaveBy = arriveBy − drive from the previous stop (supplied leg, else a straight-line estimate marked `.driveEstimated`).
    /// - The previous stop is free when its window ends (you shoot through it). Leaving earlier gives `.driveDoesNotFit`.
    ///   This is checked across days too, so an overnight drive is verified rather than assumed.
    /// - `.outOfOrder` when, on the same day, this window starts before the previous stop's window.
    public func schedule(_ trip: TripPlan, legs: [LegKey: DriveLeg]) -> TripSchedule {
        schedule(stops: Self.ordered(trip.stops), in: trip, legs: legs)
    }

    private static func ordered(_ stops: [TripStopPlan]) -> [TripStopPlan] {
        stops.enumerated().sorted { a, b in
            a.element.dayIndex != b.element.dayIndex ? a.element.dayIndex < b.element.dayIndex : a.offset < b.offset
        }.map(\.element)
    }

    private func schedule(stops: [TripStopPlan], in trip: TripPlan, legs: [LegKey: DriveLeg]) -> TripSchedule {
        var result: [StopSchedule] = []
        var previous: (stop: TripStopPlan, window: TimeSpan?)?
        for stop in stops {
            let window = engine.windows(for: stop.spot, on: trip.day(stop.dayIndex)).first { $0.kind == stop.session }?.span
            var issues: [ScheduleIssue] = []
            var setUpBy: Date?, arriveBy: Date?, leaveBy: Date?
            var leg: DriveLeg?
            let walkKnown = stop.spot.walkInMinutes != nil

            if let window {
                setUpBy = window.start.addingTimeInterval(-TimeInterval(stop.setUpBufferMinutes) * 60)
                arriveBy = setUpBy!.addingTimeInterval(-TimeInterval(stop.spot.walkInMinutes ?? 0) * 60)
            } else {
                issues.append(.windowMissing)
            }

            if let previous {
                if let supplied = legs[LegKey(previous.stop.id, stop.id)] {
                    leg = supplied
                } else {
                    leg = DriveLeg.estimate(from: previous.stop.spot.coordinate, to: stop.spot.coordinate)
                }
                if leg?.isEstimate == true { issues.append(.driveEstimated) }
                if let leg, let arriveBy {
                    leaveBy = arriveBy.addingTimeInterval(-leg.seconds)
                    if let freeAt = previous.window?.end, leaveBy! < freeAt {
                        issues.append(.driveDoesNotFit(shortBySeconds: freeAt.timeIntervalSince(leaveBy!)))
                    }
                }
                if let window, let prevWindow = previous.window,
                   previous.stop.dayIndex == stop.dayIndex, window.start < prevWindow.start {
                    issues.append(.outOfOrder)
                }
            }

            result.append(StopSchedule(stopID: stop.id, window: window, setUpBy: setUpBy, arriveBy: arriveBy, leaveBy: leaveBy,
                                       legFromPrevious: leg, walkInKnown: walkKnown, issues: issues))
            previous = (stop, window)
        }
        return TripSchedule(stops: result)
    }

    // MARK: Ordering

    /// Light-first order for each day, as a suggestion only. For each day the stops are sorted by session window start
    /// (stable; stops with no window go last). A suggestion is returned only when the order differs and the whole trip
    /// then has strictly fewer issues (`.driveEstimated` is not counted). Missing legs use estimates.
    public func suggestOrdering(_ trip: TripPlan, legs: [LegKey: DriveLeg]) -> [OrderingSuggestion] {
        let current = Self.ordered(trip.stops)
        let before = schedule(stops: current, in: trip, legs: legs).issueCount
        var out: [OrderingSuggestion] = []
        for dayIndex in 0..<trip.dayCount {
            guard let candidate = lightFirst(trip: trip, current: current, dayIndex: dayIndex) else { continue }
            let after = schedule(stops: candidate.stops, in: trip, legs: legs).issueCount
            if after < before {
                out.append(OrderingSuggestion(dayIndex: dayIndex, order: candidate.dayOrder.map(\.id), issuesBefore: before, issuesAfter: after))
            }
        }
        return out
    }

    /// Every consecutive pair of stops in the current order and in each day's light-first order, so the app knows which
    /// drives to fetch. Deduplicated, in first-seen order.
    public func legPairsNeeded(for trip: TripPlan) -> [LegKey] {
        let current = Self.ordered(trip.stops)
        var sequences = [current]
        for dayIndex in 0..<trip.dayCount {
            if let candidate = lightFirst(trip: trip, current: current, dayIndex: dayIndex) { sequences.append(candidate.stops) }
        }
        var seen = Set<LegKey>()
        var out: [LegKey] = []
        for seq in sequences {
            for (a, b) in zip(seq, seq.dropFirst()) {
                let key = LegKey(a.id, b.id)
                if seen.insert(key).inserted { out.append(key) }
            }
        }
        return out
    }

    /// The trip's stops with one day re-sorted by window start, or nil when that day's order would not change.
    private func lightFirst(trip: TripPlan, current: [TripStopPlan], dayIndex: Int) -> (stops: [TripStopPlan], dayOrder: [TripStopPlan])? {
        let day = current.filter { $0.dayIndex == dayIndex }
        guard day.count >= 2 else { return nil }
        let starts: [UUID: Date] = Dictionary(uniqueKeysWithValues: day.map { stop in
            (stop.id, engine.windows(for: stop.spot, on: trip.day(dayIndex)).first { $0.kind == stop.session }?.span.start ?? .distantFuture)
        })
        let sorted = day.enumerated().sorted { a, b in
            let sa = starts[a.element.id]!, sb = starts[b.element.id]!
            return sa != sb ? sa < sb : a.offset < b.offset
        }.map(\.element)
        guard sorted.map(\.id) != day.map(\.id) else { return nil }
        // Rebuild day-major with the re-sorted day in place.
        var stops: [TripStopPlan] = []
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
