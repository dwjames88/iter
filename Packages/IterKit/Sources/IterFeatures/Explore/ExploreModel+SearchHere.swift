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

        // Ask.
        guard let scout = app.scout else { return finishWithoutAsk(.unavailable(.unavailable("No scout"))) }
        let availability = scout.availability()
        guard availability == .available else { return finishWithoutAsk(.unavailable(availability)) }
        searchHereStatus.phase = .asking
        searchHereStatus.ask = .running

        let areaName = (try? await app.geocoder.reverseGeocode(region.center))?.locality
        guard isCurrent(generation) else { return }
        let proposals: [RegionProposal]
        do {
            proposals = try await scout.proposePlaces(in: region, areaName: (areaName?.isEmpty ?? true) ? nil : areaName)
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(generation) else { return }
            switch error {
            case RegionProposalError.unsupported: finishWithoutAsk(.unavailable(.unavailable("Unsupported")))
            case ScoutError.unavailable(let reason): finishWithoutAsk(.unavailable(reason))
            default: finishWithoutAsk(.failed)
            }
            return
        }
        guard isCurrent(generation) else { return }
        let validated = await SearchHereValidator.validate(proposals, in: region, search: search)
        guard isCurrent(generation) else { return }
        let merged = SearchHereMerge.merge(maps: mapsKept, ask: validated, region: region)
        setSearchHereResults(merged)
        let contributed = merged.filter { $0.sources.contains(.ask) }.count
        searchHereStatus.ask = contributed == 0 ? .none : .found(contributed)
        searchHereStatus.phase = .finished
        searchHereTask = nil
        requestInViewForecasts()
    }

    private func finishWithoutAsk(_ outcome: SearchHereStatus.AskOutcome) {
        searchHereStatus.ask = outcome
        searchHereStatus.phase = .finished
        searchHereTask = nil
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
            let spot = spot(from: place)
            guard Self.matches(spot, source: .appleMaps, filters: filters, query: stamp.query) else { continue }
            let event = nextEvent(for: spot, bucket: stamp.timeBucket, now: now)
            rows.append(ExploreRow(spot: spot, source: .appleMaps, window: event?.window, day: event?.day,
                                   isLoading: app.forecasts.isLoading(spot.coordinate),
                                   distanceMeters: stamp.origin.map { $0.distance(to: spot.coordinate) },
                                   note: result.note, driveSeconds: nil, viaAsk: result.sources.contains(.ask)))
        }
        return rows
    }
}
