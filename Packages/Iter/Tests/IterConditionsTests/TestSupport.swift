import Foundation
import Synchronization
import IterModel
import IterSources
import IterSky
import IterAstro
@testable import IterConditions

// MARK: Time and places

/// 2026-06-15 12:00 UTC: 06:00 in Denver, 14:00 in Zurich.
let t0 = Date(timeIntervalSince1970: 1_781_524_800)

func floorHour(_ d: Date) -> Date { Date(timeIntervalSince1970: (d.timeIntervalSince1970 / 3600).rounded(.down) * 3600) }

func makePlace(_ name: String = "Spot", lat: Double = 39.74, lon: Double = -104.99, tz: String = "America/Denver") -> Place {
    Place(name: name, coordinate: Coordinate(latitude: lat, longitude: lon), timeZoneIdentifier: tz, category: .landscape, origin: .user)
}

func swissPlace() -> Place { makePlace("Alp", lat: 46.8, lon: 8.5, tz: "Europe/Zurich") }

func localDay(of place: Place, at now: Date = t0) -> LocalDay { LocalDay(now, in: place.timeZone) }

// MARK: Descriptors

func makeDescriptor(_ id: SourceID, name: String, tier: SourceTier = .government, kinds: Set<DataKind>, coverage: Coverage = .global,
                ranks: [DataKind: Int] = [:], ttl: Duration = .seconds(3600), maxConcurrent: Int = 2, mayStore: Bool = true,
                licence: String = LicenceKey.noaaNCEP) -> SourceDescriptor {
    SourceDescriptor(id: id, name: name, operatorName: name, tier: tier, origin: SourceOrigin(tier: tier, producer: name), kinds: kinds,
                     coverage: coverage, policy: RequestPolicy(spacing: .zero, maxConcurrent: maxConcurrent), cacheTTL: ttl,
                     licence: LicenceTag(key: licence, mayStore: mayStore), ranks: ranks)
}

let usOnly = Coverage.regions([GeoRegion(center: Coordinate(latitude: 40, longitude: -100), latitudeDelta: 30, longitudeDelta: 70)])

let noaaDescriptor = makeDescriptor("test.noaa", name: "NOAA HRRR", kinds: [.forecast], coverage: usOnly, ranks: [.forecast: 10])
let metDescriptor = makeDescriptor("test.met", name: "MET Norway", kinds: [.forecast], ranks: [.forecast: 20], licence: LicenceKey.metNorway)
let smokeDescriptor = makeDescriptor(.noaaHRRRSmoke, name: "NOAA HRRR smoke", kinds: [.smoke, .aerosol], coverage: usOnly,
                                 ranks: [.smoke: 10, .aerosol: 10])

// MARK: Series

struct Recipe: Sendable {
    var cloudTotal: Double? = nil
    var layers: (low: Double, mid: Double, high: Double)? = nil
    var visibility: Double? = nil
    var precip: Double? = nil
    var rh: Double? = nil
    var wind: Double? = nil
    var smoke: Double? = nil
    var aod: Double? = nil

    func row(_ t: Date) -> HourlyConditions {
        HourlyConditions(time: t, cloudTotal: cloudTotal, cloudLow: layers?.low, cloudMid: layers?.mid, cloudHigh: layers?.high,
                         precipChance: precip, visibilityKm: visibility, rhPercent: rh, windMs: wind, aod550: aod, smokeUgm3: smoke)
    }
}

func hourlySeries(_ recipe: Recipe, span: TimeSpan) -> HourlySeries {
    var rows: [HourlyConditions] = []
    var t = floorHour(span.start)
    while t < span.end { rows.append(recipe.row(t)); t = t.addingTimeInterval(3600) }
    return HourlySeries(hours: rows)
}

// MARK: Gates

/// Holds callers until opened; a cancelled waiter is released with `CancellationError`.
final class HoldGate: Sendable {
    private struct State { var open = false; var waiters: [Int: CheckedContinuation<Void, any Error>] = [:]; var next = 0 }
    private let state = Mutex(State())

