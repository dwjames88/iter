import Foundation
import Testing
import IterModel
@testable import IterSources

@Suite("SourceHTTP")
struct SourceHTTPTests {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    static let quick = RequestPolicy(spacing: .zero, maxConcurrent: 4, timeout: .seconds(20), maxRetries: 2,
                                     initialBackoff: .seconds(2), conditional: true, honourExpires: false)

    func make(_ transport: FakeTransport, clock: ManualSourceClock = ManualSourceClock(now: t0),
              ua: UserAgent = UserAgent(version: "1.2", contact: nil)) -> SourceHTTP {
        SourceHTTP(transport: transport, clock: clock, userAgent: ua, jitter: { 1 })
    }

    func request(_ url: String = "https://a.example/x", policy: RequestPolicy = quick) -> SourceRequest {
        SourceRequest(url: URL(string: url)!, source: "test", policy: policy)
    }

    @Test func userAgentIsExactlyIterVersion() async throws {
        let t = FakeTransport(replies: [.status(200, body: "ok")])
        _ = try await make(t).send(request())
        #expect(t.requests[0].value(forHTTPHeaderField: "User-Agent") == "Iter/1.2")
    }

    @Test func userAgentIncludesContactOnlyWhenGiven() async throws {
        let t = FakeTransport(replies: [.status(200)])
        _ = try await make(t, ua: UserAgent(version: "1.2", contact: "x")).send(request())
        #expect(t.requests[0].value(forHTTPHeaderField: "User-Agent") == "Iter/1.2 (x)")
    }

    @Test func adapterCannotOverrideUserAgent() async throws {
        let t = FakeTransport(replies: [.status(200)])
        var r = request()
        r.headers["User-Agent"] = "Someone/9"
        _ = try await make(t).send(r)
        #expect(t.requests[0].value(forHTTPHeaderField: "User-Agent") == "Iter/1.2")
    }

    @Test func requestTimeoutIsPolicyTimeout() async throws {
        let t = FakeTransport(replies: [.status(200)])
        var p = Self.quick
        p.timeout = .seconds(7)
        _ = try await make(t).send(request(policy: p))
        #expect(t.requests[0].timeoutInterval == 7)
    }

    @Test func sameHostIsSpaced() async throws {
        let clock = ManualSourceClock(now: Self.t0)
        let t = FakeTransport(replies: [.status(200)])
        let http = make(t, clock: clock)
        var p = Self.quick
        p.spacing = .seconds(2)
        _ = try await http.send(request("https://a.example/1", policy: p))
        _ = try await http.send(request("https://a.example/2", policy: p))
        #expect(clock.sleeps == [.seconds(2)])
    }

    @Test func differentHostsAreNotSpaced() async throws {
        let clock = ManualSourceClock(now: Self.t0)
        let t = FakeTransport(replies: [.status(200)])
        let http = make(t, clock: clock)
        var p = Self.quick
        p.spacing = .seconds(2)
        _ = try await http.send(request("https://a.example/1", policy: p))
        _ = try await http.send(request("https://b.example/1", policy: p))
        #expect(clock.sleeps.isEmpty)
    }

    @Test func retriesOn502ThenSucceeds() async throws {
        let clock = ManualSourceClock(now: Self.t0)
        let t = FakeTransport(replies: [.status(502), .status(200, body: "fine")])
        let r = try await make(t, clock: clock).send(request())
        #expect(r.status == 200)
        #expect(r.text == "fine")
        #expect(t.callCount == 2)
        #expect(clock.sleeps == [.seconds(2)])
    }

    @Test func backoffDoublesAndGivesUp() async throws {
        let clock = ManualSourceClock(now: Self.t0)
        let t = FakeTransport(replies: [.status(503, body: "busy")])
        do {
            _ = try await make(t, clock: clock).send(request())
            Issue.record("expected a throw")
        } catch let e as SourceError {
            #expect(e == .http(status: 503, excerpt: "busy"))
        }
        #expect(t.callCount == 3)
        #expect(clock.sleeps == [.seconds(2), .seconds(4)])
    }

    @Test func backoffIsCappedAtSixtySeconds() async throws {
        let clock = ManualSourceClock(now: Self.t0)
        var p = Self.quick
        p.initialBackoff = .seconds(40)
        p.maxRetries = 2
        let t = FakeTransport(replies: [.status(504)])
        _ = try? await make(t, clock: clock).send(request(policy: p))
        #expect(clock.sleeps == [.seconds(40), .seconds(60)])
    }

    @Test func noRetryOn404AndExcerptIsBounded() async throws {
        let long = String(repeating: "x", count: 1000)
        let t = FakeTransport(replies: [.status(404, body: long)])
        do {
            _ = try await make(t).send(request())
            Issue.record("expected a throw")
        } catch let e as SourceError {
            guard case .http(let status, let excerpt) = e else { Issue.record("wrong error \(e)"); return }
            #expect(status == 404)
            #expect(excerpt?.count == 300)
        }
        #expect(t.callCount == 1)
    }

