import Foundation
import IterModel
import IterSources

/// Real outlines of named areas (national parks, protected areas, nature reserves) from OpenStreetMap through the public
/// Overpass instances. No Nominatim: one Overpass query returns the relation with its geometry, and the outline is
/// assembled, simplified (about 50 m, at most 2,000 vertices) and returned with a citation.
///
/// It shares the server rotation and retry rules with `OverpassProvider` (`OverpassRunner`) and the same descriptor
/// (`SourceCatalogue.osmOverpass` carries both the `.gazetteer` and `.boundary` kinds, one rate policy for one service).
public struct OverpassBoundaryProvider: BoundaryProvider {
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

    public func boundary(named name: String, near: Coordinate?) async throws -> NamedBoundary? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let query = OverpassQueryBuilder.boundaryQuery(name: trimmed, near: near)
        let runner = OverpassRunner(http: http, clock: clock, descriptor: descriptor, servers: servers, maxAttempts: maxAttempts)
        let body = try await runner.run(query)
        return try OverpassBoundaryMapping.boundary(from: body, named: trimmed, near: near, descriptor: descriptor, fetchedAt: clock.now)
    }
}