    func wait() async throws {
        let id = state.withLock { s -> Int in s.next += 1; return s.next }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
                let action = state.withLock { s -> Int in
                    if s.open { return 1 }
                    s.waiters[id] = c
                    return 0
                }
                if action == 1 { c.resume() } else if Task.isCancelled { cancel(id) }
            }
        } onCancel: { cancel(id) }
    }

    private func cancel(_ id: Int) {
        let c = state.withLock { s in s.waiters.removeValue(forKey: id) }
        c?.resume(throwing: CancellationError())
    }

    func open() {
        let ws = state.withLock { s -> [CheckedContinuation<Void, any Error>] in
            s.open = true
            let w = Array(s.waiters.values)
            s.waiters = [:]
            return w
        }
        for c in ws { c.resume() }
    }
}

final class Tally: Sendable {
    private let n = Mutex(0)
    var value: Int { n.withLock { $0 } }
    func bump() { n.withLock { $0 += 1 } }
}

// MARK: Fake providers

/// A single-request forecast source ("MET-like").
final class FakeForecast: ForecastProvider {
    struct Call: Sendable { var coordinate: Coordinate; var span: TimeSpan; var at: Date }
    private struct State { var calls: [Call] = []; var cancelled = 0; var failure: SourceError?; var gate: HoldGate?; var recipe: Recipe }
    let descriptor: SourceDescriptor
    let clock: any SourceClock
    let latency: Duration
    private let state: Mutex<State>

    init(_ descriptor: SourceDescriptor, clock: any SourceClock, recipe: Recipe, latency: Duration = .zero, gate: HoldGate? = nil,
         failure: SourceError? = nil) {
        self.descriptor = descriptor
        self.clock = clock
        self.latency = latency
        state = Mutex(State(failure: failure, gate: gate, recipe: recipe))
    }

    var calls: [Call] { state.withLock { $0.calls } }
    var callCount: Int { state.withLock { $0.calls.count } }
    var cancelledCount: Int { state.withLock { $0.cancelled } }
    func setFailure(_ e: SourceError?) { state.withLock { $0.failure = e } }
    func setRecipe(_ r: Recipe) { state.withLock { $0.recipe = r } }
    func setGate(_ g: HoldGate?) { state.withLock { $0.gate = g } }

    func forecast(at coordinate: Coordinate, span: TimeSpan) async throws -> Sourced<HourlySeries> {
        let (gate, failure, recipe) = state.withLock { s -> (HoldGate?, SourceError?, Recipe) in
            s.calls.append(Call(coordinate: coordinate, span: span, at: clock.now))
            return (s.gate, s.failure, s.recipe)
        }
        do {
            if let gate { try await gate.wait() }
            if latency > .zero { try await clock.sleep(for: latency) }
        } catch {
            state.withLock { $0.cancelled += 1 }
            throw error
        }
        if let failure { throw failure }
        let prov = descriptor.provenance(fetchedAt: clock.now, model: nil, issuedAt: floorHour(clock.now), distanceKm: 2.1)
        return Sourced(value: hourlySeries(recipe, span: span), provenance: prov)
    }
}

/// A batch forecast source ("NOAA-like"): cost is hours x tiles of half a degree.
final class FakeBatch: BatchForecastProvider {
    struct BatchCall: Sendable { var coordinates: [Coordinate]; var span: TimeSpan; var tiles: Int }
    private struct State { var batches: [BatchCall] = []; var singles = 0; var cancelled = 0; var failure: SourceError?; var recipe: Recipe; var gate: HoldGate? }
    let descriptor: SourceDescriptor
    let clock: any SourceClock
    let perRequest: Duration
    private let state: Mutex<State>

    init(_ descriptor: SourceDescriptor, clock: any SourceClock, recipe: Recipe, perRequest: Duration = .zero, gate: HoldGate? = nil,
         failure: SourceError? = nil) {
        self.descriptor = descriptor
        self.clock = clock
        self.perRequest = perRequest
        state = Mutex(State(failure: failure, recipe: recipe, gate: gate))
    }

