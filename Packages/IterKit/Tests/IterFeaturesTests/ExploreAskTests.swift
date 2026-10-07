import Foundation
import Testing
import IterCore
import IterData
import IterServices
@testable import IterFeatures

private let askNow = LocalDay(year: 2026, month: 10, day: 6).at(hour: 10, in: TimeZone(identifier: "America/Denver")!)

private struct AskSearch: PlaceSearching {
    var results: [PlaceResult] = []
    func search(_ query: String, near region: GeoRegion?) async throws -> [PlaceResult] { results }
    func pointsOfInterest(near center: Coordinate, radiusMeters: Double, categories: [String]) async throws -> [PlaceResult] { [] }
}

private func applePlace(_ id: String, _ name: String) -> PlaceResult {
    PlaceResult(id: id, name: name, locality: "Moab, UT", coordinate: Coordinate(latitude: 38.7, longitude: -109.6),
                timeZoneIdentifier: "America/Denver", pointOfInterestCategory: nil)
}

/// An Apple Maps suggestion, as the scout's grounding would build it.
private func appleSuggestion(_ place: PlaceResult, why: String = "Open water and a trailhead.") -> ScoutSuggestion {
    let spot = Spot(id: place.id, name: place.name, locality: place.locality, coordinate: place.coordinate,
                    timeZoneIdentifier: place.timeZoneIdentifier ?? "America/Denver", category: .landscape,
                    bestLight: [], popularity: 0, origin: .appleMaps)
    return ScoutSuggestion(id: place.id, spot: spot, provenance: .appleMaps, why: why, suggestedWindow: nil, driveSeconds: 1800)
}

@MainActor
private func makeAsk(scout: FakeScout?, search: AskSearch = AskSearch()) throws -> ExploreModel {
    let store = IterStore(container: try IterSchema.makeContainer(inMemory: true))
    let clock: @Sendable () -> Date = { askNow }
    let sample = CachedWeatherService(wrapping: SampleWeatherService(now: clock))
    let defaults = UserDefaults(suiteName: "ExploreAskTests-\(UUID().uuidString)")!
    let app = AppModel(store: store, weather: sample, search: search, geocoder: ScoutNoGeocoder(), drives: ScoutFlatDrives(),
                       scout: scout, location: UserLocationModel(defaults: defaults), sampleWeather: sample, defaults: defaults,
                       now: { askNow })
    return ExploreModel(app: app, searchDebounce: .zero, defaults: defaults)
}

@MainActor
private func settle() async {
    for _ in 0..<20 { await Task.yield() }
    try? await Task.sleep(for: .milliseconds(40))
}

private let moabRegion = GeoRegion(center: Coordinate(latitude: 38.6, longitude: -109.6), latitudeDelta: 2, longitudeDelta: 3)

@MainActor
@Suite(.serialized) struct ExploreAskTests {
    // MARK: Routing

    @Test func askModeAsksWhateverTheText() async throws {
        let fake = FakeScout(outcome: .success([scoutSuggestion("mesa-arch")]))
        let explore = try makeAsk(scout: fake)
        explore.askMode = true
        explore.query = "Portland"
        explore.submitSearch()
        await settle()
        #expect(fake.requests == ["Portland"])
        #expect(explore.searchState == .idle)
        #expect(explore.askState == .results([scoutSuggestion("mesa-arch")]))
    }

    @Test func requestsReadingLikeAsksRouteToTheScout() async throws {
        let fake = FakeScout(outcome: .success([scoutSuggestion("mesa-arch")]))
        let explore = try makeAsk(scout: fake)
        explore.query = "  foggy forest within two hours of Portland for sunrise "
        explore.submitSearch()
        await settle()
        #expect(fake.requests == ["foggy forest within two hours of Portland for sunrise"])
        #expect(explore.searchState == .idle)
    }

    @Test func placeNamesStillSearchAppleMaps() async throws {
        let fake = FakeScout(outcome: .success([scoutSuggestion("mesa-arch")]))
        let explore = try makeAsk(scout: fake, search: AskSearch(results: [applePlace("a1", "Moab Brewery")]))
        explore.query = "Moab"
        explore.submitSearch()
        await settle()
        #expect(fake.started == 0)
        #expect(explore.askState == .idle)
        #expect(explore.searchState == .finished(query: "Moab", count: 1))
        #expect(explore.appleResults.map(\.id) == ["a1"])
    }

    @Test func theAreaPassedToTheScoutIsTheVisibleRegion() async throws {
        let fake = FakeScout(outcome: .success([scoutSuggestion("mesa-arch")]))
        let explore = try makeAsk(scout: fake)
        explore.cameraDidChange(to: moabRegion)
        explore.query = "where can I shoot sunset?"
        explore.submitSearch()
        await settle()
        #expect(fake.lastArea == moabRegion)
    }