    @Test func noRetryOn403() async throws {
        let t = FakeTransport(replies: [.status(403)])
        await #expect(throws: SourceError.http(status: 403, excerpt: nil)) { try await make(t).send(request()) }
        #expect(t.callCount == 1)
    }

    @Test func retryAfterSecondsIsHonoured() async throws {
        let clock = ManualSourceClock(now: Self.t0)
        let t = FakeTransport(replies: [.status(503, headers: ["Retry-After": "7"]), .status(200)])
        _ = try await make(t, clock: clock).send(request())
        #expect(clock.sleeps == [.seconds(7)])
    }

    @Test func retryAfterHttpDateIsHonoured() async throws {
        let clock = ManualSourceClock(now: Self.t0)
        let date = HTTPDate.format(Self.t0.addingTimeInterval(10))
        let t = FakeTransport(replies: [.status(429, headers: ["Retry-After": date]), .status(200)])
        _ = try await make(t, clock: clock).send(request())
        #expect(clock.sleeps == [.seconds(10)])
    }

    @Test func rateLimitedAfterRetriesCarriesRetryAfter() async throws {
        var p = Self.quick
        p.maxRetries = 1
        let t = FakeTransport(replies: [.status(429, headers: ["Retry-After": "3"])])
        do {
            _ = try await make(t).send(request(policy: p))
            Issue.record("expected a throw")
        } catch let e as SourceError {
            guard case .rateLimited(let at) = e else { Issue.record("wrong error \(e)"); return }
            #expect(at != nil)
        }
        #expect(t.callCount == 2)
    }

    @Test func hugeRetryAfterFailsAtOnce() async throws {
        let t = FakeTransport(replies: [.status(429, headers: ["Retry-After": "3600"])])
        await #expect(throws: SourceError.self) { try await make(t).send(request()) }
        #expect(t.callCount == 1)
    }

    @Test func offlineIsMappedWithoutRetry() async throws {
        let t = FakeTransport(replies: [.error(.notConnectedToInternet)])
        await #expect(throws: SourceError.offline) { try await make(t).send(request()) }
        #expect(t.callCount == 1)
    }

    @Test func droppedConnectionRetriesThenMaps() async throws {
        let t = FakeTransport(replies: [.error(.networkConnectionLost)])
        await #expect(throws: SourceError.offline) { try await make(t).send(request()) }
        #expect(t.callCount == 3)
    }

    @Test func conditionalRequestRevalidatesOn304() async throws {
        let t = FakeTransport(replies: [
            .status(200, body: "payload", headers: ["ETag": "\"v1\"", "Last-Modified": "Sat, 15 Nov 2026 10:00:00 GMT"]),
            .status(304),
        ])
        let http = make(t)
        let first = try await http.send(request())
        #expect(first.revalidated == false)
        let second = try await http.send(request())
        #expect(second.status == 200)
        #expect(second.text == "payload")
        #expect(second.revalidated)
        #expect(second.fromMemo == false)
        let sent = t.requests[1]
        #expect(sent.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"")
        #expect(sent.value(forHTTPHeaderField: "If-Modified-Since") == "Sat, 15 Nov 2026 10:00:00 GMT")
        #expect(t.requests[0].value(forHTTPHeaderField: "If-None-Match") == nil)
    }

    @Test func conditionalOffSendsNoValidators() async throws {
        var p = Self.quick
        p.conditional = false
        let t = FakeTransport(replies: [.status(200, headers: ["ETag": "\"v1\""])])
        let http = make(t)
        _ = try await http.send(request(policy: p))
        _ = try await http.send(request(policy: p))
        #expect(t.requests[1].value(forHTTPHeaderField: "If-None-Match") == nil)
    }

    @Test func expiresShortCircuitsUntilItPasses() async throws {
        let clock = ManualSourceClock(now: Self.t0)
        var p = Self.quick
        p.honourExpires = true
        let expires = HTTPDate.format(Self.t0.addingTimeInterval(3600))
        let t = FakeTransport(replies: [.status(200, body: "forecast", headers: ["Expires": expires]),
                                        .status(200, body: "newer", headers: ["Expires": expires])])
        let http = make(t, clock: clock)
        let first = try await http.send(request(policy: p))
        #expect(first.fromMemo == false)
        let second = try await http.send(request(policy: p))
        #expect(second.fromMemo)
        #expect(second.text == "forecast")
        #expect(t.callCount == 1)
        clock.advance(by: .seconds(3601))
        let third = try await http.send(request(policy: p))
        #expect(third.fromMemo == false)
        #expect(third.text == "newer")
        #expect(t.callCount == 2)
    }

