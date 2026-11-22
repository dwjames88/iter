import Foundation
import IterCore

/// What Explore needs from discovery: find a named area, then list the places in it. `DiscoveryEngine` is the real
/// one; tests put a scripted one (or a real engine over fake providers) behind this.
public protocol Discovering: Sendable {
    func resolveArea(named name: String, fallbackSearch: (any PlaceSearching)?) async -> DiscoveryArea?
    func discover(area: DiscoveryArea, feature: FeatureKind?, text: String?, settings: DiscoverySettings) async throws -> DiscoveryReport
}

extension DiscoveryEngine: Discovering {}
