import Foundation
import IterModel
import IterSources

/// OpenStreetMap features through the public Overpass instances.
///
/// The public servers are shared and often answer 502/504 when busy, so each attempt goes to the next server in the
/// list and this type does the retrying itself (every request is sent with `maxRetries: 0`). Retried: 429, 502, 503,
/// 504, other 5xx, timeouts, and 200 responses whose `remark` reports a runtime error. A 400 (bad query) fails at once.
/// A dropped connection (`.offline`) also fails at once: retrying a missing network only wastes the user's time.
public struct OverpassProvider: GazetteerProvider {
    public static let defaultServers: [URL] = [
        URL(string: "https://overpass-api.de/api/interpreter")!,
        URL(string: "https://overpass.private.coffee/api/interpreter")!,
        URL(string: "https://overpass.kumi.systems/api/interpreter")!,
    ]

    public let descriptor: SourceDescriptor
    private let http: any HTTPClient
    private let clock: any SourceClock
    private let servers: [URL]
    private let maxAttempts: Int

    public init(http: any HTTPClient, clock: any SourceClock = SystemSourceClock(),
                descriptor: SourceDescriptor = SourceCatalogue.osmOverpass,
                servers: [URL] = OverpassProvider.defaultServers, maxAttempts: Int = 3) {
        self.http = http
        self.clock = clock
        self.descriptor = descriptor
        self.servers = servers.isEmpty ? OverpassProvider.defaultServers : servers
        self.maxAttempts = max(1, maxAttempts)
    }

    public func candidates(in area: DiscoveryArea, features: Set<FeatureKind>, limit: Int) async throws -> [PlaceCandidate] {
        guard limit > 0, !features.isEmpty else { return [] }
        guard descriptor.coverage.contains(area.region.center) else { throw SourceError.outsideCoverage }
        let query = OverpassQueryBuilder.query(area: area, features: features, limit: limit)
        let body = try await run(query)
        return try OverpassMapping.candidates(from: body, area: area, features: features, limit: limit,
                                              descriptor: descriptor, fetchedAt: clock.now)
    }

    private func run(_ query: String) async throws -> Data {
        try await OverpassRunner(http: http, clock: clock, descriptor: descriptor, servers: servers, maxAttempts: maxAttempts).run(query)
    }
}
