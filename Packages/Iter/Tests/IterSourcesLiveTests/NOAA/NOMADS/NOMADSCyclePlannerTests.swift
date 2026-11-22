import Foundation
import Testing
import IterModel
import IterSourcesLive

@Suite struct NOMADSCyclePlannerTests {
    private func at(_ h: Int, _ m: Int = 0, days: Int = 0) -> Date { NOMADSTest.at(h, m, days: days) }
    private func span(_ a: Date, hours: Double) -> TimeSpan { TimeSpan(start: a, end: a.addingTimeInterval(hours * 3600)) }

    // MARK: Schedule facts

    @Test func forecastHourLimits() {
        #expect(NOMADSModel.hrrr.maxForecastHour(cycleHourUTC: 12) == 48)
        #expect(NOMADSModel.hrrr.maxForecastHour(cycleHourUTC: 0) == 48)
        #expect(NOMADSModel.hrrr.maxForecastHour(cycleHourUTC: 13) == 18)
        #expect(NOMADSModel.hrrr.publishes(forecastHour: 18, cycleHourUTC: 13))
        #expect(!NOMADSModel.hrrr.publishes(forecastHour: 19, cycleHourUTC: 13))
        #expect(!NOMADSModel.hrrr.publishes(forecastHour: 0, cycleHourUTC: 12))
        #expect(NOMADSModel.gfs.publishes(forecastHour: 1, cycleHourUTC: 6))
        #expect(NOMADSModel.gfs.publishes(forecastHour: 120, cycleHourUTC: 6))
        #expect(!NOMADSModel.gfs.publishes(forecastHour: 121, cycleHourUTC: 6))
        #expect(!NOMADSModel.gfs.publishes(forecastHour: 122, cycleHourUTC: 6))
        #expect(NOMADSModel.gfs.publishes(forecastHour: 123, cycleHourUTC: 6))
        #expect(NOMADSModel.gfs.publishes(forecastHour: 384, cycleHourUTC: 6))
        #expect(!NOMADSModel.gfs.publishes(forecastHour: 385, cycleHourUTC: 6))
    }

    @Test func postingEstimates() {
        let h1 = NOMADSFileRef(model: .hrrr, cycle: at(12), forecastHour: 1)
        let h48 = NOMADSFileRef(model: .hrrr, cycle: at(12), forecastHour: 48)
        let g1 = NOMADSFileRef(model: .gfs, cycle: at(6), forecastHour: 1)
        let g384 = NOMADSFileRef(model: .gfs, cycle: at(6), forecastHour: 384)
        func minutes(_ r: NOMADSFileRef) -> Double { NOMADSCyclePlanner.likelyAvailable(r).timeIntervalSince(r.cycle) / 60 }
        #expect(abs(minutes(h1) - 54.5) < 0.1)
        #expect(abs(minutes(h48) - 125) < 0.1)
        #expect(abs(minutes(g1) - 210.15) < 0.1)
        #expect(abs(minutes(g384) - 267.6) < 0.1)
    }

    @Test func fileRefNaming() {
        let r = NOMADSFileRef(model: .hrrr, cycle: at(23), forecastHour: 5)
        #expect(r.dateStamp == "20261122" && r.cycleStamp == "2026112223" && r.hourLabel == "f05")
        #expect(r.validTime == at(4, days: 1))
        let g = NOMADSFileRef(model: .gfs, cycle: at(0, days: 1), forecastHour: 24)
        #expect(g.dateStamp == "20261123" && g.cycleHourUTC == 0 && g.hourLabel == "f024")
        #expect(g.cacheBucket == "gfs 2026112300 f024" && r.cacheBucket == "hrrr 2026112223 f005")
    }

    // MARK: Candidate cycles

    @Test func candidatesAt1417() {
        let now = at(14, 17)
        #expect(NOMADSCyclePlanner.candidateCycles(.hrrr, now: now) == [at(13), at(12), at(11)])
        #expect(NOMADSCyclePlanner.candidateCycles(.gfs, now: now) == [at(6), at(0), at(18, days: -1)])
        // Newest cycle at 13:50 is still 12Z (13Z f01 is expected at 13:55).
        #expect(NOMADSCyclePlanner.candidateCycles(.hrrr, now: at(13, 50), count: 2) == [at(12), at(11)])
        // GFS 12Z f001 is expected 3.5 h after 12Z.
        #expect(NOMADSCyclePlanner.candidateCycles(.gfs, now: at(15, 29), count: 1) == [at(6)])
        #expect(NOMADSCyclePlanner.candidateCycles(.gfs, now: at(15, 31), count: 1) == [at(12)])
    }

    @Test func candidatesAcrossMidnight() {
        let now = at(0, 20, days: 1)
        let h = NOMADSCyclePlanner.candidateCycles(.hrrr, now: now)
        #expect(h == [at(23), at(22), at(21)])
        #expect(NOMADSFileRef(model: .hrrr, cycle: h[0], forecastHour: 1).dateStamp == "20261122")
        #expect(NOMADSCyclePlanner.candidateCycles(.gfs, now: now, count: 1) == [at(18)])
    }

