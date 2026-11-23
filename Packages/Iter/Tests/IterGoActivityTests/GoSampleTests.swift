import Foundation
import Testing
import IterGoActivity
import IterModel

private let sampleNow = Date(timeIntervalSince1970: 1_800_000_000)

private func encoder() -> JSONEncoder {
    let e = JSONEncoder()
    e.outputFormatting = [.sortedKeys]
    return e
}

@Test(arguments: GoSample.allCases)
func sampleRoundTripsAndIsDeterministic(_ sample: GoSample) throws {
    let s = sample.snapshot(now: sampleNow)
    let data = try encoder().encode(s)
    #expect(try JSONDecoder().decode(GoSnapshot.self, from: data) == s)
    #expect(sample.snapshot(now: sampleNow) == s)
    // Contentful states carry the new fields.
    if sample != .idle && sample != .finished {
        #expect(s.hours?.count == 6)
        #expect(s.sourceDetails?.isEmpty == false)
        #expect(s.schedule?.first?.stop.id == s.next?.id)
        #expect(s.here != nil)
    }
}

@Test(arguments: GoSample.allCases)
func sampleActivityContentIsUnderTwoKilobytes(_ sample: GoSample) throws {
    let s = sample.snapshot(now: sampleNow)
    let content = GoActivityContent(snapshot: s)
    let data = try JSONEncoder().encode(content)
    #expect(data.count < 2048)
    #expect(content.phase == s.phase)
}

@Test func everySampleIsDistinct() throws {
    var seen: [Data: GoSample] = [:]
    for sample in GoSample.allCases {
        let data = try encoder().encode(sample.snapshot(now: sampleNow))
        #expect(seen[data] == nil, "\(sample) equals \(String(describing: seen[data]))")
        seen[data] = sample
    }
    #expect(seen.count == GoSample.allCases.count)
}

@Test func sampleStatesMatchTheirDocumentation() throws {
    func s(_ c: GoSample) -> GoSnapshot { c.snapshot(now: sampleNow) }
    #expect(s(.idle).phase == .idle)
    #expect(s(.armedEarly).phase == .armed && s(.armedEarly).leave?.status == .early)
    #expect(s(.leaveSoon).leave?.status == .leaveSoon && s(.leaveNow).leave?.status == .leaveNow)
    #expect(s(.drivingOnTime).phase == .driving && s(.drivingOnTime).drive?.source == .live)
    #expect(s(.drivingLate).leave?.status == .late && (s(.drivingLate).leave?.lateBySeconds ?? 0) > 0 && s(.drivingLate).alternative != nil)
    #expect(s(.drivingMissed).leave?.status == .missed && s(.drivingMissed).alternative != nil)
    #expect(s(.atStopShooting).phase == .atStop && s(.atStopShooting).stay?.cutsShortBySeconds == nil)
    #expect((s(.atStopStayCost).stay?.cutsShortBySeconds ?? 0) > 0)
    let undo = try #require(s(.arrivedUndo).undo)
    #expect(undo.expiresAt > sampleNow && undo.expiresAt <= sampleNow.addingTimeInterval(120))
    #expect(s(.betweenStops).phase == .betweenStops)
    #expect(s(.betweenOvernight).leave?.suggestedDeparture != nil)
    #expect(s(.paused).phase == .paused)
    let summary = try #require(s(.finished).summary)
    #expect(Set(summary.stops.map(\.outcome)) == [.shot, .skipped, .missed])
    #expect(s(.offline).drive?.source == .offlineEstimate && s(.offline).freshness.isOffline && s(.offline).sky?.notice == "No live data")
    #expect(s(.offline).sky?.basis == .forecastOnly)
    let stale = s(.stale)
    #expect(abs(stale.generatedAt.timeIntervalSince(sampleNow) + 3 * 3600) < 600)
    #expect(stale.freshness.etaIsStale && stale.freshness.conditionsAreStale)
    #expect(s(.alert).alerts.map(\.event).contains("Red Flag Warning") && s(.alert).alerts.map(\.event).contains("Wind Advisory"))
    #expect(s(.powerSaving).freshness.isPowerSaving)
    #expect(s(.nextWindowForecast).sky?.basis == .nextWindowForecast && s(.nextWindowForecast).sky?.liveScore == nil)
    // The military-origin source is marked as such, and the hour strip is honest about its basis.
    #expect(s(.drivingOnTime).sourceDetails?.first?.isMilitary == true)
    #expect(s(.drivingOnTime).hours?.first?.basis == .observation && s(.drivingOnTime).hours?.last?.basis == .forecast)
}

