import Foundation
import IterModel
import IterAstro

/// The Forecast Sky Index: one score per shooting window from an hourly forecast, the sky and the terrain.
/// Pure and deterministic: the caller supplies `now`.
///
/// Composition (BLUEPRINT §8.1): a baseline of 60 plus signed factor points, an overcast ceiling on daytime windows,
/// then a clamp to 0...100. Factor ranges, in points, each only when its input is present:
/// - Cloud colour and low-cloud block (golden, blue) or total cloud (night): the old curves, about -58 to +22.
/// - Precipitation: 0 to -40. Visibility: -30 to +2.
/// - Moon (night): +6 (down or thin) to -36 (full and high).
/// - Aerosol or smoke: golden and blue about -20 to +4; night 0 to -14.
/// - Terrain: golden evening and morning 0 to -30 (proportional to the fraction of the window lost); blue 0 to -4.
/// - Humidity (night): 0 to -4. Wind (blue, night): 0 or -2 to -6.
/// - Milky Way core up in dark with the moon down (night): +4.
/// - Bortle (night, only if supplied): +6 to -14. Seeing (night, only if supplied): +3 to -4.
/// Aurora and fog are flags, not terms. Every added curve is a first guess pending calibration.
public enum ForecastSkyIndex {
    /// The window's assessment. `unavailable` is what the data layer said when `inputs` is nil or has no hourly data.
    public static func score(kind: LightWindowKind, span: TimeSpan, place: Place, inputs: ForecastSkyInputs?,
                             unavailable: [NoDataReason] = [], ephemeris: any Ephemeris, now: Date) -> LightAssessment {
        evaluate(kind: kind, span: span, place: place, inputs: inputs, unavailable: unavailable, ephemeris: ephemeris, now: now).assessment
    }

    /// The window after the terrain skyline, or nil when the place has no horizon, the window is not golden, or nothing changed.
    public static func effectiveSpan(kind: LightWindowKind, span: TimeSpan, place: Place, horizon: HorizonProfile? = nil,
                                     ephemeris: any Ephemeris) -> TimeSpan? {
        guard let horizon = horizon ?? place.horizon else { return nil }
        return Terrain.assess(kind: kind, span: span, coordinate: place.coordinate, horizon: horizon, ephemeris: ephemeris)?.effectiveSpan
    }

    /// The Kp at which aurora is plausible at a latitude, by absolute geographic latitude. A rough table, not a
    /// geomagnetic model: 65 and up Kp 2, 60 Kp 3, 55 Kp 4, 50 Kp 5, 45 Kp 6, 40 Kp 7, lower Kp 9.
    public static func auroraKpThreshold(latitude: Double) -> Double {
        switch abs(latitude) {
        case 65...: 2
        case 60..<65: 3
        case 55..<60: 4
        case 50..<55: 5
        case 45..<50: 6
        case 40..<45: 7
        default: 9
        }
    }

    /// Probability at or above this percent flags aurora.
    public static let auroraProbabilityThreshold = 10.0

    struct Evaluation {
        var assessment: LightAssessment
        var effectiveSpan: TimeSpan?
    }

