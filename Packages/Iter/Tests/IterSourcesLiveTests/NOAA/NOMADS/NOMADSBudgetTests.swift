import Foundation
import Synchronization
import Testing
import IterModel
import IterSources
import IterSourcesLive

// Measures what a set of places costs against NOMADS's polite limit, old per-cell geometry against the tiles.
//
// A real `SourceHTTP` (the catalogue's NOMADS policy: 600 ms spacing, 2 in flight, 50 a minute) sits on a fake transport
// that answers every filter URL after a simulated 400 ms with a synthetic GRIB2 file built for the requested box
// (`SyntheticNOMADS`: a lat/lon grid, also for HRRR, instead of the Lambert grid; the decoder samples both the same way).
// A `ManualSourceClock` drives the limiter and the latency. A manual clock serialises concurrent sleeps (two waits add
// instead of overlapping), so every virtual time printed is an UPPER BOUND on what two parallel requests would take.
//
// The provider's own clock is held at 14:17 so every call plans the same cycles however much virtual time has passed.

private final class LatencyTransport: HTTPTransport {
    struct Entry: Sendable { let ref: NOMADSFileRef; let box: NOMADSBox; let at: Date }
    private let clock: ManualSourceClock
    private let latency: Duration
    private let log = Mutex<[Entry]>([])

    init(clock: ManualSourceClock, latency: Duration = .milliseconds(400)) {
        self.clock = clock
        self.latency = latency
    }

    var entries: [Entry] { log.withLock { $0 } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url, let r = SyntheticNOMADS.parse(url) else { throw URLError(.badURL) }
        try await clock.sleep(for: latency)
        log.withLock { $0.append(Entry(ref: r.ref, box: r.box, at: clock.now)) }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [:])!
        return (SyntheticNOMADS.file(for: r), response)
    }
}

private let now = NOMADSTest.at(14, 17)

private struct Measure {
    var requests = 0
    var firstNearTerm: TimeInterval = 0
    var allNearTerm: TimeInterval = 0
    var complete: TimeInterval = 0
    var megabytes = 0.0
}

/// Scaled from the recorded fixtures: HRRR 18.9 KB and GFS 1.87 KB per square degree of box (NOMADSTiling's table).
private func estimatedKB(_ box: NOMADSBox, _ model: NOMADSModel) -> Double {
    (box.north - box.south) * (box.east - box.west) * (model == .hrrr ? 18.9 : 1.87)
}

