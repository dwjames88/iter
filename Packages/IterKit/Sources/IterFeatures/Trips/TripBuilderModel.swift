import Foundation
import Observation
import IterCore
import IterLight
import IterData
import IterServices

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

/// One drive as the route map draws it: the road path (or a straight line when the path is unknown) into a stop.
public struct TripMapLeg: Equatable, Sendable, Identifiable {
    /// The stop the drive arrives at.
    public var id: UUID
    /// The day of that stop.
    public var day: Int
    public var path: [Coordinate]
}

/// One numbered pin on the route map.
public struct TripMapPin: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var coordinate: Coordinate
    /// 1-based position in the whole trip.
    public var number: Int
    public var day: Int
}

/// One entry of the map's day switcher.
public struct TripMapDay: Equatable, Sendable, Identifiable {
    public var index: Int
    public var date: LocalDay
    public var id: Int { index }
}

/// Everything the route map draws, as plain values. The model replaces it only when it really differs, so a forecast, a
/// schedule time or any other change that leaves the geometry alone does not invalidate the map.
public struct TripMapContent: Equatable, Sendable {
    public var days: [TripMapDay] = []
    public var legs: [TripMapLeg] = []
    public var pins: [TripMapPin] = []

    public init() {}

    init(days tripDays: [TripDay]) {
        for day in tripDays {
            days.append(TripMapDay(index: day.index, date: day.day))
            for entry in day.stops {
                pins.append(TripMapPin(id: entry.id, name: entry.stop.spot.name, coordinate: entry.stop.spot.coordinate,
                                       number: entry.number, day: day.index))
                if let leg = entry.schedule?.legFromPrevious {
                    legs.append(TripMapLeg(id: entry.id, day: day.index, path: leg.path.count >= 2 ? leg.path : [leg.from, leg.to]))
                }
            }
        }
    }
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
    /// The day-first shape of the plan: day groups with their timelines, overnight boundaries and overview cells.
    public private(set) var layout = TripDayLayout(groups: [])
    /// True while drives are being fetched.
    public private(set) var isLoadingLegs = false
    /// What the route map draws (pins, drive paths, day switcher); equal across changes that do not touch the geometry.
    public private(set) var mapContent = TripMapContent()
    /// What an automatic camera fit frames: the focus day's stops, or every stop when no day is focused (or it has none).
    public private(set) var fitCoordinates: [Coordinate] = []

    @ObservationIgnored private let store: IterStore
    @ObservationIgnored private let scheduler: TripScheduler
    @ObservationIgnored private let drives: any DriveTimeProviding
    @ObservationIgnored private let forecasts: ForecastCenter
    @ObservationIgnored private let dismissals: SuggestionDismissals
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var legTask: Task<Void, Never>?
    /// The pending coalesced recompute after drive legs arrived, and whether there is anything for it to apply.
    @ObservationIgnored private var legFlushTask: Task<Void, Never>?
    @ObservationIgnored private var legsDirty = false
    /// Legs that arrive within this window of each other cause one recompute, not one each.
    @ObservationIgnored private let legCoalescing: Duration
    /// Pairs whose last fetch failed for a reason that may pass (throttled, offline), with when to try again. They stay
    /// out of `legs` (the schedule shows its own estimate meanwhile) so the next refresh after that time asks again.
    @ObservationIgnored private var retryAfter: [LegKey: Date] = [:]
    /// Day light for each stop at the last refresh, and the session spans the scheduler works from.
    @ObservationIgnored private var lights: [UUID: DayLight] = [:]
    @ObservationIgnored private var sessionWindows: TripScheduler.SessionWindows = [:]
    @ObservationIgnored private var lightClock = Date.distantPast
    @ObservationIgnored private var lightCache: [LightKey: LightCacheEntry] = [:]
    @ObservationIgnored private var loadingKeys: Set<LegKey> = []
    @ObservationIgnored private var allSuggestions: [OrderingSuggestion] = []
    @ObservationIgnored private var seenStoreRevision = -1
    @ObservationIgnored private var seenForecastRevision = -1
    @ObservationIgnored private let defaults: UserDefaults
    /// How many times the derived state was rebuilt, and how many `dayLight` computations that took (tests and the perf
    /// script read these; nothing else does).
    @ObservationIgnored public private(set) var recomputeCount = 0
    @ObservationIgnored public private(set) var dayLightCount = 0

    // MARK: - Map camera

