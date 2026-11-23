import Foundation
import Observation
import IterModel
import IterSources
import IterStore
import IterDiscovery

/// The Find stage (BLUEPRINT §7 and §2): one search field, a typed lookup of saved places and Apple Maps, AI discovery that
/// streams sources and places, Search Here over the visible map, feature searches, filters and ordering, and the place card
/// for what is selected.
///
/// State is per property so a view that reads one thing is not invalidated by another; rows, chips and map content are
/// `Equatable` values computed here, off any view body. Every run and every follow-up (drive times, Look Around, time
/// zone) is a structured task under a generation guard: a late answer from a superseded run is dropped.
@MainActor @Observable
public final class FindModel {
    // MARK: Observable state

    /// The search field. Setting it refreshes `suggestions`.
    public var text: String = "" {
        didSet { if text != oldValue { suggestions = Self.suggestions(for: text) } }
    }
    public internal(set) var suggestions: FindSuggestions = .none
    public internal(set) var phase: FindPhase = .idle
    /// Typed-lookup matches: your saved places first, then Apple Maps.
    public internal(set) var matches: [PlaceMatch] = []
    /// The per-source list for the current discovery run, including sources that cannot be used (Reddit, Google).
    public internal(set) var chips: [SourceChip] = []
    public internal(set) var progress = FindProgress()
    /// "Basic search: AI unavailable (Apple Intelligence is turned off)"; nil when the on-device model planned the query.
    public internal(set) var planLabel: String?
    public internal(set) var isBasicSearch = false
    public internal(set) var area: FindArea?
    /// True when the strict pass found few places and related subjects were added.
    public internal(set) var widened = false
    /// Places the engine found and verification dropped (for the "why fewer?" line).
    public internal(set) var droppedCount = 0
    public internal(set) var rows: [FindRow] = []
    public internal(set) var kindFilters: [KindFilter] = []
    public internal(set) var mapContent: FindMapContent = .empty
    public internal(set) var selectedID: String?
    public internal(set) var card: PlaceCard?
    public internal(set) var lookAround: LookAroundAvailability = .unknown
    /// The selected place's Sky Index score for the card's header chip; nil when no scoring is wired or nothing is selected.
    public internal(set) var cardScore: FindScore?
    /// Set when Search Here is asked with no map region to search.
    public internal(set) var notice: String?

    // MARK: Collaborators and internals

    /// Asked once per search, so a container that rebuilds its engine from current preferences is always read fresh.
    @ObservationIgnored let runnerFactory: @MainActor () -> any DiscoveryRunning
    @ObservationIgnored let placeSearch: any PlaceSearchProvider
    @ObservationIgnored let geocoder: any Geocoder
    @ObservationIgnored let routing: any RoutingProvider
    @ObservationIgnored let streetLevel: (any StreetLevelImageryProvider)?
    @ObservationIgnored let library: LibraryStore
    @ObservationIgnored let preferences: Preferences
    @ObservationIgnored let location: any LocationProviding
    @ObservationIgnored let now: @Sendable () -> Date
    @ObservationIgnored let configuration: FindConfiguration
    /// The shared Conditions stage, for each result's score. Nil: results carry no score.
    @ObservationIgnored let scoreSource: (any FindScoreSource)?
    /// Your own spots: drop, drag, Adjust Location, coordinates and readouts.
    @ObservationIgnored public let spots: OwnSpotEditor

    @ObservationIgnored var region: GeoRegion?
    @ObservationIgnored var viewportWidth: Double = 0
    @ObservationIgnored var lastBucket: Int?
    @ObservationIgnored var raw: [DiscoveredPlace] = []
    @ObservationIgnored var rawStatuses: [SourceStatus] = []
    @ObservationIgnored var firstSeen: [String: TimeInterval] = [:]
    @ObservationIgnored var startedAt: TimeInterval = 0
    @ObservationIgnored var stoppedAt: TimeInterval?
    @ObservationIgnored var selectedKinds: Set<FeatureKind> = []
    @ObservationIgnored var driveSeconds: [String: TimeInterval] = [:]
    @ObservationIgnored var driveFailed: Set<String> = []
    @ObservationIgnored var fetchingDrive: Set<String> = []
    @ObservationIgnored var places: [String: Place] = [:]
    @ObservationIgnored var zoneResolved: Set<String> = []
    @ObservationIgnored var zoneTasks: [String: Task<Void, Never>] = [:]

    @ObservationIgnored var scoreTargets: [String: ScoreTarget] = [:]
    @ObservationIgnored var scoreValues: [String: FindScore] = [:]
    @ObservationIgnored var visibleResultIDs: Set<String>?
    @ObservationIgnored var scoreGeneration = 0

    @ObservationIgnored var runGeneration = 0
    @ObservationIgnored var lookupGeneration = 0
    @ObservationIgnored var driveGeneration = 0
    @ObservationIgnored var selectionGeneration = 0
    @ObservationIgnored var runTask: Task<Void, Never>?
    @ObservationIgnored var lookupTask: Task<Void, Never>?
    @ObservationIgnored var tickTask: Task<Void, Never>?
    @ObservationIgnored var driveTask: Task<Void, Never>?
    @ObservationIgnored var lookTask: Task<Void, Never>?

