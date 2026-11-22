import Foundation
import IterModel
import IterAstro

// The Live Sky Index (BLUEPRINT §8.2): the sky "right now and the next few hours" for a point, from the latest
// observations, the nowcast and the forecast, scored with the same scorer as the Forecast Sky Index so the two numbers
// are directly comparable.

public enum LiveTrend: String, Codable, Hashable, Sendable {
    case rising, steady, falling, unknown
}

public enum LiveState: String, Codable, Hashable, Sendable {
    /// At least one observation carries weight at the first step and was used.
    case blended
    /// No usable observation: this is the forecast (with the nowcast where it has a step), and is labelled as such.
    case forecastOnly
    /// No forecast, but a usable observation; it is held constant, so there is no future in it.
    case observationOnly
    case noData
}

public struct LiveInputUse: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case observation, nowcast, forecast, astronomy
    }

    public var kind: Kind
    public var source: SourceID?
    public var stationName: String?
    /// Observations: the station distance, as given.
    public var distanceKm: Double?
    /// Seconds since the data's time (observations) or fetch (nowcast, forecast) at `now`; nil for astronomy.
    public var age: TimeInterval?
    /// Observations: the weight at the first step (0...0.7); nil for the others.
    public var weight: Double?

    public init(kind: Kind, source: SourceID? = nil, stationName: String? = nil, distanceKm: Double? = nil, age: TimeInterval? = nil,
                weight: Double? = nil) {
        self.kind = kind
        self.source = source
        self.stationName = stationName
        self.distanceKm = distanceKm
        self.age = age
        self.weight = weight
    }
}

/// One hourly step of the blend, from now to now plus the horizon.
public struct LiveStep: Codable, Hashable, Sendable {
    public var time: Date
    public var conditions: HourlyConditions
    /// The largest observation weight at this step, 0...0.7.
    public var obsWeight: Double

    public init(time: Date, conditions: HourlyConditions, obsWeight: Double) {
        self.time = time
        self.conditions = conditions
        self.obsWeight = obsWeight
    }
}

public struct LiveSkyReading: Codable, Hashable, Sendable {
    /// The window scored; nil when none is in progress or starting within the horizon (or `target` is not).
    public var kind: LightWindowKind?
    public var window: TimeSpan?
    public var score: Int?
    public var band: LightBand?
    /// The forecast alone for the same window, for "was 45". nil without a forecast or window.
    public var forecastScore: Int?
    public var trend: LiveTrend
    public var state: LiveState
    public var inputsUsed: [LiveInputUse]
    /// Seconds since the freshest input used.
    public var age: TimeInterval?
    public var confidence: Confidence
    public var confidenceCauses: [ConfidenceCause]
    public var notes: [SkyNote]
    /// The forecast is stale and no fresh observation backs the reading.
    public var isStale: Bool
    public var steps: [LiveStep]

    public init(kind: LightWindowKind? = nil, window: TimeSpan? = nil, score: Int? = nil, band: LightBand? = nil, forecastScore: Int? = nil,
                trend: LiveTrend = .unknown, state: LiveState, inputsUsed: [LiveInputUse] = [], age: TimeInterval? = nil,
                confidence: Confidence, confidenceCauses: [ConfidenceCause] = [], notes: [SkyNote] = [], isStale: Bool = false,
                steps: [LiveStep] = []) {
        self.kind = kind
        self.window = window
        self.score = score
        self.band = band
        self.forecastScore = forecastScore
        self.trend = trend
        self.state = state
        self.inputsUsed = inputsUsed
        self.age = age
        self.confidence = confidence
        self.confidenceCauses = confidenceCauses
        self.notes = notes
        self.isStale = isStale
        self.steps = steps
    }
}

