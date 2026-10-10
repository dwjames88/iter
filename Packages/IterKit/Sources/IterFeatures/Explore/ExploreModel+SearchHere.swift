import Foundation
import IterCore
import IterData
import IterServices

/// Search Here in Explore: searches the visible map region with Apple Maps and, when it is available, Ask, then lists
/// what they found in the In View section. Maps results appear first; Ask results join them when they are confirmed.
/// The camera never moves for these results.
extension ExploreModel {
    /// Natural-language queries run alongside the points-of-interest request.
    nonisolated static let searchHereQueries = ["viewpoint", "lake", "waterfall"]

    /// The button is offered: the map has a region, the search field is empty, nothing is running, and the list is
    /// empty or no longer describes what the map shows.
    public var showsSearchHere: Bool {
        guard let visible = visibleRegion, !searchHereStatus.isSearching else { return false }
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return rows.isEmpty || SearchHereRules.isStale(listRegion: listRegion, visible: visible)
    }

    /// Searches the visible region. A second press replaces a running search. Does nothing before the map has a region.
    public func searchHere() {
        guard let region = visibleRegion else { return }
        searchHereTask?.cancel()
        searchHereGeneration += 1
        let generation = searchHereGeneration
        listRegion = region
        setSearchHereResults([])
        var status = SearchHereStatus()
        status.phase = .searchingMaps
        status.region = region
        searchHereStatus = status
        dropSelectionIfHidden()
        searchHereTask = Task { [weak self] in
            await self?.runSearchHere(region: region, generation: generation)
        }
    }

    /// Stops a running Search Here and removes its results.
    public func cancelSearchHere() {
        guard searchHereTask != nil || searchHereStatus != .idle || !searchHereResults.isEmpty else { return }
        searchHereTask?.cancel()
        searchHereTask = nil
        searchHereGeneration += 1
        searchHereStatus = .idle
        if !searchHereResults.isEmpty { setSearchHereResults([]) }
        dropSelectionIfHidden()
    }

    func setSearchHereResults(_ results: [SearchHereResult]) {
        searchHereResults = results
        searchHereRevision += 1
        searchHereStatus.total = results.count
    }

    private func isCurrent(_ generation: Int) -> Bool {
        generation == searchHereGeneration && !Task.isCancelled
    }

    /// What an extra source (Ask or Discovery) came back with. Plain values so the child tasks can return them.
    private enum HereExtra: Sendable {
        case ask(validated: [ValidatedProposal]?, failure: SearchHereStatus.AskOutcome?)
        case discovery(DiscoveryReport?)
        case cancelled
    }

    private func runSearchHere(region: GeoRegion, generation: Int) async {
        // Apple Maps.
        let search = app.search
        let found = await Self.mapsPlaces(in: region, search: search)
        guard isCurrent(generation) else { return }
        let maps = found.places.filter { SearchHereFilter.isPhotoWorthy($0) && region.contains($0.coordinate) }
        let mapsResults = SearchHereMerge.merge(maps: maps, ask: [], region: region)
        let mapsKept = mapsResults.map(\.place)
        setSearchHereResults(mapsResults)
        searchHereStatus.maps = found.anySucceeded ? .found(mapsResults.count) : .failed
        requestInViewForecasts()

        // What else runs: Ask when the device can, Discovery when there is an engine and a source switched on.
        var scout: (any Scouting)?
        if let candidate = app.scout {
            let availability = candidate.availability()
            if availability == .available { scout = candidate } else { searchHereStatus.ask = .unavailable(availability) }
        } else {
            searchHereStatus.ask = .unavailable(.unavailable("No scout"))
        }
        let settings = app.discoverySettings()
        let discovery = app.searchSettings.hasDiscoverySources ? app.discovery : nil
        guard scout != nil || discovery != nil else { return finishSearchHere() }
        searchHereStatus.phase = .asking
        if scout != nil { searchHereStatus.ask = .running }
        if discovery != nil { searchHereStatus.discoveryOutcome = .running }

        let areaName = (try? await app.geocoder.reverseGeocode(region.center))?.locality
        guard isCurrent(generation) else { return }
        let name = (areaName?.isEmpty ?? true) ? nil : areaName
        let context = ScoutContext(settings: settings)
        let area = DiscoveryArea(name: name, region: region, boundary: nil)

        var askValidated: [ValidatedProposal] = []
        var discovered: [DiscoveredPlace] = []
        await withTaskGroup(of: HereExtra.self) { group in
            if let scout {
                group.addTask { await Self.askExtra(scout, region: region, areaName: name, context: context, search: search) }
            }
            if let discovery {
                group.addTask { await Self.discoveryExtra(discovery, area: area, settings: settings) }
            }
            for await extra in group {
                guard isCurrent(generation) else { group.cancelAll(); return }
                switch extra {
                case .cancelled:
                    group.cancelAll()
                    return
                case .ask(let validated, let failure):
                    if let validated { askValidated = validated }
                    if let failure { searchHereStatus.ask = failure }
                case .discovery(let report):
                    if let report {
                        discovered = report.places
                        searchHereStatus.discovery = report.statuses
                    } else {
                        searchHereStatus.discoveryOutcome = .failed
                    }
                }
                let merged = SearchHereMerge.merge(maps: mapsKept, ask: askValidated, discovered: discovered,
                                                   locality: name ?? "", region: region)
                setSearchHereResults(merged)
                if case .ask(let validated, _) = extra, validated != nil {
                    let contributed = merged.filter { $0.sources.contains(.ask) }.count
                    searchHereStatus.ask = contributed == 0 ? .none : .found(contributed)
                }
                if case .discovery(let report) = extra, report != nil {
                    let contributed = merged.filter { $0.sources.contains(.discovery) }.count
                    searchHereStatus.discoveryOutcome = contributed == 0 ? .none : .found(contributed)
                }
                requestInViewForecasts()
            }
        }
        guard isCurrent(generation) else { return }
        finishSearchHere()
    }

