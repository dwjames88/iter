import Foundation
import Testing
import IterModel
import IterAstro
@testable import IterSky

private let place = makePlace()
private let eph = FixedEphemeris()
/// 17:00 on the test day: golden evening (17:30 to 18:20) starts in half an hour.
private let t17 = FixedEphemeris.at(testDay, 17.0)

private func clearForecast(fetchedAt: Date? = nil, ttl: TimeInterval = Freshness.defaultTTL, _ w: Wx = Wx(total: 0.05, low: 0, mid: 0.05, high: 0.05)) -> ForecastSkyInputs {
    forecast(fetchedAt: fetchedAt ?? t17.addingTimeInterval(-3600), ttl: ttl) { _ in w }
}

private func obs(ageMinutes: Double = 5, km: Double? = 5, _ c: HourlyConditions? = nil, station: String = "KTST", now: Date = t17) -> Sourced<WeatherObservation> {
    let time = now.addingTimeInterval(-ageMinutes * 60)
    var p = provenance(fetchedAt: time)
    p.source = "test.metar"
    p.distanceKm = km
    return Sourced(value: WeatherObservation(time: time, stationName: station,
                                             conditions: c ?? HourlyConditions(time: time, cloudTotal: 1.0, visibilityKm: 10)), provenance: p)
}

private func read(now: Date = t17, target: LightWindowKind? = nil, forecast: ForecastSkyInputs?, obs: [Sourced<WeatherObservation>] = [],
                  nowcast: [NowcastStep] = [], nowcastProvenance: Provenance? = nil) -> LiveSkyReading {
    LiveSkyIndex.reading(at: place, now: now, target: target, forecast: forecast, observations: obs, nowcast: nowcast,
                         nowcastProvenance: nowcastProvenance, ephemeris: eph)
}

@Suite struct LiveBlendTests {
    @Test func aFreshNearOvercastObservationPullsTheLiveScoreBelowTheForecast() throws {
        // 18:00, the golden evening in progress, the forecast clear, the METAR overcast with low cloud.
        let now = FixedEphemeris.at(testDay, 18.0)
        let overcast = HourlyConditions(time: now, cloudTotal: 1.0, cloudLow: 0.9, cloudMid: 0.9, cloudHigh: 0.9, visibilityKm: 10)
        let r = read(now: now, forecast: clearForecast(fetchedAt: now.addingTimeInterval(-3600)), obs: [obs(overcast, now: now)])
        #expect(r.state == .blended && r.kind == .goldenEvening)
        let live = try #require(r.score), was = try #require(r.forecastScore)
        #expect(live < was - 15, "live \(live) forecast \(was)")
        #expect(r.band == LightBand(score: live))
        let station = try #require(r.inputsUsed.first { $0.kind == .observation })
        #expect(station.distanceKm == 5 && station.age == 300 && station.stationName == "KTST" && station.source == "test.metar")
        #expect(abs((station.weight ?? 0) - LiveSkyIndex.weight(age: 300, distanceKm: 5)) < 1e-9)
        #expect(r.inputsUsed.contains { $0.kind == .forecast } && r.inputsUsed.contains { $0.kind == .astronomy })
        #expect(r.age == 300)
        // The observation fades into the future, toward the forecast.
        #expect(r.steps.count == 4 && r.steps[0].obsWeight > r.steps[1].obsWeight && r.steps[3].obsWeight == 0)
        #expect(r.steps[0].conditions.cloudTotal! > r.steps[2].conditions.cloudTotal!)
        #expect(r.trend == .rising)
    }

    @Test func weightEndpoints() {
        let w = LiveSkyIndex.weight
        #expect(w(0, 0) == 0.7)
        #expect(abs(w(45 * 60, 0) - 0.35) < 1e-12 && w(90 * 60, 0) == 0 && w(3 * 3600, 0) == 0)
        #expect(abs(w(0, 25) - 0.35) < 1e-12 && w(0, 50) == 0 && w(0, 80) == 0)
        #expect(abs(w(45 * 60, 25) - 0.175) < 1e-12)
        #expect(w(0, nil) == 0)
        #expect(w(-600, 0) == 0.7)   // an observation stamped slightly in the future counts as age 0
    }

