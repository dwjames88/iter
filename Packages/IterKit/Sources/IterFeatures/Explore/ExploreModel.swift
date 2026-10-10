import Foundation
import Observation
import IterCore
import IterData
import IterLight
import IterServices

/// State and derived data for the Explore screen: filters, sort, search, results, selection and camera requests.
/// One selection drives pin, row and the place panel that replaces the list column (pattern #5). Platform-neutral; the view draws it.
@MainActor
@Observable
public final class ExploreModel {
    public let app: AppModel
    /// The ask engine (the scout). Its state is what the Ask section draws.
    public let askModel: ScoutModel

    // MARK: Inputs

    public var filters = ExploreFilters() {
        didSet { if oldValue != filters { resultSetChanged() } }
    }
    /// What the user picked in the menu; nil until they pick one.
    private var chosenSort: ExploreSort?
    /// The list order. Until the user picks one: nearest first while there is a location (the list is about places
    /// you can reach), else best light first. `.distance` always means "from you" with a location, else "from the
    /// map's centre".
    public var sort: ExploreSort {
        get { chosenSort ?? (hasLocation ? .distance : .bestLight) }
        set { chosenSort = newValue }
    }
    /// The user opened "More Places" themselves.
    private var moreOpenedByUser = false
    /// The search field. Filters curated and your own spots as you type; Apple Maps runs on submit.
    public var query = "" {
        didSet { if oldValue != query { queryChanged() } }
    }
    public var isAddingSpot = false {
        didSet { if !isAddingSpot { draftCoordinate = nil } }
    }
    /// A dropped pin waiting for the spot editor.
    public var draftCoordinate: Coordinate?
    /// Row under the pointer (list or map): its pin is emphasised.
    public var hoveredID: String?
    /// Your own spot being dragged on the map: where it is now. Stored only on the drop.
    public private(set) var dragging: (id: String, coordinate: Coordinate)?
    /// Adjust Location: the map pans under a crosshair at its centre; Done saves the centre.
    public private(set) var adjusting: AdjustLocation?

    /// One Adjust Location session.
    public struct AdjustLocation: Equatable, Sendable {
        public var id: String
        public var original: Coordinate
        /// The map's centre now (the crosshair).
        public var center: Coordinate
    }

    // MARK: Outputs the view reads

    public internal(set) var appleResults: [Spot] = []
    public internal(set) var searchState: ExploreSearchState = .idle
    public private(set) var selectedID: String?
    public private(set) var selectionSource: SelectionSource = .program
    /// The list column shows the selected place's light panel instead of the list. Only while a place is selected;
    /// `closePanel()` (back, Escape) returns to the list and keeps the selection.
    public private(set) var showsPanel = false
    public private(set) var cameraRequest: CameraRequest?
    /// Asks the list to scroll a row into view when `id` changes.
    public private(set) var scrollRequest: (id: Int, target: String)?
    /// The map's visible region, reported by the view when the camera settles.
    public private(set) var visibleRegion: GeoRegion?
    /// The region the current list matches: set when the camera settles other than by the user, and to the searched
    /// region when Search Here runs. A user move leaves it, so the distance from it says the list is out of date.
    public internal(set) var listRegion: GeoRegion?
    /// Search Here progress and outcome, as facts.
    public internal(set) var searchHereStatus: SearchHereStatus = .idle
    /// What Search Here found, merged, in list order.
    public internal(set) var searchHereResults: [SearchHereResult] = []
    /// What a typed "<feature> in <area>" search found, merged, in list order. Empty for every other search.
    public internal(set) var featureResults: [SearchHereResult] = []
    /// Progress and outcome of that search, per source.
    public internal(set) var featureStatus: FeatureSearchStatus = .idle
    /// The area that search resolved (name, box and outline), for drawing it.
    public internal(set) var featureArea: DiscoveryArea?
    /// The map pane's size in points, reported by the view; the pin clusterer needs its width. Zero until known.
    public private(set) var mapViewport: CGSize = .zero
    /// Bumped once per applied batch of scores, so views and the derived cache see new scores in one change.
    private var scoreRevision = 0

    /// Chips on the map besides the selected one.
    public static let pinBudget = 6
    /// Curated `Spot.popularity` (0 to 100, high = iconic and crowded) at or above which a spot beyond the radius is
    /// listed under "Popular". It comes from the curated field; no visitor numbers are involved.
    public static let popularThreshold = 80
    /// The screen key the map camera is saved under.
    public static let cameraScreenKey = "explore"
    private static let metersPerMile = 1609.344

    @ObservationIgnored public var searchDebounce: Duration
    @ObservationIgnored public internal(set) var searchTask: Task<Void, Never>?
    @ObservationIgnored private var requestCounter = 0
    @ObservationIgnored var searchHereTask: Task<Void, Never>?
    /// Bumped by every Search Here start and cancel; a task whose number is out of date never writes.
    @ObservationIgnored var searchHereGeneration = 0
    /// Bumped when `searchHereResults` changes, so the derived stamp stays cheap to compare.
    @ObservationIgnored var searchHereRevision = 0
    /// Bumped when `featureResults` changes.
    @ObservationIgnored var featureRevision = 0
    @ObservationIgnored private var scoreCache: [ScoreKey: CachedWindow] = [:]
    /// The newest computed event per spot id, shown while a row's key is being rescored.
    @ObservationIgnored private var lastEvent: [String: CachedWindow] = [:]
    @ObservationIgnored private var pendingJobs: [ScoreKey: ScoreJob] = [:]
    @ObservationIgnored private var inFlightKeys: Set<ScoreKey> = []
    @ObservationIgnored private var scoringTask: Task<Void, Never>?
    /// How long the scheduler waits after the first missing score before it takes the batch.
    @ObservationIgnored public var scoringDelay: Duration = .milliseconds(40)
    @ObservationIgnored private var derivedCache: (stamp: DerivedStamp, value: Derived)?
    @ObservationIgnored private var mapCache: (key: MapKey, value: MapSnapshot)?
    @ObservationIgnored private let defaults: UserDefaults
    /// How many times the rows, and the map's items, were rebuilt (not read from their caches). For tests and the
    /// perf counters.
    @ObservationIgnored public private(set) var derivedBuilds = 0
    @ObservationIgnored public private(set) var mapBuilds = 0
    @ObservationIgnored public private(set) var scoreBatches = 0
    @ObservationIgnored public private(set) var cameraPolicy: MapCameraPolicy

