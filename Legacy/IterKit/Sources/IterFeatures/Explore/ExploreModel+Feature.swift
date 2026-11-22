import Foundation
import IterCore
import IterServices

/// "<feature> in <area>" typed into the search field ("mountains in Glacier National Park"): the area is looked up
/// (with its real outline when OpenStreetMap has one), Discovery lists the feature there from its sources, Apple Maps
/// searches the same text inside the area, and the two are merged into the Feature section. Anything outside the
/// outline is dropped. The camera fits the results, as a typed search does.
extension ExploreModel {
    /// The parsed query when the typed text should run as a feature search: it reads "<feature> in <area>", an engine
    /// is present, and at least one Discovery source is switched on. Otherwise the ordinary Apple Maps search runs.
    public func featureQuery(for text: String) -> FeatureAreaQuery? {
        guard app.discovery != nil, app.searchSettings.hasDiscoverySources else { return nil }
        return FeatureAreaQuery.parse(text)
    }

    /// What a feature search takes from its children, as plain values.
    private enum FeatureOutcome: Sendable {
        case maps([PlaceResult]?)
        case discovery(DiscoveryReport?)
    }

    func clearFeatureResults() {
        let had = !featureResults.isEmpty
        featureResults = []
        featureArea = nil
        featureStatus = .idle
        if had { featureRevision += 1 }
    }

    func runFeatureSearch(_ text: String, _ parsed: FeatureAreaQuery) {
        guard let discovery = app.discovery else { return }
        var status = FeatureSearchStatus()
        status.phase = .resolvingArea
        status.query = text
        status.feature = parsed.feature
        status.areaName = parsed.area
        featureStatus = status
        searchState = .searching(query: text)
        let search = app.search
        let settings = app.discoverySettings()
        let debounce = searchDebounce
        let fallbackRegion = visibleRegion
        searchTask = Task { [weak self] in
            do {
                if debounce > .zero { try await Task.sleep(for: debounce) }
                guard let area = await discovery.resolveArea(named: parsed.area, fallbackSearch: search) else {
                    // Nowhere to look: the plain Apple Maps search for the text, with the status saying so.
                    let places = try await search.search(text, near: fallbackRegion)
                    guard !Task.isCancelled, let self else { return }
                    self.finishSearch(text, places: places)
                    var fallback = FeatureSearchStatus()
                    fallback.query = text
                    fallback.feature = parsed.feature
                    fallback.areaName = parsed.area
                    fallback.areaNotFound = true
                    fallback.phase = .finished
                    fallback.total = places.count
                    self.featureStatus = fallback
                    return
                }
                guard !Task.isCancelled, let self else { return }
                await self.searchFeature(text, parsed, area: area, discovery: discovery, search: search, settings: settings)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.featureStatus = .idle
                self.searchState = .failed(query: text)
            }
        }
    }

    private func searchFeature(_ text: String, _ parsed: FeatureAreaQuery, area: DiscoveryArea, discovery: any Discovering,
                               search: any PlaceSearching, settings: DiscoverySettings) async {
        featureArea = area
        featureStatus.phase = .searching
        featureStatus.hasBoundary = !(area.boundary?.isEmpty ?? true)
        var mapsPlaces: [PlaceResult] = []
        var discovered: [DiscoveredPlace] = []
        var discoveryFailed = false
        await withTaskGroup(of: FeatureOutcome.self) { group in
            group.addTask { .maps(try? await search.search(text, near: area.region)) }
            group.addTask {
                do { return .discovery(try await discovery.discover(area: area, feature: parsed.feature, text: nil, settings: settings)) }
                catch { return .discovery(nil) }
            }
            for await outcome in group {
                guard !Task.isCancelled else { group.cancelAll(); return }
                switch outcome {
                case .maps(let places):
                    if let places {
                        mapsPlaces = places
                        featureStatus.maps = .found(places.filter { area.contains($0.coordinate) }.count)
                    } else {
                        featureStatus.maps = .failed
                    }
                case .discovery(let report):
                    if let report {
                        discovered = report.places
                        featureStatus.sources = report.statuses
                    } else {
                        discoveryFailed = true
                        featureStatus.discoveryFailed = true
                    }
                }
                publishFeature(text, area: area, maps: mapsPlaces, discovered: discovered)
            }
        }
        guard !Task.isCancelled else { return }
        featureStatus.phase = .finished
        searchTask = nil
        let failed = featureResults.isEmpty && featureStatus.maps == .failed && (discoveryFailed || discovered.isEmpty)
            && featureStatus.sources.values.allSatisfy { if case .ok = $0 { return false }; return true }
        searchState = failed ? .failed(query: text) : .finished(query: text, count: featureResults.count)
    }

    /// Merges what has arrived and shows it. Apple Maps results are cut to the area; Discovery's already are.
    private func publishFeature(_ text: String, area: DiscoveryArea, maps: [PlaceResult], discovered: [DiscoveredPlace]) {
        let merged = SearchHereMerge.merge(maps: maps, ask: [], discovered: discovered, locality: area.name ?? "",
                                           inside: area.contains)
        appleResults = []
        featureResults = merged
        featureRevision += 1
        featureStatus.total = merged.count
        searchState = .searching(query: text)
        app.forecasts.requestAll(merged.map(\.place.coordinate))
        resultSetChanged()
        showResults(merged.map(\.place.coordinate))
    }

    /// The Feature section's rows, ordered by the chosen sort.
    func featureRows(_ stamp: DerivedStamp, now: Date, claimed: Set<String>) -> [ExploreRow] {
        let rows = featureResults.filter { !claimed.contains($0.id) }.compactMap { resultRow($0, stamp: stamp, now: now) }
        return Self.sorted(rows, by: sort)
    }
}
