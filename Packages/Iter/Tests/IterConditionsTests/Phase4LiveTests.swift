import Foundation
import Synchronization
import Testing
import IterAI
import IterAstro
import IterDiscovery
import IterModel
import IterSources
import IterSourcesLive
import IterSky
@testable import IterConditions

// Phase 4 live run against the real services: Find (discovery) then Conditions for the top places. Off unless ITER_LIVE=1,
// and run only by the phase lead. One pass, no loops, well under 150 requests. Prints everything it finds; the assertions
// are the grounding invariant and the Yosemite boundary check. Apple Intelligence is used only when ITER_LIVE_AI=1.
//
//     ITER_LIVE=1 swift test --filter Phase4LiveTests            (basic search)
//     ITER_LIVE=1 ITER_LIVE_AI=1 swift test --filter Phase4LiveTests

private let live = ProcessInfo.processInfo.environment["ITER_LIVE"] == "1"
private let liveAI = ProcessInfo.processInfo.environment["ITER_LIVE_AI"] == "1"

/// Counts every request by host and passes it on to URLSession.
private final class CountingTransport: HTTPTransport {
    private let inner = URLSessionTransport()
    private let counts = Mutex<[String: Int]>([:])

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        counts.withLock { $0[request.url?.host ?? "?", default: 0] += 1 }
        return try await inner.data(for: request)
    }

    var byHost: [String: Int] { counts.withLock { $0 } }
    var total: Int { counts.withLock { $0.values.reduce(0, +) } }
}

@Suite("Phase 4 live (ITER_LIVE=1)", .enabled(if: live), .serialized)
struct Phase4LiveTests {
    private func clockSince(_ start: ContinuousClock.Instant) -> String {
        let d = ContinuousClock.now - start
        return String(format: "%6.2fs", Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18)
    }

    private func state<T: Sendable>(_ s: DataState<T>) -> String {
        switch s {
        case .fresh: "fresh"
        case .stale(_, let age): "STALE \(Int(age.timeInterval)) s"
        case .none(let r): "none \(r)"
        }
    }

    // MARK: Discovery

    private func providers(http: SourceHTTP) -> DiscoveryProviders {
        DiscoveryProviders(
            geocoders: [MapKitGeocoder()], boundaries: [OverpassBoundaryProvider(http: http)],
            gazetteers: [MapKitPOIGazetteer(), OverpassProvider(http: http), GNISProvider(http: http)],
            placeSearch: [MapKitPlaceSearch()], textEvidence: [WikipediaProvider(http: http), WikivoyageProvider(http: http)],
            photoEvidence: [CommonsProvider(http: http)])
    }

    private func describe(_ result: DiscoveryResult, elapsed: String, allowedSources: Set<SourceID>) {
        print("[live] ---- discover: \"\(result.request.text)\"  elapsed \(elapsed)")
        print("[live] plan: areaText=\(result.plan.areaText ?? "nil") mode=\(result.plan.areaMode) features=\(result.plan.features) "
              + "keywords=\(result.plan.keywords)  origin=\(result.planOrigin.label ?? "AI")")
        if let a = result.area {
            let vertices = a.area.boundary?.rings.reduce(0) { $0 + $1.count } ?? 0
            print("[live] area: \(a.area.name ?? "?") basis=\(a.basis) boundary=\(a.hasRealBoundary ? "yes, \(vertices) vertices" : "no") "
                  + "citation=\(a.boundaryCitation?.title ?? "none") \(a.boundaryCitation?.url?.absoluteString ?? "")")
        } else {
            print("[live] area: none, failure=\(String(describing: result.failure))")
        }
        for s in result.statuses { print("[live] source \(s.source) (\(s.role)): \(s.summary)") }
        for (i, p) in result.places.prefix(10).enumerated() {
            let r = p.rank
            func v(_ x: RankPart) -> String { x.value.map { String(format: "%.2f", $0) } ?? "nil" }
            print("[live] \(i + 1). \(p.name)  (\(String(format: "%.4f, %.4f", p.coordinate.latitude, p.coordinate.longitude)))  "
                  + "coord from \(p.coordinate.source) [\(p.coordinate.basis)]  \(p.verification)  sources=\(p.sources.map(\.rawValue))  photos=\(p.photoCount)")
            print("[live]      rank feature \(v(r.featureMatch)) evidence \(v(r.evidence)) preference \(v(r.preference)) light \(v(r.lightSuit)) "
                  + "reach \(v(r.reachability)) novelty \(v(r.novelty))")
            print("[live]      why: \(p.why?.text ?? "none")  cite: \(p.citations.first?.url?.absoluteString ?? "none")")
        }
        // The grounding invariant: no coordinate comes from a model, only from a provider we called.
        for p in result.places {
            #expect(p.coordinate.source != FixedSources.ai, "\(p.name) coordinate from the model")
            #expect(allowedSources.contains(p.coordinate.source), "\(p.name) coordinate from unknown source \(p.coordinate.source)")
        }
    }

