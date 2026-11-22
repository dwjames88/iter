import Foundation
import Testing
import IterModel
import IterSources
import IterSky
@testable import IterConditions

@Suite("Live conditions")
struct LiveTests {
    private func observation(minutesAgo: Double) -> WeatherObservation {
        WeatherObservation(time: t0.addingTimeInterval(-minutesAgo * 60), stationName: "KDEN",
                           conditions: HourlyConditions(time: t0, cloudTotal: 0.3, cloudLow: 0.1, cloudMid: 0.1, cloudHigh: 0.2,
                                                        visibilityKm: 16, tempC: 12, windMs: 3))
    }

    private func steps() -> [NowcastStep] {
        (0..<7).map { NowcastStep(time: t0.addingTimeInterval(Double($0) * 3600), precipMmPerHour: 0, precipChance: 0, cloudTotal: 0.25) }
    }

    @Test func aFreshObservationAndNowcastBlendWithTheForecast() async {
        let clock = ManualSourceClock(now: t0)
        let live = FakeLive(clock: clock, observation: observation(minutesAgo: 20), nowcast: steps())
        let env = makeEnv([FakeForecast(metDescriptor, clock: clock, recipe: metRecipe), live], clock: clock)
        let place = makePlace()
        let r = await env.service.live(for: place)
        #expect(r.reading.state == .blended)
        #expect(r.current?.stationName == "KDEN")
        #expect(r.current?.distanceKm == 8)
        #expect(r.current?.age == 1200)
        #expect(r.currentForecastHour == nil)
        #expect(r.strip.count == 6)
        #expect(r.strip.first?.basis == .nowcast)
        #expect(r.notice == nil)
        #expect(r.reading.inputsUsed.contains { $0.kind == .observation && $0.distanceKm == 8 })
    }

    @Test func withoutObservationsTheCurrentForecastHourIsUsedAndLabelled() async {
        let clock = ManualSourceClock(now: t0)
        let live = FakeLive(clock: clock, observation: nil, nowcast: nil)
        let env = makeEnv([FakeForecast(metDescriptor, clock: clock, recipe: metRecipe), live], clock: clock)
        let r = await env.service.live(for: makePlace())
        #expect(r.current == nil)
        #expect(r.currentForecastHour?.cloudTotal == 0.6)
        #expect(r.reading.state == .forecastOnly)
        #expect(r.notice == .noLiveData)
        #expect(r.notice?.text == "No live data")
        #expect(r.strip.allSatisfy { $0.basis == .forecast })
    }

    @Test func nothingAtAllIsNoLiveData() async {
        let clock = ManualSourceClock(now: t0)
        let env = makeEnv([], clock: clock)
        let r = await env.service.live(for: makePlace())
        #expect(r.reading.state == .noData)
        #expect(r.reading.score == nil)
        #expect(r.notice == .noLiveData)
        #expect(r.current == nil && r.currentForecastHour == nil)
    }

    @Test func anOldObservationIsNotLive() async {
        let clock = ManualSourceClock(now: t0)
        let live = FakeLive(clock: clock, observation: observation(minutesAgo: 150), nowcast: nil)
        let env = makeEnv([FakeForecast(metDescriptor, clock: clock, recipe: metRecipe), live], clock: clock)
        let r = await env.service.live(for: makePlace())
        #expect(r.reading.state == .forecastOnly)
        #expect(r.current?.age == 9000)
        #expect(r.notice != nil)
    }

    @Test func offlineLeavesTheForecastScoreLabelled() async {
        let clock = ManualSourceClock(now: t0)
        let live = FakeLive(clock: clock, observation: observation(minutesAgo: 10), nowcast: steps())
        live.setFailure(.offline)
        let env = makeEnv([FakeForecast(metDescriptor, clock: clock, recipe: metRecipe), live], clock: clock)
        let r = await env.service.live(for: makePlace())
        #expect(r.observations.reasons == [.offline(lastGood: nil)])
        #expect(r.reading.state == .forecastOnly)
        #expect(r.reading.score != nil)
        #expect(r.notice == .noLiveData)
    }
}
