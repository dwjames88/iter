import Foundation
import IterModel
import IterSources
import IterSky
import IterAstro
import IterConditions
import IterGo

/// 2026-06-15 12:00 UTC: 06:00 in Denver.
let cT0 = Date(timeIntervalSince1970: 1_781_524_800)
let denver = "America/Denver"

func cPlace(_ name: String = "Spot", lat: Double = 39.74, lon: Double = -104.99, tz: String = denver) -> Place {
    Place(name: name, coordinate: Coordinate(latitude: lat, longitude: lon), timeZoneIdentifier: tz, category: .landscape, origin: .user)
}

func cStop(_ name: String = "Spot", session: LightWindowKind = .goldenEvening, dayIndex: Int = 0, kind: StopKind = .light,
           lat: Double = 39.74, lon: Double = -104.99) -> Stop {
    Stop(place: cPlace(name, lat: lat, lon: lon), dayIndex: dayIndex, session: session, kind: kind)
}

func cTrip(_ stops: [Stop]) -> Trip {
    Trip(name: "Test", startDay: LocalDay(cT0, in: TimeZone(identifier: denver)!), dayCount: 2, stops: stops)
}

func cFix(lat: Double = 39.74, lon: Double = -104.99, at: Date = cT0) -> LocationFix {
    LocationFix(coordinate: Coordinate(latitude: lat, longitude: lon), accuracyM: 10, timestamp: at)
}

func cProvenance(at: Date = cT0) -> Provenance {
    Provenance(source: "test.src", fetchedAt: at, licence: LicenceTag(key: "test", mayStore: true))
}

func cWindow(_ kind: LightWindowKind, score: Int?, confidence: Confidence = .medium, stale: Bool = false, startsIn: TimeInterval = 4 * 3600) -> LightWindow {
    let span = TimeSpan(start: cT0.addingTimeInterval(startsIn), end: cT0.addingTimeInterval(startsIn + 3600))
    guard let score else { return LightWindow(kind: kind, span: span, assessment: .unavailable(.beyondHorizon)) }
    let s = SkyScore(value: score, band: LightBand(score: score), confidence: confidence, confidenceValue: 0.5, range: 0...100, contributors: [],
                     forecastFetchedAt: cT0, leadHours: 4, age: 0, isStale: stale)
    return LightWindow(kind: kind, span: span, assessment: .scored(s))
}

func cReport(_ place: Place, windows: [LightWindow], alerts: [WeatherAlert]? = nil, offlineNote: String? = nil,
             forecast: DataState<HourlySeries> = .none([]), generatedAt: Date = cT0) -> SkyReport {
    let day = LocalDay(cT0, in: place.timeZone)
    let sun = SunEvents(day: day, kind: .normal, solarNoon: cT0)
    let dayLight = DayLight(day: day, coordinate: place.coordinate, timeZoneIdentifier: place.timeZoneIdentifier, sun: sun,
                            moon: MoonEvents(day: day, rise: nil, set: nil), moonPhase: MoonPhase(illumination: 0.5, cycle: 0.25),
                            windows: windows)
    let alertState: DataState<[WeatherAlert]> = alerts.map { .fresh(Sourced(value: $0, provenance: cProvenance())) } ?? .none([])
    return SkyReport(placeID: place.id, coordinate: place.coordinate, timeZoneIdentifier: place.timeZoneIdentifier, day: day, generatedAt: generatedAt,
                     tier: .complete, loading: [], forecast: forecast, fieldProvenance: [], comparison: nil, forecastTTL: 3600, daylight: dayLight,
                     observations: .none([]), stationReports: .none([]), alerts: alertState, smoke: SmokeReport(), aurora: .none([]),
                     horizon: .none([]), bortle: nil, seeing: nil, gaps: [], provenanceLines: [], attributionKeys: [], pack: nil,
                     offlineNote: offlineNote)
}

func cReading(kind: LightWindowKind? = .goldenEvening, score: Int?, forecast: Int? = nil, state: LiveState = .blended,
              trend: LiveTrend = .steady, age: TimeInterval? = 300, stale: Bool = false) -> LiveSkyReading {
    LiveSkyReading(kind: kind, window: score == nil ? nil : TimeSpan(start: cT0.addingTimeInterval(3600), end: cT0.addingTimeInterval(7200)),
                   score: score, band: score.map { LightBand(score: $0) }, forecastScore: forecast, trend: trend, state: state, age: age,
                   confidence: .high, isStale: stale)
}

