import Foundation
import IterModel
import IterSources
import IterDiscovery

/// The seam between `FindModel` and the discovery pipeline. `DiscoveryEngine` conforms; tests and previews pass a script.
public protocol DiscoveryRunning: Sendable {
    func run(_ request: DiscoveryRequest) -> AsyncStream<DiscoveryEvent>
}

extension DiscoveryEngine: DiscoveryRunning {}

/// Tunables for `FindModel`. Tests shorten the times and replace the clock.
public struct FindConfiguration: Sendable {
    /// A source still searching after this long is shown as slow (never blocks the others).
    public var slowAfter: Duration
    /// How often elapsed time and slowness are re-read while a run is going.
    public var tick: Duration
    /// Results that get a real drive time after a run, and how many routes run at once.
    public var driveTimeCount: Int
    public var driveTimeConcurrency: Int
    /// Longest wait for Apple Maps on a typed lookup, and for a place's time zone and Look Around answers.
    public var lookupTimeout: Duration
    /// Seconds from any fixed point, never going back (the system uptime in the app).
    public var monotonic: @Sendable () -> TimeInterval

    public init(slowAfter: Duration = .seconds(6), tick: Duration = .seconds(1), driveTimeCount: Int = 10, driveTimeConcurrency: Int = 2,
                lookupTimeout: Duration = .seconds(8), monotonic: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.slowAfter = slowAfter
        self.tick = tick
        self.driveTimeCount = max(0, driveTimeCount)
        self.driveTimeConcurrency = max(1, driveTimeConcurrency)
        self.lookupTimeout = lookupTimeout
        self.monotonic = monotonic
    }
}

/// Runs `operation` for at most `limit`; nil when it did not finish (or threw). The loser is cancelled.
func withTimeout<T: Sendable>(_ limit: Duration, _ operation: @escaping @Sendable () async throws -> T) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { try? await operation() }
        group.addTask {
            try? await Task.sleep(for: limit)
            return nil
        }
        defer { group.cancelAll() }
        return await group.next() ?? nil
    }
}

/// Groups result pins that would overlap at the current zoom (ported from `PinClusterer`). Pure: the same input always gives
/// the same clusters. The grid is fixed to the world in Web Mercator coordinates, so panning never changes a cluster's id
/// or membership; only crossing a zoom bucket regroups. Own spots never go through here.
public enum FindPinClusterer {
    public static let cellPoints = 48.0
    /// Below this visible longitude span (degrees) nothing is clustered, so co-located places can always be reached.
    public static let minimumLongitudeSpan = 0.1
    static let maxBucket = 22

    public struct Result: Equatable, Sendable {
        public var clusters: [FindCluster]
        /// Ids that stay individual pins, in input order.
        public var singles: [String]
    }

    public static func zoomBucket(region: GeoRegion?, viewportWidth: Double) -> Int? {
        guard let region, region.longitudeDelta >= minimumLongitudeSpan, viewportWidth > 0 else { return nil }
        let bucket = Int(log2(viewportWidth * 360 / region.longitudeDelta / cellPoints).rounded())
        return min(maxBucket, max(0, bucket))
    }

    static func mercator(_ c: Coordinate) -> (x: Double, y: Double) {
        let lat = min(85.0511, max(-85.0511, c.latitude)) * .pi / 180
        let x = (c.longitude + 180) / 360
        let y = 0.5 - log(tan(.pi / 4 + lat / 2)) / (2 * .pi)
        return (min(1, max(0, x)), min(1, max(0, y)))
    }

    public static func cluster(_ items: [(id: String, coordinate: Coordinate)], region: GeoRegion?, viewportWidth: Double) -> Result {
        guard let bucket = zoomBucket(region: region, viewportWidth: viewportWidth) else {
            return Result(clusters: [], singles: items.map(\.id))
        }
        let cells = Double(1 << bucket)
        struct Cell: Hashable { var x: Int; var y: Int }
        var groups: [Cell: [(id: String, coordinate: Coordinate)]] = [:]
        for item in items {
            let m = mercator(item.coordinate)
            groups[Cell(x: min(Int(cells) - 1, Int(m.x * cells)), y: min(Int(cells) - 1, Int(m.y * cells))), default: []].append(item)
        }
        var clusters: [FindCluster] = []
        var clustered: Set<String> = []
        for (cell, members) in groups where members.count > 1 {
            let sorted = members.sorted { $0.id < $1.id }
            let n = Double(sorted.count)
            let mean = Coordinate(latitude: sorted.reduce(0) { $0 + $1.coordinate.latitude } / n,
                                  longitude: sorted.reduce(0) { $0 + $1.coordinate.longitude } / n)
            clusters.append(FindCluster(id: "cluster/\(bucket)/\(cell.x)/\(cell.y)", coordinate: mean, count: sorted.count, memberIDs: sorted.map(\.id)))
            clustered.formUnion(sorted.map(\.id))
        }
        clusters.sort { $0.id < $1.id }
        return Result(clusters: clusters, singles: items.map(\.id).filter { !clustered.contains($0) })
    }
}
