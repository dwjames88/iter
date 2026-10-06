import Foundation
import Observation
import IterCore
import IterData
import IterServices

/// State and derived data for the Explore screen: date, filters, sort, search, results, selection and camera requests.
/// One selection drives pin, row and place card (pattern #5). Platform-neutral; the view draws it.
@MainActor
@Observable
public final class ExploreModel {
    public let app: AppModel

    // MARK: Inputs

    /// The day lit on every row and pin.
    public var day: LocalDay
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

    // MARK: Outputs the view reads

    public private(set) var appleResults: [Spot] = []
    public private(set) var searchState: ExploreSearchState = .idle
    public private(set) var selectedID: String?
    public private(set) var selectionSource: SelectionSource = .program
    /// The one list row open to its actions and weather. Always nil or equal to `selectedID`.
    public private(set) var expandedID: String?
    public private(set) var cameraRequest: CameraRequest?
    /// Asks the list to scroll a row into view when `id` changes.
    public private(set) var scrollRequest: (id: Int, target: String)?
    /// The map's visible region, reported by the view when the camera settles.
    public private(set) var visibleRegion: GeoRegion?

    /// Chips on the map besides the selected one.
    public static let pinBudget = 6
    /// Curated `Spot.popularity` (0 to 100, high = iconic and crowded) at or above which a spot beyond the radius is
    /// listed under "Popular". It comes from the curated field; no visitor numbers are involved.
    public static let popularThreshold = 80
    /// The screen key the map camera is saved under.
    public static let cameraScreenKey = "explore"
    private static let metersPerMile = 1609.344

    @ObservationIgnored public var searchDebounce: Duration
    @ObservationIgnored public private(set) var searchTask: Task<Void, Never>?
    @ObservationIgnored private var requestCounter = 0
    @ObservationIgnored private var windowCache: [String: CachedWindow] = [:]
    @ObservationIgnored private var windowCacheStamp: WindowStamp?
    @ObservationIgnored private var derivedCache: (stamp: DerivedStamp, value: Derived)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored public private(set) var cameraPolicy: MapCameraPolicy

    public init(app: AppModel, searchDebounce: Duration = .milliseconds(250), defaults: UserDefaults = .standard) {
        self.app = app
        self.searchDebounce = searchDebounce
        self.defaults = defaults
        self.cameraPolicy = MapCameraPolicy.load(screen: Self.cameraScreenKey, defaults: defaults)
        self.day = app.today(in: .current)
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

    // MARK: - Day

    public var isToday: Bool { day == app.today(in: .current) }

    public func shiftDay(by days: Int) { day = day.adding(days: days) }
    public func goToToday() { day = app.today(in: .current) }

    // MARK: - Derived rows

    private struct CachedWindow { var window: LightWindow? }
    private struct WindowStamp: Equatable { var day: LocalDay; var intent: LightIntent? }
    private struct DerivedStamp: Equatable {
        var day: LocalDay
        var intent: LightIntent?
        var forecastRevision: Int
        var storeRevision: Int
        var filters: ExploreFilters
        var sort: ExploreSort
        var query: String
        var appleIDs: [String]
        /// What distances are measured from: you, else the map centre while sorting by distance.
        var origin: Coordinate?
        var hasLocation: Bool
        var radiusMiles: Int
    }
    private struct Derived {
        var sections: [ExploreSection]
        var rows: [ExploreRow]
        var byID: [String: ExploreRow]
    }

    private var derived: Derived {
        let user = app.location.coordinate
        let origin: Coordinate? = user ?? (sort == .distance ? visibleRegion?.center : nil)
        let stamp = DerivedStamp(day: day, intent: app.preferredIntent, forecastRevision: app.forecasts.revision,
                                 storeRevision: app.store.revision, filters: filters, sort: sort,
                                 query: query.trimmingCharacters(in: .whitespacesAndNewlines),
                                 appleIDs: appleResults.map(\.id), origin: origin, hasLocation: user != nil,
                                 radiusMiles: app.location.radiusMiles)
        if let cached = derivedCache, cached.stamp == stamp { return cached.value }
        let value = buildDerived(stamp)
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
        var out: [(Spot, ExploreSource)] = CuratedSpots.all.map { ($0, .curated) }
        let yours = app.store.savedPlaces().filter { $0.origin == .user }.map(\.spot)
        out += yours.map { ($0, .yours) }
        out += appleResults.map { ($0, .appleMaps) }
        return out
    }

    private func buildDerived(_ stamp: DerivedStamp) -> Derived {
        refreshWindowCache(day: stamp.day, intent: stamp.intent)
        var rows: [ExploreRow] = []
        for (spot, source) in candidates() where Self.matches(spot, source: source, filters: filters, query: stamp.query) {
            rows.append(ExploreRow(spot: spot, source: source, window: window(for: spot),
                                   distanceMeters: stamp.origin.map { $0.distance(to: spot.coordinate) }))
        }
        let own = rows.filter { $0.source != .appleMaps }
        let apple = Self.sorted(rows.filter { $0.source == .appleMaps }, by: sort)
        var sections: [ExploreSection] = []
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
        let flat = sections.flatMap(\.rows)
        return Derived(sections: sections, rows: flat, byID: Dictionary(flat.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }))
    }