    /// The route map's camera policy (never zooms out past a continent on its own; remembers where the user left it).
    @ObservationIgnored public private(set) var cameraPolicy: MapCameraPolicy
    /// The latest camera command for the map; the view applies a request when its `id` changes.
    public private(set) var cameraRequest: CameraRequest?
    /// The day the picker has chosen; the automatic fit frames its stops (nil: the whole route).
    public private(set) var focusDay: Int?
    @ObservationIgnored private var visibleRegion: GeoRegion?
    @ObservationIgnored private var requestCounter = 0

    public static func cameraScreenKey(for tripID: UUID) -> String { "trip-\(tripID.uuidString)" }

    private func updateFitCoordinates() {
        let all = days.flatMap(\.stops)
        var fit = all.map { $0.stop.spot.coordinate }
        if let focusDay {
            let day = all.filter { $0.stop.dayIndex == focusDay }
            if !day.isEmpty { fit = day.map { $0.stop.spot.coordinate } }
        }
        if fit != fitCoordinates { fitCoordinates = fit }
    }

    /// Where the map should start (saved camera, else a fit), so the view is created already framed. Records nothing.
    public var initialCameraRegion: GeoRegion? { cameraPolicy.initialRegion(for: fitCoordinates) }

    /// First appearance: the saved camera for this trip if any, else a fit (capped by the policy).
    public func requestInitialCamera() {
        guard let region = cameraPolicy.initialRegion(for: fitCoordinates) else { return }
        if cameraPolicy.savedRegion == nil { cameraPolicy.didApplyFit(region) } else { cameraPolicy.didRestoreSavedCamera() }
        cameraRequest = CameraRequest(id: nextRequestID(), kind: .fit(region))
    }

    /// The picker chose another day (nil: the whole route): refit unless the user has moved the map since the last fit.
    public func setFocusDay(_ day: Int?) {
        guard day != focusDay else { return }
        focusDay = day
        updateFitCoordinates()
        contentChanged()
    }

    /// Stops were added, removed or moved: refit unless the user has moved the map since the last fit.
    public func contentChanged() {
        guard let target = MapCameraPolicy.fit(fitCoordinates) else { return }
        if target == cameraPolicy.lastFitRegion, !cameraPolicy.userMovedSinceFit { return }
        guard let region = cameraPolicy.regionAfterContentChange(fitCoordinates) else { return }
        cameraRequest = CameraRequest(id: nextRequestID(), kind: .fit(region))
    }

    /// Pans the map so the coordinate is comfortably in view; does nothing when it already is, never changes the zoom.
    public func reveal(_ coordinate: Coordinate) {
        guard let current = visibleRegion ?? cameraPolicy.savedRegion else { return }
        let target = MapCameraPolicy.pan(current, toInclude: coordinate)
        guard target != current else { return }
        cameraPolicy.didApplyPan(target)
        cameraRequest = CameraRequest(id: nextRequestID(), kind: .pan(target))
    }

    /// The map settled at `region` (called by the view when the camera stops moving).
    /// `byUser` is true only when the user really moved the map. A settle MapKit made on its own is never a user move
    /// and is saved only when it is the camera we asked for; when it is not, a request re-applies our region.
    public func cameraDidChange(to region: GeoRegion, byUser: Bool = false) {
        IterPerf.count("trip.cameraSettle")
        guard visibleRegion != region else { return }
        visibleRegion = region
        switch cameraPolicy.cameraSettled(region, byUser: byUser) {
        case .saved:
            cameraPolicy.save(screen: Self.cameraScreenKey(for: tripID), defaults: defaults)
        case .reapply(let target):
            // MapKit settled somewhere we did not ask for: ask again (the view applies the new request).
            cameraRequest = CameraRequest(id: nextRequestID(), kind: .fit(target))
        case .ignored:
            break
        }
    }

    private func nextRequestID() -> Int {
        requestCounter += 1
        return requestCounter
    }

    public init(tripID: UUID, store: IterStore, scheduler: TripScheduler, drives: any DriveTimeProviding,
                forecasts: ForecastCenter, dismissals: SuggestionDismissals = .shared,
                defaults: UserDefaults = .standard, legCoalescing: Duration = .milliseconds(60),
                now: @escaping @MainActor () -> Date = { Date() }) {
        self.tripID = tripID
        self.store = store
        self.scheduler = scheduler
        self.drives = drives
        self.forecasts = forecasts
        self.dismissals = dismissals
        self.now = now
        self.defaults = defaults
        self.legCoalescing = legCoalescing
        self.cameraPolicy = MapCameraPolicy.load(screen: Self.cameraScreenKey(for: tripID), defaults: defaults)
        IterPerf.count("trip.modelInit")
        refresh()
    }

