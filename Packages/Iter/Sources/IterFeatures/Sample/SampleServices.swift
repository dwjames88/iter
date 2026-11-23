import Foundation
import IterModel
import IterSources
import IterSourcesLive
import IterStore
import IterConditions
import IterDiscovery
import IterAstro

/// The sample composition's services: the sample conditions and discovery over the real report and discovery engines, and
/// straight-line routing. On-device sources (World Magnetic Model, MGRS) and the honest "no source" slots are the real
/// ones (they never touch the network). Look Around is absent.
@MainActor
enum SampleServices {
    static func make(now: @escaping @Sendable () -> Date, preferences: Preferences, keys: KeyVault) -> AppServices {
        let sample = SampleConditions(now: now)
        let sources: [any SourceDescribing] = [sample, NoSkyBrightnessProvider(), NoSeeingProvider()]
        let clock = ClosureSourceClock(read: now)
        let service = ConditionsService(ConditionsDependencies(
            registry: SourceRegistry(sources: sources, settings: .current(preferences, keys: keys)),
            cache: SourceCache(directory: nil, clock: clock), clock: clock, ephemeris: Astronomy(),
            configuration: ConditionsConfiguration(coalescingWindow: .milliseconds(1), fetchesHorizon: true)))
        let providers = SampleDiscovery.providers(now: now)
        let routing = SampleRouting()
        let geocoder = SampleDiscovery.SampleGeocoder()
        let search = SampleDiscovery.PlaceSearch(now: now)
        let magnetic = WorldMagneticModelProvider()
        let mgrs = MGRSProvider()
        let descriptors = [sample.descriptor, NoSkyBrightnessProvider().descriptor, NoSeeingProvider().descriptor, routing.descriptor,
                           magnetic.descriptor, mgrs.descriptor] + SampleDiscovery.descriptors
        return AppServices(
            conditionsService: service,
            // No language model: Find shows its Basic search label, deterministically.
            discoveryFactory: { DiscoveryEngine(providers: providers.filtered(.current(preferences, keys: keys)), model: nil, clock: clock) },
            placeSearch: search, geocoder: geocoder, routing: routing, streetLevel: nil, magnetic: magnetic, gridReference: mgrs,
            sources: descriptors)
    }
}

extension AppContainer {
    /// A fully offline container over sample services: in-memory store, ephemeral preferences, in-memory keychain,
    /// `-IterLocation` or an inert location. For previews, hosted snapshot tests and the render copy's sample mode.
    /// Seeds the sample library when `options.seedTrip` (or `seed`) is set. Throws only if the in-memory store cannot open.
    public static func sample(options: LaunchOptions = LaunchOptions(), now: @escaping @Sendable () -> Date = { Date() },
                              seed: Bool? = nil) throws -> AppContainer {
        var options = options
        options.sampleData = true
        options.inMemoryStore = true
        options.storePath = nil
        let preferences = Preferences.ephemeral()
        let keys = KeyVault(keychain: InMemoryKeychain())
        let built = try StoreBuilder.build(placement: .inMemory, isRealStore: false, bundleID: nil, backupsDirectory: nil, clock: now)
        let location: any LocationProviding = options.fixedLocation.map { FixedLocationProvider($0) } ?? InertLocationProvider()
        return assemble(options: options, dataMode: .sample, now: now, built: built,
                        services: SampleServices.make(now: now, preferences: preferences, keys: keys), location: location, keys: keys,
                        preferences: preferences, seed: seed ?? options.seedTrip)
    }

    /// A package-test container: `sample(...)` with a FIXED clock (2027-03-10 18:00 UTC unless given), a fixed location
    /// (Moab, Utah unless given) and no seed unless asked. Deterministic end to end.
    public static func test(now: @escaping @Sendable () -> Date = { AppContainer.testNow },
                            location: Coordinate = Coordinate(latitude: 38.5733, longitude: -109.5498),
                            seed: Bool = false) throws -> AppContainer {
        var options = LaunchOptions()
        options.fixedLocation = location
        return try sample(options: options, now: now, seed: seed)
    }

    /// 2027-03-10 18:00 UTC.
    public nonisolated static let testNow = Date(timeIntervalSince1970: 1_804_010_400)
}