    public convenience init(discovery: any DiscoveryRunning, placeSearch: any PlaceSearchProvider, geocoder: any Geocoder, routing: any RoutingProvider,
                streetLevel: (any StreetLevelImageryProvider)?, magnetic: any MagneticModelProvider, gridReference: any GridReferenceProvider,
                library: LibraryStore, preferences: Preferences, location: any LocationProviding,
                now: @escaping @Sendable () -> Date, configuration: FindConfiguration = FindConfiguration(),
                scores: (any FindScoreSource)? = nil) {
        self.init(discoveryFactory: { discovery }, placeSearch: placeSearch, geocoder: geocoder, routing: routing, streetLevel: streetLevel,
                  magnetic: magnetic, gridReference: gridReference, library: library, preferences: preferences, location: location, now: now,
                  configuration: configuration, scores: scores)
    }

    public init(discoveryFactory: @escaping @MainActor () -> any DiscoveryRunning, placeSearch: any PlaceSearchProvider, geocoder: any Geocoder, routing: any RoutingProvider,
                streetLevel: (any StreetLevelImageryProvider)?, magnetic: any MagneticModelProvider, gridReference: any GridReferenceProvider,
                library: LibraryStore, preferences: Preferences, location: any LocationProviding,
                now: @escaping @Sendable () -> Date, configuration: FindConfiguration = FindConfiguration(),
                scores: (any FindScoreSource)? = nil) {
        self.scoreSource = scores
        self.runnerFactory = discoveryFactory
        self.placeSearch = placeSearch
        self.geocoder = geocoder
        self.routing = routing
        self.streetLevel = streetLevel
        self.library = library
        self.preferences = preferences
        self.location = location
        self.now = now
        self.configuration = configuration
        self.spots = OwnSpotEditor(library: library, geocoder: geocoder, magnetic: magnetic, grid: gridReference, now: now)
        refreshLibraryPins()
    }

    // MARK: Suggestions

