import Foundation
import Observation
import IterModel
import IterSources
import IterStore
import IterConditions
import IterDiscovery

/// Whether data comes from the network or the built-in sample services.
public enum DataMode: Sendable, Equatable {
    case live
    /// Sample data: synthetic forecasts, fixture discovery and straight-line routing. Always labelled in the UI.
    case sample
}

/// What the store open produced, for the shell's notices.
public struct StoreStatus: Sendable {
    public var placement: StorePlacement
    /// The store actually open (nil in memory).
    public var activeURL: URL?
    /// Non-nil after the app fell back to a recovered store; show the one-time notice while `needsNotice`.
    public var recovered: RecoveryInfo?
    public var backupFolder: URL?

    public init(placement: StorePlacement, activeURL: URL? = nil, recovered: RecoveryInfo? = nil, backupFolder: URL? = nil) {
        self.placement = placement
        self.activeURL = activeURL
        self.recovered = recovered
        self.backupFolder = backupFolder
    }
}

/// The composition root (BLUEPRINT §3): protocol-typed services, built once by `live(...)` or a test composition, and
/// handed piecemeal to the stage models. Models never receive the container itself (no service locator) and never touch a
/// `ModelContext`; they use `LibraryStore`'s repositories. Concrete adapters are wired only in `AppContainer+Live.swift`.
@MainActor
public final class AppContainer {
    public let options: LaunchOptions
    public let dataMode: DataMode
    /// The clock every model reads (tests pass a fixed one).
    public let now: @Sendable () -> Date

    // Library
    public let library: LibraryStore
    public let store: StoreStatus

    // Conditions
    public let conditionsService: ConditionsService
    public let conditions: ConditionsStore

    // Find
    public let discovery: DiscoveryEngine
    public let placeSearch: any PlaceSearchProvider
    public let geocoder: any Geocoder

    // Build
    public let routing: any RoutingProvider

    // Place details
    public let streetLevel: (any StreetLevelImageryProvider)?
    public let magnetic: any MagneticModelProvider
    public let gridReference: any GridReferenceProvider

    // Device and settings
    public let location: any LocationProviding
    public let keyVault: KeyVault
    public let preferences: Preferences
    /// Every source the app knows, for Settings ▸ Sources & Credits and the per-source status lists.
    public let sources: [SourceDescriptor]

    public init(options: LaunchOptions, dataMode: DataMode, now: @escaping @Sendable () -> Date, library: LibraryStore,
                store: StoreStatus, conditionsService: ConditionsService, conditions: ConditionsStore, discovery: DiscoveryEngine,
                placeSearch: any PlaceSearchProvider, geocoder: any Geocoder, routing: any RoutingProvider,
                streetLevel: (any StreetLevelImageryProvider)?, magnetic: any MagneticModelProvider,
                gridReference: any GridReferenceProvider, location: any LocationProviding, keyVault: KeyVault,
                preferences: Preferences, sources: [SourceDescriptor]) {
        self.options = options
        self.dataMode = dataMode
        self.now = now
        self.library = library
        self.store = store
        self.conditionsService = conditionsService
        self.conditions = conditions
        self.discovery = discovery
        self.placeSearch = placeSearch
        self.geocoder = geocoder
        self.routing = routing
        self.streetLevel = streetLevel
        self.magnetic = magnetic
        self.gridReference = gridReference
        self.location = location
        self.keyVault = keyVault
        self.preferences = preferences
        self.sources = sources
    }
}
