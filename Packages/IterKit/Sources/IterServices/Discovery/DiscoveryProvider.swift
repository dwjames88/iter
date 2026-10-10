import Foundation
import IterCore

/// A source of places with names (and usually coordinates), such as OpenStreetMap or Wikipedia.
public protocol DiscoveryProvider: Sendable {
    var id: DiscoverySourceID { get }
    /// Nil when ready; `.needsKey` or `.disabled` when the provider cannot run. The engine sends no request then.
    func readiness() -> DiscoverySourceStatus?
    /// Throws `DiscoveryError` for network, rate limit or server problems; `.notFound` means "nothing applicable".
    func discover(in area: DiscoveryArea, feature: FeatureKind?, text: String?, settings: DiscoverySettings) async throws -> [DiscoveredPlace]
}

extension DiscoveryProvider {
    public func readiness() -> DiscoverySourceStatus? { nil }
}

/// A source of free text that may mention places (Reddit posts, Google results). Names come out of it only through
/// a `DiscoveryExtracting` step, and are validated afterwards.
public protocol DiscoveryTextSource: Sendable {
    var id: DiscoverySourceID { get }
    func readiness() -> DiscoverySourceStatus?
    func texts(in area: DiscoveryArea, feature: FeatureKind?, text: String?, settings: DiscoverySettings) async throws -> [DiscoveryText]
}

extension DiscoveryTextSource {
    public func readiness() -> DiscoverySourceStatus? { nil }
}

/// Finds place names inside text. Names only: no coordinates, which the validator adds.
public protocol DiscoveryExtracting: Sendable {
    func extractPlaces(from texts: [DiscoveryText], area: DiscoveryArea, feature: FeatureKind?, settings: DiscoverySettings) async throws -> [DiscoveredPlace]
}

/// Resolves the real outline of a named protected area.
public protocol BoundaryResolving: Sendable {
    func resolveBoundary(areaName: String, near region: GeoRegion?) async -> GeoPolygon?
}

/// Shared search wording for the text sources.
enum DiscoveryQuery {
    /// "mountains Glacier National Park", or "Glacier National Park sunrise" when there is free text instead of a feature.
    static func terms(area: DiscoveryArea, feature: FeatureKind?, text: String?) -> String {
        var parts: [String] = []
        if let feature { parts.append(feature.pluralName) }
        if let name = area.name { parts.append(name) }
        if feature == nil {
            let t = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            parts.append(t.isEmpty ? "photography spots" : String(t.prefix(80)))
        }
        return parts.joined(separator: " ")
    }
}