    @Test func withoutAMapTheAreaIsNil() async throws {
        let fake = FakeScout(outcome: .success([scoutSuggestion("mesa-arch")]))
        let explore = try makeAsk(scout: fake)
        explore.query = "where can I shoot sunset?"
        explore.ask()
        await settle()
        #expect(fake.requests.count == 1)
        #expect(fake.lastArea == nil)
    }

    // MARK: The Ask section

    @Test func theAskSectionIsFirstAndBuiltOnlyFromSuggestions() async throws {
        let apple = appleSuggestion(applePlace("a-falls", "Negro Bill Falls"))
        let found = [scoutSuggestion("mesa-arch"), apple]
        let fake = FakeScout(outcome: .success(found))
        let explore = try makeAsk(scout: fake)
        explore.query = "find waterfalls near me"
        explore.submitSearch()
        await settle()

        let first = try #require(explore.sections.first)
        #expect(first.kind == .ask)
        #expect(first.rows.map(\.id) == ["mesa-arch", "a-falls"])
        for (row, suggestion) in zip(first.rows, found) {
            #expect(row.id == suggestion.spot.id)
            #expect(row.spot.name == suggestion.spot.name)
            #expect(row.spot.coordinate == suggestion.spot.coordinate)
            #expect(row.note == suggestion.why)
            #expect(row.driveSeconds == suggestion.driveSeconds)
        }
        #expect(explore.sections.dropFirst().allSatisfy { $0.kind != .ask })
        #expect(explore.sections.dropFirst().flatMap(\.rows).allSatisfy { $0.note == nil })
    }