    // MARK: Conditions

    private func conditions(for places: [Place], http: SourceHTTP, cacheDirectory: URL) async {
        let cache = SourceCache(directory: cacheDirectory)
        let nomads = NOMADSForecastProvider(http: http, cache: cache)
        let metar = AviationWeatherProvider(http: http)
        let nws = NWSProvider(http: http)
        let sources: [any SourceDescribing] = [
            nomads, HRRRSmokeProvider(sharing: nomads), MetNorwayProvider(http: http), metar, nws, SWPCAuroraProvider(http: http),
            HMSSmokeProvider(http: http), TerrariumTerrainProvider(http: http, blobCache: cache), NoSkyBrightnessProvider(), NoSeeingProvider(),
        ]
        let service = ConditionsService(ConditionsDependencies(
            registry: SourceRegistry(sources: sources), cache: cache, clock: SystemSourceClock(), ephemeris: Astronomy()))
        let day = LocalDay(Date(), in: places[0].timeZone)
        let start = ContinuousClock.now
        print("[live] ---- conditions for \(places.map(\.name)) on \(day)")
        for await r in service.reports(for: places.map { ConditionsRequest(place: $0, day: day) }) {
            let name = places.first { $0.id == r.placeID }?.name ?? "?"
            print("[live] [\(clockSince(start))] \(name): tier=\(r.tier) loading=\(r.loading.map(\.description))")
            for l in r.provenanceLines { print("[live]    \(l.line)\(l.staleAge.map { " (stale \(Int($0)) s)" } ?? "")") }
            for w in r.daylight.windows {
                switch w.assessment {
                case .scored(let s):
                    print("[live]    \(w.kind): \(s.value) \(s.band) confidence \(s.confidence) causes \(s.confidenceCauses)")
                case .unavailable(let u):
                    print("[live]    \(w.kind): unavailable \(u)")
                }
            }
            print("[live]    gaps: \(r.gaps.map { "\($0.subject): \($0.reasons)" })")
            if let o = r.observations.value?.first {
                print("[live]    observation: \(o.value.stationName ?? "?") \(o.provenance.distanceKm.map { String(format: "%.0f km", $0) } ?? "? km"), "
                      + "\(Int(Date().timeIntervalSince(o.value.time) / 60)) min old (\(state(r.observations)))")
            } else {
                print("[live]    observation: \(state(r.observations))")
            }
            print("[live]    alerts: \(r.alerts.value?.count.description ?? state(r.alerts))")
            print("[live]    smoke: near-surface max \(r.smoke.nearSurfaceMaxUgm3.map { String(format: "%.1f ug/m3", $0) } ?? "nil"), "
                  + "optical depth \(r.smoke.opticalDepth?.values.count.description ?? "nil") hours, HMS \(r.smoke.analysis.value.map { "\($0.density)" } ?? state(r.smoke.analysis))")
            print("[live]    aurora: \(r.aurora.value.map { "probability \($0.probabilityPercent.map { String(format: "%.0f%%", $0) } ?? "nil"), kp steps \($0.kp.count)" } ?? state(r.aurora))")
            print("[live]    horizon: \(r.horizon.value.map { "\($0.elevationsDegrees.count) azimuths, max \(String(format: "%.1f", $0.elevationsDegrees.max() ?? 0))°" } ?? state(r.horizon))")
        }
        let l = await service.live(for: places[0])
        print("[live] ---- live(for: \(places[0].name))")
        print("[live] reading: state=\(l.reading.state) score=\(l.reading.score.map(String.init) ?? "nil") trend=\(l.reading.trend) confidence=\(l.reading.confidence) notice=\(l.notice?.text ?? "none")")
        if let c = l.current { print("[live] current: \(c.stationName ?? "?") \(c.distanceKm.map { String(format: "%.0f km", $0) } ?? "? km"), age \(Int(c.age / 60)) min") }
        if let h = l.currentForecastHour { print("[live] current forecast hour (not observed): cloud \(h.cloudTotal.map { String(format: "%.2f", $0) } ?? "nil")") }
        for s in l.strip { print("[live]    strip \(s.time) \(s.basis) cloud \(s.conditions.cloudTotal.map { String(format: "%.2f", $0) } ?? "nil") precip \(s.conditions.precipChance.map { String(format: "%.2f", $0) } ?? "nil")") }
    }