    @Test func anObservationTwoHoursOldIsListedAsNotUsedWithItsReason() {
        let r = read(forecast: clearForecast(), obs: [obs(ageMinutes: 120)])
        #expect(r.state == .forecastOnly && r.score == r.forecastScore)
        #expect(r.notes.contains(.observationTooOld) && !r.inputsUsed.contains { $0.kind == .observation })
    }

    @Test func anObservationEightyKilometresAwayIsNotUsed() {
        let r = read(forecast: clearForecast(), obs: [obs(km: 80)])
        #expect(r.state == .forecastOnly && r.notes.contains(.observationTooFar) && r.score == r.forecastScore)
    }

    @Test func aMissingDistanceCountsAsFiftyKilometres() {
        let r = read(forecast: clearForecast(), obs: [obs(km: nil)])
        #expect(r.state == .forecastOnly && r.notes.contains(.observationDistanceUnknown))
    }

    @Test func noObservationsIsForecastOnlyAndSaysSo() {
        let f = clearForecast()
        let r = read(forecast: f)
        #expect(r.state == .forecastOnly && r.notes.contains(.noObservation) && r.score == r.forecastScore && r.score != nil)
        #expect(r.confidence == ForecastSkyIndex.score(kind: .goldenEvening, span: r.window!, place: place, inputs: f, ephemeris: eph, now: t17).skyScore?.confidence)
    }

    @Test func theNearestStationWinsAField() throws {
        let near = obs(km: 5, HourlyConditions(time: t17, cloudTotal: 1.0), station: "NEAR")
        let far = obs(km: 40, HourlyConditions(time: t17, cloudTotal: 0.0), station: "FAR")
        let r = read(forecast: clearForecast(Wx(total: 0.5, low: nil, mid: nil, high: nil)), obs: [far, near])
        #expect(r.inputsUsed.filter { $0.kind == .observation }.map(\.stationName) == ["NEAR"])
        #expect(r.steps[0].conditions.cloudTotal! > 0.7)
    }

    @Test func aTotalOnlyObservationScalesTheForecastLayers() throws {
        let f = clearForecast(Wx(total: 0.4, low: 0.1, mid: 0.4, high: 0.4))
        let r = read(forecast: f, obs: [obs(ageMinutes: 0, km: 0, HourlyConditions(time: t17, cloudTotal: 0.8))])
        let c = r.steps[0].conditions
        let total = 0.7 * 0.8 + 0.3 * 0.4
        #expect(abs(c.cloudTotal! - total) < 1e-9)
        #expect(abs(c.cloudMid! - min(1, 0.4 * total / 0.4)) < 1e-9 && abs(c.cloudLow! - 0.1 * total / 0.4) < 1e-9)
        // A jump of more than twice the forecast total, or from a clear forecast, says nothing about where the cloud is.
        let jump = read(forecast: clearForecast(), obs: [obs(ageMinutes: 0, km: 0, HourlyConditions(time: t17, cloudTotal: 1.0))])
        #expect(jump.steps[0].conditions.cloudLow == nil)
        // From a clear forecast total the layers cannot be scaled and are dropped, so the scorer says it used the total.
        let clear = read(forecast: clearForecast(Wx(total: 0.0, low: 0, mid: 0, high: 0)), obs: [obs(ageMinutes: 0, km: 0, HourlyConditions(time: t17, cloudTotal: 0.8))])
        #expect(clear.steps[0].conditions.cloudLow == nil && clear.notes.contains(.missing(.cloudLayers)))
    }

