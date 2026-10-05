import Foundation
import Observation
import IterCore
import IterLight
import IterData

/// One stop as the builder shows it: the plan, its schedule, and the windows of its day at its spot.
public struct TripStopEntry: Identifiable, Sendable {
    public var stop: TripStopPlan
    /// 1-based position in the whole trip (the number on the map pin).
    public var number: Int
    public var schedule: StopSchedule?
    /// The stop before this one in trip order (possibly on an earlier day).
    public var previous: TripStopPlan?
    /// Every window the sun produces on this stop's day at this spot, with its score or "no forecast".
    public var windows: [LightWindow]
    /// The window for the stop's chosen session; nil when the sun does not produce it that day.
    public var sessionWindow: LightWindow?

    public var id: UUID { stop.id }
    public var isOvernightFromPrevious: Bool { previous.map { $0.dayIndex != stop.dayIndex } ?? false }
}

/// One day of the trip with its stops and totals.
public struct TripDay: Identifiable, Sendable {
    public var index: Int
    public var day: LocalDay
    public var stops: [TripStopEntry]
    /// Driving between this day's stops plus the drive into its first stop from the day before.
    public var drivingSeconds: TimeInterval
    /// Any of those drives is a straight-line estimate.
    public var hasEstimatedDrive: Bool
    /// Sun times at the first stop's place, in that place's zone. nil when the day has no stops.
    public var sunrise: Date?
    public var sunset: Date?
    public var timeZoneIdentifier: String?

    public var id: Int { index }
    public var timeZone: TimeZone { timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current }
}

/// The trip builder's brain: the plan as a value, its drive legs (MapKit with an honest estimate on failure),
/// the backward schedule, and the light-first suggestions. Platform-neutral; the app draws it.
///
/// Call `refresh()` whenever `store.revision` or `forecasts.revision` changes. It recomputes everything that is
/// cheap straight away and fetches missing drives in the background, cancelling work that has gone stale.
@MainActor
@Observable
public final class TripBuilderModel {
    public let tripID: UUID

    /// nil when the trip no longer exists (deleted, or its creation undone).
    public private(set) var plan: TripPlan?
    public private(set) var schedule = TripSchedule(stops: [])
    public private(set) var days: [TripDay] = []
    public private(set) var legs: [LegKey: DriveLeg] = [:]
    /// Light-first suggestions that have not been dismissed.
    public private(set) var suggestions: [OrderingSuggestion] = []
    /// True while drives are being fetched.
    public private(set) var isLoadingLegs = false

    @ObservationIgnored private let store: IterStore
    @ObservationIgnored private let scheduler: TripScheduler
    @ObservationIgnored private let drives: any DriveTimeProviding
    @ObservationIgnored private let forecasts: ForecastCenter
    @ObservationIgnored private let dismissals: SuggestionDismissals
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var legTask: Task<Void, Never>?
    @ObservationIgnored private var loadingKeys: Set<LegKey> = []
    @ObservationIgnored private var allSuggestions: [OrderingSuggestion] = []
    @ObservationIgnored private var seenStoreRevision = -1
    @ObservationIgnored private var seenForecastRevision = -1

    public init(tripID: UUID, store: IterStore, scheduler: TripScheduler, drives: any DriveTimeProviding,
                forecasts: ForecastCenter, dismissals: SuggestionDismissals = .shared,
                now: @escaping @MainActor () -> Date = { Date() }) {
        self.tripID = tripID
        self.store = store
        self.scheduler = scheduler
        self.drives = drives
        self.forecasts = forecasts
        self.dismissals = dismissals
        self.now = now
        refresh()
    }

    isolated deinit { legTask?.cancel() }

    // MARK: - Refresh

    /// Refreshes only if the store or the forecasts changed since the last refresh (the view calls this on every change).
    public func refreshIfChanged() {
        if store.revision != seenStoreRevision || forecasts.revision != seenForecastRevision { refresh() }
    }

    public func refresh() {
        seenStoreRevision = store.revision
        seenForecastRevision = forecasts.revision
        guard let record = store.trip(id: tripID) else {
            legTask?.cancel()
            legTask = nil
            loadingKeys = []
            isLoadingLegs = false
            plan = nil
            schedule = TripSchedule(stops: [])
            days = []
            suggestions = []
            return
        }
        let plan = record.plan
        self.plan = plan
        forecasts.requestAll(plan.stops.map(\.spot.coordinate))
        dropStaleLegs(plan)
        recompute()
        loadMissingLegs(plan)
    }

    /// Waits for the current background drive fetch (tests).
    public func waitForLegs() async {
        await legTask?.value
    }