    @Test func memoIsBoundedLRU() async throws {
        let t = FakeTransport(replies: [.status(200, body: "x", headers: ["ETag": "\"e\""])])
        let http = SourceHTTP(transport: t, clock: ManualSourceClock(now: Self.t0), userAgent: UserAgent(version: "1"),
                              jitter: { 1 }, memoCapacity: 2)
        for i in 0..<3 { _ = try await http.send(request("https://a.example/\(i)")) }
        _ = try await http.send(request("https://a.example/0"))
        // /0 was evicted by /2, so it goes out without a validator.
        #expect(t.requests[3].value(forHTTPHeaderField: "If-None-Match") == nil)
        _ = try await http.send(request("https://a.example/0"))
        #expect(t.requests[4].value(forHTTPHeaderField: "If-None-Match") == "\"e\"")
    }

    @Test func timeoutMapsToTimedOut() async throws {
        let t = FakeTransport { _, _ in
            try await Task.sleep(for: .seconds(60))
            throw URLError(.badServerResponse)
        }
        var p = Self.quick
        p.timeout = .milliseconds(50)
        p.maxRetries = 0
        await #expect(throws: SourceError.timedOut) { try await make(t).send(request(policy: p)) }
    }

    @Test func timeoutIsRetried() async throws {
        let t = FakeTransport { req, n in
            if n == 0 { try await Task.sleep(for: .seconds(60)) }
            return try FakeTransport.Reply.status(200, body: "late but fine").make(req)
        }
        var p = Self.quick
        p.timeout = .milliseconds(50)
        p.maxRetries = 1
        let r = try await make(t).send(request(policy: p))
        #expect(r.text == "late but fine")
        #expect(t.callCount == 2)
    }

    @Test func cancellationMapsToCancelled() async throws {
        let t = FakeTransport { _, _ in
            try await Task.sleep(for: .seconds(60))
            throw URLError(.badServerResponse)
        }
        let http = make(t)
        let req = request()
        let task = Task { try await http.send(req) }
        #expect(await eventually { t.callCount == 1 })
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("expected a throw")
        } catch {
            #expect(SourceError.wrap(error) == .cancelled)
        }
        #expect(t.callCount == 1)
    }

    @Test func postBodyIsSent() async throws {
        let t = FakeTransport(replies: [.status(200)])
        let r = SourceRequest.postForm(URL(string: "https://a.example/post")!, fields: [("data", "a b")],
                                       from: SourceCatalogue.osmOverpass)
        _ = try await make(t).send(r)
        #expect(t.requests[0].httpMethod == "POST")
        #expect(t.requests[0].httpBody == Data("data=a%20b".utf8))
    }
}

@Suite("RateLimiter")
struct RateLimiterTests {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func perMinuteCapDelaysTheNextStart() async throws {
        let clock = ManualSourceClock(now: Self.t0)
        let limiter = RateLimiter(clock: clock)
        let p = RequestPolicy(spacing: .zero, maxConcurrent: 10, perMinute: 2)
        for _ in 0..<3 {
            let permit = try await limiter.acquire(key: "h", policy: p)
            await limiter.release(permit)
        }
        #expect(clock.sleeps == [.seconds(60)])
    }

    @Test func maxConcurrentBlocksUntilRelease() async throws {
        let limiter = RateLimiter(clock: ManualSourceClock(now: Self.t0))
        let p = RequestPolicy(spacing: .zero, maxConcurrent: 1)
        let first = try await limiter.acquire(key: "h", policy: p)
        let got = Counter()
        let task = Task {
            let permit = try await limiter.acquire(key: "h", policy: p)
            got.increment()
            await limiter.release(permit)
        }
        for _ in 0..<50 { await Task.yield() }
        #expect(got.value == 0)
        await limiter.release(first)
        try await task.value
        #expect(got.value == 1)
        #expect(await limiter.inFlight(for: "h") == 0)
    }

    @Test func cancelledWaiterDoesNotLeakASlot() async throws {
        let limiter = RateLimiter(clock: ManualSourceClock(now: Self.t0))
        let p = RequestPolicy(spacing: .zero, maxConcurrent: 1)
        let first = try await limiter.acquire(key: "h", policy: p)
        let waiter = Task { try await limiter.acquire(key: "h", policy: p) }
        for _ in 0..<20 { await Task.yield() }
        waiter.cancel()
        await #expect(throws: CancellationError.self) { try await waiter.value }
        await limiter.release(first)
        #expect(await limiter.inFlight(for: "h") == 0)
        let again = try await limiter.acquire(key: "h", policy: p)
        await limiter.release(again)
        #expect(await limiter.inFlight(for: "h") == 0)
    }

    @Test func withPermitReleasesOnThrow() async throws {
        let limiter = RateLimiter(clock: ManualSourceClock(now: Self.t0))
        let p = RequestPolicy(spacing: .zero, maxConcurrent: 1)
        await #expect(throws: SourceError.offline) {
            try await limiter.withPermit(key: "h", policy: p) { () async throws -> Int in throw SourceError.offline }
        }
        #expect(await limiter.inFlight(for: "h") == 0)
    }
}