    private func refreshWindowCache(day: LocalDay, intent: LightIntent?) {
        let stamp = WindowStamp(day: day, intent: intent)
        if windowCacheStamp != stamp {
            windowCache = [:]
            windowCacheStamp = stamp
        }
    }

    /// The headline window for the chosen intent. Pure read: it never starts a fetch (see `requestForecasts`).
    /// Cached per spot, day, intent and forecast state, so scrolling and revision bumps stay cheap.
    private func window(for spot: Spot) -> LightWindow? {
        let state = app.forecasts.state(for: spot.coordinate)
        let tag: String
        switch state {
        case .loading: tag = "L"
        case .loaded(let f): tag = "F\(f.fetchedAt.timeIntervalSince1970)"
        case .unavailable(let r): tag = "U\(r.hashValue)"
        }
        let key = "\(spot.id)|\(spot.coordinate.cacheKey)|\(tag)"
        if let hit = windowCache[key] { return hit.window }
        let dayLight = app.engine.dayLight(for: spot, on: day, forecast: state.forecast,
                                           unavailable: state.unavailableReason, now: app.now())
        let window = dayLight.headline(for: app.intent(for: spot))
        windowCache[key] = CachedWindow(window: window)
        return window
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

    /// One honest line for the whole list when forecasts are missing, instead of the same reason on every row.
    /// The most common specific reason among rows without a forecast; nil when everything is scored or still loading.
    public var forecastNotice: ForecastUnavailableReason? {
        var counts: [ForecastUnavailableReason: Int] = [:]
        for row in rows {
            if let reason = row.unavailableReason, reason != .notLoaded, reason != .inThePast { counts[reason, default: 0] += 1 }
        }
        return counts.max { $0.value < $1.value }?.key
    }

    /// True when any listed score was made from sample weather (the list says so once).
    public var hasSampleScores: Bool {
        rows.contains { $0.window?.assessment.lightScore?.source == .sample }
    }

    /// Forecasts still on their way.
    public var isLoadingForecasts: Bool {
        rows.contains { $0.unavailableReason == .notLoaded }
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

    /// Starts forecast fetches for every candidate that could be listed (the fetches are shared and cached).
    public func requestForecasts() {
        app.forecasts.requestAll(rows.map(\.spot.coordinate))
    }

    // MARK: - Selection and camera

    /// Selects a row (or clears with nil). The list follows a map selection by scrolling; the map follows a
    /// list selection by panning only if the pin is out of view (pattern #5).
    public func select(_ id: String?, from source: SelectionSource = .program) {
        if expandedID != id { expandedID = nil }
        guard selectedID != id else { return }
        selectedID = id
        selectionSource = source
        guard let id, let row = derived.byID[id] else { return }
        if derived.sections.first(where: { $0.kind == .morePlaces })?.rows.contains(where: { $0.id == id }) == true {
            moreOpenedByUser = true
        }
        if source == .map { scrollRequest = (nextRequestID(), id) }
        reveal(row.spot.coordinate)
    }

    /// A click on a list row: a collapsed row is selected and expanded, an expanded row collapses. The list's
    /// selection binding and the click gesture may arrive in either order; both orders end in the same state.
    public func rowClicked(_ id: String) {
        guard derived.byID[id] != nil else { return }
        if expandedID == id {
            expandedID = nil
            return
        }
        select(id, from: .list)
        expandedID = id
    }

    /// Space or Return on the selected row: expand it, or collapse it when already open.
    public func toggleExpansion() {
        guard let id = selectedID, derived.byID[id] != nil else { return }
        expandedID = expandedID == id ? nil : id
    }

    public func collapse() { expandedID = nil }

    /// Asks the list to scroll a row into view (launch-time screenshots; selection from the map does this itself).
    public func requestScroll(to id: String) {
        guard derived.byID[id] != nil else { return }
        scrollRequest = (nextRequestID(), id)
    }

    /// The place card covers up to the lower half of the map, so a revealed pin is kept in the upper part.
    static let revealMargins = MapCameraPolicy.Margins(bottom: 0.5)

    /// Pans the map so the coordinate is comfortably in view (clear of the place card); does nothing when it already
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

    /// What an automatic fit frames: the Near you rows (and Apple Maps results) when there is a location, else every
    /// listed row. Falls back to every row when filters leave Near you empty. Capped by `MapCameraPolicy.maxAutomaticSpan`.
    public var fitCoordinates: [Coordinate] {
        if hasLocation {
            let near = derived.sections.filter { $0.kind == .nearYou || $0.kind == .appleMaps }.flatMap(\.rows)
            if !near.isEmpty { return near.map(\.spot.coordinate) }
        }
        return rows.map(\.spot.coordinate)
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

    private func nextRequestID() -> Int {
        requestCounter += 1
        return requestCounter
    }

    private func resultSetChanged() {
        dropSelectionIfHidden()
        contentChanged()
    }

    private func dropSelectionIfHidden() {
        if let id = selectedID, derived.byID[id] == nil { selectedID = nil }
        if let id = expandedID, derived.byID[id] == nil { expandedID = nil }
    }

    // MARK: Pins

    /// Pin hierarchy: the selected spot and the hovered one carry a chip; so do the best few scored spots in view;
    /// everything else is a small dot (pattern #4, critique C28).
    public var pins: [ExplorePin] {
        let region = visibleRegion
        let inView = rows.filter { region?.contains($0.spot.coordinate) ?? true }
        let best = inView.filter { $0.score != nil && $0.id != selectedID }
            .sorted { ($0.score ?? 0) > ($1.score ?? 0) }
            .prefix(Self.pinBudget)
        let chipIDs = Set(best.map(\.id))
        return rows.map { row in
            if row.id == selectedID { return ExplorePin(row: row, style: .selected) }
            if row.id == hoveredID || chipIDs.contains(row.id) { return ExplorePin(row: row, style: .chip) }
            return ExplorePin(row: row, style: .dot)
        }
    }

    // MARK: - Apple Maps search

    private func queryChanged() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            searchTask?.cancel()
            searchTask = nil
            appleResults = []
            searchState = .idle
        }
        resultSetChanged()
    }

    /// Runs the Apple Maps search near the visible region. Debounced and cancellable: a second submit
    /// replaces the first, and clearing the field cancels it.
    public func submitSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searchTask?.cancel()
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

    private func finishSearch(_ query: String, places: [PlaceResult]) {
        appleResults = places.map(spot(from:))
        searchState = .finished(query: query, count: places.count)
        resultSetChanged()
    }

    /// A search result as a spot: real coordinates, no "best at" (so the user's intent or sunset is scored).
    func spot(from place: PlaceResult) -> Spot {
        Spot(id: place.id, name: place.name, locality: place.locality, coordinate: place.coordinate,
             timeZoneIdentifier: place.timeZoneIdentifier ?? zoneIdentifier(near: place.coordinate),
             category: POICategoryMapping.spotCategory(for: place.pointOfInterestCategory),
             bestLight: [], popularity: 0, origin: .appleMaps)
    }

    /// When MapKit gives no zone: the nearest curated spot's, else the Mac's.
    func zoneIdentifier(near coordinate: Coordinate) -> String {
        CuratedSpots.all.min { $0.coordinate.distance(to: coordinate) < $1.coordinate.distance(to: coordinate) }?.timeZoneIdentifier
            ?? TimeZone.current.identifier
    }

    // MARK: - Add your own spot

    public func beginAddingSpot() { isAddingSpot = true }

    /// A click on the map in Add Spot mode.
    public func dropPin(at coordinate: Coordinate) {
        guard isAddingSpot else { return }
        draftCoordinate = coordinate
    }

    /// The editor closed without saving.
    public func cancelDraft() { draftCoordinate = nil }

    /// The editor saved a new spot: leave the mode, select it, show it.
    public func didCreate(_ spot: Spot) {
        isAddingSpot = false
        // Filters could hide the new spot; the user just made it, so make sure it shows.
        if !filters.sources.contains(.yours) { filters.sources.insert(.yours) }
        select(spot.id, from: .program)
        reveal(spot.coordinate)
    }
}
