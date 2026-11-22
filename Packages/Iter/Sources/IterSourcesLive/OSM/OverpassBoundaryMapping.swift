import Foundation
import IterModel
import IterSources

/// Overpass `out geom` relations and closed ways into a `NamedBoundary`. Pure.
///
/// A park outline is a multipolygon relation whose outer ring is split over many member ways. The ways are joined end to
/// end (reversing as needed), `inner` ways become holes (`GeoPolygon` is even-odd), a ring that does not close is dropped,
/// and every ring is simplified with Douglas-Peucker so the outline stays small.
public enum OverpassBoundaryMapping {
    /// Simplification tolerance, metres.
    public static let toleranceMeters = 50.0
    /// Most vertices in the returned polygon, all rings together. The tolerance is raised until the outline fits.
    public static let maxVertices = 2_000

    struct Response: Decodable {
        var elements: [Element]?
    }

    struct Point: Decodable {
        var lat: Double
        var lon: Double
    }

    struct Member: Decodable {
        var type: String
        var role: String?
        /// `out geom` writes null for a node outside the requested bounds, so one missing entry marks the way incomplete.
        var geometry: [Point?]?
    }

    struct Element: Decodable {
        var type: String
        var id: Int64
        var tags: [String: String]?
        var members: [Member]?
        var geometry: [Point?]?
    }

    /// One candidate area, before choosing.
    struct Candidate {
        var element: Element
        var name: String
        var kind: String
        var polygon: GeoPolygon
        var areaM2: Double
        var center: Coordinate
    }

    /// The best match for `name`, or nil when nothing with a complete outline matches.
    public static func boundary(from data: Data, named name: String, near: Coordinate?, descriptor: SourceDescriptor,
                                fetchedAt: Date) throws -> NamedBoundary? {
        let response: Response
        do { response = try JSONDecoder().decode(Response.self, from: data) } catch {
            throw SourceError.decoding("overpass boundary: \(error)")
        }
        var candidates: [Candidate] = []
        var seen = Set<String>()
        for e in response.elements ?? [] {
            let tags = e.tags ?? [:]
            guard let kind = areaKind(tags), let shown = tags["name"]?.trimmingCharacters(in: .whitespacesAndNewlines), !shown.isEmpty,
                  seen.insert("\(e.type)/\(e.id)").inserted, let outline = outline(of: e) else { continue }
            candidates.append(Candidate(element: e, name: shown, kind: kind, polygon: outline.polygon, areaM2: outline.areaM2,
                                        center: outline.center))
        }
        let wanted = normalised(name)
        // The query matches the start of the raw name; this also holds the name to what was asked for once punctuation and
        // diacritics are folded, so an element that slipped through never becomes someone else's park.
        candidates.removeAll { !normalised($0.name).contains(wanted) }
        guard !candidates.isEmpty, !wanted.isEmpty else { return nil }
        func tier(_ c: Candidate) -> Int {
            let n = normalised(c.name)
            if n == wanted { return 0 }
            return n.hasPrefix(wanted) ? 1 : 2
        }
        func distance(_ c: Candidate) -> Double { near.map { $0.distance(to: c.center) } ?? 0 }
        let best = candidates.sorted { a, b in
            let ta = tier(a), tb = tier(b)
            if ta != tb { return ta < tb }
            // Areas within 1% count as equal; then the one nearer `near` wins.
            let bigger = max(a.areaM2, b.areaM2)
            if bigger > 0, abs(a.areaM2 - b.areaM2) / bigger > 0.01 { return a.areaM2 > b.areaM2 }
            let da = distance(a), db = distance(b)
            if da != db { return da < db }
            return "\(a.element.type)/\(a.element.id)" < "\(b.element.type)/\(b.element.id)"
        }[0]
        let externalID = "\(best.element.type)/\(best.element.id)"
        let citation = Citation(source: descriptor.id, url: URL(string: "https://www.openstreetmap.org/\(externalID)"),
                                title: best.name, retrievedAt: fetchedAt, licence: descriptor.licence)
        return NamedBoundary(name: best.name, polygon: best.polygon, externalID: externalID, areaKind: best.kind, citation: citation)
    }

