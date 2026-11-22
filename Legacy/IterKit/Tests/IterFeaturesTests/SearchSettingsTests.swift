import Foundation
import Testing
import IterCore
import IterData
import IterServices
@testable import IterFeatures

private func freshDefaults() -> UserDefaults { UserDefaults(suiteName: "SearchSettingsTests-\(UUID().uuidString)")! }

@MainActor
@Suite struct SearchSettingsTests {
    @Test func defaults() {
        let settings = SearchSettingsModel(defaults: freshDefaults(), keys: InMemoryDiscoveryKeyStore())
        #expect(settings.promptPrefix == "")
        #expect(settings.activePromptPrefix == nil)
        #expect(settings.enabledSources == DiscoverySourceID.keyless)
        #expect(settings.preference == .mixed)
        #expect(settings.maxResults == 20)
        #expect(settings.learnsFromLibrary)
        #expect(!settings.hasGoogleKey)
        #expect(settings.hasDiscoverySources)
    }

    @Test func everythingPersistsInTheDefaultsSuite() {
        let defaults = freshDefaults()
        let a = SearchSettingsModel(defaults: defaults, keys: InMemoryDiscoveryKeyStore())
        a.promptPrefix = "Moody light on peaks.\nLong exposures of water."
        a.setEnabled(.reddit, false)
        a.setEnabled(.google, true)
        a.preference = .unique
        a.maxResults = 35
        a.learnsFromLibrary = false

        let b = SearchSettingsModel(defaults: defaults, keys: InMemoryDiscoveryKeyStore())
        #expect(b.promptPrefix == "Moody light on peaks.\nLong exposures of water.")
        #expect(b.enabledSources == [.openStreetMap, .wikipedia, .wikivoyage, .google])
        #expect(b.preference == .unique)
        #expect(b.maxResults == 35)
        #expect(!b.learnsFromLibrary)
    }

    @Test func keysAreStableAndPrefixed() {
        let keys = [SearchSettingsModel.promptPrefixKey, SearchSettingsModel.enabledSourcesKey, SearchSettingsModel.preferenceKey,
                    SearchSettingsModel.maxResultsKey, SearchSettingsModel.learnsFromLibraryKey]
        #expect(keys.allSatisfy { $0.hasPrefix("IterSearch") })
        #expect(Set(keys).count == keys.count)
    }

    @Test func maxResultsIsClamped() {
        let defaults = freshDefaults()
        let settings = SearchSettingsModel(defaults: defaults, keys: InMemoryDiscoveryKeyStore())
        settings.maxResults = 500
        #expect(settings.maxResults == 60)
        settings.maxResults = 1
        #expect(settings.maxResults == 5)
        defaults.set(9_999, forKey: SearchSettingsModel.maxResultsKey)
        #expect(SearchSettingsModel(defaults: defaults, keys: InMemoryDiscoveryKeyStore()).maxResults == 60)
    }

    @Test func appleMapsIsAlwaysOnAndNotToggleable() {
        let settings = SearchSettingsModel(defaults: freshDefaults(), keys: InMemoryDiscoveryKeyStore())
        settings.setEnabled(.appleMaps, false)
        #expect(settings.isEnabled(.appleMaps))
        #expect(!settings.enabledSources.contains(.appleMaps))
        #expect(!SearchSettingsModel.toggleableSources.contains(.appleMaps))
        #expect(settings.discoverySettings().enabledSources.contains(.appleMaps))
        for source in SearchSettingsModel.toggleableSources { settings.setEnabled(source, false) }
        #expect(!settings.hasDiscoverySources)
        #expect(settings.discoverySettings().enabledSources == [.appleMaps])
    }

    @Test func aStoredAppleMapsOrUnknownSourceIsIgnored() {
        let defaults = freshDefaults()
        defaults.set(["appleMaps", "wikipedia", "somethingNew"], forKey: SearchSettingsModel.enabledSourcesKey)
        #expect(SearchSettingsModel(defaults: defaults, keys: InMemoryDiscoveryKeyStore()).enabledSources == [.wikipedia])
    }