    private func dropStaleLegs(_ plan: TripPlan) {
        let coordinates = Dictionary(plan.stops.map { ($0.id, $0.spot.coordinate) }, uniquingKeysWith: { first, _ in first })
        legs = legs.filter { key, leg in
            guard let a = coordinates[key.from], let b = coordinates[key.to] else { return false }
            return leg.from == a && leg.to == b
        }
    }

    private func loadMissingLegs(_ plan: TripPlan) {
        let missing = scheduler.legPairsNeeded(for: plan).filter { legs[$0] == nil }
        if missing.isEmpty {
            legTask?.cancel()
            legTask = nil
            loadingKeys = []
            isLoadingLegs = false
            return
        }
        // Nothing new to fetch: let the running task finish.
        if legTask != nil, Set(missing).isSubset(of: loadingKeys) { return }
        legTask?.cancel()
        loadingKeys = Set(missing)
        isLoadingLegs = true
        let coordinates = Dictionary(plan.stops.map { ($0.id, $0.spot.coordinate) }, uniquingKeysWith: { first, _ in first })
        let drives = self.drives
        legTask = Task { [weak self] in
            for key in missing {
                if Task.isCancelled { return }
                guard let a = coordinates[key.from], let b = coordinates[key.to] else { continue }
                let leg: DriveLeg
                do {
                    leg = try await drives.drive(from: a, to: b)
                } catch is CancellationError {
                    return
                } catch {
                    leg = DriveLeg.estimate(from: a, to: b)
                }
                if Task.isCancelled { return }
                guard let self else { return }
                self.legs[key] = leg
                self.loadingKeys.remove(key)
                self.recompute()
            }
            guard !Task.isCancelled, let self else { return }
            self.isLoadingLegs = false
            self.legTask = nil
            self.loadingKeys = []
        }
    }

    // MARK: - Derived state

    private func recompute() {
        guard let plan else { return }
        let schedule = scheduler.schedule(plan, legs: legs)
        self.schedule = schedule
        allSuggestions = scheduler.suggestOrdering(plan, legs: legs)
        suggestions = allSuggestions.filter { !dismissals.isDismissed(trip: tripID, day: $0.dayIndex, order: $0.order) }
        days = buildDays(plan: plan, schedule: schedule)
    }

    private func buildDays(plan: TripPlan, schedule: TripSchedule) -> [TripDay] {
        var number = 0
        var previous: TripStopPlan?
        var out: [TripDay] = []
        let engine = scheduler.engine
        let clock = now()
        var lightCache: [UUID: DayLight] = [:]
        for index in 0..<plan.dayCount {
            let date = plan.day(index)
            var entries: [TripStopEntry] = []
            var driving: TimeInterval = 0
            var estimated = false
            for stop in plan.stops(onDay: index) {
                number += 1
                let state = forecasts.state(for: stop.spot.coordinate)
                let light = engine.dayLight(for: stop.spot, on: date, forecast: state.forecast,
                                            unavailable: state.unavailableReason, now: clock)
                lightCache[stop.id] = light
                let entrySchedule = schedule.schedule(for: stop.id)
                if let leg = entrySchedule?.legFromPrevious {
                    driving += leg.seconds
                    if leg.isEstimate { estimated = true }
                }
                entries.append(TripStopEntry(stop: stop, number: number, schedule: entrySchedule, previous: previous,
                                             windows: light.windows, sessionWindow: light.window(stop.session)))
                previous = stop
            }
            let first = entries.first.flatMap { lightCache[$0.id] }
            out.append(TripDay(index: index, day: date, stops: entries, drivingSeconds: driving, hasEstimatedDrive: estimated,
                               sunrise: first?.sun.sunrise, sunset: first?.sun.sunset, timeZoneIdentifier: first?.timeZoneIdentifier))
        }
        return out
    }

    /// All drives in the trip, in current order.
    public var totalDriveSeconds: TimeInterval { schedule.stops.compactMap(\.legFromPrevious).reduce(0) { $0 + $1.seconds } }
    public var totalDriveMeters: Double { schedule.stops.compactMap(\.legFromPrevious).reduce(0) { $0 + $1.meters } }
    public var hasEstimatedDrive: Bool { schedule.stops.contains { $0.legFromPrevious?.isEstimate == true } }

    /// The visible suggestion for a day, if any.
    public func suggestion(forDay day: Int) -> OrderingSuggestion? {
        suggestions.first { $0.dayIndex == day }
    }

    /// How many conflicts applying the suggestion removes.
    public func conflictsFixed(by suggestion: OrderingSuggestion) -> Int {
        max(0, suggestion.issuesBefore - suggestion.issuesAfter)
    }