    /// `boundary` first (national_park, protected_area), then `leisure=nature_reserve`.
    static func areaKind(_ tags: [String: String]) -> String? {
        if let b = tags["boundary"], b == "national_park" || b == "protected_area" { return b }
        if tags["leisure"] == "nature_reserve" { return "nature_reserve" }
        return nil
    }

    /// Lower case, diacritics folded, punctuation as spaces, runs of spaces collapsed: "St. Mary's" = "st mary s".
    static func normalised(_ s: String) -> String {
        let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let words = folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return words.joined(separator: " ")
    }

    // MARK: Rings

    private struct Outline {
        var polygon: GeoPolygon
        var areaM2: Double
        var center: Coordinate
    }

    private static func outline(of e: Element) -> Outline? {
        var outerWays: [[Coordinate]] = [], innerWays: [[Coordinate]] = []
        if e.type == "relation" {
            for m in e.members ?? [] where m.type == "way" {
                guard let line = coordinates(m.geometry), line.count >= 2 else { continue }
                if m.role == "inner" { innerWays.append(line) } else { outerWays.append(line) }
            }
        } else if e.type == "way", let line = coordinates(e.geometry), line.count >= 4, line.first == line.last {
            outerWays.append(line)
        } else {
            return nil
        }
        let outer = rings(from: outerWays), inner = rings(from: innerWays)
        guard !outer.isEmpty else { return nil }
        let (polygonRings, outerCount) = simplified(outer: outer, inner: inner)
        guard outerCount > 0 else { return nil }
        let polygon = GeoPolygon(rings: polygonRings)
        guard !polygon.isEmpty else { return nil }
        let region = polygon.boundingRegion
        // Area from the unsimplified rings: outer minus holes.
        let area = outer.reduce(0) { $0 + abs(planarArea($1)) } - inner.reduce(0) { $0 + abs(planarArea($1)) }
        return Outline(polygon: polygon, areaM2: max(0, area), center: region.center)
    }

    /// The coordinates of a way, or nil when any is missing (an incomplete way).
    private static func coordinates(_ points: [Point?]?) -> [Coordinate]? {
        guard let points else { return nil }
        var out: [Coordinate] = []
        out.reserveCapacity(points.count)
        for p in points {
            guard let p else { return nil }
            out.append(Coordinate(latitude: p.lat, longitude: p.lon))
        }
        return out
    }

    /// Joins ways that share end points into closed rings (without the repeated closing vertex). Ways may be reversed.
    /// Rings that do not close are dropped.
    static func rings(from ways: [[Coordinate]]) -> [[Coordinate]] {
        var used = Array(repeating: false, count: ways.count)
        // End point to the ways that start or end there.
        var ends: [Coordinate: [Int]] = [:]
        for (i, w) in ways.enumerated() {
            guard let a = w.first, let b = w.last else { continue }
            ends[a, default: []].append(i)
            if a != b { ends[b, default: []].append(i) }
        }
        var result: [[Coordinate]] = []
        for start in ways.indices where !used[start] {
            used[start] = true
            var ring = ways[start]
            while let first = ring.first, let last = ring.last, first != last {
                guard let next = (ends[last] ?? []).first(where: { !used[$0] }) else { break }
                used[next] = true
                let w = ways[next]
                ring += (w.first == last ? w : w.reversed()).dropFirst()
            }
            guard ring.count >= 4, ring.first == ring.last else { continue }
            ring.removeLast()
            result.append(ring)
        }
        return result
    }

    // MARK: Simplification