    var batches: [BatchCall] { state.withLock { $0.batches } }
    var batchCount: Int { state.withLock { $0.batches.count } }
    var requestCount: Int { state.withLock { $0.batches.reduce(0) { $0 + Int($1.span.duration / 3600) * $1.tiles } } }
    var cancelledCount: Int { state.withLock { $0.cancelled } }
    func setFailure(_ e: SourceError?) { state.withLock { $0.failure = e } }

    func forecast(at coordinate: Coordinate, span: TimeSpan) async throws -> Sourced<HourlySeries> {
        let r = await forecasts(at: [coordinate], span: span)
        return try r[coordinate]!.get()
    }

    func forecasts(at coordinates: [Coordinate], span: TimeSpan) async -> [Coordinate: Result<Sourced<HourlySeries>, SourceError>] {
        let tiles = Set(coordinates.map { c in [Int((c.latitude / 0.5).rounded(.down)), Int((c.longitude / 0.5).rounded(.down))] }).count
        let (gate, failure, recipe) = state.withLock { s -> (HoldGate?, SourceError?, Recipe) in
            s.batches.append(BatchCall(coordinates: coordinates, span: span, tiles: tiles))
            return (s.gate, s.failure, s.recipe)
        }
        do {
            if let gate { try await gate.wait() }
            let cost = Int(span.duration / 3600) * tiles
            if perRequest > .zero { try await clock.sleep(for: perRequest * cost) }
        } catch {
            state.withLock { $0.cancelled += 1 }
            return Dictionary(coordinates.map { ($0, Result<Sourced<HourlySeries>, SourceError>.failure(.cancelled)) }, uniquingKeysWith: { a, _ in a })
        }
        var out: [Coordinate: Result<Sourced<HourlySeries>, SourceError>] = [:]
        for c in coordinates {
            if let failure { out[c] = .failure(failure); continue }
            let prov = descriptor.provenance(fetchedAt: clock.now, model: "HRRR", issuedAt: floorHour(clock.now), distanceKm: 1.2)
            out[c] = .success(Sourced(value: hourlySeries(recipe, span: span), provenance: prov))
        }
        return out
    }
}

final class FakeTerrain: TerrainProvider {
    let descriptor: SourceDescriptor
    let clock: any SourceClock
    let fetches = Tally()

    init(clock: any SourceClock) {
        self.clock = clock
        descriptor = makeDescriptor2("test.terrain", kinds: [.horizon, .elevation], licence: LicenceKey.terrainTiles)
    }

    func elevation(at coordinate: Coordinate) async throws -> Sourced<Double> { throw SourceError.noSource }

    func horizon(at coordinate: Coordinate, azimuthStep: Double) async throws -> Sourced<HorizonProfile> {
        fetches.bump()
        return Sourced(value: .flat, provenance: descriptor.provenance(fetchedAt: clock.now))
    }
}

func makeDescriptor2(_ id: SourceID, kinds: Set<DataKind>, licence: String) -> SourceDescriptor {
    makeDescriptor(id, name: id.rawValue, kinds: kinds, ttl: .seconds(86_400), licence: licence)
}

/// Observations, a nowcast, alerts and aurora, each switchable.
final class FakeLive: ObservationProvider, NowcastProvider, AlertProvider, AuroraProvider {
    let descriptor: SourceDescriptor
    let clock: any SourceClock
    private struct State { var observation: WeatherObservation?; var distanceKm = 8.0; var nowcast: [NowcastStep]?; var failure: SourceError? }
    private let state = Mutex(State())
    let obsCalls = Tally()

    init(clock: any SourceClock, observation: WeatherObservation? = nil, nowcast: [NowcastStep]? = nil) {
        self.clock = clock
        descriptor = makeDescriptor2("test.live", kinds: [.observation, .nowcast, .alerts, .aurora], licence: LicenceKey.noaaNWS)
        state.withLock { $0.observation = observation; $0.nowcast = nowcast }
    }

    func setFailure(_ e: SourceError?) { state.withLock { $0.failure = e } }

