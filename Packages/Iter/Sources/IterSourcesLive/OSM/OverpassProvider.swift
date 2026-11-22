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

    /// The longest single backoff, even when a server asks for more.
    static let maxBackoff: Duration = .seconds(120)

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
        var lastError: SourceError = .http(status: -1, excerpt: "no attempt made")
        for attempt in 0..<maxAttempts {
            let server = servers[attempt % servers.count]
            var request = SourceRequest.postForm(server, fields: [("data", query)], from: descriptor)
            request.policy.maxRetries = 0
            var retryAfter: Date?
            do {
                let response = try await http.send(request)
                if OverpassMapping.runtimeRemark(in: response.body) != nil { throw SourceError.timedOut }
                return response.body
            } catch {
                let e = SourceError.wrap(error)
                switch e {
                case .http(let status, let excerpt) where status == 400:
                    throw SourceError.invalidRequest("Overpass rejected the query" + (excerpt.map { ": \($0)" } ?? ""))
                case .rateLimited(let at):
                    retryAfter = at
                case .timedOut:
                    break
                case .http(let status, _) where status == 502 || status == 503 || status == 504 || (500..<600).contains(status):
                    break
                default:
                    throw e
                }
                lastError = e
            }
            guard attempt + 1 < maxAttempts else { break }
            var wait = descriptor.policy.initialBackoff * Int(1 << attempt)
            if let retryAfter { wait = max(wait, .interval(retryAfter.timeIntervalSince(clock.now))) }
            try await clock.sleep(for: min(wait, Self.maxBackoff))
        }
        throw lastError
    }
}
