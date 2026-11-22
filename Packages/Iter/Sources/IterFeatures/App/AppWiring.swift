import Foundation
import IterModel
import IterSources
import IterStore
import IterConditions
import IterDiscovery
import IterAstro

/// Every service the container holds besides the library, location, keys and preferences. Built in one place per mode so
/// the live and sample compositions cannot drift apart.
@MainActor
struct AppServices {
    var conditionsService: ConditionsService
    var discoveryFactory: @MainActor () -> DiscoveryEngine
    var placeSearch: any PlaceSearchProvider
    var geocoder: any Geocoder
    var routing: any RoutingProvider
    var streetLevel: (any StreetLevelImageryProvider)?
    var magnetic: any MagneticModelProvider
    var gridReference: any GridReferenceProvider
    var sources: [SourceDescriptor]
}

/// A source clock that reads a closure (so a sample composition's "now" is the container's).
struct ClosureSourceClock: SourceClock {
    var read: @Sendable () -> Date
    var now: Date { read() }
    func sleep(for duration: Duration) async throws { try await Task.sleep(for: duration) }
}

extension SourceSettings {
    /// What the owner decided: switched-off sources, switched-on-by-default-off sources, and which keys exist.
    @MainActor
    static func current(_ preferences: Preferences, keys: KeyVault) -> SourceSettings {
        SourceSettings(disabled: preferences.disabledSources, enabledOverrides: preferences.enabledOverrides,
                       hasKey: { keys.key(for: $0) != nil })
    }
}

extension DiscoveryProviders {
    /// The providers that are enabled and have what they need (a required key), in the order given.
    func filtered(_ settings: SourceSettings) -> DiscoveryProviders {
        func ok(_ d: SourceDescriptor) -> Bool { settings.isEnabled(d) && settings.keySatisfied(d) }
        func keep<P>(_ list: [P], _ descriptor: (P) -> SourceDescriptor) -> [P] { list.filter { ok(descriptor($0)) } }
        return DiscoveryProviders(geocoders: keep(geocoders) { $0.descriptor }, boundaries: keep(boundaries) { $0.descriptor },
                                  gazetteers: keep(gazetteers) { $0.descriptor }, placeSearch: keep(placeSearch) { $0.descriptor },
                                  textEvidence: keep(textEvidence) { $0.descriptor }, photoEvidence: keep(photoEvidence) { $0.descriptor })
    }
}
