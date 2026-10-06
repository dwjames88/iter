import Foundation
import IterCore

/// Groups map pins that would overlap at the current zoom. Pure: the same input always gives the same clusters.
///
/// The grid is fixed to the world in Web Mercator coordinates (x and y from 0 to 1). Its resolution is a power of two
/// picked from how many points one world is wide at the visible region's longitude span and the map's width, so a cell
/// is between about 34 and 68 points across. Because the grid does not move with the camera, panning never changes a
/// cluster's id or membership; only crossing a zoom bucket regroups.
public enum PinClusterer {
    /// The wanted cell width in points.
    public static let cellPoints = 48.0
    /// Below this visible longitude span (degrees) nothing is clustered, so co-located spots can always be reached.
    public static let minimumLongitudeSpan = 0.1
    /// The smallest span a cluster click may ask the camera for. It is below `minimumLongitudeSpan`, so the settle that
    /// follows always unclusters the members, even when they share a coordinate.
    public static let minimumFitSpan = 0.05
    /// The finest grid (cells per world side is `2^maxBucket`).
    static let maxBucket = 22

    public struct Candidate: Equatable, Sendable {
        public var id: String
        public var coordinate: Coordinate
        public var score: Int?
        public var band: LightBand?
        public init(id: String, coordinate: Coordinate, score: Int? = nil, band: LightBand? = nil) {
            self.id = id
            self.coordinate = coordinate
            self.score = score
            self.band = band
        }
    }

    public struct Result: Equatable, Sendable {
        public var clusters: [ExploreCluster]
        /// Candidates that stay individual pins (alone in their cell), in input order.
        public var singles: [String]
    }

    /// The grid's zoom bucket, or nil when there is nothing to measure (no region, no width, no span).
    public static func zoomBucket(region: GeoRegion?, viewportWidth: Double) -> Int? {
        guard let region, region.longitudeDelta >= minimumLongitudeSpan, viewportWidth > 0 else { return nil }
        let worldPoints = viewportWidth * 360 / region.longitudeDelta
        let bucket = Int((log2(worldPoints / cellPoints)).rounded())
        return min(maxBucket, max(0, bucket))
    }

    /// Web Mercator position, x east and y south, both 0 to 1.
    static func mercator(_ c: Coordinate) -> (x: Double, y: Double) {
        let lat = min(85.0511, max(-85.0511, c.latitude)) * .pi / 180
        let x = (c.longitude + 180) / 360
        let y = 0.5 - log(tan(.pi / 4 + lat / 2)) / (2 * .pi)
        return (min(1, max(0, x)), min(1, max(0, y)))
    }

    /// Clusters `candidates`. With an unknown region or a zero-width viewport nothing is clustered.
    public static func cluster(_ candidates: [Candidate], region: GeoRegion?, viewportWidth: Double) -> Result {
        guard let bucket = zoomBucket(region: region, viewportWidth: viewportWidth) else {
            return Result(clusters: [], singles: candidates.map(\.id))
        }
        let cells = Double(1 << bucket)
        struct Cell: Hashable { var x: Int; var y: Int }
        var groups: [Cell: [Candidate]] = [:]
        for candidate in candidates {
            let m = mercator(candidate.coordinate)
            let cell = Cell(x: min(Int(cells) - 1, Int(m.x * cells)), y: min(Int(cells) - 1, Int(m.y * cells)))
            groups[cell, default: []].append(candidate)
        }
        var clusters: [ExploreCluster] = []
        var clustered: Set<String> = []
        for (cell, members) in groups where members.count > 1 {
            let sorted = members.sorted { $0.id < $1.id }
            let best = sorted.filter { $0.score != nil }.max { ($0.score ?? 0) < ($1.score ?? 0) }
            let n = Double(sorted.count)
            let mean = Coordinate(latitude: sorted.reduce(0) { $0 + $1.coordinate.latitude } / n,
                                  longitude: sorted.reduce(0) { $0 + $1.coordinate.longitude } / n)
            clusters.append(ExploreCluster(id: "cluster/\(bucket)/\(cell.x)/\(cell.y)", coordinate: mean, count: sorted.count,
                                           bestScore: best?.score, bestBand: best?.band, memberIDs: sorted.map(\.id),
                                           memberCoordinates: sorted.map(\.coordinate)))
            clustered.formUnion(sorted.map(\.id))
        }
        clusters.sort { $0.id < $1.id }
        return Result(clusters: clusters, singles: candidates.map(\.id).filter { !clustered.contains($0) })
    }
}