    static func evaluate(kind: LightWindowKind, span: TimeSpan, place: Place, inputs: ForecastSkyInputs?,
                         unavailable: [NoDataReason], ephemeris: any Ephemeris, now: Date) -> Evaluation {
        // Terrain depends on the sun only, so it is known even when there is no forecast.
        let horizon = inputs?.horizon ?? place.horizon
        let terrain = horizon.flatMap { Terrain.assess(kind: kind, span: span, coordinate: place.coordinate, horizon: $0, ephemeris: ephemeris) }
        func result(_ a: LightAssessment) -> Evaluation { Evaluation(assessment: a, effectiveSpan: terrain?.effectiveSpan) }

        if span.end <= now { return result(.unavailable(.inThePast)) }
        guard let inputs, let hourly = inputs.hourly else {
            return result(.unavailable(unavailable.isEmpty ? .notLoaded : .noForecast(unavailable)))
        }
        guard hourly.firstTime != nil, let horizonDate = hourly.horizonDate else { return result(.unavailable(.beyondHorizon)) }
        // A forecast with no provenance cannot be dated, so its age, lead time and staleness are unknown: not scored.
        guard let provenance = inputs.provenance else { return result(.unavailable(.noForecast([.notProvidedBySource]))) }

        let mid = span.midpoint
        // Beyond the forecast: carry the last forecast day's weather forward, at the lowest confidence.
        var scoringSpan = span
        var persisted = false
        if mid >= horizonDate {
            let days = Int((mid.timeIntervalSince(horizonDate) / 86_400).rounded(.down)) + 1
            let shift = TimeInterval(days) * 86_400
            scoringSpan = TimeSpan(start: span.start.addingTimeInterval(-shift), end: span.end.addingTimeInterval(-shift))
            persisted = true
        }
        let conditions: WindowConditions
        switch LightEngine.aggregate(hourly, over: scoringSpan) {
        case .conditions(let c): conditions = c
        case .noHours: return result(.unavailable(.beyondHorizon))
        case .noCloud: return result(.unavailable(.noForecast([.notProvidedBySource])))
        }

        // Extras the weather does not carry.
        var extras = ScoringExtras(terrain: terrain, bortle: inputs.bortle, seeing: inputs.seeing, latitude: place.coordinate.latitude)
        var moon: MoonLight?
        if kind == .night {
            moon = MoonLight(altitude: ephemeris.moonPosition(at: mid, coordinate: place.coordinate).altitude,
                             illumination: ephemeris.moonPhase(at: mid).illumination)
            extras.milkyWay = GalacticCentre.visibility(over: span, at: place.coordinate, ephemeris: ephemeris)
            extras.aurora = auroraSignal(inputs.aurora, span: span, latitude: place.coordinate.latitude)
        }
        let scored = WindowScorer.score(kind: kind, conditions: conditions, moon: moon, extras: extras)

        // Staleness and source spread.
        let freshness = Freshness.evaluate(fetchedAt: provenance.fetchedAt, ttl: inputs.ttl, now: now)
        var notes = scored.notes
        var staleAge: TimeInterval?
        if case .stale(let age) = freshness {
            staleAge = age
            notes.append(.stale(age: age))
        }
        if persisted { notes.append(.persistence) }
        var spread = false
        if !inputs.spreadSeries.isEmpty {
            var totals = [conditions.totalCloud]
            for other in inputs.spreadSeries {
                if case .conditions(let c) = LightEngine.aggregate(other, over: scoringSpan), !c.totalCloudIsDerived { totals.append(c.totalCloud) }
            }
            if let low = totals.min(), let high = totals.max(), high - low > ConfidenceModel.spreadLimit {
                spread = true
                notes.append(.sourceSpread(low: low, high: high))
            } else if conditions.hasLayers {
                // Two models can agree on total cover and still disagree on where it sits (low cloud blocks the light,
                // high cloud colours it), which is what moves a golden-hour score most. Compare the low and high layers
                // too; the note carries the pair of values for the layer that disagrees most.
                var worst: (low: Double, high: Double)?
                for other in inputs.spreadSeries {
                    guard case .conditions(let c) = LightEngine.aggregate(other, over: scoringSpan), c.hasLayers else { continue }
                    for (a, b) in [(conditions.low, c.low), (conditions.high, c.high)] {
                        guard let a, let b, abs(a - b) > ConfidenceModel.spreadLimit else { continue }
                        if worst.map({ abs(a - b) > $0.high - $0.low }) ?? true { worst = (min(a, b), max(a, b)) }
                    }
                }
                if let worst {
                    spread = true
                    notes.append(.sourceSpread(low: worst.low, high: worst.high))
                }
            }
        }

        let issuedOrFetched = provenance.issuedAt ?? provenance.fetchedAt
        let lead = mid.timeIntervalSince(issuedOrFetched) / 3600
        let confidence = ConfidenceModel.evaluate(leadHours: lead, missingPrimary: scored.missingPrimary,
                                                  missingSecondary: scored.missingSecondary, staleAge: staleAge,
                                                  sourceSpread: spread, persisted: persisted)

        let age = max(0, now.timeIntervalSince(provenance.fetchedAt))
        let uses = scored.used.map { input in
            SkyInputUse(input: input, source: source(of: input, series: hourly, inputs: inputs, provenance: provenance),
                        age: ageOf(input, inputs: inputs, now: now, hourlyAge: age))
        }
        var sortedNotes: [SkyNote] = []
        for note in notes.sorted(by: { $0.sortKey < $1.sortKey }) where !sortedNotes.contains(note) { sortedNotes.append(note) }

        let score = SkyScore(value: scored.value, band: LightBand(score: scored.value), confidence: confidence.level,
                             confidenceValue: confidence.normalised, confidenceCauses: confidence.causes,
                             range: ConfidenceModel.range(value: scored.value, confidence: confidence.level),
                             contributors: scored.contributors, notes: sortedNotes, flags: scored.flags, inputs: uses,
                             transparency: scored.transparency, source: provenance.source, forecastIssuedAt: provenance.issuedAt,
                             forecastFetchedAt: provenance.fetchedAt, leadHours: lead, age: age, isStale: freshness.isStale,
                             model: provenance.model)
        return result(.scored(score))
    }

    // MARK: Pieces

    private static func auroraSignal(_ outlook: AuroraOutlook?, span: TimeSpan, latitude: Double) -> AuroraSignal {
        guard let outlook else { return AuroraSignal() }
        let steps = outlook.kp.filter { $0.time <= span.end && $0.time.addingTimeInterval(3 * 3600) > span.start }
        let kp = steps.map(\.value).max()
        let byKp = kp.map { $0 >= auroraKpThreshold(latitude: latitude) } ?? false
        let byProbability = (outlook.probabilityPercent ?? 0) >= auroraProbabilityThreshold
        return AuroraSignal(outlookPresent: true, probabilityPercent: outlook.probabilityPercent, kp: kp, triggered: byKp || byProbability)
    }

    private static func field(for input: SkyInput, in series: HourlySeries) -> HourlyField? {
        switch input {
        case .cloudLayers: .cloudLow
        case .cloudTotal: .cloudTotal
        case .precipitation: series.hours.contains { $0.precipChance != nil } ? .precipChance : .precipMm
        case .visibility: .visibilityKm
        case .aerosol: .aod550
        case .smoke: .smokeUgm3
        case .humidity: .rhPercent
        case .wind: .windMs
        case .horizon, .moon, .galacticCentre, .aurora, .lightPollution, .seeing: nil
        }
    }

    private static func source(of input: SkyInput, series: HourlySeries, inputs: ForecastSkyInputs, provenance: Provenance) -> SourceID? {
        switch input {
        case .aurora: return inputs.aurora?.provenance?.source
        case .horizon, .moon, .galacticCentre, .lightPollution, .seeing: return nil
        default:
            guard let f = field(for: input, in: series) else { return nil }
            return series.source(of: f) ?? provenance.source
        }
    }

    private static func ageOf(_ input: SkyInput, inputs: ForecastSkyInputs, now: Date, hourlyAge: TimeInterval) -> TimeInterval? {
        switch input {
        case .aurora: return inputs.aurora?.provenance.map { max(0, now.timeIntervalSince($0.fetchedAt)) }
        case .horizon, .moon, .galacticCentre, .lightPollution, .seeing: return nil
        default: return hourlyAge
        }
    }
}
