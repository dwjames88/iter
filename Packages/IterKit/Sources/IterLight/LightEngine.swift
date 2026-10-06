import Foundation
import IterCore

/// Turns sun geometry and a forecast into scored windows. Pure and deterministic: the caller supplies `now`.
public struct LightEngine: Sendable {
    public let ephemeris: any Ephemeris

    public init(ephemeris: any Ephemeris) {
        self.ephemeris = ephemeris
    }

    // MARK: Geometry

    /// The windows the sun produces at `spot` on `day`, chronologically, with no weather involved.
    ///
    /// Rules (a window is absent when an endpoint is missing or the span would be empty):
    /// - blueMorning: civil dawn to sunrise.
    /// - goldenMorning: sunrise to the sun reaching +6°. If the sun never reaches +6° (high-latitude winter),
    ///   sunrise to solar noon instead.
    /// - goldenEvening: the sun dropping to +6° until sunset. If it never reaches +6°, solar noon to sunset.
    /// - blueEvening: sunset to civil dusk.
    /// - night: astronomical dusk to the earlier of three hours later and the next day's astronomical dawn.
    ///   No astronomical dusk (high-latitude summer) means no night window.
    /// - Polar night (the sun never rises): the civil-twilight blue hour around noon still exists, as
    ///   blueMorning = civil dawn to solar noon and blueEvening = solar noon to civil dusk; night as above.
    /// - Polar day (midnight sun): no sunrise or sunset, so no blue hours; when the sun dips below +6° the low
    ///   sun is a golden window: goldenEvening = the +6° crossing to the next day's +6° rise (capped at 8 hours).
    public func windows(for spot: Spot, on day: LocalDay) -> [(kind: LightWindowKind, span: TimeSpan)] {
        let sun = ephemeris.sunEvents(on: day, at: spot.coordinate, in: spot.timeZone)
        return geometry(sun: sun, spot: spot, day: day)
    }

    private func geometry(sun: SunEvents, spot: Spot, day: LocalDay) -> [(kind: LightWindowKind, span: TimeSpan)] {
        var out: [(kind: LightWindowKind, span: TimeSpan)] = []
        func add(_ kind: LightWindowKind, _ start: Date?, _ end: Date?) {
            guard let start, let end, end > start else { return }
            out.append((kind, TimeSpan(start: start, end: end)))
        }
        func addNight() {
            if let dusk = sun.astronomicalDusk {
                let cap = dusk.addingTimeInterval(3 * 3600)
                let nextDawn = ephemeris.sunEvents(on: day.adding(days: 1), at: spot.coordinate, in: spot.timeZone).astronomicalDawn
                add(.night, dusk, min(cap, nextDawn ?? cap))
            }
        }
        switch sun.kind {
        case .polarNight:
            add(.blueMorning, sun.civilDawn, sun.civilDawn.map { _ in sun.solarNoon })
            add(.blueEvening, sun.civilDusk.map { _ in sun.solarNoon }, sun.civilDusk)
            addNight()
            return out
        case .polarDay:
            if let start = sun.goldenEveningStart {
                let nextRise = ephemeris.sunEvents(on: day.adding(days: 1), at: spot.coordinate, in: spot.timeZone).goldenMorningEnd
                let cap = start.addingTimeInterval(8 * 3600)
                add(.goldenEvening, start, min(cap, nextRise ?? cap))
            }
            return out
        case .normal:
            break
        }
        add(.blueMorning, sun.civilDawn, sun.sunrise)
        if sun.sunrise != nil {
            add(.goldenMorning, sun.sunrise, sun.goldenMorningEnd ?? sun.solarNoon)
        }
        if sun.sunset != nil {
            add(.goldenEvening, sun.goldenEveningStart ?? sun.solarNoon, sun.sunset)
        }
        add(.blueEvening, sun.sunset, sun.civilDusk)
        addNight()
        return out
    }

    // MARK: Days

    public func dayLight(for spot: Spot, on day: LocalDay, forecast: Forecast?, unavailable: ForecastUnavailableReason?, now: Date) -> DayLight {
        let zone = spot.timeZone
        let sun = ephemeris.sunEvents(on: day, at: spot.coordinate, in: zone)
        let moon = ephemeris.moonEvents(on: day, at: spot.coordinate, in: zone)
        let geo = geometry(sun: sun, spot: spot, day: day)
        let windows = geo.map { g in
            LightWindow(kind: g.kind, span: g.span,
                        assessment: assess(kind: g.kind, span: g.span, spot: spot, forecast: forecast, unavailable: unavailable, now: now))
        }
        let phaseAt = geo.first { $0.kind == .night }?.span.start ?? day.noon(in: zone)
        return DayLight(day: day, coordinate: spot.coordinate, timeZoneIdentifier: spot.timeZoneIdentifier, sun: sun, moon: moon,
                        moonPhase: ephemeris.moonPhase(at: phaseAt), windows: windows)
    }

