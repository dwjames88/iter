import Foundation
import IterModel
import IterSources

/// `MapItemRecord` -> `PlaceCandidate` / `GeocodeResult`. Pure.
enum MapKitPlaceMapping {
    static func candidate(from r: MapItemRecord, source: SourceID, fetchedAt: Date, licence: LicenceTag?) -> PlaceCandidate? {
        guard let name = (r.name ?? r.shortAddress)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        let citations = r.url.map {
            [Citation(source: source, url: $0, title: "Apple Maps: \(name)", retrievedAt: fetchedAt, licence: licence)]
        } ?? []
        return PlaceCandidate(name: name, coordinate: r.coordinate,
                              featureKinds: POICategoryMapping.featureKinds(forCategoryRaw: r.categoryRaw),
                              source: source, externalID: r.identifier, citations: citations)
    }

    static func geocodeResult(from r: MapItemRecord) -> GeocodeResult {
        GeocodeResult(name: r.name ?? r.shortAddress ?? r.coordinate.cacheKey, coordinate: r.coordinate,
                      formattedAddress: r.fullAddress, countryCode: r.countryCode, timeZoneIdentifier: r.timeZoneIdentifier)
    }
}
