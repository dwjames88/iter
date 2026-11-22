import Foundation
import IterModel

/// Every adapter and the HTTP layer throw this. It maps onto `NoDataReason` so the UI names the gap.
public enum SourceError: Error, Sendable, Hashable, CustomStringConvertible {
    /// No network.
    case offline
    /// The attempt (after retries) ran past the policy timeout.
    case timedOut
    /// 429 or a polite local cap; `retryAfter` when the server said.
    case rateLimited(retryAfter: Date?)
    /// Any other non-success status, with a short excerpt of the body for logs (never shown raw to users).
    case http(status: Int, excerpt: String?)
    /// The data exists upstream but is not published yet (a model cycle still running, a future date).
    case notPublished(String)
    /// The coordinate is outside the source's coverage, or the source said so.
    case outsideCoverage
    /// No source exists for this (light pollution, seeing): an honest slot.
    case noSource
    case needsKey(SourceID)
    /// The response could not be read.
    case decoding(String)
    case cancelled
    case invalidRequest(String)

    public var description: String {
        switch self {
        case .offline: "offline"
        case .timedOut: "timed out"
        case .rateLimited(let at): "rate limited" + (at.map { " until \($0)" } ?? "")
        case .http(let status, let excerpt): "HTTP \(status)" + (excerpt.map { ": \($0)" } ?? "")
        case .notPublished(let what): "not published yet: \(what)"
        case .outsideCoverage: "outside coverage"
        case .noSource: "no source"
        case .needsKey(let id): "needs a key for \(id)"
        case .decoding(let what): "unreadable response: \(what)"
        case .cancelled: "cancelled"
        case .invalidRequest(let what): "invalid request: \(what)"
        }
    }

    /// The gap the UI shows. `lastGood` is the time of the last good value, if one exists.
    public func noDataReason(source: SourceID, lastGood: Date? = nil) -> NoDataReason {
        switch self {
        case .offline, .timedOut: .offline(lastGood: lastGood)
        case .rateLimited(let at): .rateLimited(retryAfter: at)
        case .outsideCoverage: .outsideCoverage
        case .noSource: .notProvidedBySource
        case .needsKey(let id): .needsKey(id)
        case .http, .notPublished, .decoding, .cancelled, .invalidRequest: .sourceError(source, description)
        }
    }

    /// Wraps any error: a `SourceError` passes through, cancellation becomes `.cancelled`, `URLError` is classified.
    public static func wrap(_ error: any Error) -> SourceError {
        if let e = error as? SourceError { return e }
        if error is CancellationError { return .cancelled }
        if let u = error as? URLError {
            switch u.code {
            case .cancelled: return .cancelled
            case .timedOut: return .timedOut
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
                 .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed:
                return .offline
            default: return .http(status: -1, excerpt: u.code.rawValue.description)
            }
        }
        return .decoding(String(describing: error))
    }
}