    public init(app: AppModel, searchDebounce: Duration = .milliseconds(250), defaults: UserDefaults = .standard) {
        self.app = app
        self.searchDebounce = searchDebounce
        self.defaults = defaults
        self.cameraPolicy = MapCameraPolicy.load(screen: Self.cameraScreenKey, defaults: defaults)
        self.askModel = ScoutModel(app: app)
        askModel.onFinish = { [weak self] in self?.askFinished() }
    }

    // MARK: - Location

    /// True when there is a fix to measure from.
    public var hasLocation: Bool { app.location.coordinate != nil }
    /// "Near you" reaches this far, in miles.
    public var radiusMiles: Int { app.location.radiusMiles }

    /// Call when Explore first appears. Never blocks; the system permission dialog may show.
    public func start() { app.location.start() }

    /// "More Places" is open: the user opened it, or a search is narrowing the list (so a match is never hidden).
    public var isMorePlacesOpen: Bool { moreOpenedByUser || !trimmedQuery.isEmpty }
    public func setMorePlacesOpen(_ open: Bool) { moreOpenedByUser = open }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: - Derived rows

    private struct CachedWindow: Sendable { var event: (day: LocalDay, window: LightWindow)? }
    /// What a score depends on: the spot (id, place, zone), the forecast state and the five-minute time bucket.
    private struct ScoreKey: Hashable, Sendable {
        var spotID: String
        var coordinate: String
        var zone: String
        var forecastTag: String
        var timeBucket: Int
    }
    private struct ScoreJob: Sendable {
        var key: ScoreKey
        var spot: Spot
        var forecast: Forecast?
        var unavailable: ForecastUnavailableReason?
        var now: Date
    }
    private struct MapKey: Equatable {
        var stamp: DerivedStamp
        var region: GeoRegion?
        var selectedID: String?
        var hoveredID: String?
        var viewport: CGSize
    }
    private struct MapSnapshot {
        var items: [ExploreMapItem]
        var pins: [ExplorePin]
    }
    struct DerivedStamp: Equatable {
        /// Five-minute bucket of the clock, so each row's next event rolls over after its sunset.
        var timeBucket: Int
        var forecastRevision: Int
        var storeRevision: Int
        var filters: ExploreFilters
        var sort: ExploreSort
        var query: String
        var appleIDs: [String]
        var ask: [ScoutSuggestion]
        var inViewRevision: Int
        var featureRevision: Int
        /// What distances are measured from: you, else the map centre while sorting by distance.
        var origin: Coordinate?
        var hasLocation: Bool
        var radiusMiles: Int
        /// Changes once per applied batch of scores.
        var scoreRevision: Int
    }
    private struct Derived {
        var sections: [ExploreSection]
        var rows: [ExploreRow]
        var byID: [String: ExploreRow]
    }

    private static func timeBucket(_ date: Date) -> Int { Int(date.timeIntervalSince1970 / 300) }

    private var derived: Derived { derived(for: currentStamp) }

    private var currentStamp: DerivedStamp {
        let user = app.location.coordinate
        let origin: Coordinate? = user ?? (sort == .distance ? visibleRegion?.center : nil)
        let stamp = DerivedStamp(timeBucket: Self.timeBucket(app.now()), forecastRevision: app.forecasts.revision,
                                 storeRevision: app.store.revision, filters: filters, sort: sort,
                                 query: query.trimmingCharacters(in: .whitespacesAndNewlines),
                                 appleIDs: appleResults.map(\.id), ask: askSuggestions, inViewRevision: searchHereRevision, featureRevision: featureRevision, origin: origin, hasLocation: user != nil,
                                 radiusMiles: app.location.radiusMiles, scoreRevision: scoreRevision)
        return stamp
    }

    private func derived(for stamp: DerivedStamp) -> Derived {
        if let cached = derivedCache, cached.stamp == stamp { return cached.value }
        IterPerf.count("explore.buildDerived")
        derivedBuilds += 1
        let value = IterPerf.interval("explore.buildDerived") { buildDerived(stamp) }
        let shown = value.sections.filter { isMorePlacesOpen || $0.kind != .morePlaces }.flatMap(\.rows)
        if !shown.isEmpty, shown.allSatisfy({ $0.score != nil }) { IterPerf.once("explore.allScored", "rows=\(shown.count)") }
        derivedCache = (stamp, value)
        return value
    }

    /// Near you, Popular and More Places (or one Spots section without a location), then Apple Maps; empty sections
    /// are left out.
    public var sections: [ExploreSection] { derived.sections }
    /// Every visible row in list order.
    public var rows: [ExploreRow] { derived.rows }
    public func row(id: String) -> ExploreRow? { derived.byID[id] }
    public var selectedRow: ExploreRow? { selectedID.flatMap { derived.byID[$0] } }

