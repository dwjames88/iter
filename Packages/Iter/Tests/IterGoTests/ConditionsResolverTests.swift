import Foundation
import Testing
import IterModel
import IterSky
import IterSources
import IterPlan
import IterConditions
import IterGo

private let stop = cStop("Overlook", session: .goldenEvening)

// MARK: Mapping

@Test func mappingsFollowRawValues() {
    for b in LightBand.allCases { #expect(GoBand(b).rawValue == "\(b)") }
    for c in Confidence.allCases { #expect(GoConfidence(c).rawValue == c.rawValue) }
    #expect(GoTrend(.rising) == .rising && GoTrend(.falling) == .falling && GoTrend(.steady) == .steady && GoTrend(.unknown) == .unknown)
}

// MARK: Resolver

@Test func liveReadingBlended() {
    let live = cLive(stop.place, reading: cReading(score: 72, forecast: 60, state: .blended, trend: .rising, age: 300))
    let sky = SkyReadingResolver.resolve(stop: stop, live: live, report: nil, history: ForecastTrendTracker(), now: cT0)
    #expect(sky.basis == .blended)
    #expect(sky.liveScore == 72 && sky.forecastScore == 60 && sky.displayScore == 72)
    #expect(sky.band == .good)
    #expect(sky.confidence == .high)
    #expect(sky.trend == .rising)
    #expect(sky.asOf == cT0.addingTimeInterval(-300))
    #expect(sky.notice == nil && !sky.isStale)
    #expect(sky.stopID == stop.id && sky.windowKind == .goldenEvening)
}

@Test func liveReadingForecastOnlyAndObservationOnly() {
    let fo = cLive(stop.place, reading: cReading(score: 50, forecast: 50, state: .forecastOnly, stale: true), notice: .forecastOnly)
    let a = SkyReadingResolver.resolve(stop: stop, live: fo, report: nil, history: ForecastTrendTracker(), now: cT0)
    #expect(a.basis == .forecastOnly)
    #expect(a.notice == "Forecast only, no recent observation")
    #expect(a.isStale)
    let oo = cLive(stop.place, reading: cReading(score: 80, forecast: nil, state: .observationOnly))
    let b = SkyReadingResolver.resolve(stop: stop, live: oo, report: nil, history: ForecastTrendTracker(), now: cT0)
    #expect(b.basis == .observationOnly && b.forecastScore == nil && b.band == .great)
}

@Test func liveNoticeFallsBackToOfflineNote() {
    let live = cLive(stop.place, reading: cReading(score: 60))
    let report = cReport(stop.place, windows: [], offlineNote: "Forecast from 06:29, offline")
    let sky = SkyReadingResolver.resolve(stop: stop, live: live, report: report, history: ForecastTrendTracker(), now: cT0)
    #expect(sky.notice == "Forecast from 06:29, offline")
}

@Test func noLiveScoreFallsBackToTheStopsWindowForecast() {
    let live = cLive(stop.place, reading: cReading(score: nil))
    let report = cReport(stop.place, windows: [cWindow(.goldenMorning, score: 90), cWindow(.goldenEvening, score: 66, confidence: .low)])
    let sky = SkyReadingResolver.resolve(stop: stop, live: live, report: report, history: ForecastTrendTracker(), now: cT0)
    #expect(sky.basis == .nextWindowForecast)
    #expect(sky.liveScore == nil && sky.forecastScore == 66 && sky.displayScore == 66)
    #expect(sky.band == .good && sky.confidence == .low)
    #expect(sky.windowKind == .goldenEvening)
    #expect(sky.windowStart == cT0.addingTimeInterval(4 * 3600))
    #expect(sky.trend == .unknown)
}

@Test func forecastTrendAcrossThreeRefreshes() {
    var h = ForecastTrendTracker()
    let report = cReport(stop.place, windows: [cWindow(.goldenEvening, score: 60)])
    h.record(stopID: stop.id, kind: .goldenEvening, score: 60)
    #expect(SkyReadingResolver.resolve(stop: stop, live: nil, report: report, history: h, now: cT0).trend == .unknown)
    h.record(stopID: stop.id, kind: .goldenEvening, score: 63)
    #expect(SkyReadingResolver.resolve(stop: stop, live: nil, report: report, history: h, now: cT0).trend == .steady)
    h.record(stopID: stop.id, kind: .goldenEvening, score: 66)
    #expect(SkyReadingResolver.resolve(stop: stop, live: nil, report: report, history: h, now: cT0).trend == .rising)
    // A fourth sample pushes the oldest out: 63, 66, 58 is 5 down from the oldest kept.
    h.record(stopID: stop.id, kind: .goldenEvening, score: 58)
    #expect(h.samples(stopID: stop.id, kind: .goldenEvening) == [63, 66, 58])
    #expect(h.trend(stopID: stop.id, kind: .goldenEvening) == .falling)
    // Exactly 4 points is steady; another window is separate.
    var g = ForecastTrendTracker()
    g.record(stopID: stop.id, kind: .goldenEvening, score: 60)
    g.record(stopID: stop.id, kind: .goldenEvening, score: 64)
    #expect(g.trend(stopID: stop.id, kind: .goldenEvening) == .steady)
    #expect(g.trend(stopID: stop.id, kind: .blueEvening) == .unknown)
}

@Test func noDataAtAll() {
    for (live, report) in [(nil as LiveConditions?, nil as SkyReport?),
                           (cLive(stop.place, reading: cReading(score: nil)), cReport(stop.place, windows: [cWindow(.goldenEvening, score: nil)]))] {
        let sky = SkyReadingResolver.resolve(stop: stop, live: live, report: report, history: ForecastTrendTracker(), now: cT0)
        #expect(sky.basis == .noData)
        #expect(sky.notice == "No live data")
        #expect(sky.displayScore == nil && sky.band == nil)
    }
}

// MARK: Weather

@Test func weatherFromObservation() {
    let c = HourlyConditions(time: cT0, cloudTotal: 0.4, precipChance: 0.1, visibilityKm: 16, tempC: 12, windMs: 3)
    let obs = CurrentObservation(conditions: c, stationName: "KDEN", distanceKm: 7, age: 600, provenance: cProvenance())
    let live = cLive(stop.place, reading: cReading(score: 60), current: obs, forecastHour: HourlyConditions(time: cT0, tempC: 99))
    let w = ConditionsWeather.info(from: live, subject: .here)
    #expect(w?.basis == .observation && w?.subject == .here)
    #expect(w?.tempC == 12 && w?.cloudTotal == 0.4 && w?.visibilityKm == 16 && w?.precipChance == 0.1 && w?.windMs == 3)
    #expect(w?.stationName == "KDEN" && w?.stationDistanceKm == 7)
    #expect(w?.asOf == cT0.addingTimeInterval(-600))
}

@Test func weatherFromForecastHourWhenNoObservation() {
    let hour = HourlyConditions(time: cT0, cloudTotal: 0.8, visibilityKm: 10, tempC: 9)
    let live = cLive(stop.place, reading: cReading(score: 60), forecastHour: hour)
    let w = ConditionsWeather.info(from: live, subject: .stop(stop.id))
    #expect(w?.basis == .forecast && w?.subject == .stop(stop.id))
    #expect(w?.cloudTotal == 0.8 && w?.stationName == nil && w?.asOf == cT0)
    #expect(ConditionsWeather.info(from: cLive(stop.place, reading: cReading(score: 60)), subject: .here) == nil)
}

// MARK: Alerts

@Test func alertsInForceOnly() {
    let now = cT0
    let alerts = [
        WeatherAlert(id: "ended", event: "Wind Advisory", severity: .minor, ends: now.addingTimeInterval(-60)),
        WeatherAlert(id: "expired", event: "Fog", severity: .minor, expires: now.addingTimeInterval(-1)),
        WeatherAlert(id: "open", event: "Heat", severity: .moderate),
        WeatherAlert(id: "storm", event: "Severe Thunderstorm Warning", headline: "Storm", severity: .severe, ends: now.addingTimeInterval(3600)),
        WeatherAlert(id: "expiring", event: "Flood Watch", severity: .minor, ends: nil, expires: now.addingTimeInterval(600)),
    ]
    let out = ConditionsWeather.alerts(from: cReport(stop.place, windows: [], alerts: alerts), now: now)
    #expect(out.map(\.id) == ["storm", "open", "expiring"])
    #expect(out.first?.severity == "Severe" && out.first?.headline == "Storm" && out.first?.ends == now.addingTimeInterval(3600))
    #expect(ConditionsWeather.alerts(from: nil, now: now).isEmpty)
    #expect(ConditionsWeather.alerts(from: cReport(stop.place, windows: []), now: now).isEmpty)
}

// MARK: Offline flag

@Test func offlineFromReasonsAndNotes() {
    let ok = cLive(stop.place, reading: cReading(score: 60))
    #expect(!ConditionsWeather.isOffline(live: [ok], reports: [cReport(stop.place, windows: [])]))
    let offNowcast = cLive(stop.place, reading: cReading(score: 60), nowcast: .none([.offline(lastGood: nil)]))
    #expect(ConditionsWeather.isOffline(live: [offNowcast], reports: []))
    let offNote = cReport(stop.place, windows: [], offlineNote: "Forecast from 06:29, offline")
    #expect(ConditionsWeather.isOffline(live: [], reports: [offNote]))
    let rate = cLive(stop.place, reading: cReading(score: 60), nowcast: .none([.rateLimited(retryAfter: nil)]))
    #expect(!ConditionsWeather.isOffline(live: [rate], reports: []))
}

// MARK: Change detection

private func observe(_ state: inout ConditionsAlertState, _ score: Int, at t: TimeInterval = 0, live: LiveConditions? = nil) -> ConditionsChange? {
    ConditionsChangeDetector.observe(state: &state, stop: stop, score: score, live: live, now: cT0.addingTimeInterval(t))
}

@Test func changeNeedsFifteenPointsOrANewBand() {
    var s = ConditionsAlertState()
    #expect(observe(&s, 60) == nil)                     // baseline
    #expect(observe(&s, 70, at: 10) == nil)             // +10, same band (good 58-73)
    let up = observe(&s, 76, at: 20)                    // +16: also a band change; moved wins
    #expect(up?.reason == .scoreMoved && up?.previous == 60 && up?.current == 76 && up?.improved == true)
    #expect(up?.stopName == "Overlook" && up?.windowKind == .goldenEvening)
    #expect(up?.previousBand == .good && up?.currentBand == .great)
}

@Test func changeOnBandCrossingUnderFifteen() {
    var s = ConditionsAlertState()
    _ = observe(&s, 58)
    let c = observe(&s, 57, at: 4000)                   // fair/good boundary, one point
    #expect(c?.reason == .bandChanged && c?.previousBand == .good && c?.currentBand == .fair && c?.improved == false)
}

@Test func changeIsQuietForAnHour() {
    var s = ConditionsAlertState()
    _ = observe(&s, 80)
    #expect(observe(&s, 50, at: 10) != nil)
    #expect(observe(&s, 20, at: 1800) == nil)            // inside the quiet hour
    #expect(observe(&s, 20, at: 3700) != nil)            // after it, against the baseline of the last alert
}

@Test func causeText() {
    #expect(ConditionsChangeDetector.cause(live: nil) == "forecast updated")
    let high = cLive(stop.place, reading: cReading(score: 50), strip: cStrip(highFirst: 0.1, highLast: 0.35, totalFirst: 0.5, totalLast: 0.5))
    #expect(ConditionsChangeDetector.cause(live: high) == "high cloud moving in")
    let clearing = cLive(stop.place, reading: cReading(score: 50), strip: cStrip(highFirst: 0.1, highLast: 0.2, totalFirst: 0.9, totalLast: 0.6))
    #expect(ConditionsChangeDetector.cause(live: clearing) == "clearing")
    let neither = cLive(stop.place, reading: cReading(score: 50), strip: cStrip(highFirst: 0.1, highLast: 0.2, totalFirst: 0.5, totalLast: 0.4))
    #expect(ConditionsChangeDetector.cause(live: neither) == "forecast updated")
    var s = ConditionsAlertState()
    _ = observe(&s, 80)
    #expect(observe(&s, 50, at: 5, live: high)?.cause == "high cloud moving in")
}
