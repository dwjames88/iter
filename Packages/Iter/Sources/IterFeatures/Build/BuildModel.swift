import Foundation
import Observation
import IterAstro
import IterConditions
import IterModel
import IterPlan
import IterSky
import IterSources
import IterStore

/// Time and limits the builder runs on. Tests and previews pass their own `sleep`.
public struct BuildTiming: Sendable {
    /// The least gap between two drive lookups starting.
    public var spacing: Duration
    /// Drive lookups running at once.
    public var maxInFlight: Int
    /// Drive answers and forecast updates arriving within this window cause one recompute, not one each.
    public var coalescing: Duration
    public var backoff: DriveRetryBackoff
    /// A drive whose planned leave time is further ahead than this is looked up without a departure time and labelled typical.
    /// MapKit does not document its horizon; a week is the working assumption.
    public var trafficHorizon: TimeInterval
    /// An offline pack younger than this is not rebuilt when the trip is opened.
    public var packFreshness: TimeInterval
    public var sleep: @Sendable (Duration) async throws -> Void

    public init(spacing: Duration = .milliseconds(200), maxInFlight: Int = 2, coalescing: Duration = .milliseconds(60),
                backoff: DriveRetryBackoff = .standard, trafficHorizon: TimeInterval = 7 * 86_400,
                packFreshness: TimeInterval = 3600,
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.spacing = spacing
        self.maxInFlight = maxInFlight
        self.coalescing = coalescing
        self.backoff = backoff
        self.trafficHorizon = trafficHorizon
        self.packFreshness = packFreshness
        self.sleep = sleep
    }

    public static let live = BuildTiming()
}

/// The Trip Builder's model, one per open trip (BLUEPRINT §9). It reads the trip through `LibraryStore.trips`, plans it with
/// IterPlan's `Scheduler`, `TripDays` and `TripDayLayout`, asks MapKit for drive times (spaced, capped, cached, retried), asks
/// Conditions for each stop's forecast in the order the user is looking, and publishes plain `Equatable` values a view maps
/// straight onto the IterUI components. Edits go through the repository (named undo); the model never touches a `ModelContext`.
///
/// State is per property: choosing a stop changes `selectedStopID` only; the rows, the map content and the header are each
/// assigned only when they really changed.
@MainActor @Observable
public final class BuildModel {
    public let tripID: UUID

    // MARK: Published state

    /// The trip as a value; nil when it no longer exists (deleted elsewhere).
    public private(set) var trip: Trip?
    public private(set) var header: BuildHeader?
    public private(set) var dayItems: [BuildDayItem] = []
    /// The builder list, top to bottom.
    public private(set) var rows: [BuildRow] = []
    /// Every stop id in trip order (day-major), for arrow-key selection and the map.
    public private(set) var stopIDs: [UUID] = []
    public private(set) var startPlace: BuildStartPlace?
    /// The day the picker chose; nil shows the whole trip.
    public internal(set) var selectedDay: Int?
    public internal(set) var selectedStopID: UUID?
    public private(set) var mapContent = BuildMapContent()
    /// The region that frames the selected day's stops (the whole trip with no day, or a day with no stops).
    public private(set) var cameraRegion: GeoRegion?
    /// Drive lookups are queued or running.
    public private(set) var isLoadingDrives = false
    public private(set) var conditionsProgress = BuildConditionsProgress()
    public internal(set) var packState: BuildPackState = .none
    public private(set) var isOpen = false

    // MARK: Internals

    @ObservationIgnored let library: LibraryStore
    @ObservationIgnored let conditions: any BuildConditionsSource
    @ObservationIgnored let packs: (any OfflinePackBuilding)?
    @ObservationIgnored let now: @Sendable () -> Date
    @ObservationIgnored let timing: BuildTiming
    @ObservationIgnored let engine: LightEngine
    @ObservationIgnored let scheduler = Scheduler()
    @ObservationIgnored let fetcher: DriveFetcher

    @ObservationIgnored var seenRevision = -1
    @ObservationIgnored var legsDirty = false
    @ObservationIgnored var pendingWants: [DriveFetcher.Want] = []
    @ObservationIgnored var kept: [SlotKey: KeptSample] = [:]
    @ObservationIgnored var requested: Set<SlotKey> = []
    @ObservationIgnored var dismissed: Set<Dismissal> = []
    @ObservationIgnored var lightCache: [LightKey: DayLight] = [:]
    @ObservationIgnored var simplified: [UUID: (leg: Leg, path: [Coordinate])] = [:]
    @ObservationIgnored var refreshTask: Task<Void, Never>?
    @ObservationIgnored var observing = false
    @ObservationIgnored var packTask: Task<Void, Never>?
    @ObservationIgnored var packDirty = false
    @ObservationIgnored var packSignatureBuilt: [String]?
    @ObservationIgnored var currentPlaces: [Place] = []
    @ObservationIgnored var currentDays: [(day: LocalDay, places: [Place])] = []