    @Test func askRowsAreScoredLikeOtherRows() async throws {
        let fake = FakeScout(outcome: .success([scoutSuggestion("mesa-arch")]))
        let explore = try makeAsk(scout: fake)
        explore.query = "find a sunrise arch"
        explore.ask()
        await settle()
        let spot = try #require(CuratedSpots.spot(id: "mesa-arch"))
        _ = await explore.app.forecasts.load(spot.coordinate)
        // Scores are computed off the main actor and land a moment after the rows.
        await explore.waitForScoring()

        let row = try #require(explore.row(id: "mesa-arch"))
        let expected = try #require(explore.app.engine.nextEvent(for: spot, forecast: explore.app.forecasts.state(for: spot.coordinate).forecast,
                                                                  unavailable: nil, now: askNow))
        #expect(row.window == expected.window)
        #expect(row.day == expected.day)
        #expect(row.score != nil)
    }

    @Test func spotsInTheAskSectionLeaveTheOtherSections() async throws {
        let place = applePlace("a-dup", "Dup Place")
        let fake = FakeScout(outcome: .success([scoutSuggestion("mesa-arch"), appleSuggestion(place)]))
        let explore = try makeAsk(scout: fake, search: AskSearch(results: [place, applePlace("a-other", "Other Place")]))
        explore.query = "find a sunrise arch"
        explore.searchAppleMaps()
        await settle()
        #expect(explore.appleResults.map(\.id) == ["a-dup", "a-other"])
        explore.ask()
        await settle()

        let ids = explore.rows.map(\.id)
        #expect(ids.count == Set(ids).count, "every row id appears once")
        #expect(explore.sections.first?.rows.map(\.id) == ["mesa-arch", "a-dup"])
        #expect(explore.sections.dropFirst().flatMap(\.rows).map(\.id).contains("mesa-arch") == false)
        #expect(explore.sections.first { $0.kind == .appleMaps }?.rows.map(\.id) == ["a-other"])
    }

    @Test func filtersAndTheQueryDoNotHideAskRows() async throws {
        let fake = FakeScout(outcome: .success([scoutSuggestion("mesa-arch"), appleSuggestion(applePlace("a-falls", "Negro Bill Falls"))]))
        let explore = try makeAsk(scout: fake)
        explore.query = "zzz quiet waterfalls near me"      // matches no spot's name, locality or tags
        explore.ask()
        await settle()
        explore.filters.categories = [.waterfall]            // mesa-arch is a desert spot
        explore.filters.sources = [.curated]                 // and the Apple Maps suggestion is not curated
        #expect(explore.rows.map(\.id) == ["mesa-arch", "a-falls"])
        #expect(explore.sections.map(\.kind) == [.ask])
    }

    @Test func fitCoordinatesIncludeAskRows() async throws {
        let apple = appleSuggestion(applePlace("a-falls", "Negro Bill Falls"))
        let fake = FakeScout(outcome: .success([apple]))
        let explore = try makeAsk(scout: fake)
        explore.query = "find waterfalls near me"
        explore.filters.sources = [.yours]                   // nothing else listed
        explore.ask()
        await settle()
        #expect(explore.fitCoordinates == [apple.spot.coordinate])
        // Results arriving call the content-changed refit.
        #expect(explore.cameraRequest != nil)
    }

    @Test func askResultsAreFramedEvenAfterTheUserMovedTheMap() async throws {
        let apple = appleSuggestion(applePlace("a-falls", "Negro Bill Falls"))
        let explore = try makeAsk(scout: FakeScout(outcome: .success([apple])))
        // The person dragged the map far away (Portland); an automatic refit would now leave it alone.
        explore.cameraDidChange(to: GeoRegion(center: Coordinate(latitude: 45.5, longitude: -122.7), latitudeDelta: 2, longitudeDelta: 2), byUser: true)
        explore.query = "find waterfalls near me"
        explore.ask()
        await settle()
        guard case .fit(let region)? = explore.cameraRequest?.kind else {
            Issue.record("expected a fit request for the ask results"); return
        }
        #expect(region.contains(apple.spot.coordinate))
    }

    // MARK: Lifecycle

    @Test func cancelReturnsToIdle() async throws {
        let fake = FakeScout(outcome: .success([scoutSuggestion("mesa-arch")]))
        fake.holdUntilReleased()
        let explore = try makeAsk(scout: fake)
        explore.query = "find waterfalls near me"
        explore.ask()
        await settle()
        #expect(explore.isAsking)
        #expect(explore.hasAskContent)
        explore.cancelAsk()
        #expect(explore.askState == .idle)
        #expect(!explore.hasAskContent)
        #expect(explore.query == "find waterfalls near me")
        await settle()
        #expect(fake.cancelledCount == 1)
        #expect(explore.sections.first?.kind != .ask)
    }

    @Test func clearingTheQueryResetsTheAsk() async throws {
        let fake = FakeScout(outcome: .success([scoutSuggestion("mesa-arch")]))
        let explore = try makeAsk(scout: fake)
        explore.query = "find waterfalls near me"
        explore.ask()
        await settle()
        #expect(explore.askState == .results([scoutSuggestion("mesa-arch")]))
        explore.query = ""
        #expect(explore.askState == .idle)
        #expect(explore.askSubmittedRequest == "")
        #expect(explore.sections.first?.kind != .ask)
    }

    @Test func clearingTheQueryCancelsARunningAsk() async throws {
        let fake = FakeScout(outcome: .success([scoutSuggestion("mesa-arch")]))
        fake.holdUntilReleased()
        let explore = try makeAsk(scout: fake)
        explore.query = "find waterfalls near me"
        explore.ask()
        await settle()
        explore.query = ""
        #expect(explore.askState == .idle)
        await settle()
        #expect(fake.cancelledCount == 1)
    }

    @Test func unavailableFailsWithoutCallingTheScout() async throws {
        let fake = FakeScout(availability: .appleIntelligenceNotEnabled)
        let explore = try makeAsk(scout: fake)
        explore.query = "find waterfalls near me"
        explore.submitSearch()
        await settle()
        #expect(explore.askState == .failed(.unavailable(.appleIntelligenceNotEnabled)))
        #expect(explore.askSubmittedRequest == "find waterfalls near me")
        #expect(fake.started == 0)
        #expect(explore.sections.first?.kind != .ask)
        #expect(explore.hasAskContent)
    }

    @Test func noScoutInTheBuildIsUnavailableToo() async throws {
        let explore = try makeAsk(scout: nil)
        explore.query = "find waterfalls near me"
        explore.ask()
        if case .failed(.unavailable) = explore.askState {} else { Issue.record("expected unavailable, got \(explore.askState)") }
    }

    @Test func searchAppleMapsInsteadDropsTheAskAndSearches() async throws {
        let fake = FakeScout(availability: .deviceNotEligible)
        let explore = try makeAsk(scout: fake, search: AskSearch(results: [applePlace("a1", "Moab Brewery")]))
        explore.askMode = true
        explore.query = "find waterfalls near me"
        explore.ask()
        #expect(explore.hasAskContent)
        explore.searchAppleMapsInstead()
        await settle()
        #expect(!explore.hasAskContent)
        #expect(!explore.askMode)
        #expect(explore.searchState == .finished(query: "find waterfalls near me", count: 1))
    }

    @Test func theAskRowIsOfferedUntilAnAskIsRunningOrShownForThatText() async throws {
        let fake = FakeScout(outcome: .success([scoutSuggestion("mesa-arch")]))
        let explore = try makeAsk(scout: fake)
        #expect(!explore.offersAsk)                         // empty field
        explore.query = "Moab"
        #expect(explore.offersAsk)                          // text, nothing asked
        fake.holdUntilReleased()
        explore.ask()
        await settle()
        #expect(!explore.offersAsk)                         // running
        fake.release()
        await settle()
        #expect(!explore.offersAsk)                         // shown for that text
        explore.query = "Moab Utah"
        #expect(explore.offersAsk)                          // the text moved on
    }
}