    private func finishSearchHere() {
        searchHereStatus.phase = .finished
        searchHereTask = nil
        requestInViewForecasts()
    }

    /// Ask: the scout names places in the region and each name is confirmed by a search. A failure is an outcome,
    /// not a throw; only cancellation stops the lot.
    private nonisolated static func askExtra(_ scout: any Scouting, region: GeoRegion, areaName: String?, context: ScoutContext,
                                             search: any PlaceSearching) async -> HereExtra {
        let proposals: [RegionProposal]
        do {
            proposals = try await scout.proposePlaces(in: region, areaName: areaName, context: context)
        } catch is CancellationError {
            return .cancelled
        } catch RegionProposalError.unsupported {
            return .ask(validated: nil, failure: .unavailable(.unavailable("Unsupported")))
        } catch ScoutError.unavailable(let reason) {
            return .ask(validated: nil, failure: .unavailable(reason))
        } catch {
            return .ask(validated: nil, failure: .failed)
        }
        if Task.isCancelled { return .cancelled }
        let validated = await SearchHereValidator.validate(proposals, in: region, search: search)
        if Task.isCancelled { return .cancelled }
        return .ask(validated: validated, failure: nil)
    }

    private nonisolated static func discoveryExtra(_ discovery: any Discovering, area: DiscoveryArea,
                                                   settings: DiscoverySettings) async -> HereExtra {
        do {
            return .discovery(try await discovery.discover(area: area, feature: nil, text: nil, settings: settings))
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .discovery(nil)
        }
    }

    private func requestInViewForecasts() {
        app.forecasts.requestAll(searchHereResults.map(\.place.coordinate))
    }

    /// Apple Maps places for a region: the scenic points of interest and a few natural-language searches, concurrently.
    /// `anySucceeded` is false only when every request threw.
    private nonisolated static func mapsPlaces(in region: GeoRegion, search: any PlaceSearching) async -> (places: [PlaceResult], anySucceeded: Bool) {
        await withTaskGroup(of: (Int, [PlaceResult]?).self) { group in
            group.addTask { (0, try? await search.pointsOfInterest(in: region, categories: POICategoryMapping.scenicCategories)) }
            for (i, q) in searchHereQueries.enumerated() {
                group.addTask { (i + 1, try? await search.search(q, near: region)) }
            }
            var batches: [(Int, [PlaceResult])] = []
            for await (index, batch) in group {
                if let batch { batches.append((index, batch)) }
            }
            // Completion order varies; points of interest first, then the queries in order, keeps the list stable.
            return (batches.sorted { $0.0 < $1.0 }.flatMap(\.1), !batches.isEmpty)
        }
    }

    /// The In View rows: the results in merge order, minus any that a curated or your own spot already lists.
    func inViewRows(_ stamp: DerivedStamp, now: Date, claimed: Set<String>) -> [ExploreRow] {
        guard !searchHereResults.isEmpty else { return [] }
        let own = CuratedSpots.all + app.store.savedPlaces().filter { $0.origin == .user }.map(\.spot)
        var rows: [ExploreRow] = []
        for result in searchHereResults where !claimed.contains(result.id) {
            let place = result.place
            let listed = own.contains { spot in
                spot.id == place.id || (spot.coordinate.distance(to: place.coordinate) <= SearchHereMerge.sameNameMeters
                                        && SearchHereNames.match(spot.name, place.name))
            }
            if listed { continue }
            if let row = resultRow(result, stamp: stamp, now: now) { rows.append(row) }
        }
        return rows
    }

    /// One row for a Search Here or feature-search result, scored through the normal path. Nil when the filters hide it.
    func resultRow(_ result: SearchHereResult, stamp: DerivedStamp, now: Date) -> ExploreRow? {
        let spot = spot(from: result)
        guard Self.matches(spot, source: .appleMaps, filters: filters, query: stamp.query) else { return nil }
        let event = nextEvent(for: spot, bucket: stamp.timeBucket, now: now)
        var row = ExploreRow(spot: spot, source: .appleMaps, window: event?.window, day: event?.day,
                             isLoading: app.forecasts.isLoading(spot.coordinate),
                             distanceMeters: stamp.origin.map { $0.distance(to: spot.coordinate) },
                             note: result.note, driveSeconds: nil, viaAsk: result.sources.contains(.ask))
        row.sources = result.discoverySources
        row.elevationMeters = result.elevationMeters
        row.links = result.links
        return row
    }

    /// A result as a spot: the place, Discovery's kind when Apple Maps has no category, and the elevation.
    func spot(from result: SearchHereResult) -> Spot {
        var spot = spot(from: result.place)
        if result.place.pointOfInterestCategory == nil, let category = result.category { spot.category = category }
        spot.elevationMeters = result.elevationMeters
        return spot
    }
}
