import Foundation
import Synchronization
import Testing
import IterModel
import IterSources
import IterSourcesLive
import IterSky
import IterAstro
@testable import IterConditions

// ConditionsService over the REAL NOMADS (batch, standard tiles), HRRR smoke and MET Norway adapters, one real SourceHTTP
// (the catalogue policies: per-host spacing, in-flight caps, 50 a minute for NOMADS) on a fake transport. The transport
// answers NOMADS filter URLs with a synthetic GRIB2 file for the requested box, cycle and hour, and MET Norway URLs with the
// recorded fixture shifted to the virtual now, each after a simulated 400 ms.

private enum Host: String { case nomads = "nomads.ncep.noaa.gov", met = "api.met.no" }

private final class BudgetTransport: HTTPTransport {
    struct NomadsEntry: Sendable { var ref: NOMADSFileRef; var box: NOMADSBox; var at: Date }
    private struct State { var nomads: [NomadsEntry] = []; var met: [(URL, Date)] = []; var other: [URL] = [] }
    private let state = Mutex(State())
    private let clock: any SourceClock
    private let latency: Duration
    private let metBody: @Sendable () -> Data

    init(clock: any SourceClock, latency: Duration = .milliseconds(400), metBody: @escaping @Sendable () -> Data) {
        self.clock = clock
        self.latency = latency
        self.metBody = metBody
    }

    var nomads: [NomadsEntry] { state.withLock { $0.nomads } }
    var metURLs: [URL] { state.withLock { $0.met.map(\.0) } }
    var other: [URL] { state.withLock { $0.other } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else { throw URLError(.badURL) }
        try await clock.sleep(for: latency)
        switch url.host {
        case Host.nomads.rawValue:
            guard let r = SyntheticNOMADS.parse(url) else { throw URLError(.badURL) }
            state.withLock { $0.nomads.append(NomadsEntry(ref: r.ref, box: r.box, at: clock.now)) }
            return (SyntheticNOMADS.file(for: r), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [:])!)
        case Host.met.rawValue:
            state.withLock { $0.met.append((url, clock.now)) }
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = .gmt
            f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
            let headers = ["Content-Type": "application/json", "Expires": f.string(from: clock.now.addingTimeInterval(900)),
                           "Last-Modified": f.string(from: clock.now)]
            return (metBody(), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)!)
        default:
            state.withLock { $0.other.append(url) }
            throw URLError(.badURL)
        }
    }
}

/// The recorded MET Norway answer with every timestamp moved by whole hours so its first row is `firstHour`.
private func shiftedMetFixture(firstHour: Date) -> Data {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("IterSourcesLiveTests/Fixtures/MetNo/locationforecast-S.json")
    let original = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    let fmt = ISO8601DateFormatter()
    fmt.formatOptions = [.withInternetDateTime]
    let first = fmt.date(from: "2026-11-22T13:00:00Z")!
    let shift = (firstHour.timeIntervalSince(first) / 3600).rounded() * 3600
    let regex = try! NSRegularExpression(pattern: "\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z")
    var out = ""
    var last = original.startIndex
    for m in regex.matches(in: original, range: NSRange(original.startIndex..., in: original)) {
        guard let r = Range(m.range, in: original), let d = fmt.date(from: String(original[r])) else { continue }
        out += original[last..<r.lowerBound] + fmt.string(from: d.addingTimeInterval(shift))
        last = r.upperBound
    }
    out += original[last...]
    return Data(out.utf8)
}

private struct Outcome {
    var name: String
    var nomadsRequests: Int
    var nomadsDistinctTiles: Int
    var nomadsDistinctFiles: Int
    var metRequests: Int
    var firstScores: [TimeInterval]
    var nearTermAll: TimeInterval
    var complete: TimeInterval
    var reports: Int
}

/// 2026-11-22 14:17 UTC.
private let budgetNow = Date(timeIntervalSince1970: 1_795_305_600 + 14 * 3600 + 17 * 60)

@Suite("Real adapter budget", .serialized)
struct RealAdapterBudgetTests {
    static let lonePine = Coordinate(latitude: 36.6, longitude: -118.06)

    static var twenty: [Coordinate] {
        (0..<20).map { i in
            if i == 0 { return lonePine }
            let r = 0.36 * (Double(i) / 19).squareRoot()
            let a = Double(i) * 2.399963
            return Coordinate(latitude: lonePine.latitude + r * cos(a), longitude: lonePine.longitude + r * sin(a) / cos(lonePine.latitude * .pi / 180))
        }
    }

    /// Lone Pine, Death Valley, Las Vegas, Zion, Bryce, Page.
    static let trip = [lonePine, Coordinate(latitude: 36.46, longitude: -116.87), Coordinate(latitude: 36.17, longitude: -115.14),
                       Coordinate(latitude: 37.30, longitude: -113.03), Coordinate(latitude: 37.59, longitude: -112.18),
                       Coordinate(latitude: 36.91, longitude: -111.46)]

    private func place(_ name: String, _ c: Coordinate, tz: String = "America/Los_Angeles") -> Place {
        makePlace(name, lat: c.latitude, lon: c.longitude, tz: tz)
    }

