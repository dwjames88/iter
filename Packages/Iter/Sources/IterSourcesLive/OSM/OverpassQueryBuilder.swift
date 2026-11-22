import Foundation
import IterModel

/// Builds Overpass QL from the features' `osmTags`. Pure.
public enum OverpassQueryBuilder {
    /// The server-side timeout (seconds) written into every query. It must stay below the client timeout in the
    /// source's `RequestPolicy`, so the server answers (even with a timeout remark) before the client gives up.
    public static let serverTimeoutSeconds = 25

    /// The search box as `(south,west,north,east)`: the boundary's bounding box when the area has one, else its region.
    public static func bbox(for area: DiscoveryArea) -> (south: Double, west: Double, north: Double, east: Double) {
        let r = (area.boundary.flatMap { $0.isEmpty ? nil : $0.boundingRegion }) ?? area.region
        let south = max(-90, r.center.latitude - r.latitudeDelta / 2)
        let north = min(90, r.center.latitude + r.latitudeDelta / 2)
        let west = max(-180, r.center.longitude - r.longitudeDelta / 2)
        let east = min(180, r.center.longitude + r.longitudeDelta / 2)
        return (south, west, north, east)
    }

    /// Peaks and cave entrances are mapped as points; everything else may be a node, a way or a relation.
    static func elementType(for feature: FeatureKind) -> String {
        switch feature {
        case .peak, .cave: "node"
        default: "nwr"
        }
    }

    /// `[out:json][timeout:25];(...statements...);out center <limit>;`. Every statement requires a name.
    public static func query(area: DiscoveryArea, features: Set<FeatureKind>, limit: Int) -> String {
        let b = bbox(for: area)
        let box = String(format: "(%.6f,%.6f,%.6f,%.6f)", b.south, b.west, b.north, b.east)
        var statements: [String] = []
        for feature in FeatureKind.allCases where features.contains(feature) {
            for tag in feature.osmTags {
                statements.append(elementType(for: feature) + tag.overpassFilters + box + ";")
            }
        }
        return "[out:json][timeout:\(serverTimeoutSeconds)];(" + statements.joined() + ");out center \(max(1, limit));"
    }

    /// The `[timeout:N]` value of a built query, or nil.
    public static func serverTimeout(in query: String) -> Int? {
        guard let r = query.range(of: "[timeout:") else { return nil }
        let digits = query[r.upperBound...].prefix { $0.isNumber }
        return Int(digits)
    }

    // MARK: Boundaries

    /// How far from `near` a named area is searched, metres.
    public static let boundarySearchRadiusM = 100_000
    /// The most elements a search without `near` returns (a name like "Park" matches thousands worldwide).
    public static let globalBoundaryLimit = 10

    /// Escapes regex metacharacters, so a name is matched as text.
    static func regexEscaped(_ s: String) -> String {
        var out = ""
        for ch in s {
            if "\\.^$*+?()[]{}|".contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    /// A string for an Overpass QL literal: backslash and double quote escaped.
    static func qlString(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Relations and ways tagged as a national park, protected area or nature reserve whose name starts with `name`
    /// (case-insensitive; "Yosemite" finds "Yosemite National Park"), within `boundarySearchRadiusM` of `near` when given.
    /// `out geom` returns every member way's coordinates, so one request gives the whole outline. Administrative
    /// boundaries are not asked for.
    ///
    ///     [out:json][timeout:25];(relation["boundary"~"^(national_park|protected_area)$"]["name"~"^Yosemite",i](around:100000,37.8,-119.5);...);out geom;
    public static func boundaryQuery(name: String, near: Coordinate?) -> String {
        let pattern = qlString("^" + regexEscaped(name))
        let around = near.map { "(around:\(boundarySearchRadiusM),\(coordinateText($0.latitude)),\(coordinateText($0.longitude)))" } ?? ""
        var statements: [String] = []
        for type in ["relation", "way"] {
            statements.append("\(type)[\"boundary\"~\"^(national_park|protected_area)$\"][\"name\"~\"\(pattern)\",i]\(around);")
            statements.append("\(type)[\"leisure\"=\"nature_reserve\"][\"name\"~\"\(pattern)\",i]\(around);")
        }
        let out = near == nil ? "out geom \(globalBoundaryLimit);" : "out geom;"
        return "[out:json][timeout:\(serverTimeoutSeconds)];(" + statements.joined() + ");" + out
    }

    private static func coordinateText(_ v: Double) -> String {
        var s = String(format: "%.6f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s == "-0" ? "0" : s
    }
}