    func latest(near coordinate: Coordinate, within km: Double, maxAge: Duration) async throws -> [Sourced<WeatherObservation>] {
        obsCalls.bump()
        let (o, d, f) = state.withLock { ($0.observation, $0.distanceKm, $0.failure) }
        if let f { throw f }
        guard let o else { return [] }
        return [Sourced(value: o, provenance: descriptor.provenance(fetchedAt: clock.now, issuedAt: o.time, distanceKm: d))]
    }

    func nowcast(at coordinate: Coordinate) async throws -> Sourced<[NowcastStep]> {
        let (n, f) = state.withLock { ($0.nowcast, $0.failure) }
        if let f { throw f }
        guard let n else { throw SourceError.outsideCoverage }
        return Sourced(value: n, provenance: descriptor.provenance(fetchedAt: clock.now))
    }

    func alerts(at coordinate: Coordinate) async throws -> Sourced<[WeatherAlert]> {
        if let f = state.withLock({ $0.failure }) { throw f }
        return Sourced(value: [], provenance: descriptor.provenance(fetchedAt: clock.now))
    }

    func aurora(at coordinate: Coordinate) async throws -> Sourced<AuroraReading> {
        if let f = state.withLock({ $0.failure }) { throw f }
        return Sourced(value: AuroraReading(probabilityPercent: 3, observedAt: clock.now, forecastFor: clock.now),
                       provenance: descriptor.provenance(fetchedAt: clock.now))
    }

    func kpForecast() async throws -> Sourced<[KpPeriod]> {
        Sourced(value: [KpPeriod(start: clock.now, kp: 2, kind: .predicted)], provenance: descriptor.provenance(fetchedAt: clock.now))
    }
}

/// The honest "no source" slots.
final class FakeNoSource: SkyBrightnessProvider, SeeingProvider {
    let descriptor: SourceDescriptor
    init() { descriptor = makeDescriptor(.noSkyBrightness, name: "none", tier: .device, kinds: [.lightPollution, .seeing], ttl: .seconds(86_400),
                                     licence: LicenceKey.none) }
    func skyBrightness(at coordinate: Coordinate) async throws -> Sourced<SkyBrightness> { throw SourceError.noSource }
    func seeing(at coordinate: Coordinate, span: TimeSpan) async throws -> Sourced<[SeeingEstimate]> { throw SourceError.noSource }
}

// MARK: Environment

struct Env {
    let clock: ManualSourceClock
    let cache: SourceCache
    let service: ConditionsService
}

func makeEnv(_ sources: [any SourceDescribing], clock: ManualSourceClock = ManualSourceClock(now: t0), packDirectory: URL? = nil,
             configuration: ConditionsConfiguration? = nil, cache: SourceCache? = nil) -> Env {
    var cfg = configuration ?? ConditionsConfiguration()
    if configuration == nil {
        cfg.incrementalSources = []
        cfg.smokeOnlyOpticalDepth = [.noaaHRRRSmoke]
    }
    let cache = cache ?? SourceCache(clock: clock)
    let deps = ConditionsDependencies(registry: SourceRegistry(sources: sources), cache: cache, clock: clock, ephemeris: Astronomy(),
                                      packDirectory: packDirectory, configuration: cfg)
    return Env(clock: clock, cache: cache, service: ConditionsService(deps))
}

func tempDirectory() -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("iter-conditions-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// Every report a stream yields until it ends.
func collect(_ stream: AsyncStream<SkyReport>) async -> [SkyReport] {
    var out: [SkyReport] = []
    for await r in stream { out.append(r) }
    return out
}

let clearRecipe = Recipe(cloudTotal: 0.2, layers: (0.1, 0.1, 0.2), visibility: 30, precip: 0.0, rh: 50, wind: 2)
let metRecipe = Recipe(cloudTotal: 0.6, layers: (0.2, 0.3, 0.5), precip: 0.1, rh: 55, wind: 3)

/// Polls (in real time) until `condition` holds or about two seconds pass.
func eventually(_ condition: @Sendable () -> Bool) async -> Bool {
    for _ in 0..<2000 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return condition()
}

@MainActor
func eventuallyOnMain(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<2000 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return condition()
}