    /// Every ring simplified with one tolerance, raised from `toleranceMeters` until the total fits `maxVertices`. A ring
    /// that collapses below three vertices is dropped. Returns the rings (outer first) and how many outer rings remain.
    private static func simplified(outer: [[Coordinate]], inner: [[Coordinate]]) -> (rings: [[Coordinate]], outerCount: Int) {
        var tolerance = toleranceMeters
        for _ in 0..<20 {
            let o = outer.map { douglasPeucker($0, toleranceMeters: tolerance) }.filter { $0.count >= 3 }
            let i = inner.map { douglasPeucker($0, toleranceMeters: tolerance) }.filter { $0.count >= 3 }
            if o.reduce(0, { $0 + $1.count }) + i.reduce(0, { $0 + $1.count }) <= maxVertices || tolerance > 50_000 {
                return (o + i, o.count)
            }
            tolerance *= 2
        }
        return ([], 0)
    }

    /// Douglas-Peucker on a closed ring (given without the repeated closing vertex): it is split at the vertex farthest
    /// from the first and each half is simplified as an open line. Distances are measured in metres on a local plane.
    static func douglasPeucker(_ ring: [Coordinate], toleranceMeters: Double) -> [Coordinate] {
        guard ring.count > 3 else { return ring }
        let lat0 = ring.map(\.latitude).reduce(0, +) / Double(ring.count)
        let kx = cos(lat0 * .pi / 180) * 111_320, ky = 111_320.0
        let pts = ring.map { (x: $0.longitude * kx, y: $0.latitude * ky) }

        // Perpendicular distance of p from segment a-b.
        func dist(_ p: (x: Double, y: Double), _ a: (x: Double, y: Double), _ b: (x: Double, y: Double)) -> Double {
            let dx = b.x - a.x, dy = b.y - a.y
            let len2 = dx * dx + dy * dy
            if len2 == 0 { return ((p.x - a.x) * (p.x - a.x) + (p.y - a.y) * (p.y - a.y)).squareRoot() }
            let t = min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
            let cx = a.x + t * dx, cy = a.y + t * dy
            return ((p.x - cx) * (p.x - cx) + (p.y - cy) * (p.y - cy)).squareRoot()
        }

        var far = 1
        var farDistance = -1.0
        for i in 1..<pts.count {
            let d = (pow(pts[i].x - pts[0].x, 2) + pow(pts[i].y - pts[0].y, 2)).squareRoot()
            if d > farDistance { farDistance = d; far = i }
        }
        var keep = Array(repeating: false, count: pts.count)
        keep[0] = true
        keep[far] = true
        // Open lines 0...far and far...count (the last vertex is index 0 again).
        var stack: [(Int, Int)] = [(0, far), (far, pts.count)]
        while let (lo, hi) = stack.popLast() {
            guard hi - lo > 1 else { continue }
            let a = pts[lo], b = pts[hi % pts.count]
            var index = -1
            var maxD = toleranceMeters
            for i in (lo + 1)..<hi {
                let d = dist(pts[i], a, b)
                if d > maxD { maxD = d; index = i }
            }
            if index >= 0 {
                keep[index] = true
                stack.append((lo, index))
                stack.append((index, hi))
            }
        }
        return ring.enumerated().filter { keep[$0.offset] }.map(\.element)
    }

    /// Shoelace area of a ring in square metres on a local plane (signed).
    static func planarArea(_ ring: [Coordinate]) -> Double {
        guard ring.count >= 3 else { return 0 }
        let lat0 = ring.map(\.latitude).reduce(0, +) / Double(ring.count)
        let kx = cos(lat0 * .pi / 180) * 111_320, ky = 111_320.0
        var sum = 0.0
        for i in ring.indices {
            let a = ring[i], b = ring[(i + 1) % ring.count]
            sum += (a.longitude * kx) * (b.latitude * ky) - (b.longitude * kx) * (a.latitude * ky)
        }
        return sum / 2
    }
}