    struct SlotKey: Hashable, Sendable {
        var placeID: UUID
        var day: LocalDay
    }

    struct KeptSample: Equatable {
        var tier: ForecastTier
        var scores: [LightWindowKind: Int]
        var pending: [SourceID]
    }

    struct Dismissal: Hashable {
        var day: Int
        var order: [UUID]
    }

    struct LightKey: Hashable {
        var placeID: UUID
        var day: LocalDay
        var coordinate: Coordinate
        var zone: String
    }

    /// Every stop card in trip order (a convenience over `rows`; reading it re-reads the rows).
    public var stops: [BuildStop] { rows.compactMap { if case .stop(let s) = $0.kind { s } else { nil } } }

    // MARK: Counters (tests and the perf script)

    /// How many times the published state was rebuilt, and how many `dayLight` computations and `Scheduler.schedule` passes
    /// that took (the plan's own ordering search is not counted).
    @ObservationIgnored public private(set) var recomputeCount = 0
    @ObservationIgnored public private(set) var dayLightCount = 0
    @ObservationIgnored public private(set) var scheduleCount = 0
    /// How many times the rows really changed.
    @ObservationIgnored public private(set) var rowsPublishCount = 0
    /// How many times the map content really changed.
    @ObservationIgnored public private(set) var mapPublishCount = 0
    /// Drive lookups started, and each one's departure time (nil = typical).
    public var directionsRequestCount: Int { fetcher.requestCount }
    public var directionsRequests: [(from: Coordinate, to: Coordinate, departing: Date?)] {
        fetcher.requests.map { ($0.from, $0.to, $0.departing) }
    }
    public var peakDirectionsInFlight: Int { fetcher.peakInFlight }
    /// A drive lookup is queued or running right now (unlike `isLoadingDrives`, never stale between recomputes).
    var drivesPending: Bool { fetcher.fetches.values.contains { $0 == .queued || $0 == .loading } }

    // MARK: Init

    public init(tripID: UUID, library: LibraryStore, conditions: any BuildConditionsSource, packs: (any OfflinePackBuilding)?,
                routing: any RoutingProvider, now: @escaping @Sendable () -> Date,
                engine: LightEngine = LightEngine(ephemeris: Astronomy()), timing: BuildTiming = .live) {
        self.tripID = tripID
        self.library = library
        self.conditions = conditions
        self.packs = packs
        self.now = now
        self.timing = timing
        self.engine = engine
        fetcher = DriveFetcher(routing: routing, backoff: timing.backoff, spacing: timing.spacing, maxInFlight: timing.maxInFlight,
                               now: now, sleep: timing.sleep)
        fetcher.onChange = { [weak self] in self?.driveChanged() }
        _ = updateKept()
        recompute()
    }

    isolated deinit {
        refreshTask?.cancel()
        packTask?.cancel()
    }

    // MARK: Lifecycle

    /// The builder came on screen: start the drive lookups, ask Conditions for every stop in view order, watch the store and the
    /// forecasts, and (for a pinned trip) build or refresh its offline pack.
    public func open() {
        guard !isOpen else { return }
        isOpen = true
        requested = []
        fetcher.want(pendingWants)
        isLoadingDrives = fetcher.isLoading(pendingWants)
        syncConditions()
        armObservation()
        refreshPackIfNeeded(onOpen: true)
    }

    /// The builder left the screen or the trip closed: every lookup, retry, load and observation is cancelled.
    public func close() {
        guard isOpen else { return }
        isOpen = false
        fetcher.stop()
        refreshTask?.cancel()
        refreshTask = nil
        packTask?.cancel()
        packTask = nil
        packDirty = false
        if packState == .building { packState = .none }
        isLoadingDrives = false
        conditions.setActiveTrip([])
    }

    // MARK: Refreshing

    /// Recomputes if the store, the drives or the forecasts changed since the last time. Cheap when nothing did.
    public func refreshIfChanged() {
        var changed = legsDirty || library.revision != seenRevision
        if updateKept() { changed = true }
        legsDirty = false
        if changed { recompute() }
    }

