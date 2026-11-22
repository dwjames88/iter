import Foundation
import IterModel
import IterSources

/// USGS Geographic Names (GNIS) in an area, via The National Map's ArcGIS service. United States only.
public struct GNISProvider: GazetteerProvider {
    static let endpoint = "https://carto.nationalmap.gov/arcgis/rest/services/geonames/MapServer/5/query"
    /// Pages fetched at most, when the server reports `exceededTransferLimit`.
    static let maxPages = 5

    public let descriptor: SourceDescriptor
    private let http: any HTTPClient
    private let clock: any SourceClock

    public init(http: any HTTPClient, clock: any SourceClock = SystemSourceClock(),
                descriptor: SourceDescriptor = SourceCatalogue.usgsGNIS) {
        self.http = http
        self.clock = clock
        self.descriptor = descriptor
    }

    static func url(area: DiscoveryArea, offset: Int) -> URL {
        let b = OverpassQueryBuilder.bbox(for: area)
        var s = endpoint + "?geometry=" + [b.west, b.south, b.east, b.north].map { String(format: "%.5f", $0) }.joined(separator: ",")
        s += "&geometryType=esriGeometryEnvelope&inSR=4326&spatialRel=esriSpatialRelIntersects"
        s += "&outFields=gaz_id,gaz_name,gaz_featureclass&returnGeometry=true&outSR=4326&f=json"
        if offset > 0 { s += "&resultOffset=\(offset)" }
        return URL(string: s)!
    }

    public func candidates(in area: DiscoveryArea, features: Set<FeatureKind>, limit: Int) async throws -> [PlaceCandidate] {
        guard descriptor.coverage.contains(area.region.center) else { throw SourceError.outsideCoverage }
        guard limit > 0 else { return [] }
        var out: [PlaceCandidate] = []
        var seen = Set<String>()
        var offset = 0
        for _ in 0..<Self.maxPages {
            let page: GNISMapping.Page
            do {
                let response = try await http.send(.get(Self.url(area: area, offset: offset), from: descriptor))
                page = try GNISMapping.page(from: response.body, area: area, features: features, descriptor: descriptor,
                                            fetchedAt: clock.now)
            } catch { throw SourceError.wrap(error) }
            for c in page.candidates where seen.insert(c.externalID ?? c.name).inserted { out.append(c) }
            guard out.count < limit, page.exceededTransferLimit, page.featureCount > 0 else { break }
            offset += page.featureCount
        }
        return Array(out.prefix(limit))
    }
}