/// Blending choices, all first guesses pending calibration:
/// - **Weight** of an observation at a step: `0.7 * max(0, 1 - ageAtStep / 90 min) * max(0, 1 - distanceKm / 50)`, where
///   `ageAtStep` is the step time minus the observation time, so influence fades into the future. A missing distance counts
///   as 50 km (weight 0) and is noted.
/// - **Best observation per field**, not a mix of observations: for each field the observation that has it and the highest
///   weight (the earliest on a tie) is blended with the base as `w * obs + (1 - w) * base`. When there is no base value for
///   the field, the observation's value is taken whole.
/// - **Base** is the nowcast step nearest the step time (within 30 minutes) for total cloud and precipitation, else the
///   forecast hour; every other field comes from the forecast hour. A nowcast step carrying either precipitation figure
///   replaces both of the forecast's precipitation fields.
/// - **Cloud layers**: an observation with all three layers blends them layer by layer. With only a total, the total is
///   blended and the base layers are scaled by (new total / base total), capped at 1; if the base total is 0 or unknown,
///   or the scale factor would exceed `maxLayerScale`, the layers are dropped (the scorer then uses its total-cloud fallback and says so).
public enum LiveSkyIndex {
    public static let maxObservationWeight = 0.7
    public static let observationLifetime: TimeInterval = 90 * 60
    public static let observationRangeKm = 50.0
    public static let nowcastTolerance: TimeInterval = 30 * 60
    /// Weight at the first step from which an observation counts as fresh and near enough to raise confidence.
    public static let freshObservationWeight = 0.35
    /// Score change over the next 60 minutes needed to call the trend.
    public static let trendThreshold = 5
    /// Base layers are scaled to a new total only up to this factor; a bigger jump (a clear forecast, an overcast report)
    /// says nothing about where the new cloud is, so the layers are dropped instead of inflated.
    public static let maxLayerScale = 2.0

    public static func weight(age: TimeInterval, distanceKm: Double?) -> Double {
        let d = distanceKm ?? observationRangeKm
        return maxObservationWeight * max(0, 1 - max(0, age) / observationLifetime) * max(0, 1 - d / observationRangeKm)
    }