    static func suggestions(for text: String) -> FindSuggestions {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return .none }
        return FindSuggestions(lookup: t, ask: FindIntent.classify(t) == .ask ? t : nil, feature: FeatureAreaQuery.parse(t))
    }

    // MARK: Map region

    /// The visible map region, for Search Here and to bias lookups. Reading never moves the map.
    public var mapRegion: GeoRegion? {
        get { region }
        set { region = newValue }
    }

    /// The map settled at `region` (debounced by the view) with this width in points. Regroups clusters only when the zoom
    /// bucket changed; panning inside a bucket does no work.
    public func setViewport(region newRegion: GeoRegion, width: Double) {
        region = newRegion
        viewportWidth = width
        let bucket = FindPinClusterer.zoomBucket(region: newRegion, viewportWidth: width)
        if bucket != lastBucket {
            lastBucket = bucket
            rebuildMapContent()
        }
    }

    // MARK: Running

    /// Return in the field. "<feature> in <area>" goes through discovery; anything else is a lookup of your saved places
    /// and Apple Maps. Blank text does nothing.
    public func submit() {
        let s = suggestions
        guard let query = s.lookup else { return }
        if s.feature != nil { runDiscovery(query) } else { lookUp(query) }
    }

    /// The Ask Iter suggestion: run the text as an AI discovery search whatever it looks like.
    public func askIter() {
        guard let query = suggestions.lookup else { return }
        runDiscovery(query)
    }

    /// Search Here: discovery over the visible map region. Never moves the map. The field's text says what to look for
    /// (a feature, keywords); an area it names is replaced by the map's.
    public func searchHere() {
        guard let region else {
            notice = "Move the map to the area you want to search."
            return
        }
        notice = nil
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        runDiscovery(Self.hereQuery(from: t), region: region)
    }

    static func hereQuery(from text: String) -> String {
        guard !text.isEmpty else { return "photo spots in this area" }
        let plan = BasicQueryParser.parse(text, hasMapRegion: true)
        let what = plan.features.map(\.pluralName) + plan.keywords.filter { k in !plan.features.contains { $0.synonyms.contains(k.lowercased()) } }
        return what.isEmpty ? "\(text) in this area" : what.joined(separator: " ") + " in this area"
    }

    /// Stops the run and ignores anything it still sends. What arrived stays on screen, marked as stopped.
    public func cancel() {
        runGeneration += 1
        lookupGeneration += 1
        runTask?.cancel(); runTask = nil
        lookupTask?.cancel(); lookupTask = nil
        stopTicking()
        cancelDriveTimes()
        if phase == .discovering || phase == .lookingUp { stoppedAt = configuration.monotonic() }
        if phase == .discovering || phase == .lookingUp { phase = .cancelled }
        progress.isRunning = false
        rebuildChips()
    }

    /// Clears the field and everything a search left.
    public func clear() {
        cancel()
        text = ""
        resetResults()
        phase = .idle
        notice = nil
        deselect()
    }

    func resetResults() {
        raw = []
        rawStatuses = []
        firstSeen = [:]
        driveSeconds = [:]
        driveFailed = []
        fetchingDrive = []
        selectedKinds = []
        matches = []
        chips = []
        progress = FindProgress()
        planLabel = nil
        isBasicSearch = false
        area = nil
        widened = false
        droppedCount = 0
        rows = []
        kindFilters = []
        resetScores()
        rebuildMapContent()
    }

    func runDiscovery(_ query: String, region searchRegion: GeoRegion? = nil) {
        cancel()
        resetResults()
        notice = nil
        runGeneration += 1
        let mine = runGeneration
        phase = .discovering
        startedAt = configuration.monotonic()
        stoppedAt = nil
        progress = FindProgress(isRunning: true)
        let saved = library.places.savedValues()
        let request = DiscoveryRequest(
            text: query, mapRegion: searchRegion ?? region, currentLocation: location.current, ordering: preferences.ordering,
            preferenceText: preferences.preferenceText.isEmpty ? nil : preferences.preferenceText,
            library: saved.map { LibraryReference(name: $0.name, coordinate: $0.coordinate) }, maxResults: preferences.resultCap)
        let stream = runnerFactory().run(request)
        startTicking(generation: mine)
        runTask = Task { [weak self] in
            for await event in stream {
                guard let self, self.runGeneration == mine, !Task.isCancelled else { return }
                self.apply(event)
            }
            guard let self, self.runGeneration == mine, self.phase == .discovering else { return }
            self.finishRun()
        }
    }

    private func apply(_ event: DiscoveryEvent) {
        switch event {
        case .planReady(_, let origin):
            planLabel = origin.label
            isBasicSearch = origin.isBasic
        case .areaResolved(let resolved):
            area = FindArea.make(resolved)
            rebuildMapContent()
        case .statusChanged(let s):
            upsert(s)
            rebuildChips()
        case .partial(let list):
            raw = list
            rebuildRows()
        case .finished(let result):
            raw = result.places
            rawStatuses = []
            for s in result.statuses { upsert(s) }
            planLabel = result.planOrigin.label
            isBasicSearch = result.planOrigin.isBasic
            area = result.area.map(FindArea.make) ?? area
            widened = result.widened
            droppedCount = result.dropped.count
            if let failure = result.failure { phase = .failed(failure.description) } else { phase = .finished }
            finishRun()
        }
    }

    private func finishRun() {
        if phase == .discovering { phase = .finished }
        stopTicking()
        stoppedAt = stoppedAt ?? configuration.monotonic()
        progress.isRunning = false
        rebuildChips()
        rebuildRows()
        if phase == .finished { startDriveTimes() }
    }

    private func upsert(_ s: SourceStatus) {
        if firstSeen[s.id] == nil { firstSeen[s.id] = configuration.monotonic() }
        if let i = rawStatuses.firstIndex(where: { $0.id == s.id }) {
            if case .searching = s.state, case .searching = rawStatuses[i].state {} else if case .searching = s.state { firstSeen[s.id] = configuration.monotonic() }
            rawStatuses[i] = s
        } else {
            rawStatuses.append(s)
        }
    }

    // MARK: Ticking (elapsed time and slow sources)

    private func startTicking(generation: Int) {
        tickTask?.cancel()
        let tick = configuration.tick
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: tick)
                guard let self, !Task.isCancelled, self.runGeneration == generation else { return }
                self.rebuildChips()
            }
        }
    }

    func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    /// Rebuilds the source list and the progress line from the raw statuses and the clock.
    func rebuildChips() {
        let t = configuration.monotonic()
        let slowSeconds = configuration.slowAfter.timeInterval
        let stopped = phase == .cancelled
        var out: [SourceChip] = []
        for s in rawStatuses {
            let waited = t - (firstSeen[s.id] ?? t)
            var chip = SourceChip.make(s, slow: waited >= slowSeconds)
            if stopped, chip.isWorking {
                chip.state = .skipped
                chip.text = "\(s.name): stopped"
                chip.reason = "You stopped the search before it answered."
            }
            out.append(chip)
        }
        // Working and answered sources first, then the ones that cannot be used, so the useful rows lead.
        let order: (SourceChip) -> Int = { c in c.state == .unavailable ? 2 : (c.state == .skipped ? 1 : 0) }
        out = out.enumerated().sorted { (order($0.element), $0.offset) < (order($1.element), $1.offset) }.map(\.element)
        if out != chips { chips = out }
        let asked = out.filter(\.isAsked)
        let p = FindProgress(done: asked.filter { !$0.isWorking }.count, total: asked.count,
                             elapsed: startedAt == 0 ? 0 : max(0, (stoppedAt ?? t) - startedAt), isRunning: phase == .discovering)
        if p != progress { progress = p }
    }
}

extension Duration {
    var timeInterval: TimeInterval { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
