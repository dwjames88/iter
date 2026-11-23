import Foundation
import Observation
import IterModel
import IterSources
import IterSky
import IterAstro
import IterConditions

// Deterministic Conditions fixtures: a fixed place and instant, `SkyReport`s built by the real `LightEngine` over synthetic
// hourly forecasts (so every score, confidence and cause is genuine), and a fake feed. No network, no `Date.now`.

public enum ConditionsFixtures {
    /// 2026-10-12 12:00 UTC, which is 06:00 at the fixed place.
    public static let now = Date(timeIntervalSince1970: 1_791_806_400)
    public static let zone = TimeZone(identifier: "America/Denver")!
    /// Mesa Arch, Canyonlands National Park: 38.3884, -109.8680, faces east (sunrise through the arch).
    public static let place = Place(id: UUID(uuidString: "00000000-0000-0000-0000-00000000A001")!, curatedID: "mesa-arch", name: "Mesa Arch",
                                    locality: "Canyonlands National Park, UT", coordinate: Coordinate(latitude: 38.3884, longitude: -109.8680),
                                    timeZoneIdentifier: "America/Denver", category: .desert, bestLight: [.sunrise], facing: 90,
                                    elevationMeters: 1800, origin: .curated, createdAt: now, updatedAt: now)
    public static var today: LocalDay { LocalDay(now, in: zone) }
    public static let ephemeris: any Ephemeris = Astronomy()

    // Cloud by day offset: low, mid, high fractions chosen to spread scores (clear sunrise through to socked in).
    static let pattern: [(low: Double, mid: Double, high: Double)] = [
        (0.10, 0.30, 0.55), (0.75, 0.60, 0.80), (0.05, 0.35, 0.60), (0.35, 0.30, 0.30), (0.85, 0.70, 0.75),
        (0.15, 0.25, 0.50), (0.05, 0.40, 0.65), (0.40, 0.45, 0.35), (0.20, 0.30, 0.45), (0.70, 0.55, 0.60),
    ]

    public static func provenance(_ source: SourceID = .noaaNOMADS, model: String? = "HRRR", fetchedAt: Date = now, licence: String = LicenceKey.noaaNCEP,
                                  origin: SourceOrigin? = SourceOrigin(tier: .government, producer: "NOAA/NCEP")) -> Provenance {
        Provenance(source: source, model: model, issuedAt: fetchedAt.addingTimeInterval(-3600), fetchedAt: fetchedAt,
                   licence: LicenceTag(key: licence, mayStore: true), origin: origin)
    }