    public static func reading(at place: Place, now: Date, target: LightWindowKind? = nil, forecast: ForecastSkyInputs?,
                               observations: [Sourced<WeatherObservation>], nowcast: [NowcastStep],
                               nowcastProvenance: Provenance? = nil, ephemeris: any Ephemeris,
                               horizonHours: Double = 3) -> LiveSkyReading {
        let horizonSeconds = max(0, horizonHours) * 3600
        let stepCount = max(Int(horizonHours.rounded(.down)), 1) + 1
        var notes: [SkyNote] = []

        // The window.
        let engine = LightEngine(ephemeris: ephemeris)
        let chosen = selectWindow(engine: engine, place: place, now: now, target: target, horizonSeconds: horizonSeconds)

        // Observations: weights, reasons for ignoring.
        let weightsNow = observations.map { weight(age: now.timeIntervalSince($0.value.time), distanceKm: $0.provenance.distanceKm) }
        if observations.isEmpty { notes.append(.noObservation) }
        for (o, w) in zip(observations, weightsNow) where w <= 0 {
            if o.provenance.distanceKm == nil { notes.append(.observationDistanceUnknown) }
            else if o.provenance.distanceKm! >= observationRangeKm { notes.append(.observationTooFar) }
            if now.timeIntervalSince(o.value.time) >= observationLifetime { notes.append(.observationTooOld) }
        }
        let freshObservationAtNow = weightsNow.contains { $0 > 0 }

        // The blend.
        let forecastSeries = forecast?.hourly
        var usedObservations = Set<Int>()
        var nowcastUsed = false
        var steps: [LiveStep] = []
        var rows: [HourlyConditions] = []
        for k in 0..<stepCount {
            let time = now.addingTimeInterval(Double(k) * 3600)
            let base = forecastSeries?.hour(at: time) ?? HourlyConditions(time: time)
            var row = HourlyConditions(time: time)
            let step = nearestNowcast(nowcast, to: time)
            if step != nil { nowcastUsed = true }
            let weights = observations.map { weight(age: time.timeIntervalSince($0.value.time), distanceKm: $0.provenance.distanceKm) }
            blend(into: &row, base: base, nowcast: step, observations: observations, weights: weights,
                  track: { i in if k == 0 { usedObservations.insert(i) } })
            steps.append(LiveStep(time: time, conditions: row, obsWeight: weights.max() ?? 0))
            rows.append(row)
        }

        // State.
        let state: LiveState
        if freshObservationAtNow, forecastSeries != nil { state = .blended }
        else if forecastSeries != nil { state = .forecastOnly }
        else if freshObservationAtNow { state = .observationOnly }
        else { state = .noData }

        // Inputs used.
        var uses: [LiveInputUse] = []
        for i in observations.indices where usedObservations.contains(i) && weightsNow[i] > 0 {
            let o = observations[i]
            uses.append(LiveInputUse(kind: .observation, source: o.provenance.source, stationName: o.value.stationName,
                                     distanceKm: o.provenance.distanceKm, age: max(0, now.timeIntervalSince(o.value.time)), weight: weightsNow[i]))
        }
        if nowcastUsed, state != .noData {
            uses.append(LiveInputUse(kind: .nowcast, source: nowcastProvenance?.source,
                                     age: nowcastProvenance.map { max(0, now.timeIntervalSince($0.fetchedAt)) }))
        }
        if let p = forecast?.provenance, forecastSeries != nil {
            uses.append(LiveInputUse(kind: .forecast, source: p.source, age: max(0, now.timeIntervalSince(p.fetchedAt))))
        }
        if chosen != nil { uses.append(LiveInputUse(kind: .astronomy)) }
        let age = uses.compactMap(\.age).min()

        // Staleness: the forecast is old and nothing fresh backs it.
        var forecastStale = false
        if let forecast, let p = forecast.provenance, forecast.hourly != nil {
            forecastStale = Freshness.evaluate(fetchedAt: p.fetchedAt, ttl: forecast.ttl, now: now).isStale
        }
        let isStale = forecastStale && !freshObservationAtNow

        guard let chosen, state != .noData else {
            return LiveSkyReading(kind: chosen?.kind, window: chosen?.span, state: state, inputsUsed: state == .noData ? uses.filter { $0.kind == .astronomy } : uses,
                                  age: state == .noData ? nil : age, confidence: .low,
                                  confidenceCauses: state == .noData ? [.missingPrimary(.cloudTotal)] : [],
                                  notes: tidy(notes), isStale: isStale, steps: steps)
        }

        // The blended series: forecast rows outside the blended steps, the steps themselves.
        let blendedEnd = now.addingTimeInterval(Double(stepCount) * 3600)
        var hours: [HourlyConditions] = (forecastSeries?.hours ?? []).filter {
            $0.time.addingTimeInterval(3600) <= now || $0.time >= blendedEnd
        }
        hours.append(contentsOf: rows)
        let provenance: Provenance? = forecast?.provenance ?? observations.indices.filter { weightsNow[$0] > 0 }
            .max { weightsNow[$0] < weightsNow[$1] }.map { observations[$0].provenance }
        let inputs = ForecastSkyInputs(hourly: HourlySeries(hours: hours, fieldSources: forecastSeries?.fieldSources ?? [:]),
                                       provenance: provenance, ttl: forecast?.ttl ?? observationLifetime, horizon: forecast?.horizon,
                                       aurora: forecast?.aurora, bortle: forecast?.bortle, seeing: forecast?.seeing,
                                       spreadSeries: forecast?.spreadSeries ?? [])
        // A window already under way is scored from now to its end: the past part is gone.
        let evalSpan = TimeSpan(start: max(chosen.span.start, now), end: chosen.span.end)
        let live = ForecastSkyIndex.evaluate(kind: chosen.kind, span: evalSpan, place: place, inputs: inputs, unavailable: [],
                                             ephemeris: ephemeris, now: now).assessment.skyScore

        guard let live else {
            return LiveSkyReading(kind: chosen.kind, window: chosen.span, state: .noData, inputsUsed: uses.filter { $0.kind == .astronomy },
                                  confidence: .low, confidenceCauses: [.missingPrimary(.cloudTotal)], notes: tidy(notes), isStale: isStale, steps: steps)
        }

        // The forecast alone, for comparison and as the confidence baseline.
        let forecastScore = forecast.flatMap {
            ForecastSkyIndex.evaluate(kind: chosen.kind, span: evalSpan, place: place, inputs: $0, unavailable: [],
                                      ephemeris: ephemeris, now: now).assessment.skyScore
        }

        // Confidence.
        var confidence = forecastScore?.confidence ?? live.confidence
        var causes = forecastScore?.confidenceCauses ?? live.confidenceCauses
        switch state {
        case .blended:
            if (weightsNow.max() ?? 0) >= freshObservationWeight {
                confidence = confidence == .low ? .medium : .high
            }
        case .observationOnly:
            confidence = min(live.confidence, .medium)
            causes = live.confidenceCauses
        default:
            break
        }

        // Trend: the same window's formula on the conditions now and an hour on.
        let trend: LiveTrend
        if state == .observationOnly || steps.count < 2 {
            trend = .unknown
        } else if let a = instantScore(chosen, row: rows[0], place: place, ephemeris: ephemeris),
                  let b = instantScore(chosen, row: rows[1], place: place, ephemeris: ephemeris) {
            trend = b - a >= trendThreshold ? .rising : (a - b >= trendThreshold ? .falling : .steady)
        } else {
            trend = .unknown
        }

        let outNotes = notes + live.notes.filter { if case .stale = $0 { return isStale } else { return true } }
        return LiveSkyReading(kind: chosen.kind, window: chosen.span, score: live.value, band: live.band,
                              forecastScore: forecastScore?.value, trend: trend, state: state, inputsUsed: uses, age: age,
                              confidence: confidence, confidenceCauses: causes, notes: tidy(outNotes), isStale: isStale, steps: steps)
    }