    // MARK: Plans

    @Test func twelveHourSpanAt1417() throws {
        let now = at(14, 17)
        let plan = NOMADSCyclePlanner.plan(span: TimeSpan(start: at(14), end: at(2, days: 1)), now: now)
        #expect(!plan.thinned)
        #expect(plan.hours.count == 13)
        #expect(plan.hours.first?.validTime == at(14) && plan.hours.last?.validTime == at(2, days: 1))
        // HRRR 13Z f01...f13 are the preferred files.
        let primaries = plan.primaryFiles
        #expect(primaries.allSatisfy { $0.model == .hrrr && $0.cycle == at(13) })
        #expect(primaries.map(\.forecastHour) == Array(1...13))
        // Alternatives for the first hour: three HRRR cycles, then GFS 06Z, 00Z and the previous day's 18Z.
        let alts = try #require(plan.hours.first).alternatives
        #expect(alts.map(\.description) == ["HRRR 2026112213 f01", "HRRR 2026112212 f02", "HRRR 2026112211 f03",
                                            "GFS 2026112206 f008", "GFS 2026112200 f014", "GFS 2026112118 f020"])
    }

    /// A span that brackets: a start inside an hour includes the hour before it, an end inside an hour the hour after.
    @Test func spanEndsAreBracketed() {
        let plan = NOMADSCyclePlanner.plan(span: TimeSpan(start: at(14, 17), end: at(16, 40)), now: at(14, 17))
        #expect(plan.hours.map(\.validTime) == [at(14), at(15), at(16), at(17)])
    }

    @Test func fortyEightHourSpanStitchesHRRRSynopticThenGFS() throws {
        let now = at(14, 17)
        let plan = NOMADSCyclePlanner.plan(span: TimeSpan(start: now, end: now.addingTimeInterval(48 * 3600)), now: now)
        #expect(!plan.thinned)
        #expect(plan.hours.count == 50)  // 14:00 day 0 to 15:00 day 2, hourly
        let byTime = Dictionary(uniqueKeysWithValues: plan.hours.map { ($0.validTime, $0) })
        // The 13Z cycle serves to f16 (f17 and f18 are expected only at 14:18 and 14:20); after that the 12Z synoptic
        // run (f19...f48).
        #expect(byTime[at(4, days: 1)]?.primary?.description == "HRRR 2026112213 f15")
        #expect(byTime[at(7, days: 1)]?.primary?.description == "HRRR 2026112212 f19")
        #expect(byTime[at(8, days: 1)]?.primary?.description == "HRRR 2026112212 f20")
        #expect(byTime[at(12, days: 2)]?.primary?.description == "HRRR 2026112212 f48")
        // HRRR is gone after f48: GFS 06Z takes over hourly.
        #expect(byTime[at(13, days: 2)]?.primary?.description == "GFS 2026112206 f055")
        #expect(byTime[at(15, days: 2)]?.primary?.description == "GFS 2026112206 f057")
        // The HRRR alternatives at 08Z tomorrow are the synoptic cycles only (12Z f20, 06Z f26, 00Z f32), then GFS.
        let alts = byTime[at(8, days: 1)]?.alternatives.map(\.description) ?? []
        #expect(Array(alts.prefix(3)) == ["HRRR 2026112212 f20", "HRRR 2026112206 f26", "HRRR 2026112200 f32"])
        #expect(alts.dropFirst(3).allSatisfy { $0.hasPrefix("GFS") })
    }

    @Test func gfsOnlyPlanForAPointOutsideHRRR() {
        let now = at(14, 17)
        let plan = NOMADSCyclePlanner.plan(span: TimeSpan(start: at(14), end: at(2, days: 1)), now: now, models: [.gfs])
        #expect(plan.hours.count == 13)
        #expect(plan.primaryFiles.map(\.forecastHour) == Array(8...20))
        #expect(plan.primaryFiles.allSatisfy { $0.model == .gfs && $0.cycle == at(6) })
    }

    @Test func planAcrossTheDayBoundary() throws {
        let now = at(0, 20, days: 1)  // 00:20Z on the 23rd: the 00Z HRRR cycle is not out yet
        let plan = NOMADSCyclePlanner.plan(span: TimeSpan(start: at(0, days: 1), end: at(3, days: 1)), now: now)
        let first = try #require(plan.primaryFiles.first)
        // Valid 00:00 comes from the 23Z cycle of the previous day (f01), in the previous day's directory.
        #expect(first.description == "HRRR 2026112223 f01" && first.dateStamp == "20261122")
        #expect(plan.primaryFiles.map(\.forecastHour) == [1, 2, 3, 4])
        #expect(plan.hours.first?.alternatives.contains { $0.description == "GFS 2026112218 f006" } == true)
    }

    @Test func sixteenDaySpanIsThinnedToThreeHourly() {
        let now = at(14, 17)
        let plan = NOMADSCyclePlanner.plan(span: TimeSpan(start: now, end: now.addingTimeInterval(384 * 3600)), now: now)
        #expect(plan.thinned)
        let times = plan.hours.map(\.validTime)
        #expect(times.allSatisfy { Int($0.timeIntervalSince(NOMADSTest.day0)) / 3600 % 3 == 0 })
        #expect(times == times.sorted() && Set(times).count == times.count)
        #expect(times.first == at(12) && times.last == at(6, days: 16))
        #expect(plan.hours.count == 127)
        // The last valid time is GFS 06Z f384; beyond f120 only 3-hourly files exist.
        #expect(plan.hours.last?.primary?.description == "GFS 2026112206 f384")
        #expect(plan.primaryFiles.filter { $0.model == .gfs }.allSatisfy { $0.forecastHour <= 120 || $0.forecastHour % 3 == 0 })
        // HRRR is still used for its first 48 h, 3-hourly.
        #expect(plan.primaryFiles.filter { $0.model == .hrrr }.count == 17)
    }

    @Test func spanUnder72HoursIsNotThinned() {
        let now = at(14, 17)
        let p72 = NOMADSCyclePlanner.plan(span: TimeSpan(start: now, end: now.addingTimeInterval(72 * 3600)), now: now)
        #expect(!p72.thinned)
        let p73 = NOMADSCyclePlanner.plan(span: TimeSpan(start: now, end: now.addingTimeInterval(73 * 3600)), now: now)
        #expect(p73.thinned && p73.hours.count < p72.hours.count)
    }

    @Test func gfsHourlyBeyondF120IsNeverRequested() {
        // A cycle's hourly files stop at f120: valid times 5 days out (f121...f122) are not on the hourly grid.
        let now = at(14, 17)
        let start = at(6, days: 5)  // GFS 06Z f120 is valid exactly here
        let plan = NOMADSCyclePlanner.plan(span: TimeSpan(start: start, end: start.addingTimeInterval(6 * 3600)), now: now, models: [.gfs])
        let hours = plan.primaryFiles.map(\.forecastHour)
        #expect(hours == [120, 123, 126])
        #expect(plan.hours.map(\.validTime) == [start, start.addingTimeInterval(3 * 3600), start.addingTimeInterval(6 * 3600)])
    }

    @Test func spanInThePastIsServedFromEarlierCyclesOrEmpty() {
        let now = at(14, 17)
        // Yesterday 06Z to 12Z: past hours come from earlier cycles (GFS back 48 h; HRRR f01 of cycles up to 30 h back,
        // so only 10:00 onward can come from HRRR).
        let past = NOMADSCyclePlanner.plan(span: TimeSpan(start: at(6, days: -1), end: at(12, days: -1)), now: now)
        #expect(past.hours.count == 7)
        #expect(past.primaryFiles.first?.model == .gfs)
        #expect(past.hours.first?.validTime == at(6, days: -1) && past.hours.last?.validTime == at(12, days: -1))
        // Older than the retained cycles: nothing.
        let old = NOMADSCyclePlanner.plan(span: TimeSpan(start: at(0, days: -5), end: at(6, days: -5)), now: now)
        #expect(old.isEmpty)
    }

    @Test func spanBeyondTheLastForecastHourIsEmpty() {
        let now = at(14, 17)
        let plan = NOMADSCyclePlanner.plan(span: TimeSpan(start: at(0, days: 20), end: at(6, days: 20)), now: now)
        #expect(plan.isEmpty)
    }

    @Test func spanStartingBeforeTheFirstHourStartsThere() {
        // 2 days before "now" the models have nothing (earliest planned time is now - 48 h floor).
        let now = at(14, 17)
        let plan = NOMADSCyclePlanner.plan(span: TimeSpan(start: at(0, days: -3), end: at(1, days: -2)), now: now)
        // The span ends after the earliest reachable valid time, so it starts at the earliest one rather than at the span start.
        #expect(plan.hours.first.map { $0.validTime > at(0, days: -3) } ?? true)
    }

    @Test func knownMissingFilesAreSkipped() {
        let now = at(14, 17)
        let plan = NOMADSCyclePlanner.plan(span: TimeSpan(start: at(14), end: at(16)), now: now) { $0.model == .hrrr && $0.cycle == at(13) }
        #expect(plan.primaryFiles.map(\.description) == ["HRRR 2026112212 f02", "HRRR 2026112212 f03", "HRRR 2026112212 f04"])
    }

    @Test func requestCountsForTypicalSpans() {
        let now = at(14, 17)
        func count(_ hours: Double, _ models: [NOMADSModel]) -> Int {
            NOMADSCyclePlanner.plan(span: TimeSpan(start: now, end: now.addingTimeInterval(hours * 3600)), now: now, models: models).primaryFiles.count
        }
        #expect(count(12, [.hrrr, .gfs]) == 14)
        #expect(count(12, [.gfs]) == 14)
        #expect(count(48, [.hrrr, .gfs]) == 50)
        #expect(count(48, [.gfs]) == 50)
        #expect(count(240, [.hrrr, .gfs]) == 82)
        #expect(count(240, [.gfs]) == 82)
    }
}