    // MARK: The run

    @Test func findThenConditions() async throws {
        let transport = CountingTransport()
        let http = SourceHTTP(transport: transport, userAgent: UserAgent(version: "0.0-dev"))
        let model: (any LanguageModeling)? = liveAI ? ResilientLanguageModel(FoundationModelsLanguageModel()) : nil
        print("[live] language model: \(model == nil ? "none (basic search)" : "Foundation Models")")
        let p = providers(http: http)
        let allowed = Set(p.geocoders.map(\.descriptor.id) + p.boundaries.map(\.descriptor.id) + p.gazetteers.map(\.descriptor.id)
                          + p.placeSearch.map(\.descriptor.id) + p.textEvidence.map(\.descriptor.id) + p.photoEvidence.map(\.descriptor.id))
        let engine = DiscoveryEngine(providers: p, model: model)

        // Lone Pine.
        var start = ContinuousClock.now
        let lonePine = await engine.discover(DiscoveryRequest(text: "viewpoints near Lone Pine, California"))
        describe(lonePine, elapsed: clockSince(start), allowedSources: allowed)

        // Yosemite, inside its boundary.
        start = ContinuousClock.now
        let yosemite = await engine.discover(DiscoveryRequest(text: "waterfalls in Yosemite National Park"))
        describe(yosemite, elapsed: clockSince(start), allowedSources: allowed)
        if let area = yosemite.area, area.hasRealBoundary {
            for place in yosemite.places { #expect(area.area.contains(place.coordinate.value), "\(place.name) is outside the Yosemite boundary") }
        } else {
            print("[live] Yosemite: no real boundary found, so no inside-boundary check")
        }

        // Conditions for the top two Lone Pine places.
        let places = lonePine.places.prefix(2).map { $0.makePlace(timeZoneIdentifier: "America/Los_Angeles", discoveredAt: Date()) }
        #expect(!places.isEmpty, "Find returned nothing for Lone Pine")
        if !places.isEmpty {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("iter-live-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: dir) }
            await conditions(for: Array(places), http: http, cacheDirectory: dir)
        }

        print("[live] requests by host: \(transport.byHost.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")) total=\(transport.total)")
        #expect(transport.total < 150)
    }
}

extension PendingPart {
    fileprivate var description: String {
        switch self {
        case .forecast(let s): "forecast:\(s.rawValue)"
        case .observations: "observations"
        case .alerts: "alerts"
        case .aurora: "aurora"
        case .smokeAnalysis: "smokeAnalysis"
        case .horizon: "horizon"
        case .lightAndSeeing: "lightAndSeeing"
        }
    }
}
