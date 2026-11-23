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