    /// Ten days of hourly forecast from the hour containing `now`.
    public static func series(from start: Date = now, hours: Int = 240, cloudShift: Double = 0, source: SourceID = .noaaNOMADS) -> HourlySeries {
        let first = Date(timeIntervalSince1970: (start.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
        let rows = (0..<hours).map { h -> HourlyConditions in
            let t = first.addingTimeInterval(Double(h) * 3600)
            let d = min(pattern.count - 1, h / 24)
            let p = pattern[d]
            let wobble = 0.05 * sin(Double(h) * 0.7)
            func c(_ v: Double) -> Double { min(1, max(0, v + wobble + cloudShift)) }
            let low = c(p.low), mid = c(p.mid), high = c(p.high)
            return HourlyConditions(time: t, cloudTotal: min(1, max(low, mid, high) + 0.1), cloudLow: low, cloudMid: mid, cloudHigh: high,
                                    precipChance: low > 0.6 ? 0.4 : 0.03, precipMm: low > 0.6 ? 0.4 : 0, visibilityKm: 24,
                                    tempC: 11 + 7 * sin(Double(h % 24 - 8) / 24 * 2 * .pi), dewpointC: 2, rhPercent: 38, windMs: 3.2,
                                    gustMs: 5.5, windDirDeg: 250, smokeUgm3: 4)
        }
        var sources: [HourlyField: SourceID] = [:]
        for f in HourlyField.allCases where rows.first?[f] != nil { sources[f] = source }
        return HourlySeries(hours: rows, fieldSources: sources)
    }

    /// A skyline with a ridge to the east (azimuth 80 to 110, 9 degrees) that delays the sunrise window.
    public static var ridge: HorizonProfile {
        HorizonProfile(azimuthStepDegrees: 5, elevationsDegrees: (0..<72).map { i in
            let az = Double(i) * 5
            return (80...110).contains(az) ? 9 : 2.5
        })
    }

    public struct Options: Sendable {
        public var tier: ForecastTier = .complete
        public var fetchedAt: Date = ConditionsFixtures.now
        public var staleAge: Duration?
        public var offline = false
        public var outOfCoverage = false
        public var withHorizon = true
        public var withComparison = false
        public var withObservation = true
        public var militaryStation = false
        public var withAlert = false
        public var cloudShift: Double = 0
        public init() {}
    }

    /// A `SkyReport` for `day` built by the real light engine.
    public static func report(day: LocalDay, options o: Options = Options(), place p: Place = place) -> SkyReport {
        let engine = LightEngine(ephemeris: ephemeris)
        let prov = provenance(o.tier == .quick ? .metNorway : .noaaNOMADS, model: o.tier == .quick ? "MET Nordic" : "HRRR", fetchedAt: o.fetchedAt,
                              licence: o.tier == .quick ? LicenceKey.metNorway : LicenceKey.noaaNCEP)
        let hourly = series(cloudShift: o.cloudShift, source: prov.source)
        let horizon: HorizonProfile? = o.withHorizon && o.tier != .quick ? ridge : nil
        var comparison: ForecastComparison?
        if o.withComparison, !o.outOfCoverage {
            let other = series(cloudShift: 0.42, source: .metNorway)
            comparison = ForecastComparison(source: .metNorway, sourceName: "MET Norway", series: other,
                                            provenance: provenance(.metNorway, model: "MET Nordic", fetchedAt: o.fetchedAt, licence: LicenceKey.metNorway),
                                            maxCloudDifference: 0.42)
        }
        let inputs = ForecastSkyInputs(hourly: o.outOfCoverage ? nil : hourly, provenance: o.outOfCoverage ? nil : prov, ttl: Freshness.defaultTTL,
                                       horizon: horizon, spreadSeries: comparison.map { [$0.series] } ?? [])
        let daylight = engine.dayLight(for: p, on: day, inputs: o.outOfCoverage ? nil : inputs,
                                       unavailable: o.outOfCoverage ? [.outsideCoverage] : [], now: now)

        let forecast: DataState<HourlySeries>
        if o.outOfCoverage { forecast = .none([.outsideCoverage]) }
        else if let age = o.staleAge { forecast = .stale(Sourced(value: hourly, provenance: prov), age: age) }
        else { forecast = .fresh(Sourced(value: hourly, provenance: prov)) }

        let fieldProvenance = o.outOfCoverage ? [] : hourly.fieldSources.keys.sorted { $0.rawValue < $1.rawValue }.map {
            FieldProvenance(field: $0, provenance: prov, contributors: [prov.source])
        }
        let live = day == LocalDay(now, in: p.timeZone) && !o.outOfCoverage && o.tier != .quick
        var stations: DataState<[Sourced<StationReport>]> = .none([])
        if live, o.withObservation {
            let reportTime = now.addingTimeInterval(-47 * 60)
            let station = o.militaryStation
                ? StationReport(stationID: "KDPG", stationName: "Michael Army Airfield", coordinate: Coordinate(latitude: 40.199, longitude: -112.913), elevationM: 1316,
                                distanceKm: 292, isMilitary: true, observedAt: reportTime, rawMETAR: "KDPG 121253Z 25004KT 10SM FEW120 07/M03 A3021",
                                observation: WeatherObservation(time: reportTime, stationName: "Michael Army Airfield",
                                                                conditions: HourlyConditions(time: reportTime, cloudTotal: 0.2, visibilityKm: 16, tempC: 7, windMs: 2, windDirDeg: 250)),
                                cloudLayers: [CloudLayer(cover: .few, baseM: 3650)], flightCategory: "VFR")
                : StationReport(stationID: "KCNY", stationName: "Canyonlands Field", coordinate: Coordinate(latitude: 38.755, longitude: -109.755), elevationM: 1387,
                                distanceKm: 38, isMilitary: false, observedAt: reportTime, rawMETAR: "KCNY 121253Z 24005KT 10SM CLR 06/M04 A3018",
                                observation: WeatherObservation(time: reportTime, stationName: "Canyonlands Field",
                                                                conditions: HourlyConditions(time: reportTime, cloudTotal: 0, visibilityKm: 16, tempC: 6, windMs: 2.5, windDirDeg: 240)),
                                cloudLayers: [], flightCategory: "VFR")
            let origin = o.militaryStation
                ? SourceOrigin(tier: .military, producer: "US Army", distributor: "NOAA Aviation Weather Center")
                : SourceOrigin(tier: .government, producer: "FAA and NWS", distributor: "NOAA Aviation Weather Center")
            stations = .fresh(Sourced(value: [Sourced(value: station, provenance: provenance(.aviationWeather, model: nil, fetchedAt: now, licence: LicenceKey.noaaAWC, origin: origin))],
                                      provenance: provenance(.aviationWeather, model: nil, licence: LicenceKey.noaaAWC, origin: origin)))
        } else if live, o.tier == .quick { stations = .none([]) }

        var alerts: DataState<[WeatherAlert]> = live ? .fresh(Sourced(value: [], provenance: provenance(.nwsAPI, model: nil, licence: LicenceKey.noaaNWS))) : .none([])
        if live, o.withAlert {
            let alert = WeatherAlert(id: "urn:nws:1", event: "Wind Advisory", headline: "Wind Advisory until 6 PM MDT", severity: .moderate, urgency: "Expected",
                                     onset: now.addingTimeInterval(3 * 3600), ends: now.addingTimeInterval(12 * 3600), senderName: "NWS Grand Junction CO")
            alerts = .fresh(Sourced(value: [alert], provenance: provenance(.nwsAPI, model: nil, licence: LicenceKey.noaaNWS)))
        }
        let smokeProv = provenance(.hmsSmoke, model: nil, licence: LicenceKey.noaaHMS)
        let kp = (0..<8).map { AuroraOutlook.KpStep(time: now.addingTimeInterval(Double($0) * 10800), value: [2, 2.33, 3, 2.67, 2, 1.67, 2, 2.33][$0]) }
        let aurora: DataState<AuroraOutlook> = live && o.tier != .quick
            ? .fresh(Sourced(value: AuroraOutlook(kp: kp, probabilityPercent: 3, provenance: nil), provenance: provenance(.swpc, model: nil, licence: LicenceKey.noaaSWPC)))
            : .none([])
        let horizonState: DataState<HorizonProfile> = horizon.map { .fresh(Sourced(value: $0, provenance: provenance(.terrariumTiles, model: nil, licence: LicenceKey.terrainTiles))) } ?? .none([])

        var loading: [PendingPart] = []
        if o.tier == .quick { loading = [.forecast(.noaaNOMADS), .observations, .alerts, .aurora, .smokeAnalysis, .horizon, .lightAndSeeing] }
        else if o.tier == .nearTerm { loading = [.forecast(.noaaNOMADS)] }

        return SkyReport(
            placeID: p.id, coordinate: p.coordinate, timeZoneIdentifier: p.timeZoneIdentifier, day: day, generatedAt: now, tier: o.tier, loading: loading,
            forecast: forecast, fieldProvenance: fieldProvenance, comparison: comparison, forecastTTL: Freshness.defaultTTL, daylight: daylight,
            observations: .none([]), stationReports: stations, alerts: alerts,
            smoke: live && o.tier != .quick
                ? SmokeReport(analysis: .fresh(Sourced(value: SmokeAnalysis(density: .light, day: now, polygonCount: 14), provenance: smokeProv)),
                              nearSurfaceMaxUgm3: 9, nearSurfaceSource: .noaaHRRRSmoke) : SmokeReport(),
            aurora: aurora, horizon: horizonState, bortle: nil, seeing: nil,
            gaps: o.tier == .quick ? [] : [ConditionsGap(subject: .lightPollution, reasons: [.notProvidedBySource]),
                                            ConditionsGap(subject: .seeing, reasons: [.notProvidedBySource])],
            provenanceLines: o.outOfCoverage ? [] : [ProvenanceLine(label: "Cloud layers", text: "\(prov.model ?? "forecast"), \(prov.source.rawValue)"),
                                                     ProvenanceLine(label: "Terrain", text: "Terrain tiles, 5 degree steps")],
            attributionKeys: o.outOfCoverage ? [] : [prov.licence.key, LicenceKey.terrainTiles], pack: nil,
            offlineNote: o.offline ? "Forecast from \(clock(o.fetchedAt)), offline" : nil)
    }

    static func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = zone
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    /// The report with chosen scores on its windows (kind to score), for tests of ranking and ties. Confidence is kept.
    public static func report(_ r: SkyReport, scores: [LightWindowKind: Int], confidence: Confidence = .high) -> SkyReport {
        var out = r
        out.daylight.windows = r.daylight.windows.map { w in
            var w = w
            guard let v = scores[w.kind] else { w.assessment = .unavailable(.beyondHorizon); return w }
            let cv: Double = confidence == .high ? 1 : (confidence == .medium ? 0.5 : 0.2)
            w.assessment = .scored(SkyScore(value: v, band: LightBand(score: v), confidence: confidence, confidenceValue: cv, range: v...v, contributors: [],
                                            forecastFetchedAt: now, leadHours: 6, age: 0, isStale: false))
            return w
        }
        return out
    }
}

/// A feed the test or preview drives by hand: set a slot's state and every `ConditionsModel` reading it re-tracks.
@MainActor @Observable
public final class FakeConditionsFeed: ConditionsFeed {
    public struct Request: Equatable, Sendable {
        public var day: LocalDay
        public var priority: ConditionsPriority
        public var isRefresh: Bool
    }
    private struct Key: Hashable { var id: UUID; var day: LocalDay }

    private var states: [Key: ConditionsLoadState] = [:]
    @ObservationIgnored public private(set) var requests: [Request] = []
    @ObservationIgnored public var liveResult: LiveConditions?
    @ObservationIgnored public private(set) var liveCalls = 0
    @ObservationIgnored public var liveDelay: Duration = .zero

    public init() {}

    public func set(_ state: ConditionsLoadState, place: UUID = ConditionsFixtures.place.id, day: LocalDay) {
        states[Key(id: place, day: day)] = state
    }

    public func state(for placeID: UUID, day: LocalDay) -> ConditionsLoadState { states[Key(id: placeID, day: day)] ?? .idle }
    public func request(_ place: Place, day: LocalDay, priority: ConditionsPriority) { requests.append(Request(day: day, priority: priority, isRefresh: false)) }
    public func refresh(_ place: Place, day: LocalDay, priority: ConditionsPriority) { requests.append(Request(day: day, priority: priority, isRefresh: true)) }
    public func cancel(_ placeID: UUID, day: LocalDay) {}

    public func live(for place: Place) async -> LiveConditions {
        liveCalls += 1
        if liveDelay > .zero { try? await Task.sleep(for: liveDelay) }
        return liveResult ?? ConditionsFixtures.liveConditions()
    }
}

extension ConditionsFixtures {
    /// A "Now" reading: forecast only, from the nearest forecast hour.
    public static func liveConditions(place p: Place = place) -> LiveConditions {
        let reading = LiveSkyIndex.reading(at: p, now: now, target: nil, forecast: report(day: today).forecastInputs, observations: [], nowcast: [],
                                           nowcastProvenance: nil, ephemeris: ephemeris, horizonHours: 6)
        return LiveConditions(placeID: p.id, generatedAt: now, reading: reading, current: nil,
                              currentForecastHour: series().hour(at: now), strip: [], notice: .forecastOnly, nowcast: .none([]),
                              observations: .none([]), forecastTier: .complete, forecastOfflineNote: nil)
    }
}
