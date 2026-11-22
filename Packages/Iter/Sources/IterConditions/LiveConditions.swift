import Foundation
import IterModel
import IterSources
import IterSky

/// Why live data is thin, as a label the UI shows.
public enum LiveNotice: String, Codable, Hashable, Sendable {
    /// Nothing live: no observation and no nowcast. The score is the forecast's, or absent.
    case noLiveData
    /// Observations are missing or too old; the score rests on the nowcast and forecast.
    case forecastOnly

    public var text: String {
        switch self {
        case .noLiveData: "No live data"
        case .forecastOnly: "Forecast only, no recent observation"
        }
    }
}

/// The nearest observation, with how far and how old.
public struct CurrentObservation: Codable, Hashable, Sendable {
    public var conditions: HourlyConditions
    public var stationName: String?
    public var distanceKm: Double?
    public var age: TimeInterval
    public var provenance: Provenance

    public init(conditions: HourlyConditions, stationName: String?, distanceKm: Double?, age: TimeInterval, provenance: Provenance) {
        self.conditions = conditions
        self.stationName = stationName
        self.distanceKm = distanceKm
        self.age = age
        self.provenance = provenance
    }
}

/// One hour of the six-hour strip.
public struct LiveStripHour: Codable, Hashable, Sendable {
    public enum Basis: String, Codable, Hashable, Sendable { case observation, nowcast, forecast }

    public var time: Date
    public var conditions: HourlyConditions
    public var basis: Basis

    public init(time: Date, conditions: HourlyConditions, basis: Basis) {
        self.time = time
        self.conditions = conditions
        self.basis = basis
    }
}

/// Trip mode's view of one place right now: the Live Sky Index reading, the nearest observation, the current forecast hour
/// when nothing was observed, and a six-hour strip (nowcast first, then forecast).
public struct LiveConditions: Codable, Hashable, Sendable {
    public var placeID: UUID
    public var generatedAt: Date
    public var reading: LiveSkyReading
    public var current: CurrentObservation?
    /// The forecast hour containing now, used (and labelled) when there is no observation.
    public var currentForecastHour: HourlyConditions?
    public var strip: [LiveStripHour]
    public var notice: LiveNotice?
    public var nowcast: DataState<[NowcastStep]>
    public var observations: DataState<[Sourced<WeatherObservation>]>
    /// The forecast report the reading was blended with.
    public var forecastTier: ForecastTier
    public var forecastOfflineNote: String?

    public init(placeID: UUID, generatedAt: Date, reading: LiveSkyReading, current: CurrentObservation?, currentForecastHour: HourlyConditions?,
                strip: [LiveStripHour], notice: LiveNotice?, nowcast: DataState<[NowcastStep]>,
                observations: DataState<[Sourced<WeatherObservation>]>, forecastTier: ForecastTier, forecastOfflineNote: String?) {
        self.placeID = placeID
        self.generatedAt = generatedAt
        self.reading = reading
        self.current = current
        self.currentForecastHour = currentForecastHour
        self.strip = strip
        self.notice = notice
        self.nowcast = nowcast
        self.observations = observations
        self.forecastTier = forecastTier
        self.forecastOfflineNote = forecastOfflineNote
    }
}

extension ConditionsService {
    /// The Live Sky Index and current conditions for `place`. Asks the nearest observations, the nowcast and the current
    /// forecast concurrently; any of them may be missing, and the result says so ("No live data").
    public func live(for place: Place, target: LightWindowKind? = nil, priority: ConditionsPriority = .activeTrip) async -> LiveConditions {
        let now = clock.now
        let today = LocalDay(now, in: place.timeZone)
        async let observations = nearbyObservations(place.coordinate)
        async let nowcast = loadNowcast(place.coordinate)
        async let forecast = report(for: place, day: today, priority: priority, waitFor: .quick)
        let (obsState, nowcastState, report) = await (observations, nowcast, forecast)

        let obs = obsState.value ?? []
        let steps = nowcastState.value ?? []
        let reading = LiveSkyIndex.reading(
            at: place, now: now, target: target, forecast: report.forecast.value == nil ? nil : report.forecastInputs,
            observations: obs, nowcast: steps, nowcastProvenance: nowcastState.provenance, ephemeris: ephemeris, horizonHours: 6)

        var current: CurrentObservation?
        if let o = obs.first {
            current = CurrentObservation(conditions: o.value.conditions, stationName: o.value.stationName, distanceKm: o.provenance.distanceKm,
                                         age: max(0, now.timeIntervalSince(o.value.time)), provenance: o.provenance)
        }
        let strip = reading.steps.prefix(6).map { step -> LiveStripHour in
            let basis: LiveStripHour.Basis
            if steps.contains(where: { abs($0.time.timeIntervalSince(step.time)) <= LiveSkyIndex.nowcastTolerance }) { basis = .nowcast }
            else if step.obsWeight > 0 { basis = .observation }
            else { basis = .forecast }
            return LiveStripHour(time: step.time, conditions: step.conditions, basis: basis)
        }
        let liveInputs = reading.inputsUsed.contains { $0.kind == .observation || $0.kind == .nowcast }
        let notice: LiveNotice? = steps.isEmpty && current == nil ? .noLiveData : (liveInputs ? nil : .forecastOnly)
        return LiveConditions(placeID: place.id, generatedAt: now, reading: reading, current: current,
                              currentForecastHour: current == nil ? report.forecast.value?.hour(at: now) : nil, strip: Array(strip),
                              notice: notice, nowcast: nowcastState, observations: obsState, forecastTier: report.tier,
                              forecastOfflineNote: report.offlineNote)
    }

    /// The 0-6 hour nowcast, from the first provider that has one. Kept for 15 minutes.
    func loadNowcast(_ c: Coordinate) async -> DataState<[NowcastStep]> {
        let providers = registry.providers((any NowcastProvider).self, kind: .nowcast, at: c)
        return await firstState(providers, kind: .nowcast, at: c) { p in
            let d = p.descriptor
            return await self.cachedState(CacheKey(source: d.id, kind: .nowcast, cell: c.cacheKey, bucket: ""), descriptor: d,
                                          ttl: .seconds(900)) { try await p.nowcast(at: c) }
        }
    }
}
