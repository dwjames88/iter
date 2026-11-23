import Foundation
import IterModel
import IterSources
import IterSourcesLive
import IterStore
import IterConditions
import IterDiscovery
import IterAstro
import IterAI

extension AppContainer {
    /// The owner's real store for this platform (`StoreLocation.directStoreURL()` on the Mac).
    public static var defaultRealStoreURL: URL {
#if os(macOS)
        StoreLocation.directStoreURL()
#else
        StoreLocations.iOSStoreURL(applicationSupportDirectory:
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
#endif
    }

    private static var defaultBackupsDirectory: URL {
#if os(macOS)
        StoreLocations.backupsDirectory()
#else
        StoreLocations.backupsDirectory(applicationSupportDirectory:
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
#endif
    }

    /// The composition root of the app (and of the render copy). Decisions, all structural:
    ///
    /// - **Store.** `StorePlacement.resolve` against `realStoreURL`: only the real bundle id outside a test host can get the
    ///   real store; everything else gets memory or an explicit scratch path (refused inside the real folder, throwing
    ///   `AppContainerError.storePlacementRefused`). A file placement opens through `StoreOpener` only (backup before the
    ///   first V5 open, recovery on failure) with backups beside a scratch store in `Backups/`; the real store uses the real
    ///   backups folder and first runs the one-time copy out of the old sandbox container.
    /// - **Keys.** `KeyVault.system()` only for the real process; every other composition uses an in-memory keychain.
    /// - **Preferences.** The standard defaults only for the real process on its real store; otherwise ephemeral.
    /// - **Location.** `-IterLocation` fixes it; the real process uses `LiveLocationProvider` (asks at launch, nothing
    ///   gated); anything else is inert, so nothing ever prompts.
    /// - **Data.** `-IterSampleDataEnabled YES` swaps every network service for the sample services (`DataMode.sample`).
    ///   Otherwise live adapters. Their construction does no I/O; nothing is requested until a search or a report.
    /// - **Source toggles.** Find rebuilds its engine from `Preferences` on every read of `container.discovery`, so a toggle
    ///   takes effect on the next search. Conditions reads its source settings at launch: a toggle there applies on the
    ///   next launch (the Settings pane says so).
    /// - **Seed.** `-IterSeedTrip YES` adds the sample library, except on the real store.
    ///
    /// - Parameter appVersion: for the User-Agent (app name and version only); the bundle's version when nil.
    public static func live(options: LaunchOptions, bundleID: String?, environment: [String: String],
                            realStoreURL: URL = AppContainer.defaultRealStoreURL, appVersion: String? = nil,
                            now: @escaping @Sendable () -> Date = { Date() }) throws -> AppContainer {
        let placement: StorePlacement
        do {
            placement = try StorePlacement.resolve(bundleID: bundleID, options: options, environment: environment, realStoreURL: realStoreURL)
        } catch let refusal as StorePlacement.Refusal {
            throw AppContainerError.storePlacementRefused(refusal)
        }
        let isRealProcess = StorePlacement.isRealProcess(bundleID: bundleID, environment: environment)
        let isRealStore = isRealProcess && placement == .file(realStoreURL)

        let built = try StoreBuilder.build(placement: placement, isRealStore: isRealStore, bundleID: bundleID,
                                           backupsDirectory: isRealStore ? defaultBackupsDirectory : nil, clock: now)
        let keys = isRealProcess ? KeyVault.system() : KeyVault(keychain: InMemoryKeychain())
        let preferences = isRealStore ? Preferences(defaults: .standard) : Preferences.ephemeral()

        let location: any LocationProviding
        if let fixed = options.fixedLocation { location = FixedLocationProvider(fixed) }
        else if isRealProcess { location = LiveLocationProvider() }
        else { location = InertLocationProvider() }

        let services: AppServices
        let dataMode: DataMode
        if options.sampleData {
            dataMode = .sample
            services = SampleServices.make(now: now, preferences: preferences, keys: keys)
        } else {
            dataMode = .live
            let version = appVersion.map { UserAgent(version: $0) } ?? UserAgent.current
            services = LiveServices.make(userAgent: version, preferences: preferences, keys: keys, now: now,
                                         persistent: isRealStore, storeDirectory: placement.directory)
        }
        return assemble(options: options, dataMode: dataMode, now: now, built: built, services: services, location: location,
                        keys: keys, preferences: preferences, seed: options.seedTrip && !isRealStore)
    }

    /// The common last step of every composition.
    static func assemble(options: LaunchOptions, dataMode: DataMode, now: @escaping @Sendable () -> Date, built: StoreBuilder.Built,
                         services: AppServices, location: any LocationProviding, keys: KeyVault, preferences: Preferences,
                         seed: Bool) -> AppContainer {
        built.library.actionName = { StoreActionNames.english($0) }
        let container = AppContainer(
            options: options, dataMode: dataMode, now: now, library: built.library, store: built.status,
            conditionsService: services.conditionsService, conditions: ConditionsStore(service: services.conditionsService),
            discovery: services.discoveryFactory(), placeSearch: services.placeSearch, geocoder: services.geocoder,
            routing: services.routing, streetLevel: services.streetLevel, magnetic: services.magnetic,
            gridReference: services.gridReference, location: location, keyVault: keys, preferences: preferences,
            sources: services.sources)
        // "Learn From My Library": the profile is summed from the library at search time (cheap), only when the toggle is on.
        let library = built.library
        container.discoveryFactory = { [preferences] in
            let engine = services.discoveryFactory()
            guard preferences.learnFromLibrary else { return engine }
            return engine.with(libraryProfile: LibraryProfile.current(in: library))
        }
        container.recoveryNoticeWriter = built.recoveryWriter
        if seed { SampleLibrary.seed(into: built.library, now: now()) }
        return container
    }
}

extension StorePlacement {
    /// The folder the placement lives in (nil in memory): where per-store support folders (offline packs) go.
    var directory: URL? {
        if case .file(let url) = self { return url.deletingLastPathComponent() }
        return nil
    }
}

/// The live adapters, wired exactly as `Phase4LiveTests` wires them.
@MainActor
enum LiveServices {
    static func make(userAgent: UserAgent, preferences: Preferences, keys: KeyVault, now: @escaping @Sendable () -> Date,
                     persistent: Bool, storeDirectory: URL?) -> AppServices {
        let http = SourceHTTP(userAgent: userAgent)
        let cacheDirectory: URL? = persistent
            ? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appending(path: "Iter/Sources", directoryHint: .isDirectory)
            : nil
        let cache = SourceCache(directory: cacheDirectory)

        let nomads = NOMADSForecastProvider(http: http, cache: cache)
        let metar = AviationWeatherProvider(http: http)
        let conditionSources: [any SourceDescribing] = [
            nomads, HRRRSmokeProvider(sharing: nomads), MetNorwayProvider(http: http), metar, NWSProvider(http: http),
            SWPCAuroraProvider(http: http), HMSSmokeProvider(http: http), TerrariumTerrainProvider(http: http, blobCache: cache),
            NoSkyBrightnessProvider(), NoSeeingProvider(),
        ]
        let overpass = OverpassProvider(http: http)
        let discoveryProviders = DiscoveryProviders(
            geocoders: [MapKitGeocoder()], boundaries: [OverpassBoundaryProvider(http: http)],
            gazetteers: [MapKitPOIGazetteer(), overpass, GNISProvider(http: http)],
            placeSearch: [MapKitPlaceSearch()], textEvidence: [WikipediaProvider(http: http), WikivoyageProvider(http: http)],
            photoEvidence: [CommonsProvider(http: http)])

        let placeSearch = MapKitPlaceSearch()
        let geocoder = MapKitGeocoder()
        let routing = MapKitDirections()
        let lookAround = MapKitLookAround()
        let magnetic = WorldMagneticModelProvider()
        let mgrs = MGRSProvider()

        // Descriptors for Settings ▸ Sources & Credits: every wired source plus the catalogue entries nothing here uses yet
        // (satellite and radar overlays, point elevation), so the credits cover everything the app can show.
        var descriptors = conditionSources.map(\.descriptor)
        descriptors += [placeSearch.descriptor, geocoder.descriptor, routing.descriptor, lookAround.descriptor, magnetic.descriptor, mgrs.descriptor]
        let wired = Set(descriptors.map(\.id))
        descriptors += discoveryProviders.geocoders.map(\.descriptor) + discoveryProviders.boundaries.map(\.descriptor)
            + discoveryProviders.gazetteers.map(\.descriptor) + discoveryProviders.textEvidence.map(\.descriptor)
            + discoveryProviders.photoEvidence.map(\.descriptor)
        var seen = Set<SourceID>()
        descriptors = (descriptors + SourceCatalogue.all.filter { !wired.contains($0.id) }).filter { seen.insert($0.id).inserted }

        let service = ConditionsService(ConditionsDependencies(
            registry: SourceRegistry(sources: conditionSources, settings: .current(preferences, keys: keys)), cache: cache,
            clock: SystemSourceClock(), ephemeris: Astronomy(),
            packDirectory: storeDirectory?.appending(path: "OfflinePacks", directoryHint: .isDirectory)))

        return AppServices(
            conditionsService: service,
            discoveryFactory: {
                DiscoveryEngine(providers: discoveryProviders.filtered(.current(preferences, keys: keys)), model: LiveServices.languageModel())
            },
            placeSearch: placeSearch, geocoder: geocoder, routing: routing, streetLevel: lookAround, magnetic: magnetic,
            gridReference: mgrs, sources: descriptors)
    }

    /// Apple Intelligence through the resilient wrapper; the engine falls back to Basic search when it is unavailable.
    static func languageModel() -> (any LanguageModeling)? { ResilientLanguageModel(FoundationModelsLanguageModel()) }
}

extension AppContainer {
    /// The Settings model over this container's preferences, keys and source list (the model never sees the container).
    public func settingsModel() -> SettingsModel {
        SettingsModel(preferences: preferences, keyVault: keyVault, sources: sources, dataMode: dataMode)
    }

    /// The library model over this container's store and clock.
    public func libraryModel(timeZone: TimeZone = .current) -> LibraryModel {
        LibraryModel(library: library, now: now, timeZone: timeZone)
    }
}