    private func run(_ name: String, _ build: (VirtualClock) -> [ConditionsRequest]) async -> Outcome {
        let clock = VirtualClock(now: budgetNow)
        let body = shiftedMetFixture(firstHour: floorHour(budgetNow))
        let transport = BudgetTransport(clock: clock, metBody: { body })
        let http = SourceHTTP(transport: transport, clock: clock, userAgent: UserAgent(version: "test"), jitter: { 1 })
        let blobs = InMemoryBlobCache(clock: clock)
        // The NOMADS engine plans cycles from its own clock; it is pinned so every call plans the same cycles.
        let pinned = ManualSourceClock(now: budgetNow)
        let nomads = NOMADSForecastProvider(http: http, clock: pinned, cache: blobs)
        let smoke = HRRRSmokeProvider(sharing: nomads)
        let met = MetNorwayProvider(http: http, clock: clock)
        let sources: [any SourceDescribing] = [nomads, smoke, met]
        var cfg = ConditionsConfiguration()
        cfg.fetchesHorizon = false
        let service = ConditionsService(ConditionsDependencies(
            registry: SourceRegistry(sources: sources), cache: SourceCache(clock: clock), clock: clock, ephemeris: Astronomy(), configuration: cfg))
        let requests = build(clock)
        let start = clock.now
        struct Timing: Sendable { var first: [UUID: TimeInterval] = [:]; var near: [String: TimeInterval] = [:]; var complete: [String: TimeInterval] = [:] }
        let timing = await clock.drive {
            var t = Timing()
            for await r in service.reports(for: requests) {
                let at = clock.now.timeIntervalSince(start)
                if t.first[r.placeID] == nil, r.daylight.windows.contains(where: { $0.score != nil }) { t.first[r.placeID] = at }
                if r.tier >= .nearTerm, t.near[r.id] == nil { t.near[r.id] = at }
                if r.tier == .complete, t.complete[r.id] == nil { t.complete[r.id] = at }
            }
            return t
        }
        let entries = transport.nomads
        #expect(transport.other.isEmpty)
        return Outcome(name: name, nomadsRequests: entries.count, nomadsDistinctTiles: Set(entries.map { "\($0.box.south),\($0.box.west)" }).count,
                       nomadsDistinctFiles: Set(entries.map { "\($0.ref.model)|\($0.ref.cycle)|\($0.ref.forecastHour)|\($0.box.south),\($0.box.west)" }).count,
                       metRequests: transport.metURLs.count, firstScores: timing.first.values.sorted(),
                       nearTermAll: timing.near.values.max() ?? 0, complete: timing.complete.values.max() ?? 0, reports: timing.complete.count)
    }

    private func row(_ o: Outcome) -> String {
        func m(_ s: TimeInterval) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
        let f = o.firstScores
        let median = f.isEmpty ? 0 : f[f.count / 2]
        return o.name.padding(toLength: 22, withPad: " ", startingAt: 0)
            + String(format: "| NOMADS %4d (%d tiles) | MET %2d | first score min/med/max %@ / %@ / %@ | nearTerm all %@ | complete %@",
                     o.nomadsRequests, o.nomadsDistinctTiles, o.metRequests, m(f.first ?? 0), m(median), m(f.last ?? 0),
                     m(o.nearTermAll), m(o.complete))
    }

    private func check(_ o: Outcome, places: Int, metCells: Int) {
        #expect(o.reports == places)
        // Every NOMADS file once: no repeats, and never more than tiles x distinct (model, cycle, hour).
        #expect(o.nomadsRequests == o.nomadsDistinctFiles)
        #expect(o.metRequests == metCells)
        #expect(o.firstScores.count == places)
        #expect((o.firstScores.last ?? .infinity) <= o.complete)
    }

    @Test func onePlace() async {
        let p = place("Lone Pine", Self.lonePine)
        let o = await run("1 place") { _ in [ConditionsRequest(place: p, day: localDay(of: p, at: budgetNow))] }
        print("BUDGET " + row(o))
        check(o, places: 1, metCells: 1)
        #expect(o.nomadsDistinctTiles <= 2)
    }

    @Test func twentyPlacesNearLonePine() async {
        let places = Self.twenty.enumerated().map { place("P\($0)", $1) }
        let day = localDay(of: places[0], at: budgetNow)
        let cells = Set(Self.twenty.map { GeoCell.key($0, degrees: 0.01) }).count
        let o = await run("20 places, 40 km") { _ in places.map { ConditionsRequest(place: $0, day: day) } }
        print("BUDGET " + row(o))
        check(o, places: 20, metCells: cells)
        // Shared tiles: far fewer files than twenty separate places would need.
        #expect(o.nomadsDistinctTiles <= 4)
    }

    @Test func sixStopTripAcross500Km() async {
        let zones = ["America/Los_Angeles", "America/Los_Angeles", "America/Los_Angeles", "America/Denver", "America/Denver", "America/Phoenix"]
        let stops = Self.trip.enumerated().map { place("Stop \($0)", $1, tz: zones[$0]) }
        let first = localDay(of: stops[0], at: budgetNow)
        let o = await run("6-stop trip, 500 km") { _ in
            stops.enumerated().map { i, p in ConditionsRequest(place: p, day: first.adding(days: i / 2), priority: i == 0 ? .activeTrip : .pinnedTrip) }
        }
        print("BUDGET " + row(o))
        check(o, places: 6, metCells: 6)
    }
}
