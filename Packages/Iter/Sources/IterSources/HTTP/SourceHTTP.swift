import Foundation
import IterModel

/// The real `HTTPClient`. Per request it: answers from the memo when `Expires` has not passed (`honourExpires`),
/// waits its turn per host (`RateLimiter`), sets the User-Agent and validators, runs one attempt under the policy
/// timeout, and retries 429/502/503/504, timeouts and dropped connections with exponential backoff (or `Retry-After`).
///
/// Timeouts: each attempt sets `URLRequest.timeoutInterval` to the policy timeout and is also raced against a real
/// timer of the same length, so a transport that ignores the request timeout still ends. The timer uses
/// `Task.sleep`, not the injected clock, because the injected clock may be a manual one that never really waits.
public actor SourceHTTP: HTTPClient {
    /// Longest backoff between attempts.
    public static let maxBackoff: Duration = .seconds(60)
    /// A `Retry-After` longer than this is not waited for: the call fails with `.rateLimited(retryAfter:)` at once.
    public static let maxRetryAfter: Duration = .seconds(120)

    private struct MemoKey: Hashable {
        let method: String
        let url: URL
        let body: Data?
    }

    private struct Memo {
        var etag: String?
        var lastModified: String?
        var expires: Date?
        var headers: [String: String]
        var body: Data
        var url: URL
        var lastUsed: UInt64
    }

    private let transport: any HTTPTransport
    private let clock: any SourceClock
    private let limiter: RateLimiter
    private let userAgent: String
    private let jitter: @Sendable () -> Double
    private let memoCapacity: Int
    private var memo: [MemoKey: Memo] = [:]
    private var useCounter: UInt64 = 0

    /// - Parameters:
    ///   - jitter: multiplier applied to each backoff (default 0.8...1.2 random); tests pass `{ 1 }`.
    ///   - memoCapacity: most conditional-request memos kept (least recently used evicted).
    public init(transport: any HTTPTransport = URLSessionTransport(), clock: any SourceClock = SystemSourceClock(),
                userAgent: UserAgent = .current, limiter: RateLimiter? = nil,
                jitter: @escaping @Sendable () -> Double = { Double.random(in: 0.8...1.2) }, memoCapacity: Int = 200) {
        self.transport = transport
        self.clock = clock
        self.limiter = limiter ?? RateLimiter(clock: clock)
        self.userAgent = userAgent.headerValue
        self.jitter = jitter
        self.memoCapacity = max(1, memoCapacity)
    }

    public func send(_ request: SourceRequest) async throws -> SourceResponse {
        let policy = request.policy
        let memoKey = MemoKey(method: request.method, url: request.url, body: request.body)
        if policy.honourExpires, let m = touch(memoKey), let expires = m.expires, expires > clock.now {
            return SourceResponse(status: 200, headers: m.headers, body: m.body, url: m.url, receivedAt: clock.now,
                                  fromMemo: true)
        }
        let host = request.url.host?.lowercased() ?? request.url.absoluteString
        var attempt = 0
        while true {
            if Task.isCancelled { throw SourceError.cancelled }
            let validators = policy.conditional ? touch(memoKey) : nil
            let urlRequest = build(request, validators: validators)
            let outcome: Outcome
            do {
                let permit = try await limiter.acquire(key: host, policy: policy)
                do {
                    let (data, http) = try await attemptWithTimeout(urlRequest, timeout: policy.timeout)
                    await limiter.release(permit)
                    outcome = .response(data, http)
                } catch {
                    await limiter.release(permit)
                    outcome = .failure(error)
                }
            } catch {
                throw SourceError.wrap(error)
            }

            switch outcome {
            case .response(let data, let http):
                let status = http.statusCode
                let headers = Self.headers(http)
                if (200..<300).contains(status) {
                    remember(memoKey, policy: policy, headers: headers, body: data, url: http.url ?? request.url)
                    return SourceResponse(status: status, headers: headers, body: data, url: http.url ?? request.url,
                                          receivedAt: clock.now)
                }
                if status == 304, let m = touch(memoKey), policy.conditional {
                    refreshMemo(memoKey, headers: headers)
                    let merged = memo[memoKey]?.headers ?? m.headers
                    return SourceResponse(status: 200, headers: merged, body: m.body, url: m.url,
                                          receivedAt: clock.now, revalidated: true)
                }
                let retryAfter = Self.retryAfter(headers["retry-after"], now: clock.now)
                if [429, 502, 503, 504].contains(status) {
                    if let ra = retryAfter, ra.duration > Self.maxRetryAfter { throw Self.statusError(status, data, ra.date) }
                    if attempt < policy.maxRetries {
                        try await backoff(attempt: attempt, policy: policy, retryAfter: retryAfter?.duration)
                        attempt += 1
                        continue
                    }
                }
                throw Self.statusError(status, data, retryAfter?.date)
            case .failure(let error):
                let wrapped = SourceError.wrap(error)
                let retryable = (error as? URLError).map { $0.code == .timedOut || $0.code == .networkConnectionLost } ?? false
                if retryable, attempt < policy.maxRetries {
                    try await backoff(attempt: attempt, policy: policy, retryAfter: nil)
                    attempt += 1
                    continue
                }
                throw wrapped
            }
        }
    }

    // MARK: Attempts

    private enum Outcome {
        case response(Data, HTTPURLResponse)
        case failure(any Error)
    }

    private func build(_ request: SourceRequest, validators: Memo?) -> URLRequest {
        var r = URLRequest(url: request.url, cachePolicy: .reloadIgnoringLocalCacheData,
                           timeoutInterval: max(0.001, request.policy.timeout.timeInterval))
        r.httpMethod = request.method
        r.httpBody = request.body
        r.httpShouldHandleCookies = false
        for (k, v) in request.headers { r.setValue(v, forHTTPHeaderField: k) }
        if let v = validators {
            if let etag = v.etag, r.value(forHTTPHeaderField: "If-None-Match") == nil {
                r.setValue(etag, forHTTPHeaderField: "If-None-Match")
            }
            if let lm = v.lastModified, r.value(forHTTPHeaderField: "If-Modified-Since") == nil {
                r.setValue(lm, forHTTPHeaderField: "If-Modified-Since")
            }
        }
        r.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return r
    }

    private func attemptWithTimeout(_ request: URLRequest, timeout: Duration) async throws -> (Data, HTTPURLResponse) {
        let transport = self.transport
        return try await withThrowingTaskGroup(of: (Data, HTTPURLResponse).self) { group in
            group.addTask { try await transport.data(for: request) }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw URLError(.unknown) }
            return first
        }
    }

    private func backoff(attempt: Int, policy: RequestPolicy, retryAfter: Duration?) async throws {
        let delay: Duration
        if let retryAfter {
            delay = retryAfter
        } else {
            let base = policy.initialBackoff.timeInterval * pow(2, Double(attempt)) * jitter()
            delay = .interval(min(base, Self.maxBackoff.timeInterval))
        }
        do { try await clock.sleep(for: delay) } catch { throw SourceError.wrap(error) }
    }

    // MARK: Memo

    private func touch(_ key: MemoKey) -> Memo? {
        guard var m = memo[key] else { return nil }
        useCounter += 1
        m.lastUsed = useCounter
        memo[key] = m
        return m
    }

    private func remember(_ key: MemoKey, policy: RequestPolicy, headers: [String: String], body: Data, url: URL) {
        let etag = headers["etag"]
        let lastModified = headers["last-modified"]
        let expires = policy.honourExpires ? headers["expires"].flatMap(HTTPDate.parse) : nil
        let usable = (policy.conditional && (etag != nil || lastModified != nil)) || expires != nil
        guard usable else {
            memo[key] = nil
            return
        }
        useCounter += 1
        memo[key] = Memo(etag: etag, lastModified: lastModified, expires: expires, headers: headers, body: body, url: url,
                         lastUsed: useCounter)
        while memo.count > memoCapacity, let oldest = memo.min(by: { $0.value.lastUsed < $1.value.lastUsed })?.key {
            memo[oldest] = nil
        }
    }

    /// A 304 may carry fresh `Expires`, `ETag` or `Last-Modified`; fold them into the memo.
    private func refreshMemo(_ key: MemoKey, headers: [String: String]) {
        guard var m = memo[key] else { return }
        if let e = headers["etag"] { m.etag = e; m.headers["etag"] = e }
        if let l = headers["last-modified"] { m.lastModified = l; m.headers["last-modified"] = l }
        if let x = headers["expires"] { m.expires = HTTPDate.parse(x); m.headers["expires"] = x }
        memo[key] = m
    }

    // MARK: Helpers

    private static func headers(_ http: HTTPURLResponse) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in http.allHeaderFields {
            if let k = k as? String, let v = v as? String { out[k.lowercased()] = v }
        }
        return out
    }

    /// `Retry-After` as delta-seconds or an HTTP date.
    private static func retryAfter(_ value: String?, now: Date) -> (duration: Duration, date: Date)? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        if let seconds = Double(value), seconds >= 0 {
            return (.interval(seconds), now.addingTimeInterval(seconds))
        }
        if let date = HTTPDate.parse(value) {
            return (.interval(max(0, date.timeIntervalSince(now))), date)
        }
        return nil
    }

    private static func statusError(_ status: Int, _ body: Data, _ retryAfter: Date?) -> SourceError {
        if status == 429 { return .rateLimited(retryAfter: retryAfter) }
        let text = String(decoding: body, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return .http(status: status, excerpt: text.isEmpty ? nil : String(text.prefix(300)))
    }
}