    @Test func anObservationWithLayersBlendsThemLayerByLayer() {
        let f = clearForecast(Wx(total: 0.2, low: 0, mid: 0.2, high: 0.2))
        let o = HourlyConditions(time: t17, cloudTotal: 0.9, cloudLow: 0.9, cloudMid: 0.1, cloudHigh: 0.1)
        let c = read(forecast: f, obs: [obs(ageMinutes: 0, km: 0, o)]).steps[0].conditions
        #expect(abs(c.cloudLow! - 0.63) < 1e-9 && abs(c.cloudMid! - (0.07 + 0.06)) < 1e-9)
    }
}

@Suite struct LiveAvailabilityTests {
    @Test func noForecastWithAnObservationIsObservationOnly() {
        let r = read(forecast: nil, obs: [obs(ageMinutes: 5, km: 5, HourlyConditions(time: t17, cloudTotal: 0.3, cloudLow: 0.1, cloudMid: 0.3, cloudHigh: 0.3, precipChance: 0))])
        #expect(r.state == .observationOnly && r.score != nil && r.forecastScore == nil)
        #expect(r.confidence <= .medium && r.trend == .unknown)
        #expect(r.inputsUsed.contains { $0.kind == .observation } && !r.inputsUsed.contains { $0.kind == .forecast })
    }

    @Test func nothingAtAllIsNoDataWithNoScore() {
        let r = read(forecast: nil)
        #expect(r.state == .noData && r.score == nil && r.band == nil && r.forecastScore == nil && r.confidence == .low)
        #expect(r.notes.contains(.noObservation) && r.trend == .unknown)
        // An observation too old to count, and no forecast, is still no data.
        let old = read(forecast: nil, obs: [obs(ageMinutes: 200)])
        #expect(old.state == .noData && old.score == nil && old.notes.contains(.observationTooOld))
    }

    @Test func nowcastAloneWithoutForecastOrObservationIsNotEnough() {
        let r = read(forecast: nil, nowcast: [NowcastStep(time: t17, cloudTotal: 0.2)])
        #expect(r.state == .noData && r.score == nil)
    }

    @Test func aFreshNearObservationRaisesConfidenceOneStepCappedAtHigh() {
        // A forecast fetched 40 hours before the window is medium; the observation lifts it to high.
        let old = clearForecast(fetchedAt: t17.addingTimeInterval(-40 * 3600), ttl: 100 * 3600)
        let withoutObs = read(forecast: old)
        let withObs = read(forecast: old, obs: [obs()])
        #expect(withoutObs.confidence == .medium && withObs.confidence == .high)
        // A far observation does not.
        #expect(read(forecast: old, obs: [obs(km: 45)]).confidence == .medium)
        // Already high stays high.
        #expect(read(forecast: clearForecast(), obs: [obs()]).confidence == .high)
    }

    @Test func aStaleForecastIsStaleUnlessAFreshObservationBacksIt() {
        let stale = clearForecast(fetchedAt: t17.addingTimeInterval(-5 * 3600))
        let alone = read(forecast: stale)
        #expect(alone.isStale && alone.notes.contains { if case .stale = $0 { true } else { false } })
        let backed = read(forecast: stale, obs: [obs()])
        #expect(!backed.isStale && !backed.notes.contains { if case .stale = $0 { true } else { false } })
        // An observation too old to count does not rescue it.
        #expect(read(forecast: stale, obs: [obs(ageMinutes: 200)]).isStale)
        #expect(!read(forecast: clearForecast()).isStale)
    }
}

@Suite struct LiveNowcastTests {
    @Test func theNowcastIsUsedBeforeTheForecast() throws {
        let nc = (0...3).map { NowcastStep(time: t17.addingTimeInterval(Double($0) * 3600), precipMmPerHour: 2, cloudTotal: 1.0) }
        var p = provenance(fetchedAt: t17.addingTimeInterval(-300))
        p.source = "test.nowcast"
        let r = read(forecast: clearForecast(), nowcast: nc, nowcastProvenance: p)
        #expect(r.state == .forecastOnly)
        #expect(r.steps[0].conditions.cloudTotal == 1.0 && r.steps[0].conditions.precipMm == 2 && r.steps[0].conditions.precipChance == nil)
        #expect(try #require(r.score) < (try #require(r.forecastScore)) - 20)
        let use = try #require(r.inputsUsed.first { $0.kind == .nowcast })
        #expect(use.source == "test.nowcast" && use.age == 300)
        #expect(r.notes.contains(.precipitationFromAmount))
    }

