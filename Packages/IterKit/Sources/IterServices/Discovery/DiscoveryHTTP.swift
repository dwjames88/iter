import Foundation
import CryptoKit
import IterCore

/// Why a discovery request failed. Never carries a URL or a key; `reason` is short enough for a status line.
public enum DiscoveryError: Error, Equatable, Sendable {
    case rateLimited
    case busy
    case offline
    case timedOut
    case notFound
    case http(Int)
    case badResponse
    case unavailable(String)

    /// A short phrase for `DiscoverySourceStatus.unavailable`.
    public var reason: String {
        switch self {
        case .rateLimited: "Rate limited"
        case .busy: "Server busy"
        case .offline: "Offline"
        case .timedOut: "Timed out"
        case .notFound: "Not found"
        case .http(let status): "HTTP \(status)"
        case .badResponse: "Unreadable response"
        case .unavailable(let why): why
        }
    }

    /// Turns anything thrown into a `DiscoveryError`, with every `secrets` string removed from free text.
    static func map(_ error: any Error, redacting secrets: [String] = []) -> DiscoveryError {
        if let e = error as? DiscoveryError { return e }
        if let url = error as? URLError {
            switch url.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
                 .internationalRoamingOff, .dataNotAllowed: return .offline
            case .timedOut: return .timedOut
            default: return .unavailable("Network error \(url.code.rawValue)")
            }
        }
        if error is DecodingError { return .badResponse }
        var text = "\(type(of: error))"
        for s in secrets where !s.isEmpty { text = text.replacingOccurrences(of: s, with: "•••") }
        return .unavailable(text)
    }
}

/// The hosts discovery talks to, each with its own politeness settings.
public enum DiscoveryHost: String, CaseIterable, Sendable {
    case overpass, wikipedia, wikivoyage, reddit, google

    /// Least time between the starts of two requests to the host.
    public var minimumInterval: TimeInterval {
        switch self {
        case .reddit: 2
        case .overpass: 1
        case .wikipedia, .wikivoyage: 0.2
        case .google: 0.2
        }
    }

    /// Requests allowed in flight at once.
    public var maximumConcurrent: Int { 1 }

    /// How long a cached response stays good.
    public var timeToLive: TimeInterval {
        switch self {
        case .reddit: 6 * 3600
        case .overpass, .wikipedia, .wikivoyage, .google: 7 * 86_400
        }
    }
}

/// Spaces out requests per host and limits how many run at once. A request holds its slot between
/// `acquire` and `release`.
public actor DiscoveryRateLimiter {
    private let intervals: [DiscoveryHost: TimeInterval]
    private var nextStart: [DiscoveryHost: Date] = [:]
    private var active: [DiscoveryHost: Int] = [:]
    private var waiters: [DiscoveryHost: [CheckedContinuation<Void, Never>]] = [:]

    /// `intervals` overrides `DiscoveryHost.minimumInterval` (tests pass small values or zero).
    public init(intervals: [DiscoveryHost: TimeInterval] = [:]) {
        self.intervals = intervals
    }

    private func interval(_ host: DiscoveryHost) -> TimeInterval { intervals[host] ?? host.minimumInterval }

    public func acquire(_ host: DiscoveryHost) async throws {
        if active[host, default: 0] >= host.maximumConcurrent {
            await withCheckedContinuation { waiters[host, default: []].append($0) }
        } else {
            active[host, default: 0] += 1
        }
        let now = Date()
        let start = max(now, nextStart[host] ?? now)
        nextStart[host] = start.addingTimeInterval(interval(host))
        let wait = start.timeIntervalSince(now)
        if wait > 0 {
            do { try await Task.sleep(for: .seconds(wait)) }
            catch { release(host); throw error }
        }
    }

    public func release(_ host: DiscoveryHost) {
        if var queue = waiters[host], !queue.isEmpty {
            let next = queue.removeFirst()
            waiters[host] = queue
            next.resume()   // the slot passes to the waiter
        } else {
            active[host, default: 1] -= 1
        }
    }
}