    isolated deinit {
        legTask?.cancel()
        legFlushTask?.cancel()
    }

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
            legFlushTask?.cancel()
            legFlushTask = nil
            legsDirty = false
            loadingKeys = []
            isLoadingLegs = false
            plan = nil
            schedule = TripSchedule(stops: [])
            days = []
            suggestions = []
            layout = TripDayLayout(groups: [])
            mapContent = TripMapContent()
            fitCoordinates = []
            lights = [:]
            sessionWindows = [:]
            lightCache = [:]
            return
        }
        let plan = record.plan
        if self.plan != plan { self.plan = plan }
        forecasts.requestAll(plan.stops.map(\.spot.coordinate))
        refreshLight(plan)
        let pairs = scheduler.legPairsNeeded(for: plan, windows: sessionWindows)
        dropStaleLegs(plan)
        fillKnownLegs(pairs, plan)
        recompute()
        loadMissingLegs(pairs, plan)
    }

    /// Waits for the current background drive fetch (tests).
    public func waitForLegs() async {
        await legTask?.value
    }

    private func dropStaleLegs(_ plan: TripPlan) {
        let coordinates = Dictionary(plan.stops.map { ($0.id, $0.spot.coordinate) }, uniquingKeysWith: { first, _ in first })
        let kept = legs.filter { key, leg in
            guard let a = coordinates[key.from], let b = coordinates[key.to] else { return false }
            return leg.from == a && leg.to == b
        }
        if kept.count != legs.count { legs = kept }
        retryAfter = retryAfter.filter { coordinates[$0.key.from] != nil && coordinates[$0.key.to] != nil }
    }

    /// Takes the pairs the provider already knows (its cache, an offline pack) before the first recompute, so a trip
    /// that was planned before shows its drives at once instead of one asynchronous hop per leg.
    private func fillKnownLegs(_ pairs: [LegKey], _ plan: TripPlan) {
        let coordinates = Dictionary(plan.stops.map { ($0.id, $0.spot.coordinate) }, uniquingKeysWith: { first, _ in first })
        var filled = legs
        for key in pairs where filled[key] == nil {
            guard let a = coordinates[key.from], let b = coordinates[key.to], let leg = drives.cachedLeg(from: a, to: b) else { continue }
            filled[key] = leg
        }
        if filled.count != legs.count { legs = filled }
    }

    private func loadMissingLegs(_ pairs: [LegKey], _ plan: TripPlan) {
        let clock = now()
        let missing = pairs.filter { legs[$0] == nil && (retryAfter[$0].map { $0 <= clock } ?? true) }
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
                var fetched: DriveLeg?
                var transient = false
                do {
                    fetched = try await drives.drive(from: a, to: b)
                } catch is CancellationError {
                    return
                } catch let error as MapServiceError where error == .noRoute || error == .invalidRequest {
                    // Final: no road route exists for this pair, so the straight-line estimate stands.
                    fetched = DriveLeg.estimate(from: a, to: b)
                } catch {
                    // Throttled or offline: may pass. Keep no estimate in `legs`; ask again on a later refresh.
                    transient = true
                }
                if Task.isCancelled { return }
                guard let self else { return }
                self.loadingKeys.remove(key)
                if let fetched {
                    self.legArrived(key, fetched)
                } else if transient {
                    self.retryAfter[key] = self.now().addingTimeInterval(Self.retryDelay)
                }
            }
            guard !Task.isCancelled, let self else { return }
            self.flushLegs()
            self.isLoadingLegs = false
            self.legTask = nil
            self.loadingKeys = []
        }
    }

    /// How long a pair that failed for a passing reason waits before the next refresh asks again.
    static let retryDelay: TimeInterval = 30

    private func legArrived(_ key: LegKey, _ leg: DriveLeg) {
        legs[key] = leg
        legsDirty = true
        guard legFlushTask == nil else { return }
        let delay = legCoalescing
        legFlushTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.flushLegs()
        }
    }

    private func flushLegs() {
        legFlushTask?.cancel()
        legFlushTask = nil
        if legsDirty { recompute() }
    }

    // MARK: - Light

    private struct LightKey: Hashable {
        var spot: Spot
        var day: LocalDay
    }

    private struct LightCacheEntry {
        var state: ForecastState
        var clock: Date
        var light: DayLight
    }

    /// A day of light is reused while the forecast it was scored with is the same one and the clock is within a minute.
    private static let lightFreshness: TimeInterval = 60

    private static func sameForecast(_ a: ForecastState, _ b: ForecastState) -> Bool {
        switch (a, b) {
        case (.loaded(let x), .loaded(let y)): x.fetchedAt == y.fetchedAt && x.source == y.source && x.coordinate == y.coordinate
        default: a == b
        }
    }

    /// The day of light for every stop at its own spot on its own day, reusing what the last refresh computed when the
    /// spot, day and forecast are unchanged. None of it depends on drive legs, so a leg arriving never comes here.
    private func refreshLight(_ plan: TripPlan) {
        let clock = now()
        var used: [LightKey: LightCacheEntry] = [:]
        var out: [UUID: DayLight] = [:]
        for stop in plan.stops {
            let day = plan.day(stop.dayIndex)
            let key = LightKey(spot: stop.spot, day: day)
            let state = forecasts.state(for: stop.spot.coordinate)
            if let entry = used[key] ?? lightCache[key], Self.sameForecast(entry.state, state),
               abs(clock.timeIntervalSince(entry.clock)) < Self.lightFreshness {
                used[key] = entry
                out[stop.id] = entry.light
                continue
            }
            dayLightCount += 1
            let light = scheduler.engine.dayLight(for: stop.spot, on: day, forecast: state.forecast,
                                                  unavailable: state.unavailableReason, now: clock)
            used[key] = LightCacheEntry(state: state, clock: clock, light: light)
            out[stop.id] = light
        }
        lightCache = used
        lights = out
        lightClock = clock
        sessionWindows = Dictionary(plan.stops.compactMap { stop in out[stop.id]?.window(stop.session).map { (stop.id, $0.span) } },
                                    uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Derived state

    private func recompute() {
        guard let plan else { return }
        IterPerf.count("trip.recompute")
        recomputeCount += 1
        legsDirty = false
        legFlushTask?.cancel()
        legFlushTask = nil
        let schedule = scheduler.schedule(plan, legs: legs, windows: sessionWindows)
        if self.schedule != schedule { self.schedule = schedule }
        allSuggestions = scheduler.suggestOrdering(plan, legs: legs, windows: sessionWindows)
        suggestions = allSuggestions.filter { !dismissals.isDismissed(trip: tripID, day: $0.dayIndex, order: $0.order) }
        days = buildDays(plan: plan, schedule: schedule)
        layout = TripDayLayout.make(days: days, suggestions: suggestions)
        let content = TripMapContent(days: days)
        if content != mapContent { mapContent = content }
        updateFitCoordinates()
    }

    private func buildDays(plan: TripPlan, schedule: TripSchedule) -> [TripDay] {
        var number = 0
        var previous: TripStopPlan?
        var out: [TripDay] = []
        for index in 0..<plan.dayCount {
            let date = plan.day(index)
            var entries: [TripStopEntry] = []
            var driving: TimeInterval = 0
            var estimated = false
            for stop in plan.stops(onDay: index) {
                number += 1
                guard let light = lights[stop.id] else { continue }
                let entrySchedule = schedule.schedule(for: stop.id)
                if let leg = entrySchedule?.legFromPrevious {
                    driving += leg.seconds
                    if leg.isEstimate { estimated = true }
                }
                entries.append(TripStopEntry(stop: stop, number: number, schedule: entrySchedule, previous: previous,
                                             windows: light.windows, sessionWindow: light.window(stop.session)))
                previous = stop
            }
            let first = entries.first.flatMap { lights[$0.id] }
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
        layout = TripDayLayout.make(days: days, suggestions: suggestions)
    }

    // MARK: - Add stop

    /// The "Add stop" list for one day: saved and curated spots, nearest first.
    public func addStopList(forDay day: Int, query: String) -> AddStopList {
        let plan = self.plan ?? TripPlan(name: "", startDay: LocalDay(year: 1970, month: 1, day: 1), dayCount: 1)
        return AddStopCandidates.make(plan: plan, day: day, saved: store.savedPlaces().map(\.spot),
                                      curated: CuratedSpots.all, query: query)
    }
}