    public func outlook(for spot: Spot, from day: LocalDay, days: Int, forecast: Forecast?, unavailable: ForecastUnavailableReason?, now: Date) -> [DayLight] {
        guard days > 0 else { return [] }
        return (0..<days).map { dayLight(for: spot, on: day.adding(days: $0), forecast: forecast, unavailable: unavailable, now: now) }
    }

    /// The best scored window for `intent` over the next `days` days. Only scored windows count (a "no forecast"
    /// window never wins). Ties go to higher confidence, then to the earlier window. nil if nothing is scored.
    public func bestUpcoming(for spot: Spot, intent: LightIntent, from day: LocalDay, days: Int, forecast: Forecast?,
                             unavailable: ForecastUnavailableReason?, now: Date) -> (day: LocalDay, window: LightWindow)? {
        var best: (day: LocalDay, window: LightWindow, score: LightScore)?
        for dl in outlook(for: spot, from: day, days: days, forecast: forecast, unavailable: unavailable, now: now) {
            for window in dl.windows where intent.windows.contains(window.kind) {
                guard let score = window.assessment.lightScore else { continue }
                if let current = best {
                    let better = score.value > current.score.value
                        || (score.value == current.score.value && score.confidence > current.score.confidence)
                        || (score.value == current.score.value && score.confidence == current.score.confidence
                            && window.span.start < current.window.span.start)
                    if !better { continue }
                }
                best = (dl.day, window, score)
            }
        }
        return best.map { ($0.day, $0.window) }
    }

    // MARK: Assessment

    func assess(kind: LightWindowKind, span: TimeSpan, spot: Spot, forecast: Forecast?, unavailable: ForecastUnavailableReason?, now: Date) -> LightAssessment {
        if span.end <= now { return .noForecast(.inThePast) }
        guard let forecast else { return .noForecast(unavailable ?? .notLoaded) }
        let mid = span.midpoint
        guard let first = forecast.hours.first, let horizon = forecast.horizon, mid >= first.date, mid < horizon else {
            return .noForecast(.beyondHorizon)
        }
        guard let conditions = Self.conditions(in: forecast, over: span) else { return .noForecast(.beyondHorizon) }

        var moon: MoonLight?
        if kind == .night {
            moon = MoonLight(altitude: ephemeris.moonPosition(at: mid, coordinate: spot.coordinate).altitude,
                             illumination: ephemeris.moonPhase(at: mid).illumination)
        }
        let scored = WindowScorer.score(kind: kind, conditions: conditions, moon: moon)
        let lead = mid.timeIntervalSince(forecast.fetchedAt) / 3600
        let confidence = WindowScorer.confidence(leadHours: lead, layersMissing: scored.usedLayerFallback,
                                                 resolutions: conditions.resolutions)
        return .scored(LightScore(value: scored.value, band: LightBand(score: scored.value), confidence: confidence,
                                  range: WindowScorer.range(value: scored.value, confidence: confidence),
                                  contributors: scored.contributors, source: forecast.source,
                                  forecastFetchedAt: forecast.fetchedAt, leadHours: lead, model: forecast.model,
                                  notes: WindowScorer.notes(scored: scored, resolutions: conditions.resolutions)))
    }

    /// Weather averaged over the hours overlapping `span`, weighted by overlap seconds.
    static func conditions(in forecast: Forecast, over span: TimeSpan) -> WindowConditions? {
        var hours = forecast.hours(overlapping: span).map { h -> (HourlyConditions, Double) in
            let overlap = min(span.end, h.date.addingTimeInterval(3600)).timeIntervalSince(max(span.start, h.date))
            return (h, max(0, overlap))
        }
        if hours.isEmpty || hours.reduce(0, { $0 + $1.1 }) <= 0 {
            guard let h = forecast.hour(at: span.midpoint) else { return nil }
            hours = [(h, 1)]
        }
        let weight = hours.reduce(0) { $0 + $1.1 }
        func mean(_ f: (HourlyConditions) -> Double) -> Double { hours.reduce(0) { $0 + f($1.0) * $1.1 } / weight }
        /// Mean over the hours that have the value (weighted by overlap); nil when none do.
        func optionalMean(_ f: (HourlyConditions) -> Double?) -> Double? {
            var sum = 0.0, w = 0.0
            for (h, overlap) in hours { if let v = f(h) { sum += v * overlap; w += overlap } }
            return w > 0 ? sum / w : nil
        }
        let hasLayers = hours.allSatisfy { $0.0.cloudLow != nil && $0.0.cloudMid != nil && $0.0.cloudHigh != nil }
        return WindowConditions(
            totalCloud: mean(\.cloudCover),
            low: hasLayers ? mean { $0.cloudLow ?? 0 } : nil,
            mid: hasLayers ? mean { $0.cloudMid ?? 0 } : nil,
            high: hasLayers ? mean { $0.cloudHigh ?? 0 } : nil,
            precipitationChance: optionalMean(\.precipitationChance),
            precipitationMm: optionalMean(\.precipitationMm),
            visibilityMeters: optionalMean(\.visibilityMeters),
            resolutions: Set(hours.map { $0.0.resolution }))
    }
}