    func driveChanged() {
        legsDirty = true
        scheduleRefresh()
    }

    /// One coalesced refresh a moment from now (drive answers and forecast updates arrive in bursts).
    func scheduleRefresh() {
        guard isOpen, refreshTask == nil else { return }
        let sleep = timing.sleep, delay = timing.coalescing
        refreshTask = Task { [weak self] in
            if delay > .zero { do { try await sleep(delay) } catch { return } }
            guard !Task.isCancelled, let self else { return }
            self.refreshTask = nil
            self.refreshIfChanged()
            self.armObservation()
        }
    }

    /// Watches the store's revision and every stop's forecast slot; a change schedules a coalesced refresh and re-arms.
    func armObservation() {
        guard isOpen, !observing else { return }
        observing = true
        let keys = slotKeys()
        withObservationTracking {
            _ = library.revision
            for key in keys { _ = conditions.sample(placeID: key.placeID, day: key.day) }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observing = false
                self.scheduleRefresh()
            }
        }
    }

    func slotKeys() -> [SlotKey] {
        var seen = Set<SlotKey>()
        var out: [SlotKey] = []
        for (day, places) in currentDays {
            for place in places where seen.insert(SlotKey(placeID: place.id, day: day)).inserted {
                out.append(SlotKey(placeID: place.id, day: day))
            }
        }
        return out
    }

    // MARK: Recompute

    /// Rebuilds everything derived from the trip. Each published property is assigned only when it changed.
    func recompute() {
        recomputeCount += 1
        seenRevision = library.revision
        guard let record = library.trips.trip(id: tripID) else {
            clear()
            return
        }
        let trip = record.value()
        let start = trip.startPlaceID.flatMap { library.places.value(id: $0) }
        let instant = now()

        // Light: one DayLight per stop, kept while the place, day and zone are the same.
        var lights: [UUID: DayLight] = [:]
        var windows: SessionWindows = [:]
        for stop in trip.stops {
            let light = dayLight(for: stop, trip: trip, now: instant)
            lights[stop.id] = light
            if stop.kind == .light, let span = light.window(stop.session)?.span { windows[stop.id] = span }
        }

        // Drives: what is known, the plan worked from the typical times, then what traffic changes.
        let ordered = Self.ordered(trip.stops)
        var coordinates: [UUID: Coordinate] = Dictionary(trip.stops.map { ($0.id, $0.place.coordinate) }, uniquingKeysWith: { a, _ in a })
        if let start { coordinates[start.id] = start.coordinate }
        let pairs = scheduler.legPairsNeeded(for: trip, start: start, windows: windows)
        var typical: [LegKey: Leg] = [:]
        for pair in pairs {
            guard let a = coordinates[pair.from], let b = coordinates[pair.to],
                  let leg = fetcher.leg(for: .init(leg: pair, bucket: nil), from: a, to: b) else { continue }
            typical[pair] = leg
        }
        scheduleCount += 1
        let base = scheduler.schedule(trip: trip, start: start, windows: windows, legs: typical)

        var pairFor: [UUID: LegKey] = [:]
        for (index, stop) in ordered.enumerated() {
            if index > 0 { pairFor[stop.id] = LegKey(ordered[index - 1].id, stop.id) }
            else if let start { pairFor[stop.id] = LegKey(start.id, stop.id) }
        }

        var wants: [DriveFetcher.Want] = []
        for pair in pairs {
            guard let a = coordinates[pair.from], let b = coordinates[pair.to] else { continue }
            wants.append(.init(key: .init(leg: pair, bucket: nil), from: a, to: b, departing: nil))
        }
        var effective = typical
        var basis: [LegKey: DriveBasis] = typical.mapValues { _ in .typical }
        var overlaid = false
        for stop in ordered {
            guard let pair = pairFor[stop.id], let known = typical[pair], !known.isEstimate,
                  let a = coordinates[pair.from], let b = coordinates[pair.to],
                  let leaveBy = base.schedule(for: stop.id)?.leaveBy,
                  leaveBy >= instant, leaveBy <= instant.addingTimeInterval(timing.trafficHorizon) else { continue }
            let bucket = DriveFetcher.bucket(of: leaveBy)
            let key = DriveFetcher.Key(leg: pair, bucket: bucket)
            let departing = DriveFetcher.start(ofBucket: bucket)
            wants.append(.init(key: key, from: a, to: b, departing: departing))
            if let leg = fetcher.leg(for: key, from: a, to: b) {
                effective[pair] = leg
                basis[pair] = .trafficAware(departing: departing)
                overlaid = true
            }
        }
        let schedule: TripSchedule
        if overlaid {
            scheduleCount += 1
            schedule = scheduler.schedule(trip: trip, start: start, windows: windows, legs: effective)
        } else {
            schedule = base
        }
        pendingWants = wants
        if isOpen { fetcher.want(wants) }
        var states: [LegKey: DriveLegState] = [:]
        for pair in pairs {
            guard let a = coordinates[pair.from], let b = coordinates[pair.to] else { continue }
            states[pair] = fetcher.state(of: .init(leg: pair, bucket: nil), from: a, to: b)
        }
        let loading = isOpen && fetcher.isLoading(wants)

        // Plan values.
        let suggestions = scheduler.suggestOrdering(trip: trip, start: start, windows: windows, legs: effective).filter {
            !dismissed.contains(Dismissal(day: $0.dayIndex, order: $0.order))
        }
        let days = TripDays.make(trip: trip, start: start, schedule: schedule, lights: lights)
        let layout = TripDayLayout.make(days: days, suggestions: suggestions)
        var scores: [UUID: BuildRowContext.StopScores] = [:]
        for stop in trip.stops {
            let day = trip.day(stop.dayIndex)
            if let sample = kept[SlotKey(placeID: stop.place.id, day: day)] {
                scores[stop.id] = .init(scores: sample.scores, improving: sample.tier != .complete)
            }
        }
        let context = BuildRowContext(trip: trip, scores: scores, pairFor: pairFor, states: states, basis: basis)
        let rows = BuildRowFactory.rows(layout: layout, context: context)
        let dayItems = BuildRowFactory.dayItems(layout: layout, context: context)

        // Header.
        var seconds = 0.0, meters = 0.0, estimated = false
        for entry in schedule.stops {
            guard let leg = entry.legFromPrevious else { continue }
            seconds += leg.seconds
            meters += leg.meters
            if leg.isEstimate { estimated = true }
        }
        let header = BuildHeader(name: trip.name, startDay: trip.startDay, endDay: trip.day(trip.dayCount - 1), dayCount: trip.dayCount,
                                 stopCount: trip.stops.count, drivingSeconds: seconds, drivingMeters: meters,
                                 drivingIncludesEstimate: estimated, issueCount: schedule.issueCount, isPinned: trip.isPinned)

        // Start place and the first leave-by.
        var startValue: BuildStartPlace?
        if let start {
            let first = ordered.first.flatMap { schedule.schedule(for: $0.id) }
            startValue = BuildStartPlace(placeID: start.id, name: start.name, locality: start.locality, coordinate: start.coordinate,
                                         firstLeaveBy: first?.fromStart == true ? first?.leaveBy : nil, timeZone: start.timeZone)
        }

        // Map.
        let map = mapContent(layout: layout, start: start)

        publish(\.trip, trip)
        publish(\.header, header)
        publish(\.dayItems, dayItems)
        if rows != self.rows { rowsPublishCount += 1; self.rows = rows }
        publish(\.stopIDs, ordered.map(\.id))
        publish(\.startPlace, startValue)
        if map != mapContent { mapPublishCount += 1; mapContent = map }
        publish(\.isLoadingDrives, loading)
        currentDays = (0..<trip.dayCount).map { index in (trip.day(index), trip.stops(onDay: index).map(\.place)) }
        currentPlaces = trip.stops.map(\.place)
        fixSelection(trip: trip)
        publish(\.cameraRegion, fitRegion(trip: trip))
        publish(\.conditionsProgress, progress(for: trip))
        if isOpen {
            syncConditions()
            refreshPackIfNeeded(onOpen: false)
        }
    }

    private func clear() {
        trip = nil
        header = nil
        dayItems = []
        rows = []
        stopIDs = []
        startPlace = nil
        selectedStopID = nil
        mapContent = BuildMapContent()
        cameraRegion = nil
        conditionsProgress = BuildConditionsProgress()
        currentDays = []
        currentPlaces = []
        pendingWants = []
        fetcher.stop()
        isLoadingDrives = false
    }

    /// Assigns only when different, so a view that reads the property is not invalidated by an equal value.
    func publish<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<BuildModel, T>, _ value: T) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }

    /// The stops in trip order: by day, then as stored (the scheduler's order).
    static func ordered(_ stops: [Stop]) -> [Stop] {
        stops.enumerated().sorted { a, b in
            a.element.dayIndex != b.element.dayIndex ? a.element.dayIndex < b.element.dayIndex : a.offset < b.offset
        }.map(\.element)
    }

    private func dayLight(for stop: Stop, trip: Trip, now: Date) -> DayLight {
        let day = trip.day(stop.dayIndex)
        let key = LightKey(placeID: stop.place.id, day: day, coordinate: stop.place.coordinate, zone: stop.place.timeZoneIdentifier)
        if let known = lightCache[key] { return known }
        dayLightCount += 1
        let light = engine.dayLight(for: stop.place, on: day, inputs: nil, unavailable: [], now: now)
        lightCache[key] = light
        return light
    }

    // MARK: Map

    private func mapContent(layout: TripDayLayout, start: Place?) -> BuildMapContent {
        var waypoints: [BuildWaypoint] = []
        var legs: [BuildMapLeg] = []
        var live: Set<UUID> = []
        for group in layout.groups {
            for entry in group.stops {
                waypoints.append(BuildWaypoint(stopID: entry.id, number: entry.number, coordinate: entry.stop.place.coordinate,
                                               kind: entry.stop.kind, name: entry.stop.place.name, day: group.index))
                guard let leg = entry.schedule?.legFromPrevious else { continue }
                live.insert(entry.id)
                let path: [Coordinate]
                if let cached = simplified[entry.id], cached.leg == leg {
                    path = cached.path
                } else {
                    path = PathSimplifier.simplify(leg.path.isEmpty ? [leg.from, leg.to] : leg.path, tolerance: PathSimplifier.routeTolerance)
                    simplified[entry.id] = (leg, path)
                }
                legs.append(BuildMapLeg(toStopID: entry.id, day: group.index, path: path, isEstimate: leg.isEstimate))
            }
        }
        for id in simplified.keys where !live.contains(id) { simplified[id] = nil }
        return BuildMapContent(waypoints: waypoints, legs: legs, startCoordinate: start?.coordinate)
    }

    private func fitRegion(trip: Trip) -> GeoRegion? {
        var coordinates = trip.stops.map(\.place.coordinate)
        if let day = selectedDay {
            let ofDay = trip.stops(onDay: day).map(\.place.coordinate)
            if !ofDay.isEmpty { coordinates = ofDay }
        }
        return GeoRegion.enclosing(coordinates)
    }

    // MARK: Selection

    /// Chooses a day (nil: the whole trip; a day the trip does not have is ignored). A selected stop on another day is deselected.
    public func selectDay(_ day: Int?) {
        if let day, !(0..<(trip?.dayCount ?? 0)).contains(day) { return }
        guard day != selectedDay else { return }
        selectedDay = day
        if let id = selectedStopID, let day, trip?.stops.first(where: { $0.id == id })?.dayIndex != day { selectedStopID = nil }
        if let trip { publish(\.cameraRegion, fitRegion(trip: trip)) }
        if isOpen { conditions.setVisible(visiblePlaceIDs()) }
    }

    /// Selects a stop (nil clears). Its day becomes the selected day; the camera does not move for a stop on the same day.
    public func selectStop(_ id: UUID?) {
        guard id != selectedStopID else { return }
        guard let id else { selectedStopID = nil; return }
        guard let stop = trip?.stops.first(where: { $0.id == id }) else { return }
        selectedStopID = id
        if selectedDay != stop.dayIndex { selectDay(stop.dayIndex) }
    }

    /// The next stop in trip order, across days (down arrow). With no selection, the first. Stays on the last.
    public func selectNext() { selectStop(Self.adjacentStop(in: stopIDs, from: selectedStopID, step: 1)) }

    /// The previous stop in trip order (up arrow). With no selection, the last. Stays on the first.
    public func selectPrevious() { selectStop(Self.adjacentStop(in: stopIDs, from: selectedStopID, step: -1)) }

    /// The stop an arrow key selects: `step` +1 (down) or -1 (up) from `current` in trip order. With no (or an unknown)
    /// selection down gives the first stop and up the last; at either end it stays on the same stop (no wrap).
    public static func adjacentStop(in ids: [UUID], from current: UUID?, step: Int) -> UUID? {
        guard !ids.isEmpty else { return nil }
        guard let current, let index = ids.firstIndex(of: current) else { return step > 0 ? ids.first : ids.last }
        return ids[min(max(index + step, 0), ids.count - 1)]
    }

    private func fixSelection(trip: Trip) {
        if let day = selectedDay, day >= trip.dayCount { selectedDay = nil }
        if let id = selectedStopID, !trip.stops.contains(where: { $0.id == id }) { selectedStopID = nil }
    }
}