    @Test func googleCredentialsLiveOnlyInTheKeyStore() throws {
        let defaults = freshDefaults()
        let keys = InMemoryDiscoveryKeyStore()
        let settings = SearchSettingsModel(defaults: defaults, keys: keys)
        #expect(!settings.isEnabled(.google))
        try settings.setGoogle(key: "  SECRET-KEY-123 ", engineID: " engine-9 ")
        #expect(settings.hasGoogleKey)
        #expect(settings.googleEngineID == "engine-9")
        #expect(keys.googleAPIKey == "SECRET-KEY-123")
        #expect(keys.googleEngineID == "engine-9")
        #expect(settings.isEnabled(.google))   // saving credentials switches Google on
        // Nothing of it is in UserDefaults.
        let dump = String(describing: defaults.dictionaryRepresentation())
        #expect(!dump.contains("SECRET-KEY-123"))
        #expect(!dump.contains("engine-9"))

        // A new model over the same store sees the credentials.
        #expect(SearchSettingsModel(defaults: defaults, keys: keys).hasGoogleKey)

        try settings.removeGoogle()
        #expect(!settings.hasGoogleKey)
        #expect(settings.googleEngineID == nil)
        #expect(keys.googleAPIKey == nil)
        #expect(!settings.isEnabled(.google))
    }

    @Test func discoverySettingsCarryEverything() {
        let settings = SearchSettingsModel(defaults: freshDefaults(), keys: InMemoryDiscoveryKeyStore())
        settings.promptPrefix = "Dark skies"
        settings.preference = .popular
        settings.maxResults = 12
        settings.setEnabled(.wikivoyage, false)
        let built = settings.discoverySettings(tasteSummary: "Recently saved: Mesa Arch")
        #expect(built.promptPrefix == "Dark skies")
        #expect(built.preference == .popular)
        #expect(built.maxResults == 12)
        #expect(built.enabledSources == [.appleMaps, .openStreetMap, .wikipedia, .reddit])
        #expect(built.tasteSummary == "Recently saved: Mesa Arch")
    }

    @Test func turningLearningOffDropsTheTasteSummary() {
        let settings = SearchSettingsModel(defaults: freshDefaults(), keys: InMemoryDiscoveryKeyStore())
        settings.learnsFromLibrary = false
        #expect(settings.discoverySettings(tasteSummary: "Recently saved: Mesa Arch").tasteSummary == nil)
    }

    @Test func activePromptPrefixIsTrimmedAndNilWhenBlank() {
        let settings = SearchSettingsModel(defaults: freshDefaults(), keys: InMemoryDiscoveryKeyStore())
        settings.promptPrefix = "  \n  "
        #expect(settings.activePromptPrefix == nil)
        settings.promptPrefix = "  Moody peaks \n"
        #expect(settings.activePromptPrefix == "Moody peaks")
    }
}

// MARK: - Taste summary

@MainActor
@Suite struct TasteSummaryTests {
    private func store() throws -> IterStore { IterStore(container: try IterSchema.makeContainer(inMemory: true)) }
    private func spot(_ id: String) -> Spot { CuratedSpots.spot(id: id)! }

    @Test func emptyLibraryHasNothingToSay() throws {
        #expect(TasteSummary.make(store: try store()) == nil)
    }

    @Test func savedSpotsAreNamedWithTheirCategories() throws {
        let store = try store()
        store.setSaved(spot("mesa-arch"), true)
        store.setSaved(spot("tunnel-view"), true)
        let text = try #require(TasteSummary.make(store: store))
        #expect(text.hasPrefix("Recently saved: "))
        #expect(text.contains("Mesa Arch"))
        #expect(text.contains("Tunnel View"))
        #expect(text.contains("("))
        #expect(text.count <= TasteSummary.maximumLength)
    }

    @Test func pinnedPlacesComeFirst() throws {
        let store = try store()
        store.setSaved(spot("mesa-arch"), true)
        store.setSaved(spot("bodie"), true)       // saved later, so most recent
        let mesa = try #require(store.savedPlaces().first { $0.curatedID == "mesa-arch" })
        store.setPinned(mesa, true)
        let text = try #require(TasteSummary.make(store: store))
        let mesaAt = try #require(text.range(of: "Mesa Arch"))
        let bodieAt = try #require(text.range(of: "Bodie"))
        #expect(mesaAt.lowerBound < bodieAt.lowerBound)
    }

    @Test func tripsAreListed() throws {
        let store = try store()
        let trip = store.createTrip(name: "Canyon Country", startDay: LocalDay(year: 2026, month: 11, day: 1), dayCount: 2)
        _ = store.addStop(spot("mesa-arch"), to: trip, day: 0)
        store.setPinned(trip, true)
        let text = try #require(TasteSummary.make(store: store))
        #expect(text.contains("trips: Canyon Country"))
    }

    @Test func aTripAloneStillSummarises() throws {
        let store = try store()
        _ = store.createTrip(name: "Coast Run", startDay: LocalDay(year: 2026, month: 11, day: 1), dayCount: 1)
        #expect(TasteSummary.make(store: store) == "trips: Coast Run")
    }