func cLive(_ place: Place, reading: LiveSkyReading, at: Date = cT0, current: CurrentObservation? = nil, forecastHour: HourlyConditions? = nil,
           strip: [LiveStripHour] = [], notice: LiveNotice? = nil, nowcast: DataState<[NowcastStep]> = .none([]),
           observations: DataState<[Sourced<WeatherObservation>]> = .none([]), offlineNote: String? = nil) -> LiveConditions {
    LiveConditions(placeID: place.id, generatedAt: at, reading: reading, current: current, currentForecastHour: forecastHour, strip: strip,
                   notice: notice, nowcast: nowcast, observations: observations, forecastTier: .complete, forecastOfflineNote: offlineNote)
}

func cStrip(highFirst: Double, highLast: Double, totalFirst: Double, totalLast: Double) -> [LiveStripHour] {
    [LiveStripHour(time: cT0, conditions: HourlyConditions(time: cT0, cloudTotal: totalFirst, cloudHigh: highFirst), basis: .nowcast),
     LiveStripHour(time: cT0.addingTimeInterval(5 * 3600),
                   conditions: HourlyConditions(time: cT0.addingTimeInterval(5 * 3600), cloudTotal: totalLast, cloudHigh: highLast), basis: .forecast)]
}

// MARK: Fake provider

/// Records every call in order; scores and failures are set per place by the test.
final class FakeConditions: TripConditionsProviding, @unchecked Sendable {
    enum Call: Equatable {
        case live(UUID, LightWindowKind?, ConditionsPriority)
        case report(UUID, ConditionsPriority)
        case pack(UUID)
    }
    private let lock = NSLock()
    private var _calls: [Call] = []
    private var liveScores: [UUID: Int] = [:]
    private var reportScores: [UUID: Int] = [:]
    private var _packFails = false
    private var _packBuilt: [UUID: Date] = [:]
    private var _offline = false
    private var _strip: [LiveStripHour] = []
    private var gate: Gate?
    var now: @Sendable () -> Date = { cT0 }

    var calls: [Call] { lock.withLock { _calls } }
    func clearCalls() { lock.withLock { _calls = [] } }
    func setLive(_ id: UUID, _ score: Int?) { lock.withLock { liveScores[id] = score } }
    func setReport(_ id: UUID, _ score: Int?) { lock.withLock { reportScores[id] = score } }
    func setPackFails(_ v: Bool) { lock.withLock { _packFails = v } }
    func setPackBuilt(_ id: UUID, _ d: Date?) { lock.withLock { _packBuilt[id] = d } }
    func setOffline(_ v: Bool) { lock.withLock { _offline = v } }
    func setStrip(_ s: [LiveStripHour]) { lock.withLock { _strip = s } }
    func setGate(_ g: Gate?) { lock.withLock { gate = g } }

    func live(for place: Place, target: LightWindowKind?, priority: ConditionsPriority) async -> LiveConditions {
        let (score, strip, offline, g) = lock.withLock { () -> (Int?, [LiveStripHour], Bool, Gate?) in
            _calls.append(.live(place.id, target, priority))
            return (liveScores[place.id], _strip, _offline, gate)
        }
        if let g { await g.wait() }
        let when = now()
        return cLive(place, reading: cReading(kind: target, score: score, forecast: score), at: when, strip: strip,
                     nowcast: offline ? .none([.offline(lastGood: nil)]) : .none([]))
    }

    func report(for place: Place, day: LocalDay, priority: ConditionsPriority) async -> SkyReport {
        let (score, offline) = lock.withLock { () -> (Int?, Bool) in
            _calls.append(.report(place.id, priority))
            return (reportScores[place.id], _offline)
        }
        return cReport(place, windows: LightWindowKind.allCases.map { cWindow($0, score: score) },
                       offlineNote: offline ? "Forecast from 06:29, offline" : nil, generatedAt: now())
    }

    func buildTripPack(for trip: Trip) async throws -> Date {
        let (fails, built) = lock.withLock { () -> (Bool, Date) in
            _calls.append(.pack(trip.id))
            return (_packFails, now())
        }
        if fails { throw PackFailure.boom }
        lock.withLock { _packBuilt[trip.id] = built }
        return built
    }

    func packBuiltAt(tripID: UUID) async -> Date? { lock.withLock { _packBuilt[tripID] } }

    enum PackFailure: Error { case boom }
}

/// Holds callers until opened.
final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            let resume = lock.withLock { () -> Bool in
                if isOpen { return true }
                waiters.append(c)
                return false
            }
            if resume { c.resume() }
        }
    }

    func open() {
        let ws = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            isOpen = true
            defer { waiters = [] }
            return waiters
        }
        for w in ws { w.resume() }
    }
}