    @Test func aNowcastStepFarFromTheStepIsIgnored() {
        let r = read(forecast: clearForecast(), nowcast: [NowcastStep(time: t17.addingTimeInterval(3 * 3600), cloudTotal: 1.0)])
        #expect(r.steps[0].conditions.cloudTotal == 0.05 && r.steps[3].conditions.cloudTotal == 1.0)
    }

    @Test func theTrendFollowsAClearingOrCloudingNowcast() {
        func trend(now c0: Double, then c1: Double) -> LiveTrend {
            read(forecast: clearForecast(), nowcast: [NowcastStep(time: t17, cloudTotal: c0), NowcastStep(time: t17.addingTimeInterval(3600), cloudTotal: c1)]).trend
        }
        #expect(trend(now: 0.95, then: 0.3) == .rising)
        #expect(trend(now: 0.3, then: 0.95) == .falling)
        #expect(trend(now: 0.3, then: 0.3) == .steady)
        #expect(read(forecast: clearForecast()).trend == .steady)
    }
}

@Suite struct LiveWindowSelectionTests {
    @Test func aWindowInProgressIsScored() {
        let now = FixedEphemeris.at(testDay, 18.0)
        let r = read(now: now, forecast: clearForecast(fetchedAt: now.addingTimeInterval(-3600)), obs: [obs(now: now)])
        #expect(r.kind == .goldenEvening && r.window!.contains(now))
    }

    @Test func theNextWindowStartingWithinThreeHoursIsScored() {
        #expect(read(forecast: clearForecast()).kind == .goldenEvening)
        // 19:00: blue evening has ended at 18:50; night starts at 20:10.
        let now = FixedEphemeris.at(testDay, 19.0)
        let r = read(now: now, forecast: clearForecast(fetchedAt: now.addingTimeInterval(-3600)))
        #expect(r.kind == .night && r.window?.start == FixedEphemeris.at(testDay, 20.167))
    }

    @Test func nothingWithinTheHorizonMeansNoKindAndNoScoreButStillAState() {
        let now = FixedEphemeris.at(testDay, 12.0)
        let r = read(now: now, forecast: clearForecast(fetchedAt: now.addingTimeInterval(-3600)), obs: [obs(now: now)])
        #expect(r.kind == nil && r.window == nil && r.score == nil && r.forecastScore == nil)
        #expect(r.state == .blended && r.steps.count == 4 && r.steps[0].conditions.cloudTotal! > 0.5)
    }

    @Test func aTargetIsScoredOnlyIfInProgressOrStartingSoon() {
        let f = clearForecast()
        #expect(read(target: .blueEvening, forecast: f).kind == .blueEvening)        // starts 18:20, within 3 h
        #expect(read(target: .night, forecast: f).kind == nil)                        // 20:10 is more than 3 h from 17:00
        #expect(read(target: .goldenMorning, forecast: f).kind == nil)                // tomorrow's, hours away
        let inProgress = read(now: FixedEphemeris.at(testDay, 18.0), target: .goldenEvening, forecast: f)
        #expect(inProgress.kind == .goldenEvening)
        // A night window still running after midnight belongs to the previous day.
        let night = LightEngine(ephemeris: eph).windows(for: place, on: testDay).first { $0.kind == .night }!.span
        let late = night.midpoint
        #expect(read(now: late, target: .night, forecast: forecast(fetchedAt: late.addingTimeInterval(-3600)) { _ in Wx() }).kind == .night)
    }

    @Test func aReadingRoundTripsThroughCodable() throws {
        let r = read(forecast: clearForecast(), obs: [obs()], nowcast: [NowcastStep(time: t17, cloudTotal: 0.5)])
        #expect(try JSONDecoder().decode(LiveSkyReading.self, from: JSONEncoder().encode(r)) == r)
    }
}
