import Foundation
import IterModel
import Synchronization

/// One request as an adapter describes it. `SourceHTTP` adds the User-Agent, spacing, validators, timeout and retries.
public struct SourceRequest: Sendable, Hashable {
    public var url: URL
    public var method: String
    public var headers: [String: String]
    public var body: Data?
    /// The source asking (for logs, rate limits and error mapping).
    public var source: SourceID
    public var policy: RequestPolicy

    public init(url: URL, method: String = "GET", headers: [String: String] = [:], body: Data? = nil,
                source: SourceID, policy: RequestPolicy) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.source = source
        self.policy = policy
    }

    /// A GET with the descriptor's policy.
    public static func get(_ url: URL, from descriptor: SourceDescriptor, headers: [String: String] = [:]) -> SourceRequest {
        SourceRequest(url: url, headers: headers, source: descriptor.id, policy: descriptor.policy)
    }

    /// A form-encoded POST (`application/x-www-form-urlencoded`) with the descriptor's policy.
    public static func postForm(_ url: URL, fields: [(String, String)], from descriptor: SourceDescriptor,
                                headers: [String: String] = [:]) -> SourceRequest {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        let body = fields.map { k, v in
            let ek = k.addingPercentEncoding(withAllowedCharacters: allowed) ?? k
            let ev = (v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v)
            return "\(ek)=\(ev)"
        }.joined(separator: "&")
        var h = headers
        h["Content-Type"] = "application/x-www-form-urlencoded"
        return SourceRequest(url: url, method: "POST", headers: h, body: Data(body.utf8), source: descriptor.id,
                             policy: descriptor.policy)
    }
}

/// A response. Header names are lower-cased. On a 304 `SourceHTTP` returns the remembered body with status 200 and
/// `revalidated = true`; when `Expires` had not passed it returns the remembered body without a request, `fromMemo = true`.
public struct SourceResponse: Sendable, Hashable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data
    public var url: URL
    public var receivedAt: Date
    public var revalidated: Bool
    public var fromMemo: Bool

    public init(status: Int, headers: [String: String] = [:], body: Data, url: URL, receivedAt: Date,
                revalidated: Bool = false, fromMemo: Bool = false) {
        self.status = status
        self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
        self.body = body
        self.url = url
        self.receivedAt = receivedAt
        self.revalidated = revalidated
        self.fromMemo = fromMemo
    }

    public func header(_ name: String) -> String? { headers[name.lowercased()] }

    /// RFC 7231 date headers (`Expires`, `Last-Modified`, `Date`).
    public func dateHeader(_ name: String) -> Date? { header(name).flatMap(HTTPDate.parse) }

    public var text: String? { String(data: body, encoding: .utf8) }
}

/// The one seam between adapters and the network. `SourceHTTP` is the real one; tests use `StubHTTPClient`.
/// Contract: returns only 2xx responses (and 304-revalidated ones as 200). Everything else throws `SourceError`:
/// 404/403/other statuses as `.http(status:excerpt:)`, 429 as `.rateLimited`, network loss as `.offline`.
/// Adapters may catch `.http` to recognise a source-specific meaning (NOMADS "not present" → `.notPublished`).
public protocol HTTPClient: Sendable {
    func send(_ request: SourceRequest) async throws -> SourceResponse
}

/// The honest generic User-Agent: "Iter/<version>", plus " (<contact>)" only when a contact is configured.
/// The contact comes from `UserAgent.configuredContact`, the single configuration point, empty by default:
/// the owner has not chosen one. Never put a name, email, username or repository URL here unless the owner says so.
public struct UserAgent: Sendable, Hashable {
    /// The one place a contact (a project web page or a role address) would go. Empty: none is sent.
    public static let configuredContact: String = ""

    public var appName: String
    public var version: String
    public var contact: String?

    public init(appName: String = "Iter", version: String, contact: String? = UserAgent.configuredContact) {
        self.appName = appName
        self.version = version
        let trimmed = contact?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.contact = (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    /// The app's own version from the main bundle, or "dev".
    public static var current: UserAgent {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return UserAgent(version: (v?.isEmpty == false ? v : nil) ?? "dev")
    }

    public var headerValue: String {
        contact.map { "\(appName)/\(version) (\($0))" } ?? "\(appName)/\(version)"
    }
}

/// RFC 7231 / RFC 850 / asctime HTTP dates.
public enum HTTPDate {
    private static let formats = ["EEE, dd MMM yyyy HH:mm:ss zzz", "EEEE, dd-MMM-yy HH:mm:ss zzz", "EEE MMM d HH:mm:ss yyyy"]

    public static func parse(_ s: String) -> Date? {
        for f in formats {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(identifier: "GMT")
            df.dateFormat = f
            if let d = df.date(from: s.trimmingCharacters(in: .whitespaces)) { return d }
        }
        return nil
    }

    public static func format(_ d: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "GMT")
        df.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return df.string(from: d)
    }
}

/// A scripted `HTTPClient` for tests: each route matches a request and returns a canned response or throws.
/// Unmatched requests throw `.http(status: 404, ...)`. Every request is recorded.
public final class StubHTTPClient: HTTPClient {
    public typealias Matcher = @Sendable (SourceRequest) -> Bool
    public enum Reply: Sendable {
        case ok(Data, headers: [String: String] = [:])
        case status(Int, Data = Data(), headers: [String: String] = [:])
        case error(SourceError)
    }

    private struct Route { let match: Matcher; var replies: [Reply] }
    private struct State { var routes: [Route] = []; var requests: [SourceRequest] = [] }
    private let state = Mutex(State())
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 0) }) { self.now = now }

    /// Adds a route. With several replies they are returned in order and the last one repeats.
    public func on(_ match: @escaping Matcher, reply: Reply...) {
        state.withLock { $0.routes.append(Route(match: match, replies: reply)) }
    }

    /// Route on a substring of the absolute URL.
    public func on(urlContaining fragment: String, reply: Reply...) {
        let replies = reply
        state.withLock { $0.routes.append(Route(match: { $0.url.absoluteString.contains(fragment) }, replies: replies)) }
    }

    public var requests: [SourceRequest] { state.withLock { $0.requests } }

    public func send(_ request: SourceRequest) async throws -> SourceResponse {
        let reply: Reply? = state.withLock { s in
            s.requests.append(request)
            guard let i = s.routes.firstIndex(where: { $0.match(request) }) else { return nil }
            let r = s.routes[i].replies.first
            if s.routes[i].replies.count > 1 { s.routes[i].replies.removeFirst() }
            return r
        }
        switch reply {
        case .none:
            throw SourceError.http(status: 404, excerpt: "no stub for \(request.url.absoluteString)")
        case .ok(let data, let headers)?:
            return SourceResponse(status: 200, headers: headers, body: data, url: request.url, receivedAt: now())
        case .status(let code, let data, let headers)?:
            if (200..<300).contains(code) {
                return SourceResponse(status: code, headers: headers, body: data, url: request.url, receivedAt: now())
            }
            if code == 429 { throw SourceError.rateLimited(retryAfter: nil) }
            throw SourceError.http(status: code, excerpt: String(data: data.prefix(300), encoding: .utf8))
        case .error(let e)?:
            throw e
        }
    }
}
