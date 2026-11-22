import Foundation
import IterModel
import IterSources

/// Sends one Overpass query to the public instances, rotating servers and backing off. Shared by `OverpassProvider` and
/// `OverpassBoundaryProvider`; the rules are described on `OverpassProvider`.
struct OverpassRunner: Sendable {
    /// The longest single backoff, even when a server asks for more.
    static let maxBackoff: Duration = .seconds(120)

    let http: any HTTPClient
    let clock: any SourceClock
    let descriptor: SourceDescriptor
    let servers: [URL]
    let maxAttempts: Int

    /// The response body of the first attempt that succeeds. Throws `SourceError`.
    func run(_ query: String) async throws -> Data {
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
