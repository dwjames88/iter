import Foundation
import IterModel
import IterSources

/// USGS Geographic Names (ArcGIS JSON) into `PlaceCandidate`s. Pure.
public enum GNISMapping {
    /// The photographable feature a GNIS feature class stands for, or nil when it is skipped.
    ///
    /// Summit and Pillar are peaks; Ridge and Range are not (a range is an area, not a point to shoot). Lake and
    /// Reservoir are lakes. Spring counts as a hot spring only when its name says "Hot". Valley or Gap is a canyon only
    /// when its name contains "Canyon". Flat, Plain, Gap (otherwise), Valley (otherwise) and the rest are skipped.
    public static func kind(featureClass: String, name: String) -> FeatureKind? {
        switch featureClass {
        case "Summit", "Pillar": return .peak
        case "Lake", "Reservoir": return .lake
        case "Falls": return .waterfall
        case "Arch": return .arch
        case "Beach": return .beach
        case "Glacier": return .glacier
        case "Cave": return .cave
        case "Bridge": return .bridge
        case "Spring": return name.localizedCaseInsensitiveContains("hot") ? .hotSpring : nil
        case "Valley", "Gap": return name.localizedCaseInsensitiveContains("canyon") ? .canyon : nil
        default: return nil
        }
    }

    /// One page of results.
    public struct Page: Sendable {
        public var candidates: [PlaceCandidate]
        /// The server stopped at its record limit; ask again with `resultOffset`.
        public var exceededTransferLimit: Bool
        /// Features in the page, mapped or not (the next `resultOffset` step).
        public var featureCount: Int
    }

    struct Response: Decodable {
        struct Err: Decodable { var code: Int?; var message: String? }
        struct Geometry: Decodable { var points: [[Double]]?; var x: Double?; var y: Double? }
        struct Feature: Decodable {
            struct Attributes: Decodable {
                var gaz_id: Int?
                var gaz_name: String?
                var gaz_featureclass: String?
            }
            var attributes: Attributes
            var geometry: Geometry?
        }
        var error: Err?
        var features: [Feature]?
        var exceededTransferLimit: Bool?
    }

    public static func page(from data: Data, area: DiscoveryArea, features: Set<FeatureKind>, descriptor: SourceDescriptor,
                            fetchedAt: Date) throws -> Page {
        let response: Response
        do { response = try JSONDecoder().decode(Response.self, from: data) } catch {
            throw SourceError.decoding("gnis: \(error)")
        }
        if let e = response.error { throw SourceError.http(status: e.code ?? -1, excerpt: e.message) }
        let rows = response.features ?? []
        var out: [PlaceCandidate] = []
        var seen = Set<String>()
        for f in rows {
            guard let id = f.attributes.gaz_id,
                  let name = f.attributes.gaz_name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                  let fc = f.attributes.gaz_featureclass, let kind = kind(featureClass: fc, name: name),
                  features.isEmpty || features.contains(kind) else { continue }
            let coordinate: Coordinate
            if let p = f.geometry?.points?.first, p.count >= 2 { coordinate = Coordinate(latitude: p[1], longitude: p[0]) }
            else if let x = f.geometry?.x, let y = f.geometry?.y { coordinate = Coordinate(latitude: y, longitude: x) }
            else { continue }
            guard area.contains(coordinate), seen.insert("gnis/\(id)").inserted else { continue }
            let citation = Citation(source: descriptor.id,
                                    url: URL(string: "https://edits.nationalmap.gov/apps/gaz-domestic/public/summary/\(id)"),
                                    title: "USGS GNIS: \(name)", retrievedAt: fetchedAt, licence: descriptor.licence)
            out.append(PlaceCandidate(name: name, coordinate: coordinate, featureKinds: [kind], source: descriptor.id,
                                      externalID: "gnis/\(id)", citations: [citation]))
        }
        return Page(candidates: out, exceededTransferLimit: response.exceededTransferLimit ?? false, featureCount: rows.count)
    }
}
