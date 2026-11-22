import Foundation
import IterModel
import IterSources

/// Every provider a Find run may call, grouped by what it does. Build it in one place from the live adapters:
///
///     DiscoveryProviders(geocoders: [MapKitGeocoder()], boundaries: [...], gazetteers: [OverpassProvider(...), MapKitPOIGazetteer(), GNISProvider(...)],
///                        placeSearch: [MapKitPlaceSearch()], textEvidence: [WikipediaProvider(...)], photoEvidence: [CommonsProvider(...)])
///
/// or from a `SourceRegistry` with `init(registry:at:)`, which applies enablement, keys and coverage for one point.
/// A user-key text provider (Reddit OAuth, say) is just another entry in `textEvidence`.
public struct DiscoveryProviders: Sendable {
    public var geocoders: [any Geocoder]
    public var boundaries: [any BoundaryProvider]
    public var gazetteers: [any GazetteerProvider]
    public var placeSearch: [any PlaceSearchProvider]
    public var textEvidence: [any TextEvidenceProvider]
    public var photoEvidence: [any PhotoEvidenceProvider]

    public init(geocoders: [any Geocoder] = [], boundaries: [any BoundaryProvider] = [], gazetteers: [any GazetteerProvider] = [],
                placeSearch: [any PlaceSearchProvider] = [], textEvidence: [any TextEvidenceProvider] = [],
                photoEvidence: [any PhotoEvidenceProvider] = []) {
        self.geocoders = geocoders
        self.boundaries = boundaries
        self.gazetteers = gazetteers
        self.placeSearch = placeSearch
        self.textEvidence = textEvidence
        self.photoEvidence = photoEvidence
    }

    /// The providers the registry selects at `point` (enabled, keyed, covering), in its preference order.
    public init(registry: SourceRegistry, at point: Coordinate) {
        self.init(
            geocoders: registry.providers((any Geocoder).self, kind: .geocode, at: point),
            boundaries: registry.providers((any BoundaryProvider).self, kind: .boundary, at: point),
            gazetteers: registry.providers((any GazetteerProvider).self, kind: .gazetteer, at: point),
            placeSearch: registry.providers((any PlaceSearchProvider).self, kind: .places, at: point),
            textEvidence: registry.providers((any TextEvidenceProvider).self, kind: .textEvidence, at: point),
            photoEvidence: registry.providers((any PhotoEvidenceProvider).self, kind: .photoEvidence, at: point))
    }

    var allTextAndStructured: [any SourceDescribing] {
        textEvidence.map { $0 as any SourceDescribing }
    }
}