private func measure(_ points: [Coordinate], hours: Double, tiling: NOMADSTiling, batch: Bool) async throws -> Measure {
    let clock = ManualSourceClock(now: now)
    let transport = LatencyTransport(clock: clock)
    let http = SourceHTTP(transport: transport, clock: clock, userAgent: UserAgent(version: "test"), jitter: { 1 })
    let cache = InMemoryBlobCache(clock: clock)
    let provider = NOMADSForecastProvider(http: http, clock: ManualSourceClock(now: now), cache: cache, tiling: tiling)
    let span = TimeSpan(start: NOMADSTest.at(14), end: NOMADSTest.at(14).addingTimeInterval(hours * 3600))
    if batch {
        let results = await provider.forecasts(at: points, span: span)
        for p in points { #expect((try? results[p]?.get()) != nil, "no series for \(p)") }
    } else {
        // How callers had to do it: one call per place, sharing a cache (places in one cell share its files).
        for p in points { _ = try await provider.forecast(at: p, span: span) }
    }
    let entries = transport.entries
    var m = Measure()
    m.requests = entries.count
    m.complete = (entries.map(\.at).max() ?? now).timeIntervalSince(now)
    // The first place's own near-term series (12 h) is complete when its tile has delivered every hour up to now + 12 h.
    let end12 = NOMADSTest.at(14).addingTimeInterval(12 * 3600)
    func nearTerm(of p: Coordinate) -> TimeInterval {
        let tile = NOMADSRequestBuilder.box(for: p, model: .hrrr, tiling: tiling)
        return (entries.filter { $0.box == tile && $0.ref.validTime <= end12 }.map(\.at).max() ?? now).timeIntervalSince(now)
    }
    m.firstNearTerm = nearTerm(of: points[0])
    m.allNearTerm = points.map(nearTerm).max() ?? 0
    m.megabytes = entries.reduce(0) { $0 + estimatedKB($1.box, $1.ref.model) } / 1000
    return m
}

private func clock(_ seconds: TimeInterval) -> String {
    let s = Int(seconds.rounded())
    return String(format: "%d:%02d", s / 60, s % 60)
}

@Suite struct NOMADSBudgetTests {
    static let lonePine = Coordinate(latitude: 36.6, longitude: -118.06)

    /// 20 places spread over a 40 km radius around Lone Pine (a golden-angle spiral; Lone Pine is the first).
    static var twenty: [Coordinate] {
        let center = lonePine
        return (0..<20).map { i in
            if i == 0 { return center }
            let r = 0.36 * (Double(i) / 19).squareRoot()  // degrees of latitude, about 40 km at most
            let a = Double(i) * 2.399963
            return Coordinate(latitude: center.latitude + r * cos(a),
                              longitude: center.longitude + r * sin(a) / cos(center.latitude * .pi / 180))
        }
    }

    /// Lone Pine, Death Valley, Las Vegas, Zion, Bryce, Page: about 500 km as the crow flies.
    static let trip = [lonePine, Coordinate(latitude: 36.46, longitude: -116.87), Coordinate(latitude: 36.17, longitude: -115.14),
                       Coordinate(latitude: 37.30, longitude: -113.03), Coordinate(latitude: 37.59, longitude: -112.18),
                       Coordinate(latitude: 36.91, longitude: -111.46)]

    @Test func fortyPlacesAreWithinFortyKilometres() {
        for p in Self.twenty { #expect(Self.lonePine.distance(to: p) < 41_000, "\(p)") }
        #expect(Self.twenty.count == 20 && Set(Self.twenty).count == 20)
        #expect(Self.trip[0].distance(to: Self.trip[5]) > 400_000)
    }

    @Test func requestsAndVirtualTime() async throws {
        let policy = SourceCatalogue.noaaNOMADS.policy
        #expect(policy.perMinute == 50 && policy.spacing == .milliseconds(600) && policy.maxConcurrent == 2)
        let scenarios: [(String, [Coordinate])] = [("1 place", [Self.lonePine]), ("20 places", Self.twenty), ("6-stop trip", Self.trip)]
        let spans: [(String, Double)] = [("12 h", 12), ("48 h", 48), ("10 d", 240)]
        var lines: [String] = []
        for (name, points) in scenarios {
            for (spanName, hours) in spans {
                let old = try await measure(points, hours: hours, tiling: .legacy, batch: false)
                let new = try await measure(points, hours: hours, tiling: .standard, batch: true)
                func cells(_ m: Measure) -> String {
                    [String(m.requests).pad(5), clock(m.firstNearTerm).pad(6), clock(m.allNearTerm).pad(6), clock(m.complete).pad(6),
                     String(format: "%6.2f", m.megabytes)].joined(separator: " ")
                }
                lines.append("\(name.padRight(12)) \(spanName.padRight(5)) | \(cells(old)) | \(cells(new))")
                // Never more requests than the old geometry; fewer when places share a tile.
                #expect(new.requests <= old.requests, "\(name) \(spanName)")
                if name == "20 places" { #expect(new.requests * 2 < old.requests, "\(name) \(spanName)") }

                // The batch request count is tiles x hours planned: every planned hour once per distinct tile of its model.
                let plan = NOMADSCyclePlanner.plan(span: TimeSpan(start: NOMADSTest.at(14), end: NOMADSTest.at(14).addingTimeInterval(hours * 3600)), now: now)
                func tiles(_ model: NOMADSModel) -> Int { Set(points.map { NOMADSRequestBuilder.box(for: $0, model: model) }).count }
                let expected = plan.hours.reduce(0) { $0 + tiles($1.primary?.model ?? .gfs) }
                #expect(new.requests == expected, "\(name) \(spanName): \(new.requests) requests, \(expected) = tiles x hours expected")
            }
        }
        print("""

        NOMADS request budget. Simulated latency 400 ms, real SourceHTTP policy (600 ms spacing, 2 in flight, 50 a minute).
        Virtual times (m:ss) come from a manual clock that serialises concurrent sleeps, so they are UPPER BOUNDS.
        t12 = until the first place's own 12 h series is complete; t12all = until every place's is; done = until everything is
        fetched (a 10 d span plans 3-hourly times, so its 12 h series is only 4 files). MB are estimates
        scaled from the fixtures (HRRR 18.9 KB, GFS 1.87 KB per square degree of box). OLD = one call per place on 0.25/0.5 degree
        cells with a shared cache; NEW = one batch call on 1/2 degree tiles.
        \("scenario     span  |  OLD req    t12 t12all   done     MB |  NEW req    t12 t12all   done     MB")
        \(lines.joined(separator: "\n"))

        """)
    }
}

private extension String {
    func pad(_ n: Int) -> String { String(repeating: " ", count: max(0, n - count)) + self }
    func padRight(_ n: Int) -> String { self + String(repeating: " ", count: max(0, n - count)) }
}