    // MARK: - Edits (all undoable through the store)

    private func record() -> TripRecord? { store.trip(id: tripID) }

    private func stopRecord(_ id: UUID) -> StopRecord? {
        record()?.orderedStops.first { $0.id == id }
    }

    public func rename(to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let record = record() else { return }
        store.renameTrip(record, to: trimmed)
        refresh()
    }

    /// How many stops would move to the last day if the trip had `dayCount` days.
    public func stopsDisplaced(byDayCount dayCount: Int) -> Int {
        guard let plan else { return 0 }
        let last = max(1, dayCount) - 1
        return plan.stops.filter { $0.dayIndex > last }.count
    }

    /// Returns how many stops moved to the last day.
    @discardableResult
    public func setDates(start: LocalDay, dayCount: Int) -> Int {
        guard let record = record() else { return 0 }
        let moved = store.setDates(record, startDay: start, dayCount: dayCount)
        refresh()
        return moved
    }

    public func deleteTrip() {
        guard let record = record() else { return }
        store.deleteTrip(record)
        refresh()
    }

    @discardableResult
    public func addStop(_ spot: Spot, toDay day: Int, defaultBufferMinutes: Int) -> UUID? {
        guard let record = record() else { return nil }
        let stop = store.addStop(spot, to: record, day: day)
        let id = stop.id
        if stop.setUpBufferMinutes != defaultBufferMinutes { store.setBuffer(stop, minutes: defaultBufferMinutes) }
        refresh()
        return id
    }

    public func removeStop(_ id: UUID) {
        guard let stop = stopRecord(id) else { return }
        store.removeStop(stop)
        refresh()
    }

    /// Moves a stop to `day`, placing it before the stop `before` (which must be on that day) or at the end.
    public func moveStop(_ id: UUID, toDay day: Int, before: UUID? = nil) {
        guard let plan, let stop = stopRecord(id) else { return }
        let target = plan.stops(onDay: day).filter { $0.id != id }
        let index = before.flatMap { anchor in target.firstIndex { $0.id == anchor } }
        store.moveStop(stop, toDay: day, index: index)
        refresh()
    }

    /// Moves a stop one place earlier or later within its day (the keyboard and VoiceOver route).
    public func nudgeStop(_ id: UUID, by offset: Int) {
        guard let plan, let stop = plan.stops.first(where: { $0.id == id }) else { return }
        let day = plan.stops(onDay: stop.dayIndex)
        guard let current = day.firstIndex(where: { $0.id == id }) else { return }
        let target = current + offset
        guard day.indices.contains(target), let record = stopRecord(id) else { return }
        store.moveStop(record, toDay: stop.dayIndex, index: target)
        refresh()
    }

    public func canNudge(_ id: UUID, by offset: Int) -> Bool {
        guard let plan, let stop = plan.stops.first(where: { $0.id == id }) else { return false }
        let day = plan.stops(onDay: stop.dayIndex)
        guard let current = day.firstIndex(where: { $0.id == id }) else { return false }
        return day.indices.contains(current + offset)
    }

    public func setSession(_ id: UUID, to session: LightWindowKind) {
        guard let stop = stopRecord(id) else { return }
        store.setSession(stop, to: session)
        refresh()
    }

    public func setNote(_ id: UUID, to note: String) {
        guard let stop = stopRecord(id) else { return }
        store.setNote(stop, to: note)
        refresh()
    }

    public func setBuffer(_ id: UUID, minutes: Int) {
        guard let stop = stopRecord(id) else { return }
        store.setBuffer(stop, minutes: minutes)
        refresh()
    }

    // MARK: - Suggestions

    public func apply(_ suggestion: OrderingSuggestion) {
        guard let record = record() else { return }
        store.reorder(day: suggestion.dayIndex, in: record, to: suggestion.order)
        refresh()
    }

    public func dismiss(_ suggestion: OrderingSuggestion) {
        dismissals.dismiss(trip: tripID, day: suggestion.dayIndex, order: suggestion.order)
        suggestions = allSuggestions.filter { !dismissals.isDismissed(trip: tripID, day: $0.dayIndex, order: $0.order) }
    }

    // MARK: - Add stop

    /// The "Add stop" list for one day: saved and curated spots, nearest first.
    public func addStopList(forDay day: Int, query: String) -> AddStopList {
        let plan = self.plan ?? TripPlan(name: "", startDay: LocalDay(year: 1970, month: 1, day: 1), dayCount: 1)
        return AddStopCandidates.make(plan: plan, day: day, saved: store.savedPlaces().map(\.spot),
                                      curated: CuratedSpots.all, query: query)
    }
}