    // MARK: Pieces

    private static func tidy(_ notes: [SkyNote]) -> [SkyNote] {
        var out: [SkyNote] = []
        for n in notes.sorted(by: { $0.sortKey < $1.sortKey }) where !out.contains(n) { out.append(n) }
        return out
    }

    /// The window to score: `target` if it is in progress or starts within the horizon; else (no target) the window in
    /// progress, else the soonest starting within the horizon.
    static func selectWindow(engine: LightEngine, place: Place, now: Date, target: LightWindowKind?,
                             horizonSeconds: TimeInterval) -> (kind: LightWindowKind, span: TimeSpan)? {
        let today = LocalDay(now, in: place.timeZone)
        var all: [(kind: LightWindowKind, span: TimeSpan)] = []
        for offset in -1...1 { all += engine.windows(for: place, on: today.adding(days: offset)) }
        all = all.filter { target == nil || $0.kind == target }
        if let inProgress = all.filter({ $0.span.start <= now && now < $0.span.end }).min(by: { $0.span.start < $1.span.start }) {
            return inProgress
        }
        let horizon = now.addingTimeInterval(horizonSeconds)
        return all.filter { $0.span.start > now && $0.span.start <= horizon }.min { $0.span.start < $1.span.start }
    }

    private static func nearestNowcast(_ steps: [NowcastStep], to time: Date) -> NowcastStep? {
        steps.filter { abs($0.time.timeIntervalSince(time)) <= nowcastTolerance }
            .min { abs($0.time.timeIntervalSince(time)) < abs($1.time.timeIntervalSince(time)) }
    }

    private static func mix(_ w: Double, _ obs: Double, _ base: Double?) -> Double {
        guard let base else { return obs }
        return w * obs + (1 - w) * base
    }

    /// The observation with the field and the highest weight (earliest on a tie).
    private static func best(_ observations: [Sourced<WeatherObservation>], _ weights: [Double],
                             where has: (HourlyConditions) -> Bool) -> Int? {
        var pick: Int?
        for i in observations.indices where has(observations[i].value.conditions) {
            if pick == nil || weights[i] > weights[pick!] { pick = i }
        }
        return pick
    }

