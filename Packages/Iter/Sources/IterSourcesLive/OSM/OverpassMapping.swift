import Foundation
import IterModel
import IterSources

/// Overpass JSON into `PlaceCandidate`s. Pure.
public enum OverpassMapping {
    struct Response: Decodable {
        var remark: String?
        var elements: [Element]?
    }

    struct Element: Decodable {
        struct Center: Decodable { var lat: Double; var lon: Double }
        var type: String
        var id: Int64
        var lat: Double?
        var lon: Double?
        var center: Center?
        var tags: [String: String]?
    }

    /// The `remark` of a 200 response when it reports a runtime error ("runtime error: Query timed out ..."), else nil.
    public static func runtimeRemark(in data: Data) -> String? {
        guard let r = try? JSONDecoder().decode(Response.self, from: data), let remark = r.remark,
              remark.lowercased().contains("runtime error") else { return nil }
        return remark
    }

    /// Candidates for `features` (all kinds when empty), inside the area's boundary when it has one, de-duplicated and
    /// capped to `limit`.
    public static func candidates(from data: Data, area: DiscoveryArea, features: Set<FeatureKind>, limit: Int,
                                  descriptor: SourceDescriptor, fetchedAt: Date) throws -> [PlaceCandidate] {
        let response: Response
        do { response = try JSONDecoder().decode(Response.self, from: data) } catch {
            throw SourceError.decoding("overpass: \(error)")
        }
        let wanted = FeatureKind.allCases.filter { features.isEmpty || features.contains($0) }
        var out: [PlaceCandidate] = []
        var seenIDs = Set<String>()
        for e in response.elements ?? [] {
            guard out.count < limit else { break }
            let tags = e.tags ?? [:]
            let kinds = wanted.filter { kind in kind.osmTags.contains { matches($0, tags) } }
            guard !kinds.isEmpty, let name = displayName(tags) else { continue }
            let coordinate: Coordinate
            if let lat = e.lat, let lon = e.lon { coordinate = Coordinate(latitude: lat, longitude: lon) }
            else if let c = e.center { coordinate = Coordinate(latitude: c.lat, longitude: c.lon) }
            else { continue }
            if let boundary = area.boundary, !boundary.isEmpty, !boundary.contains(coordinate) { continue }
            let externalID = "\(e.type)/\(e.id)"
            guard seenIDs.insert(externalID).inserted else { continue }
            // The same thing mapped twice (a node and a way): same name and kinds within 100 m.
            if out.contains(where: {
                $0.name.caseInsensitiveCompare(name) == .orderedSame && $0.featureKinds == kinds
                    && ($0.coordinate?.distance(to: coordinate) ?? .infinity) < 100
            }) { continue }
            let citation = Citation(source: descriptor.id, url: URL(string: "https://www.openstreetmap.org/\(externalID)"),
                                    title: "OpenStreetMap: \(name)", retrievedAt: fetchedAt, licence: descriptor.licence)
            out.append(PlaceCandidate(name: name, coordinate: coordinate, elevationMeters: elevation(tags["ele"]),
                                      featureKinds: kinds, source: descriptor.id, externalID: externalID, citations: [citation]))
        }
        return out
    }

    static func displayName(_ tags: [String: String]) -> String? {
        for key in ["name", "name:en"] {
            if let v = tags[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty { return v }
        }
        return nil
    }

    /// The tag test of `OSMTag`, applied to an element's tags.
    static func matches(_ tag: OSMTag, _ tags: [String: String]) -> Bool {
        guard let v = tags[tag.key], tag.values.contains(v) else { return false }
        for (k, allowed) in tag.also {
            guard let t = tags[k], allowed.contains(t) else { return false }
        }
        if let nameContains = tag.nameContains {
            guard let name = displayName(tags), name.contains(nameContains) else { return false }
        }
        return displayName(tags) != nil
    }

    /// Metres from an OSM `ele` value: "4266", "4266.5", "4266 m", "14,000 ft", "14000'", "4266,5" (decimal comma).
    /// Nil when unparseable, ambiguous (lists, ranges) or outside -500...9000 m.
    public static func elevation(_ raw: String?) -> Double? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !s.isEmpty else { return nil }
        let numberChars = Set("0123456789,.-")
        let number = String(s.prefix { numberChars.contains($0) })
        s = String(s.dropFirst(number.count)).trimmingCharacters(in: .whitespaces)
        var factor = 1.0
        switch s {
        case "", "m", "meter", "meters", "metre", "metres": break
        case "ft", "feet", "foot", "'": factor = 0.3048
        default: return nil
        }
        guard let digits = normalisedNumber(number) else { return nil }
        guard let value = Double(digits) else { return nil }
        let metres = value * factor
        return (-500...9000).contains(metres) ? metres : nil
    }

    /// "14,000", "1,234,567", "14,000.5" (thousands commas), "4266,5" (decimal comma), "4266.5". Nil when malformed.
    private static func normalisedNumber(_ number: String) -> String? {
        guard number.contains(",") else { return number }
        let dotParts = number.components(separatedBy: ".")
        let integerGroups = dotParts[0].components(separatedBy: ",")
        let commaCount = integerGroups.count - 1
        let thousands = dotParts.count == 2 || commaCount > 1 || (integerGroups.last?.count == 3)
        if thousands {
            guard dotParts.count <= 2, integerGroups.dropFirst().allSatisfy({ $0.count == 3 }) else { return nil }
            return integerGroups.joined() + (dotParts.count == 2 ? "." + dotParts[1] : "")
        }
        return number.replacingOccurrences(of: ",", with: ".")
    }
}