/// 2026-10-24 22:30 UTC, 16:30 MDT in Moab: the `now` every render uses. Sunset there is about 18:20, sunrise about 07:35.
@Test(arguments: GoSample.allCases)
func sampleLightWindowsStartAtPlausibleLocalHours(_ sample: GoSample) throws {
    let now = sample.renderNow
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/Denver"))
    let atStop: Set<GoSample> = [.atStopShooting, .atStopStayCost, .arrivedUndo]
    #expect(calendar.component(.hour, from: now) == (atStop.contains(sample) ? 17 : 16) && calendar.component(.minute, from: now) == (atStop.contains(sample) ? 45 : 30))
    let s = sample.snapshot(now: now)

    func hour(_ d: Date) -> Double { Double(calendar.component(.hour, from: d)) + Double(calendar.component(.minute, from: d)) / 60 }
    func check(_ kind: LightWindowKind?, _ start: Date?, _ what: String) {
        guard let kind, let start else { return }
        let h = hour(start)
        let range: ClosedRange<Double>
        switch kind {
        case .blueMorning: range = 6.0...7.5
        case .goldenMorning: range = 6.75...8.5
        case .goldenEvening: range = 16.5...18.5
        case .blueEvening: range = 18.0...19.5
        case .night: range = 19.0...23.99
        }
        #expect(range.contains(h), "\(sample) \(what) \(kind) starts at \(h)")
    }
    for stop in [s.current, s.next].compactMap({ $0 }) + (s.schedule ?? []).map(\.stop) {
        check(stop.windowKind, stop.windowStart, stop.name)
    }
    check(s.sky?.windowKind, s.sky?.windowStart, "sky")
    check(s.alternative?.windowKind, s.alternative?.windowStart, "alternative")
    // A golden evening ends at sunset, about 18:20 (or 18:19 the next day).
    for stop in [s.current, s.next].compactMap({ $0 }) where stop.windowKind == .goldenEvening {
        #expect((18.0...18.6).contains(hour(try #require(stop.windowEnd))), "\(sample) sunset")
    }
    // Overnight: the next stop is tomorrow's sunrise, leave-by in the early morning, the suggestion this evening.
    if sample == .betweenOvernight {
        let next = try #require(s.next)
        #expect(next.dayIndex == 1 && next.windowKind == .goldenMorning)
        #expect((7.4...7.8).contains(hour(try #require(next.windowStart))))
        #expect((5.75...6.75).contains(hour(try #require(s.leave?.leaveBy))))
        #expect((19.5...20.5).contains(hour(try #require(s.leave?.suggestedDeparture))))
        #expect(s.leave?.earliestDeparture == nil)
        #expect(try #require(s.leave?.leaveBy) > now.addingTimeInterval(12 * 3600))
    }
}

@Test func atStopSamplesDrawAWindowThatIsRunning() throws {
    for sample in [GoSample.atStopShooting, .atStopStayCost, .arrivedUndo] {
        let now = sample.renderNow
        let s = sample.snapshot(now: now)
        let current = try #require(s.current)
        let start = try #require(current.windowStart), end = try #require(current.windowEnd)
        #expect(start < now && end > now && end.timeIntervalSince(now) > 30 * 60 && end.timeIntervalSince(now) < 40 * 60)
        #expect(s.sky?.stopID == current.id && s.sky?.basis == .blended && s.sky?.liveScore != nil)
        #expect(s.hours?.contains { $0.isInWindow } == true)
        #expect(s.weather.contains { $0.subject == .stop(current.id) })
    }
    let cost = GoSample.atStopStayCost.snapshot(now: GoSample.atStopStayCost.renderNow)
    #expect(cost.next?.name == "Mesa Arch" && cost.next?.windowKind == .blueEvening)
    #expect((cost.stay?.cutsShortBySeconds ?? 0) > 20 * 60)
}