    @Test func composeFitsTheLimitByDroppingNamesFromTheEnd() {
        let names = (1...5).map { "A Very Long Place Name Number \($0) In The Backcountry" }
        let text = TasteSummary.compose(places: names, categories: ["landscape", "desert"], trips: ["Big Trip One", "Big Trip Two"])
        #expect(text != nil)
        #expect((text ?? "").count <= TasteSummary.maximumLength)
        #expect((text ?? "").contains("Number 1"))
        #expect(!(text ?? "").contains("Number 5"))
    }

    @Test func composeCleansNamesAndKeepsTheLimitForHugeOnes() {
        let huge = String(repeating: "x", count: 500)
        let text = TasteSummary.compose(places: ["Line\nBreak; Name", huge], categories: [], trips: [])
        #expect(text?.contains("\n") == false)
        #expect(text?.contains("Line Break Name") == true)
        #expect((text ?? "").count <= TasteSummary.maximumLength)
    }

    @Test func theAppModelGatesTheSummaryOnTheOptIn() throws {
        let store = try store()
        store.setSaved(spot("mesa-arch"), true)
        let clock: @Sendable () -> Date = { scoutTestNow }
        let sample = CachedWeatherService(wrapping: SampleWeatherService(now: clock))
        let defaults = freshDefaults()
        let app = AppModel(store: store, weather: sample, search: ScoutNoSearch(), geocoder: ScoutNoGeocoder(), drives: ScoutFlatDrives(),
                           scout: nil, sampleWeather: sample, defaults: defaults, now: { scoutTestNow })
        #expect(app.discoverySettings().tasteSummary?.contains("Mesa Arch") == true)
        app.searchSettings.learnsFromLibrary = false
        #expect(app.discoverySettings().tasteSummary == nil)
        app.searchSettings.promptPrefix = "Quiet water"
        #expect(app.discoverySettings().promptPrefix == "Quiet water")
        #expect(app.discovery == nil)
    }
}

// MARK: - The scout gets the settings

/// Records the context it is called with. Overrides the context forms, as `AppleIntelligenceScout` does.
private final class ContextScout: Scouting, @unchecked Sendable { // test double; state guarded by the lock
    private let lock = NSLock()
    private var _contexts: [ScoutContext] = []
    var contexts: [ScoutContext] { lock.withLock { _contexts } }
    func availability() -> ScoutAvailability { .available }
    func scout(_ request: String, progress: @escaping @Sendable (ScoutProgress) -> Void) async throws -> [ScoutSuggestion] { [] }
    func scout(_ request: String, near area: GeoRegion?, context: ScoutContext, progress: @escaping @Sendable (ScoutProgress) -> Void) async throws -> [ScoutSuggestion] {
        lock.withLock { _contexts.append(context) }
        return [scoutSuggestion("mesa-arch")]
    }
}

@MainActor
@Suite struct ScoutContextTests {
    @Test func theAskReceivesThePrefixAndTheTaste() async throws {
        let scout = ContextScout()
        let app = scoutAppModel(weather: ScoutFailingWeather(error: .notEnabled), scout: scout)
        app.store.setSaved(CuratedSpots.spot(id: "mesa-arch")!, true)
        app.searchSettings.promptPrefix = "Quiet water at dawn"
        let model = ScoutModel(app: app)
        model.request = "waterfalls"
        model.run()
        for _ in 0..<200 where scout.contexts.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        let context = try #require(scout.contexts.first)
        #expect(context.settings.promptPrefix == "Quiet water at dawn")
        #expect(context.settings.tasteSummary?.contains("Mesa Arch") == true)
    }

    @Test func aScoutWithoutContextFormsStillWorks() async throws {
        let fake = FakeScout(outcome: .success([scoutSuggestion("mesa-arch")]))
        let app = scoutAppModel(weather: ScoutFailingWeather(error: .notEnabled), scout: fake)
        let model = ScoutModel(app: app)
        model.request = "arches"
        model.run()
        for _ in 0..<200 where fake.started == 0 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(fake.started == 1)
        // The default forms forward to the plain ones.
        let proposals = try? await fake.proposePlaces(in: GeoRegion(center: Coordinate(latitude: 1, longitude: 1), latitudeDelta: 1, longitudeDelta: 1),
                                                       areaName: nil, context: ScoutContext())
        #expect(proposals == nil)   // FakeScout has no proposals: the default throws `unsupported`
    }
}