    private static func blend(into row: inout HourlyConditions, base: HourlyConditions, nowcast: NowcastStep?,
                              observations: [Sourced<WeatherObservation>], weights: [Double], track: (Int) -> Void) {
        func apply(_ i: Int, _ obs: Double, _ base: Double?) -> Double {
            if weights[i] > 0 { track(i) }
            return mix(weights[i], obs, base)
        }

        // Total cloud.
        let baseTotal = nowcast?.cloudTotal ?? base.cloudTotal
        var total = baseTotal
        if let i = best(observations, weights, where: { $0.cloudTotal != nil }), let v = observations[i].value.conditions.cloudTotal {
            total = apply(i, v, baseTotal)
        }
        row.cloudTotal = total

        // Layers.
        if let i = best(observations, weights, where: { $0.cloudLow != nil && $0.cloudMid != nil && $0.cloudHigh != nil }) {
            let c = observations[i].value.conditions
            row.cloudLow = apply(i, c.cloudLow!, base.cloudLow)
            row.cloudMid = apply(i, c.cloudMid!, base.cloudMid)
            row.cloudHigh = apply(i, c.cloudHigh!, base.cloudHigh)
        } else if let l = base.cloudLow, let m = base.cloudMid, let h = base.cloudHigh {
            if total == base.cloudTotal {
                (row.cloudLow, row.cloudMid, row.cloudHigh) = (l, m, h)
            } else if let t = total, let b = base.cloudTotal, b > 0, t / b <= maxLayerScale {
                let f = t / b
                (row.cloudLow, row.cloudMid, row.cloudHigh) = (min(1, l * f), min(1, m * f), min(1, h * f))
            }
        }

        // Precipitation: the nowcast replaces both forecast figures when it has either.
        var chance = base.precipChance, mm = base.precipMm
        if let n = nowcast, n.precipChance != nil || n.precipMmPerHour != nil {
            chance = n.precipChance
            mm = n.precipMmPerHour
        }
        if let i = best(observations, weights, where: { $0.precipChance != nil }), let v = observations[i].value.conditions.precipChance {
            chance = apply(i, v, chance)
        }
        if let i = best(observations, weights, where: { $0.precipMm != nil }), let v = observations[i].value.conditions.precipMm {
            mm = apply(i, v, mm)
        }
        row.precipChance = chance
        row.precipMm = mm

        // Everything else.
        let special: Set<HourlyField> = [.cloudTotal, .cloudLow, .cloudMid, .cloudHigh, .precipChance, .precipMm]
        for field in HourlyField.allCases where !special.contains(field) {
            var value = base[field]
            if let i = best(observations, weights, where: { $0[field] != nil }), let v = observations[i].value.conditions[field] {
                value = apply(i, v, value)
            }
            row.set(field, value)
        }
    }

    /// The window kind's score from one blended hour alone (no terrain, no flags): used only to compare the sky now with the
    /// sky an hour on.
    private static func instantScore(_ w: (kind: LightWindowKind, span: TimeSpan), row: HourlyConditions, place: Place,
                                     ephemeris: any Ephemeris) -> Int? {
        let span = TimeSpan(start: row.time, end: row.time.addingTimeInterval(3600))
        guard let c = LightEngine.conditions(in: HourlySeries(hours: [row]), over: span) else { return nil }
        var moon: MoonLight?
        if w.kind == .night {
            let mid = w.span.midpoint
            moon = MoonLight(altitude: ephemeris.moonPosition(at: mid, coordinate: place.coordinate).altitude,
                             illumination: ephemeris.moonPhase(at: mid).illumination)
        }
        return WindowScorer.score(kind: w.kind, conditions: c, moon: moon).value
    }
}

extension HourlyConditions {
    mutating func set(_ field: HourlyField, _ value: Double?) {
        switch field {
        case .cloudTotal: cloudTotal = value
        case .cloudLow: cloudLow = value
        case .cloudMid: cloudMid = value
        case .cloudHigh: cloudHigh = value
        case .cloudBaseM: cloudBaseM = value
        case .precipChance: precipChance = value
        case .precipMm: precipMm = value
        case .visibilityKm: visibilityKm = value
        case .tempC: tempC = value
        case .dewpointC: dewpointC = value
        case .rhPercent: rhPercent = value
        case .windMs: windMs = value
        case .gustMs: gustMs = value
        case .windDirDeg: windDirDeg = value
        case .aod550: aod550 = value
        case .smokeUgm3: smokeUgm3 = value
        case .pm25: pm25 = value
        }
    }
}