/// A response cache keyed by request, with a time to live per read. Memory always; disk too when given a directory
/// (under the system Caches directory in the app, nil in tests).
public actor DiscoveryCache {
    private struct Entry { var data: Data; var date: Date }
    private let directory: URL?
    private let now: @Sendable () -> Date
    private var memory: [String: Entry] = [:]

    public init(directory: URL? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.now = now
    }

    /// `Caches/Iter/Discovery`, or nil if the system gives no Caches directory.
    public static var defaultDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Iter", isDirectory: true).appendingPathComponent("Discovery", isDirectory: true)
    }

    public func data(for key: String, maxAge: TimeInterval) -> Data? {
        if let e = memory[key] {
            if now().timeIntervalSince(e.date) < maxAge { return e.data }
            memory[key] = nil
        }
        guard let url = fileURL(key),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attributes[.modificationDate] as? Date,
              now().timeIntervalSince(date) < maxAge,
              let data = try? Data(contentsOf: url) else { return nil }
        memory[key] = Entry(data: data, date: date)
        return data
    }

    public func store(_ data: Data, for key: String) {
        let date = now()
        memory[key] = Entry(data: data, date: date)
        guard let directory, let url = fileURL(key) else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        } catch {
            // A cache that cannot persist is still a working cache.
        }
    }

    public func removeAll() {
        memory.removeAll()
        guard let directory, let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for f in files where f.pathExtension == "cache" { try? FileManager.default.removeItem(at: f) }
    }

    private func fileURL(_ key: String) -> URL? {
        guard let directory else { return nil }
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest + ".cache")
    }
}

/// Everything the providers share for talking to the network: the transport, an honest User-Agent,
/// per-host spacing, timeouts and the response cache.
public struct DiscoveryHTTP: Sendable {
    public static let timeout: TimeInterval = 10

    /// `Iter/<version or dev> (photography trip planner; https://github.com/dwjames88)`. No email, no user name.
    public static func userAgent(version: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) -> String {
        let v = (version?.isEmpty == false) ? version! : "dev"
        return "Iter/\(v) (photography trip planner; https://github.com/dwjames88)"
    }

    private let transport: any HTTPTransport
    private let limiter: DiscoveryRateLimiter
    private let cache: DiscoveryCache
    private let agent: String

    public init(transport: any HTTPTransport, cache: DiscoveryCache = DiscoveryCache(), limiter: DiscoveryRateLimiter = DiscoveryRateLimiter(),
                userAgent: String = DiscoveryHTTP.userAgent()) {
        self.transport = transport
        self.cache = cache
        self.limiter = limiter
        self.agent = userAgent
    }

    /// GET. Served from the cache when fresh. `isCacheable` lets a provider keep a bad 200 (an HTML error page) out of it.
    public func get(_ url: URL, host: DiscoveryHost, accept: String = "application/json", isCacheable: @Sendable (Data) -> Bool = { _ in true }) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: Self.timeout)
        request.httpMethod = "GET"
        request.setValue(accept, forHTTPHeaderField: "Accept")
        return try await perform(request, host: host, cacheKey: url.absoluteString, isCacheable: isCacheable)
    }

    /// POST of a form (`application/x-www-form-urlencoded`).
    public func post(_ url: URL, form: [String: String], host: DiscoveryHost, isCacheable: @Sendable (Data) -> Bool = { _ in true }) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: Self.timeout)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body = form.keys.sorted().map { Self.formEncode($0) + "=" + Self.formEncode(form[$0] ?? "") }.joined(separator: "&")
        request.httpBody = Data(body.utf8)
        return try await perform(request, host: host, cacheKey: url.absoluteString + "?" + body, isCacheable: isCacheable)
    }

    private func perform(_ request: URLRequest, host: DiscoveryHost, cacheKey: String, isCacheable: @Sendable (Data) -> Bool) async throws -> Data {
        if let hit = await cache.data(for: cacheKey, maxAge: host.timeToLive) { return hit }
        var request = request
        request.setValue(agent, forHTTPHeaderField: "User-Agent")
        try await limiter.acquire(host)
        let data: Data, status: Int
        do {
            let (body, response) = try await transport.data(for: request)
            data = body; status = response.statusCode
        } catch {
            await limiter.release(host)
            if error is CancellationError { throw error }
            throw DiscoveryError.map(error)
        }
        await limiter.release(host)
        switch status {
        case 200..<300: break
        case 404: throw DiscoveryError.notFound
        case 403, 429: throw DiscoveryError.rateLimited
        case 502, 503, 504: throw DiscoveryError.busy
        default: throw DiscoveryError.http(status)
        }
        if isCacheable(data) { await cache.store(data, for: cacheKey) }
        return data
    }

    static func formEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? s
    }

    /// Builds a URL from a base and query items, every name and value percent-encoded.
    static func url(_ base: String, _ items: [(String, String)]) -> URL? {
        let query = items.map { formEncode($0.0) + "=" + formEncode($0.1) }.joined(separator: "&")
        return URL(string: base + (query.isEmpty ? "" : "?" + query))
    }
}