    /// All spots that could be listed before the search text and filters, with their source.
    private func candidates() -> [(Spot, ExploreSource)] {
        // A saved spot shows the user's edits (name, place, notes, and for their own and Apple Maps spots the facts too).
        let saved = app.store.savedPlaces()
        let edited = Dictionary(saved.compactMap { r in r.curatedID.map { ($0, r.spot) } }, uniquingKeysWith: { a, _ in a })
        let editedApple = Dictionary(saved.compactMap { r in r.externalID.map { ($0, r.spot) } }, uniquingKeysWith: { a, _ in a })
        var out: [(Spot, ExploreSource)] = CuratedSpots.all.map { (edited[$0.id] ?? $0, .curated) }
        let yours = saved.filter { $0.origin == .user }.map(\.spot)
        out += yours.map { ($0, .yours) }
        out += appleResults.map { (editedApple[$0.id] ?? $0, .appleMaps) }
        // The Ask section and In View own their spots: they appear once, there.
        let owned = Set(askSuggestions.map(\.spot.id)).union(searchHereResults.map(\.id)).union(featureResults.map(\.id))
        return owned.isEmpty ? out : out.filter { !owned.contains($0.0.id) }
    }

    private func buildDerived(_ stamp: DerivedStamp) -> Derived {
        let now = app.now()
        var rows: [ExploreRow] = []
        for (spot, source) in candidates() where Self.matches(spot, source: source, filters: filters, query: stamp.query) {
            let event = nextEvent(for: spot, bucket: stamp.timeBucket, now: now)
            rows.append(ExploreRow(spot: spot, source: source, window: event?.window, day: event?.day,
                                   isLoading: app.forecasts.isLoading(spot.coordinate),
                                   distanceMeters: stamp.origin.map { $0.distance(to: spot.coordinate) },
                                   sources: source == .appleMaps ? [.appleMaps] : [], elevationMeters: spot.elevationMeters))
        }
        let own = rows.filter { $0.source != .appleMaps }
        let apple = Self.sorted(rows.filter { $0.source == .appleMaps }, by: sort)
        var sections: [ExploreSection] = []
        let askRows = Self.uniqued(stamp.ask).map { suggestion -> ExploreRow in
            let spot = suggestion.spot
            let event = nextEvent(for: spot, bucket: stamp.timeBucket, now: now)
            return ExploreRow(spot: spot, source: suggestion.provenance == .curated ? .curated : .appleMaps,
                              window: event?.window, day: event?.day,
                              isLoading: app.forecasts.isLoading(spot.coordinate),
                              distanceMeters: stamp.origin.map { $0.distance(to: spot.coordinate) },
                              note: suggestion.why.isEmpty ? nil : suggestion.why, driveSeconds: suggestion.driveSeconds)
        }
        if !askRows.isEmpty { sections.append(ExploreSection(kind: .ask, rows: askRows)) }
        let featureRows = featureRows(stamp, now: now, claimed: Set(askRows.map(\.id)))
        if !featureRows.isEmpty { sections.append(ExploreSection(kind: .feature, rows: featureRows)) }
        let inViewRows = inViewRows(stamp, now: now, claimed: Set(askRows.map(\.id)))
        if stamp.hasLocation {
            let radius = Double(stamp.radiusMiles) * Self.metersPerMile
            let near = own.filter { ($0.distanceMeters ?? .infinity) <= radius }
            let far = own.filter { ($0.distanceMeters ?? .infinity) > radius }
            let popular = far.filter { $0.source == .curated && $0.spot.popularity >= Self.popularThreshold }
            let popularIDs = Set(popular.map(\.id))
            let more = far.filter { !popularIDs.contains($0.id) }
            let groups: [(ExploreSectionKind, [ExploreRow])] = [
                (.nearYou, Self.sorted(near, by: sort)),
                (.popular, Self.sorted(popular, by: .popularity)),
                (.morePlaces, Self.sorted(more, by: sort)),
            ]
            for (kind, group) in groups where !group.isEmpty { sections.append(ExploreSection(kind: kind, rows: group)) }
        } else {
            let spots = Self.sorted(own, by: sort)
            if !spots.isEmpty { sections.append(ExploreSection(kind: .spots, rows: spots)) }
        }
        if !apple.isEmpty { sections.append(ExploreSection(kind: .appleMaps, rows: apple)) }
        if !inViewRows.isEmpty { sections.insert(ExploreSection(kind: .inView, rows: inViewRows), at: 0) }
        let flat = sections.flatMap(\.rows)
        return Derived(sections: sections, rows: flat, byID: Dictionary(flat.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }))
    }

    /// The spot's next sunrise or sunset, read from the score cache. Pure read: it never computes and never starts a
    /// fetch (see `requestForecasts`). A missing key is queued for the batch scorer, and meanwhile the spot's last
    /// computed event (if any) stands in, so a row keeps its old score instead of flashing empty.
    func nextEvent(for spot: Spot, bucket: Int, now: Date) -> (day: LocalDay, window: LightWindow)? {
        let state = app.forecasts.state(for: spot.coordinate)
        let tag: String
        switch state {
        case .loading: tag = "L"
        case .loaded(let f): tag = "F\(f.fetchedAt.timeIntervalSince1970)"
        case .unavailable(let r): tag = "U\(r.hashValue)"
        }
        let key = ScoreKey(spotID: spot.id, coordinate: spot.coordinate.cacheKey, zone: spot.timeZoneIdentifier,
                           forecastTag: tag, timeBucket: bucket)
        if let hit = scoreCache[key] { return hit.event }
        if pendingJobs[key] == nil, !inFlightKeys.contains(key) {
            pendingJobs[key] = ScoreJob(key: key, spot: spot, forecast: state.forecast, unavailable: state.unavailableReason, now: now)
            scheduleScoring()
        }
        return lastEvent[spot.id]?.event
    }

    // MARK: Scoring off the main actor

    /// Starts the single coalescing scheduler if it is not running. It waits `scoringDelay` after the first missing
    /// score, takes everything queued, scores it in one detached task, applies it in one observable change, and
    /// repeats while more arrived.
    private func scheduleScoring() {
        guard scoringTask == nil else { return }
        scoringTask = Task { [weak self] in
            while let self {
                if pendingJobs.isEmpty { scoringTask = nil; return }
                if scoringDelay > .zero { try? await Task.sleep(for: scoringDelay) }
                await scoreBatch()
            }
        }
    }

    private func scoreBatch() async {
        // A job from an earlier time bucket is stale: its row has been queued again under the new bucket.
        let bucket = Self.timeBucket(app.now())
        let jobs = pendingJobs.values.filter { $0.key.timeBucket == bucket }
        pendingJobs = [:]
        guard !jobs.isEmpty else { return }
        inFlightKeys = Set(jobs.map(\.key))
        let engine = app.engine
        let results = await Task.detached(priority: .userInitiated) { Self.score(jobs, engine: engine) }.value
        inFlightKeys = []
        let current = Self.timeBucket(app.now())
        let fresh = results.filter { $0.0.timeBucket == current }
        guard !fresh.isEmpty else { return }
        IterPerf.count("explore.scoreBatch")
        scoreBatches += 1
        scoreCache = scoreCache.filter { $0.key.timeBucket == current }
        for (key, cached) in fresh {
            scoreCache[key] = cached
            lastEvent[key.spotID] = cached
        }
        scoreRevision += 1
    }

    private nonisolated static func score(_ jobs: [ScoreJob], engine: LightEngine) -> [(ScoreKey, CachedWindow)] {
        IterPerf.interval("explore.scoreBatch") {
            jobs.map { job in
                (job.key, CachedWindow(event: engine.nextEvent(for: job.spot, forecast: job.forecast,
                                                               unavailable: job.unavailable, now: job.now)))
            }
        }
    }

    /// Returns when no scores are queued or being computed. For tests: scores arrive some milliseconds after the rows.
    public func waitForScoring() async {
        _ = derived
        while let task = scoringTask {
            await task.value
            _ = derived
        }
    }

    /// Suggestions with one entry per spot, in the scout's order (best first).
    static func uniqued(_ suggestions: [ScoutSuggestion]) -> [ScoutSuggestion] {
        var seen = Set<String>()
        return suggestions.filter { seen.insert($0.spot.id).inserted }
    }

    // MARK: Filtering and sorting (static so tests can drive them directly)

    static func matches(_ spot: Spot, source: ExploreSource, filters: ExploreFilters, query: String) -> Bool {
        guard filters.sources.contains(source) else { return false }
        if !filters.categories.isEmpty, !filters.categories.contains(spot.category) { return false }
        if !filters.bestLight.isEmpty, source != .appleMaps, filters.bestLight.isDisjoint(with: spot.bestLight) { return false }
        // Apple Maps results already answer the query; the text only narrows your own list.
        if source != .appleMaps, !query.isEmpty {
            let haystack = ([spot.name, spot.locality] + spot.tags).joined(separator: " ")
            for token in query.split(whereSeparator: \.isWhitespace) {
                if haystack.range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) == nil { return false }
            }
        }
        return true
    }

    static func sorted(_ rows: [ExploreRow], by sort: ExploreSort) -> [ExploreRow] {
        func byName(_ a: ExploreRow, _ b: ExploreRow) -> Bool {
            let order = a.spot.name.localizedStandardCompare(b.spot.name)
            return order == .orderedSame ? a.id < b.id : order == .orderedAscending
        }
        switch sort {
        case .name:
            return rows.sorted(by: byName)
        case .popularity:
            return rows.sorted { a, b in
                a.spot.popularity != b.spot.popularity ? a.spot.popularity > b.spot.popularity : byName(a, b)
            }
        case .distance:
            return rows.sorted { a, b in
                switch (a.distanceMeters, b.distanceMeters) {
                case let (x?, y?): x != y ? x < y : byName(a, b)
                case (_?, nil): true
                case (nil, _?): false
                case (nil, nil): byName(a, b)
                }
            }
        case .bestLight:
            return rows.sorted { a, b in
                switch (a.score, b.score) {
                case let (x?, y?): x != y ? x > y : byName(a, b)
                case (_?, nil): true
                case (nil, _?): false
                case (nil, nil): byName(a, b)
                }
            }
        }
    }

    // MARK: Header facts

    /// Why weather is missing, shown once for the whole screen (never per row).
    public var weatherStatus: WeatherStatus { app.weatherStatus }

    /// True when any listed score was made from sample weather (the list says so once).
    public var hasSampleScores: Bool {
        rows.contains { $0.window?.assessment.lightScore?.source == .sample }
    }

    /// Forecasts still on their way.
    /// Only rows on screen count: a collapsed "More Places" is not fetched until it opens, so it must not keep the
    /// header spinner going.
    public var isLoadingForecasts: Bool {
        fetchedRows.contains { $0.isLoading }
    }

    /// Rows whose forecasts are fetched now, in list order (everything but a collapsed "More Places").
    private var fetchedRows: [ExploreRow] {
        let hidden: Set<ExploreSectionKind> = isMorePlacesOpen ? [] : [.morePlaces]
        return sections.filter { !hidden.contains($0.kind) }.flatMap(\.rows)
    }

    /// True when search text or a filter is narrowing the list (offers "Clear Filters").
    public var isNarrowed: Bool {
        filters.isActive || !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func clearFilters() {
        let hadSearch = !query.isEmpty
        filters = .none
        if hadSearch { query = "" }
    }

    // MARK: Forecasts

    /// Starts forecast fetches, in list order, for the rows that are showing ("More Places" waits until it is open).
    /// The fetches are shared and cached.
    public func requestForecasts() {
        app.forecasts.requestAll(fetchedRows.map(\.spot.coordinate))
    }

    /// A row appeared on screen: make sure its forecast is on its way.
    public func requestForecast(for id: String) {
        guard let row = derived.byID[id] else { return }
        app.forecasts.request(row.spot.coordinate)
    }

    // MARK: - Selection and camera

    /// Selects a row (or clears with nil). The list follows a map selection by scrolling; the map follows a
    /// list selection by zooming to a 25-mile radius around the spot (only panning when already closer in). A map selection opens the panel (a
    /// different pin while it is open switches it); clearing returns to the list. A list click opens the panel
    /// through `openPanel()`, which the view calls once it knows the click was not the first of a double-click.
    public func select(_ id: String?, from source: SelectionSource = .program) {
        if id == nil {
            showsPanel = false
        } else if source == .map, let id, derived.byID[id] != nil {
            showsPanel = true
        }
        guard selectedID != id else { return }
        selectedID = id
        selectionSource = source
        guard let id, let row = derived.byID[id] else { return }
        if derived.sections.first(where: { $0.kind == .morePlaces })?.rows.contains(where: { $0.id == id }) == true {
            moreOpenedByUser = true
        }
        if source == .map { scrollRequest = (nextRequestID(), id) }
        zoomToSelection(row.spot.coordinate)
    }

    // MARK: Panel

    /// Shows the panel for the current selection. Does nothing without one.
    public func openPanel() {
        guard selectedRow != nil else { return }
        showsPanel = true
    }

    /// Back to the list (the header's Back button, Escape). The selection stays, so the row is still highlighted.
    public func closePanel() { showsPanel = false }

    /// The selected place's place in the list, for the header ("3 of 16"). `index` counts from 1. Nil without a selection.
    public var panelPosition: (index: Int, count: Int)? {
        let all = rows
        guard let id = selectedID, let i = all.firstIndex(where: { $0.id == id }) else { return nil }
        return (i + 1, all.count)
    }
    public var canSelectNext: Bool { panelPosition.map { $0.index < $0.count } ?? false }
    public var canSelectPrevious: Bool { panelPosition.map { $0.index > 1 } ?? false }

    /// Steps to the next place in list order (the order `rows` and the list draw). Stays put at the end. Steps into
    /// "More Places" open it, as `select` does. The panel keeps its state; the list scrolls to the row meanwhile.
    public func selectNext() { step(by: 1) }
    public func selectPrevious() { step(by: -1) }

    private func step(by offset: Int) {
        let all = rows
        guard let id = selectedID, let i = all.firstIndex(where: { $0.id == id }), all.indices.contains(i + offset) else { return }
        let target = all[i + offset].id
        select(target, from: .keyboard)
        requestScroll(to: target)
    }

    /// Asks the list to scroll a row into view (launch-time screenshots; selection from the map does this itself).
    public func requestScroll(to id: String) {
        guard derived.byID[id] != nil else { return }
        scrollRequest = (nextRequestID(), id)
    }

    /// Nothing covers the map, so a revealed pin is kept just inside the edge on every side.
    static let revealMargins = MapCameraPolicy.Margins()

    /// Frames a newly selected spot: a `MapCameraPolicy.selectionRadiusMiles` radius around it, or a pan to centre it
    /// when the map is already closer in. A programmatic request, never a user move. Leaving the panel asks for nothing.
    public func zoomToSelection(_ coordinate: Coordinate) {
        // Before the map has settled anywhere, the starting camera already includes the selection (see `startPlan`).
        guard let current = visibleRegion else { return }
        let target = MapCameraPolicy.selectionRegion(current: current, spot: coordinate)
        cameraPolicy.didApplySelection(target)
        cameraRequest = CameraRequest(id: nextRequestID(), kind: .pan(target))
    }

    /// Pans the map so the coordinate is comfortably in view; does nothing when it already
    /// is, and never changes the zoom.
    public func reveal(_ coordinate: Coordinate) {
        // Before the map has settled anywhere, the starting camera already includes the selection (see
        // `startRegion`), so there is nothing to pan; the first camera request carries it.
        guard let current = visibleRegion else { return }
        let target = MapCameraPolicy.pan(current, toInclude: coordinate, margins: Self.revealMargins)
        guard target != current else { return }
        cameraPolicy.didApplyPan(target)
        cameraRequest = CameraRequest(id: nextRequestID(), kind: .pan(target))
    }

    /// What an automatic fit frames: the Near you rows (and Apple Maps results) and the user's own position when there is a location, else every
    /// listed row. Falls back to every row when filters leave Near you empty. Capped by `MapCameraPolicy.maxAutomaticSpan`.
    public var fitCoordinates: [Coordinate] {
        if hasLocation {
            let near = derived.sections.filter { $0.kind == .ask || $0.kind == .feature || $0.kind == .nearYou || $0.kind == .appleMaps }.flatMap(\.rows)
            if !near.isEmpty { return near.map(\.spot.coordinate) + [app.location.coordinate].compactMap { $0 } }
        }
        // Search Here results never move the camera.
        return derived.sections.filter { $0.kind != .inView }.flatMap(\.rows).map(\.spot.coordinate)
    }

    /// Where the map should start, and how it was chosen. The saved camera is kept when the user chose it or when it
    /// still contains a Near you row; a stale automatic one (saved far from here) gives way to a fresh fit. A selection
    /// made before the map exists is folded in with a pan (never a zoom).
    private func startPlan() -> (region: GeoRegion, base: GeoRegion, usesSaved: Bool)? {
        let coordinates = fitCoordinates
        var base: GeoRegion
        var usesSaved = false
        if let saved = cameraPolicy.savedRegion {
            let stale = hasLocation && !cameraPolicy.savedByUser && !coordinates.contains(where: saved.contains)
            if stale, let fit = MapCameraPolicy.fit(coordinates) { base = fit } else { base = saved; usesSaved = true }
        } else if let fit = MapCameraPolicy.fit(coordinates) {
            base = fit
        } else {
            return nil
        }
        var region = base
        if let id = selectedID, let row = derived.byID[id] {
            region = MapCameraPolicy.pan(base, toInclude: row.spot.coordinate, margins: Self.revealMargins)
        }
        return (region, base, usesSaved)
    }

    /// Where the map should start, so the pane can be created already framed and MapKit never shows its automatic
    /// camera. Pure: records nothing.
    public var initialCameraRegion: GeoRegion? { startPlan()?.region }

    /// First appearance: the starting camera (restored across launches, else a fit), including any selection.
    public func requestInitialCamera() {
        guard let plan = startPlan() else { return }
        if plan.usesSaved { cameraPolicy.didRestoreSavedCamera() } else { cameraPolicy.didApplyFit(plan.base) }
        if plan.region != plan.base { cameraPolicy.didApplyPan(plan.region) }
        cameraRequest = CameraRequest(id: nextRequestID(), kind: .fit(plan.region))
    }

    /// The list changed (filters, search, radius, a location fix): refit, unless the user has moved the map since
    /// the last fit.
    public func contentChanged() {
        guard let region = cameraPolicy.regionAfterContentChange(fitCoordinates) else { return }
        cameraRequest = CameraRequest(id: nextRequestID(), kind: .fit(region))
    }

    /// A location fix arrived (the sections regroup around it): fit the Near You rows unless the user has really moved
    /// the map away from the last automatic fit.
    public func locationChanged() {
        guard let region = cameraPolicy.regionAfterLocationFix(fitCoordinates, visible: visibleRegion) else { return }
        cameraRequest = CameraRequest(id: nextRequestID(), kind: .fit(region))
    }

    /// The map settled at `region` (called by the view when the camera stops moving).
    /// `byUser` is true only when the user really moved the map. A settle MapKit made on its own is never a user move
    /// and is saved only when it is the camera we asked for; when it is not, a request re-applies our region.
    public func cameraDidChange(to region: GeoRegion, byUser: Bool = false) {
        guard visibleRegion != region else { return }
        visibleRegion = region
        if !byUser { listRegion = region }
        switch cameraPolicy.cameraSettled(region, byUser: byUser) {
        case .saved:
            cameraPolicy.save(screen: Self.cameraScreenKey, defaults: defaults)
        case .reapply(let target):
            // MapKit settled somewhere we did not ask for: ask again (the view applies the new request).
            cameraRequest = CameraRequest(id: nextRequestID(), kind: .fit(target))
        case .ignored:
            break
        }
    }

    /// Ask results arrived: the person asked for them, so the map frames them even when it was moved by hand.
    private func askFinished() {
        resultSetChanged()
        let asked = sections.first { $0.kind == .ask }?.rows.map(\.spot.coordinate) ?? []
        guard let region = MapCameraPolicy.fit(asked) else { return }
        cameraPolicy.didApplyFit(region)
        cameraRequest = CameraRequest(id: nextRequestID(), kind: .fit(region))
    }

    private func nextRequestID() -> Int {
        requestCounter += 1
        return requestCounter
    }

    func resultSetChanged() {
        dropSelectionIfHidden()
        contentChanged()
    }

    func dropSelectionIfHidden() {
        if let id = selectedID, derived.byID[id] == nil {
            selectedID = nil
            showsPanel = false
        }
    }

    // MARK: Pins and clusters

    /// The map pane's size changed.
    public func setMapViewport(_ size: CGSize) {
        guard size != mapViewport else { return }
        mapViewport = size
    }

    /// What the map draws, already ordered for drawing (dots, clusters, chips, hovered, selected last; by stable id within each) and grouped:
    /// pins that would overlap at this zoom become clusters. Cached per derived stamp, region, selection, hover and
    /// viewport, so a body pass that changes none of them does no work.
    public var mapItems: [ExploreMapItem] { mapSnapshot.items }

    /// The pins drawn individually (everything in `mapItems` that is not a cluster), in the same order.
    public var pins: [ExplorePin] { mapSnapshot.pins }

    private var mapSnapshot: MapSnapshot {
        let stamp = currentStamp
        let key = MapKey(stamp: stamp, region: visibleRegion, selectedID: selectedID, hoveredID: hoveredID, viewport: mapViewport)
        if let cached = mapCache, cached.key == key { return cached.value }
        IterPerf.count("explore.pins")
        mapBuilds += 1
        let value = IterPerf.interval("explore.mapItems") { buildMapSnapshot(derived(for: stamp)) }
        mapCache = (key, value)
        return value
    }

    /// Pin hierarchy: the selected spot and the hovered one carry a chip; so do the best few scored spots in view;
    /// everything else is a small dot (pattern #4, critique C28). The selected and hovered pins are never clustered,
    /// and the chip budget is spent on pins that stay individual.
    private func buildMapSnapshot(_ value: Derived) -> MapSnapshot {
        let region = visibleRegion
        let fixed = Set([selectedID, hoveredID].compactMap { $0 })
        let candidates = value.rows.filter { !fixed.contains($0.id) }.map {
            PinClusterer.Candidate(id: $0.id, coordinate: $0.spot.coordinate, score: $0.score,
                                   band: $0.window?.assessment.lightScore?.band)
        }
        let grouped = PinClusterer.cluster(candidates, region: region, viewportWidth: Double(mapViewport.width))
        let single = Set(grouped.singles)
        let chipIDs = Set(value.rows
            .filter { single.contains($0.id) && $0.score != nil && (region?.contains($0.spot.coordinate) ?? true) }
            .sorted { ($0.score ?? 0) != ($1.score ?? 0) ? ($0.score ?? 0) > ($1.score ?? 0) : $0.id < $1.id }
            .prefix(Self.pinBudget).map(\.id))
        let now = app.now()
        var pins: [ExplorePin] = []
        for row in value.rows where single.contains(row.id) || fixed.contains(row.id) {
            let style: ExplorePinStyle = row.id == selectedID ? .selected : (row.id == hoveredID || chipIDs.contains(row.id)) ? .chip : .dot
            pins.append(Self.pin(for: row, style: style, now: now))
        }
        // Draw order (later is on top): dots, clusters, chips, the hovered pin, the selected pin; by id within each.
        let (selected, hovered) = (selectedID, hoveredID)
        let rank: @Sendable (String, ExplorePinStyle?) -> Int = { id, style in
            if id == selected { return 4 }
            if id == hovered { return 3 }
            switch style {
            case .chip?: return 2
            case nil: return 1
            default: return 0
            }
        }
        var items: [ExploreMapItem] = pins.map { .pin($0) } + grouped.clusters.map { .cluster($0) }
        items.sort { a, b in
            func r(_ i: ExploreMapItem) -> Int {
                switch i {
                case .pin(let p): rank(p.id, p.style)
                case .cluster(let c): rank(c.id, nil)
                }
            }
            return r(a) != r(b) ? r(a) < r(b) : a.id < b.id
        }
        pins.sort { a, b in
            rank(a.id, a.style) != rank(b.id, b.style) ? rank(a.id, a.style) < rank(b.id, b.style) : a.id < b.id
        }
        return MapSnapshot(items: items, pins: pins)
    }

    private static func pin(for row: ExploreRow, style: ExplorePinStyle, now: Date) -> ExplorePin {
        var light: ExplorePinLight?
        if let window = row.window {
            let score = window.assessment.lightScore.map { ExplorePinLight.Score(value: $0.value, band: $0.band, confidence: $0.confidence) }
            let isTomorrow = row.day.map { $0 != LocalDay(now, in: row.spot.timeZone) } ?? false
            light = ExplorePinLight(kind: window.kind, score: score, start: window.span.start, isLoading: row.isLoading,
                                    isTomorrow: isTomorrow)
        }
        return ExplorePin(id: row.id, name: row.spot.name, locality: row.spot.locality, coordinate: row.spot.coordinate,
                          timeZoneIdentifier: row.spot.timeZoneIdentifier, style: style, light: light)
    }

    /// A cluster was clicked: zoom the camera to fit its members. Goes through the camera policy as a programmatic
    /// request, so the settle that follows is never taken for a user move.
    public func zoomToCluster(_ id: String) {
        guard let cluster = mapItems.lazy.compactMap({ item -> ExploreCluster? in
            if case .cluster(let c) = item, c.id == id { return c }
            return nil
        }).first else { return }
        // The fit is the members' extent, never narrower than `minimumFitSpan`: that is below
        // `PinClusterer.minimumLongitudeSpan`, so the settle that follows unclusters members even at one coordinate.
        let floor = PinClusterer.minimumFitSpan
        guard let region = GeoRegion.enclosing(cluster.memberCoordinates, padding: 0.6, minimumDelta: floor) else { return }
        cameraPolicy.didApplyPan(region)
        cameraRequest = CameraRequest(id: nextRequestID(), kind: .fit(region))
    }

    /// Perf script only (`-IterPerfScript YES`): asks the map for a region as if the user had moved it there.
    public func perfRequestCamera(_ region: GeoRegion) {
        cameraRequest = CameraRequest(id: nextRequestID(), kind: .pan(region))
    }

    // MARK: - Apple Maps search

    private func queryChanged() {
        // A new or cleared search is about the list.
        closePanel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            searchTask?.cancel()
            searchTask = nil
            appleResults = []
            clearFeatureResults()
            searchState = .idle
            askModel.reset()
        } else {
            cancelSearchHere()
        }
        resultSetChanged()
    }

    /// Return in the search field: always the local search (the curated filter and Apple Maps). A request-like text
    /// also offers an Ask row (`searchSuggestions`), which the person chooses.
    public func submitSearch() {
        closePanel()
        searchAppleMaps()
    }

    /// Runs the Apple Maps search near the visible region. Debounced and cancellable: a second submit
    /// replaces the first, and clearing the field cancels it.
    public func searchAppleMaps() {
        closePanel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        cancelSearchHere()
        searchTask?.cancel()
        if let parsed = featureQuery(for: trimmed) { return runFeatureSearch(trimmed, parsed) }
        featureStatus = .idle
        searchState = .searching(query: trimmed)
        let region = visibleRegion
        let search = app.search
        let debounce = searchDebounce
        searchTask = Task { [weak self] in
            do {
                if debounce > .zero { try await Task.sleep(for: debounce) }
                let places = try await search.search(trimmed, near: region)
                guard !Task.isCancelled, let self else { return }
                self.finishSearch(trimmed, places: places)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.searchState = .failed(query: trimmed)
            }
        }
    }

    public func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        if searchState.isSearching { searchState = .idle }
    }

    func finishSearch(_ query: String, places: [PlaceResult]) {
        clearFeatureResults()
        appleResults = places.map(spot(from:))
        searchState = .finished(query: query, count: places.count)
        resultSetChanged()
        showSearchResults()
    }

    /// The person searched, so a result off the map is brought into view, as Ask does: a fit of the results alone (the
    /// densest cluster when they spread wider than an automatic fit may show), a programmatic request even after the
    /// map was moved by hand. `resultSetChanged` refits the whole list only while the user has not moved the map, and
    /// that fit weighs every Near You spot, so a result far from them was left off screen. Nothing moves when every
    /// result is already visible.
    private func showSearchResults() {
        showResults(appleResults.map(\.coordinate))
    }

    func showResults(_ found: [Coordinate]) {
        guard !found.isEmpty, let region = MapCameraPolicy.fit(found) else { return }
        if let visible = visibleRegion, found.allSatisfy(visible.contains) { return }
        cameraPolicy.didApplyFit(region)
        cameraRequest = CameraRequest(id: nextRequestID(), kind: .fit(region))
    }

    /// A search result as a spot: real coordinates, no "best at" (so the user's intent or sunset is scored).
    func spot(from place: PlaceResult) -> Spot {
        Spot(id: place.id, name: place.name, locality: place.locality, coordinate: place.coordinate,
             timeZoneIdentifier: place.timeZoneIdentifier ?? zoneIdentifier(near: place.coordinate),
             category: POICategoryMapping.spotCategory(for: place.pointOfInterestCategory),
             bestLight: [], popularity: 0, origin: .appleMaps)
    }

    /// When MapKit gives no zone: the nearest curated spot's, else a longitude-based offset (never the Mac's).
    func zoneIdentifier(near coordinate: Coordinate) -> String {
        TimeZoneEstimate.identifier(for: coordinate)
    }

    /// The user's "What I like to shoot" text, trimmed; nil when empty. The Ask row says "Using: ..." with it.
    public var activePromptPrefix: String? { app.searchSettings.activePromptPrefix }

    // MARK: - Add your own spot

    public func beginAddingSpot() { isAddingSpot = true }

    /// A click on the map in Add Spot mode.
    public func dropPin(at coordinate: Coordinate) {
        guard isAddingSpot else { return }
        draftCoordinate = coordinate
    }

    // MARK: - Move your own spot

    /// Only your own spots move; curated and found places are Apple's and ours.
    public func canMove(_ id: String) -> Bool {
        guard let uuid = UUID(uuidString: id), let place = app.store.place(id: uuid) else { return false }
        return place.origin == .user
    }

    /// Saves a new place for one of your own spots. The coordinate is yours exactly (never a lookup's), the change is one
    /// undo step ("Move Spot"), and the forecast for the new place is fetched.
    public func move(_ id: String, to coordinate: Coordinate) {
        guard canMove(id), app.store.moveSpot(id: id, to: coordinate) else { return }
        if let row = row(id: id) { app.spotSaved(row.spot) }
    }

    /// Where to draw a pin: the drag's coordinate while it is being dragged, else the stored one.
    public func displayCoordinate(for id: String, stored: Coordinate) -> Coordinate {
        if let dragging, dragging.id == id { return dragging.coordinate }
        return stored
    }

    /// Starts a drag on one of your own pins, selected or not: a press on an unselected pin selects it in the same gesture
    /// (see `selectForDrag`), so the first drag never needs a click first.
    @discardableResult
    public func beginDrag(_ id: String) -> Bool {
        guard canMove(id), adjusting == nil, !isAddingSpot, let row = row(id: id) else { return false }
        selectForDrag(id)
        dragging = (id, row.spot.coordinate)
        return true
    }

    /// Selects a pin the way a map click does (the panel opens, the list scrolls to the row) but leaves the camera alone:
    /// the map must stay still under the pointer while the pin is dragged.
    private func selectForDrag(_ id: String) {
        guard derived.byID[id] != nil else { return }
        showsPanel = true
        guard selectedID != id else { return }
        selectedID = id
        selectionSource = .map
        scrollRequest = (nextRequestID(), id)
    }

    public func drag(to coordinate: Coordinate) {
        guard let current = dragging else { return }
        dragging = (current.id, coordinate)
    }

    /// The drop. `commit` stores the dragged-to coordinate; otherwise the pin goes back.
    public func endDrag(commit: Bool) {
        guard let current = dragging else { return }
        dragging = nil
        if commit { move(current.id, to: current.coordinate) }
    }

    /// Adjust Location from the place card: remembers where the spot was; the view pans the map to it.
    @discardableResult
    public func beginAdjusting(_ id: String) -> Bool {
        guard canMove(id), dragging == nil, let row = row(id: id) else { return false }
        adjusting = AdjustLocation(id: id, original: row.spot.coordinate, center: row.spot.coordinate)
        return true
    }

    public func adjustCenterChanged(_ center: Coordinate) { adjusting?.center = center }

    /// Done saves the crosshair's coordinate; Cancel leaves the spot where it was.
    public func finishAdjusting(commit: Bool) {
        guard let session = adjusting else { return }
        adjusting = nil
        if commit { move(session.id, to: session.center) }
    }

    /// The editor closed without saving.
    public func cancelDraft() { draftCoordinate = nil }

    /// The editor saved a new spot: leave the mode, select it, show it.
    public func didCreate(_ spot: Spot) {
        isAddingSpot = false
        app.spotSaved(spot)
        // Filters could hide the new spot; the user just made it, so make sure it shows.
        if !filters.sources.contains(.yours) { filters.sources.insert(.yours) }
        select(spot.id, from: .program)
        openPanel()
        reveal(spot.coordinate)
    }
}
