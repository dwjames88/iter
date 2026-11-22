import Foundation
import Testing
import IterCore
import IterAstro
@testable import IterLight

/// Pins for the parts of the engine the audit covered: the forecast hours a window reads, persistence beyond the
/// horizon, the next-event rule against a forecast, and the score's clamps, confidence limits and dropped fields.

// MARK: Hourly-to-window mapping

@Suite struct HourlyMappingTests {
    func hour(_ hourOfDay: Double, cloud: Double, low: Double? = nil, mid: Double? = nil, high: Double? = nil, rain: Double? = 0,
              mm: Double? = nil, visibility: Double? = 20_000, _ res: HourlyConditions.Resolution = .hourly) -> HourlyConditions {
        HourlyConditions(date: FixedEphemeris.at(testDay, hourOfDay), cloudCover: cloud, cloudLow: low, cloudMid: mid, cloudHigh: high,
                         precipitationChance: rain, precipitationMm: mm, visibilityMeters: visibility, windSpeedKph: 5, temperatureC: 12,
                         humidity: 0.5, symbolName: "sun.max", condition: "clear", resolution: res)
    }

    func forecast(_ hours: [HourlyConditions]) -> Forecast {
        Forecast(coordinate: Coordinate(latitude: 40, longitude: -110), hours: hours, days: [], fetchedAt: now0, source: .appleWeather)
    }

    func span(_ a: Double, _ b: Double) -> TimeSpan { TimeSpan(start: FixedEphemeris.at(testDay, a), end: FixedEphemeris.at(testDay, b)) }

    @Test func hoursAreWeightedByOverlapSeconds() throws {
        // 18:30 to 19:15 reads hour 18 for 30 minutes and hour 19 for 15.
        let f = forecast([hour(17, cloud: 0.9), hour(18, cloud: 0.2), hour(19, cloud: 0.8), hour(20, cloud: 0.9)])
        let c = try #require(LightEngine.conditions(in: f, over: span(18.5, 19.25)))
        #expect(abs(c.totalCloud - (0.2 * 1800 + 0.8 * 900) / 2700) < 1e-9)
        // An hour touching the span only at its edge is not read.
        let edge = try #require(LightEngine.conditions(in: f, over: span(18, 19)))
        #expect(abs(edge.totalCloud - 0.2) < 1e-9)
    }

    @Test func fieldsAverageOverTheHoursThatHaveThem() throws {
        let f = forecast([hour(18, cloud: 0.4, rain: nil, mm: 1.0, visibility: nil), hour(19, cloud: 0.4, rain: 0.6, mm: nil, visibility: 8_000)])
        let c = try #require(LightEngine.conditions(in: f, over: span(18, 20)))
        #expect(c.precipitationChance == 0.6)
        #expect(c.precipitationMm == 1.0)
        #expect(c.visibilityMeters == 8_000)
        let none = try #require(LightEngine.conditions(in: forecast([hour(18, cloud: 0.4, rain: nil, visibility: nil)]), over: span(18, 19)))
        #expect(none.precipitationChance == nil && none.precipitationMm == nil && none.visibilityMeters == nil)
    }

    @Test func layersCountOnlyWhenEveryHourHasAllThree() throws {
        let full = hour(18, cloud: 0.5, low: 0.1, mid: 0.4, high: 0.6)
        let partial = hour(19, cloud: 0.5, low: 0.1, mid: 0.4, high: nil)
        let both = try #require(LightEngine.conditions(in: forecast([full, partial]), over: span(18, 20)))
        #expect(!both.hasLayers && both.low == nil && both.mid == nil && both.high == nil)
        let one = try #require(LightEngine.conditions(in: forecast([full, partial]), over: span(18, 19)))
        #expect(one.hasLayers && one.high == 0.6)
    }

    @Test func resolutionsAreTheUnionOfTheHoursRead() throws {
        let f = forecast([hour(18, cloud: 0.5), hour(19, cloud: 0.5, .interpolated), hour(20, cloud: 0.5, .dailySummary)])
        #expect(try #require(LightEngine.conditions(in: f, over: span(18, 19))).resolutions == [.hourly])
        #expect(try #require(LightEngine.conditions(in: f, over: span(18.5, 19.5))).resolutions == [.hourly, .interpolated])
        #expect(try #require(LightEngine.conditions(in: f, over: span(18, 21))).resolutions == [.hourly, .interpolated, .dailySummary])
    }

    @Test func nightSpanningMidnightReadsBothDays() throws {
        let hours = (20..<30).map { h in hour(Double(h), cloud: Double(h - 20) / 10) }   // 20:00 ... 05:00 next day
        let f = forecast(hours)
        // 22:30 to 01:30: 1.5 h before midnight (hours 22 and 23: clouds 0.2, 0.3) and 1.5 h after (0 and 1: 0.4, 0.5).
        let c = try #require(LightEngine.conditions(in: f, over: span(22.5, 25.5)))
        let expected = (0.2 * 0.5 + 0.3 * 1 + 0.4 * 1 + 0.5 * 0.5) / 3
        #expect(abs(c.totalCloud - expected) < 1e-9)
    }

    @Test func aZeroLengthWindowReadsTheHourItSitsIn() throws {
        let f = forecast([hour(18, cloud: 0.2), hour(19, cloud: 0.8)])
        let c = try #require(LightEngine.conditions(in: f, over: span(19.5, 19.5)))
        #expect(c.totalCloud == 0.8)
    }

    @Test func outsideTheForecastThereIsNothingToRead() {
        let f = forecast([hour(18, cloud: 0.2), hour(19, cloud: 0.8)])
        #expect(LightEngine.conditions(in: f, over: span(21, 22)) == nil)       // after the last hour
        // Before the first hour the first hour stands in (a window that began before the data did).
        #expect(LightEngine.conditions(in: f, over: span(10, 11))?.totalCloud == 0.2)
    }
}

// MARK: Persistence and the next-event rule against a forecast

@Suite struct PersistenceTests {
    let engine = LightEngine(ephemeris: FixedEphemeris())
    let spot = makeSpot()

    /// Cloud depends on the hour of the day so a carried-forward window can be traced to the hour it copied.
    func dayShapedForecast() -> Forecast {
        forecast(fetchedAt: now0) { date in
            let hour = Calendar(identifier: .gregorian).dateComponents(in: utc, from: date).hour!
            return Wx(total: Double(hour) / 30, low: 0.05, mid: Double(hour) / 40, high: 0.2)
        }
    }

    @Test func aWindowBeyondTheHorizonCopiesTheSameClockTimeOnTheLastDay() throws {
        let f = dayShapedForecast()   // hours from testDay-1 00:00 to testDay+1 23:00; horizon testDay+2 00:00
        let lastCovered = try #require(engine.dayLight(for: spot, on: testDay.adding(days: 1), forecast: f, unavailable: nil, now: now0)
            .window(.goldenEvening)?.assessment.lightScore)
        #expect(!lastCovered.notes.contains(.persistence))
        for ahead in [2, 3, 4, 9] {
            let far = try #require(engine.dayLight(for: spot, on: testDay.adding(days: ahead), forecast: f, unavailable: nil, now: now0)
                .window(.goldenEvening)?.assessment.lightScore)
            #expect(far.value == lastCovered.value, "day +\(ahead) carries the last day's evening forward")
            #expect(far.contributors == lastCovered.contributors)
            #expect(far.confidence == .low && far.notes.contains(.persistence))
            #expect(far.range == WindowScorer.range(value: far.value, confidence: .low))
        }
    }

    @Test func theHorizonItselfIsBeyondTheForecast() throws {
        // Forecast hours end at testDay+2 00:00. A window whose middle is exactly then is persisted; one 6 minutes
        // earlier is read directly.
        let f = dayShapedForecast()
        let on = engine.assess(kind: .goldenEvening, span: TimeSpan(start: FixedEphemeris.at(testDay, 47), end: FixedEphemeris.at(testDay, 49)),
                               spot: spot, forecast: f, unavailable: nil, now: now0)
        #expect(on.lightScore?.notes.contains(.persistence) == true)
        let before = engine.assess(kind: .goldenEvening, span: TimeSpan(start: FixedEphemeris.at(testDay, 46.9), end: FixedEphemeris.at(testDay, 48.9)),
                                   spot: spot, forecast: f, unavailable: nil, now: now0)
        #expect(before.lightScore?.notes.contains(.persistence) == false)
    }

    @Test func aStaleForecastStillScoresEverythingByPersistence() {
        // Every hour of this forecast is days in the past: nothing is ever `.noForecast` while any hours exist.
        let stale = forecast(day: testDay.adding(days: -20), fetchedAt: FixedEphemeris.at(testDay.adding(days: -20), 6)) { _ in Wx() }
        let dl = engine.dayLight(for: spot, on: testDay, forecast: stale, unavailable: nil, now: now0)
        for w in dl.windows {
            let s = w.assessment.lightScore
            #expect(s != nil && s?.confidence == .low && s?.notes.contains(.persistence) == true, "\(w.kind)")
        }
    }

    @Test func aForecastStartingLaterStillScoresEarlierWindowsFromItsFirstHour() {
        let later = forecast(day: testDay.adding(days: 5), fetchedAt: now0) { _ in Wx(total: 0.35) }
        let dl = engine.dayLight(for: spot, on: testDay, forecast: later, unavailable: nil, now: now0)
        #expect(dl.windows.allSatisfy { $0.assessment.lightScore != nil })
    }

    @Test func nextEventNeverLeaksNoForecastWhenAnyHoursExist() throws {
        let engine = LightEngine(ephemeris: Astronomy())
        for spot in EngineEquivalenceTests.spots {
            for now in EngineEquivalenceTests.instants.prefix(30) {
                // Hours far in the past, far ahead, or a single hour: all count as "some forecast data".
                let past = EngineBenchmark.forecast(for: spot, from: now.addingTimeInterval(-30 * 86_400))
                let ahead = EngineBenchmark.forecast(for: spot, from: now.addingTimeInterval(20 * 86_400))
                var one = EngineBenchmark.forecast(for: spot, from: now)
                one.hours = [one.hours[0]]
                for f in [past, ahead, one] {
                    guard let next = engine.nextEvent(for: spot, forecast: f, unavailable: nil, now: now) else { continue }
                    #expect(next.window.assessment.lightScore != nil, "\(spot.id) \(now): \(next.window.assessment)")
                }
            }
        }
    }

    @Test func nextEventAtTheExactEndMovesOn() throws {
        let engine = LightEngine(ephemeris: Astronomy())
        let spot = EngineZonesTests.la
        let day = LocalDay(year: 2026, month: 10, day: 7)
        let evening = try #require(engine.windows(for: spot, on: day).first { $0.kind == .goldenEvening }).span
        let inside = try #require(engine.nextEvent(for: spot, forecast: nil, unavailable: nil, now: evening.end.addingTimeInterval(-1)))
        #expect(inside.window.kind == .goldenEvening && inside.day == day)
        let at = try #require(engine.nextEvent(for: spot, forecast: nil, unavailable: nil, now: evening.end))
        #expect(at.window.kind == .goldenMorning && at.day == day.adding(days: 1))
    }

    @Test func nextEventNeverPicksNightAndLooksFourDaysAtMost() throws {
        let engine = LightEngine(ephemeris: Astronomy())
        for spot in EngineEquivalenceTests.spots {
            for now in EngineEquivalenceTests.instants {
                guard let next = engine.nextEvent(for: spot, forecast: nil, unavailable: nil, now: now) else { continue }
                let today = LocalDay(now, in: spot.timeZone)
                #expect(next.window.kind != .night)
                #expect((0...3).contains(today.days(until: next.day)), "\(spot.id) \(now)")
                #expect(next.window.span.end > now)
            }
        }
    }
}

// MARK: Outlook length

@Suite struct OutlookCountTests {
    let engine = LightEngine(ephemeris: FixedEphemeris())

    @Test func clampsAtBothEnds() {
        let spot = makeSpot()
        let f = forecast(fetchedAt: now0, days: 3) { _ in Wx() }   // testDay-1 ... testDay+3 inclusive: 5 days
        #expect(engine.outlookDayCount(for: spot, from: testDay.adding(days: -1), forecast: f, max: 0) == 0)
        #expect(engine.outlookDayCount(for: spot, from: testDay.adding(days: -1), forecast: f, max: -2) == 0)
        #expect(engine.outlookDayCount(for: spot, from: testDay.adding(days: -1), forecast: f, max: 1) == 1)
        #expect(engine.outlookDayCount(for: spot, from: testDay.adding(days: -1), forecast: f, max: 99) == 5)
        #expect(engine.outlookDayCount(for: spot, from: testDay.adding(days: 3), forecast: f, max: 99) == 1)
        #expect(engine.outlookDayCount(for: spot, from: testDay.adding(days: 50), forecast: f, max: 8) == 1)
    }

    @Test func coverageIsCountedInTheSpotsZone() {
        // Hours end at 12:00 UTC on 2026-10-12 (exclusive): Auckland (UTC+13) has begun the 12th and the 13th by then,
        // Phoenix (UTC-7) has begun the 12th only.
        let end = FixedEphemeris.at(testDay, 12)
        let start = end.addingTimeInterval(-48 * 3600)
        let hours = (0..<48).map { i in
            HourlyConditions(date: start.addingTimeInterval(Double(i) * 3600), cloudCover: 0.3, precipitationChance: 0, visibilityMeters: 20_000,
                             windSpeedKph: 5, temperatureC: 12, humidity: 0.5, symbolName: "sun.max", condition: "clear")
        }
        let f = Forecast(coordinate: Coordinate(latitude: 0, longitude: 0), hours: hours, days: [], fetchedAt: start, source: .appleWeather)
        let auckland = EngineZonesTests.auckland, phoenix = EngineZonesTests.phoenix
        #expect(engine.outlookDayCount(for: auckland, from: testDay, forecast: f, max: 10) == 2)
        #expect(engine.outlookDayCount(for: phoenix, from: testDay, forecast: f, max: 10) == 1)
    }
}

// MARK: Score composition

@Suite struct ScorerPinTests {
    static func conditions(total: Double, low: Double? = 0.1, mid: Double? = 0.3, high: Double? = 0.3, rain: Double? = 0,
                           mm: Double? = nil, visibility: Double? = 20_000, _ res: Set<HourlyConditions.Resolution> = [.hourly]) -> WindowConditions {
        WindowConditions(totalCloud: total, low: low, mid: mid, high: high, precipitationChance: rain, precipitationMm: mm,
                         visibilityMeters: visibility, resolutions: res)
    }

    @Test func theWorstSkyIsFiveNotZeroAndNothingPassesOneHundred() {
        let worst = Self.conditions(total: 1, low: 1, mid: 1, high: 1, rain: 1, visibility: 0)
        for kind in LightWindowKind.allCases {
            let s = WindowScorer.score(kind: kind, conditions: worst, moon: MoonLight(altitude: 60, illumination: 1))
            #expect(s.value == 5, "\(kind) floor")
        }
        var rng = SeededRNG(seed: 99)
        func unit() -> Double { Double(rng.next() % 1001) / 1000 }
        for _ in 0..<3000 {
            let c = Self.conditions(total: unit(), low: unit(), mid: unit(), high: unit(), rain: unit(), visibility: unit() * 30_000)
            for kind in LightWindowKind.allCases {
                let s = WindowScorer.score(kind: kind, conditions: c, moon: MoonLight(altitude: unit() * 90 - 20, illumination: unit()))
                #expect((5...100).contains(s.value))
                #expect(LightBand(score: s.value) == LightBand(score: s.value))
                // The bars add up to the score (60 baseline plus every contributor) whenever the score was not clamped.
                if s.value > 5 && s.value < 100 {
                    #expect(60 + s.contributors.reduce(0) { $0 + $1.points } == s.value, "\(kind) \(c)")
                }
            }
        }
    }

    @Test func droppedFieldsLeaveTheOtherFactorsAlone() {
        let full = WindowScorer.score(kind: .goldenEvening, conditions: Self.conditions(total: 0.4), moon: nil)
        func points(_ s: ScoredWindow, _ f: LightContributor.Factor) -> Int? { s.contributors.first { $0.factor == f }?.points }

        let noVis = WindowScorer.score(kind: .goldenEvening, conditions: Self.conditions(total: 0.4, visibility: nil), moon: nil)
        #expect(noVis.notes == [.noVisibility] && !noVis.contributors.contains { $0.factor == .visibility })
        #expect(points(noVis, .midHighCloud) == points(full, .midHighCloud) && points(noVis, .lowCloud) == points(full, .lowCloud))

        let noRain = WindowScorer.score(kind: .goldenEvening, conditions: Self.conditions(total: 0.4, rain: nil), moon: nil)
        #expect(!noRain.contributors.contains { $0.factor == .precipitation } && !noRain.notes.contains(.precipitationFromAmount))

        let amountOnly = WindowScorer.score(kind: .goldenEvening, conditions: Self.conditions(total: 0.4, rain: nil, mm: 0.5), moon: nil)
        #expect(amountOnly.notes.contains(.precipitationFromAmount))
        #expect(points(amountOnly, .precipitation) == -12)

        // A chance, when there is one, wins over an amount.
        let both = WindowScorer.score(kind: .goldenEvening, conditions: Self.conditions(total: 0.4, rain: 0.0, mm: 2), moon: nil)
        #expect(!both.notes.contains(.precipitationFromAmount) && !both.contributors.contains { $0.factor == .precipitation })
    }

    @Test func confidenceLimits() {
        let table: [(Double, Bool, Set<HourlyConditions.Resolution>, Confidence)] = [
        (36.0, false, [.hourly], .high),
        (36.01, false, [.hourly], .medium),
        (72.0, false, [.hourly], .medium),
        (72.01, false, [.hourly], .low),
        (0.0, false, [.hourly, .dailySummary], .low),
        (24.0, false, [.hourly, .interpolated], .high),
        (24.01, false, [.hourly, .interpolated], .medium),
        (72.01, false, [.interpolated], .low),
        (12.0, true, [.hourly], .medium),
        (50.0, true, [.hourly], .low),
        (100.0, true, [.hourly], .low),
        (12.0, true, [.interpolated, .dailySummary], .low),
        (-5.0, false, [.hourly], .high),
        ]
        for (lead, missing, resolutions, expected) in table {
            #expect(WindowScorer.confidence(leadHours: lead, layersMissing: missing, resolutions: resolutions) == expected,
                    "lead \(lead) layersMissing \(missing) \(resolutions)")
        }
    }

    @Test func onlyWindowsThatWantLayersLoseConfidenceWithoutThem() {
        let bare = Self.conditions(total: 0.4, low: nil, mid: nil, high: nil)
        #expect(WindowScorer.score(kind: .goldenMorning, conditions: bare, moon: nil).usedLayerFallback)
        #expect(WindowScorer.score(kind: .goldenEvening, conditions: bare, moon: nil).usedLayerFallback)
        #expect(WindowScorer.score(kind: .blueMorning, conditions: bare, moon: nil).usedLayerFallback)
        #expect(WindowScorer.score(kind: .blueEvening, conditions: bare, moon: nil).usedLayerFallback)
        #expect(!WindowScorer.score(kind: .night, conditions: bare, moon: MoonLight(altitude: -10, illumination: 0.2)).usedLayerFallback)
        #expect(!WindowScorer.score(kind: .goldenEvening, conditions: Self.conditions(total: 0.4), moon: nil).usedLayerFallback)
    }

    @Test func bandBoundariesAndOutOfRangeScores() {
        let table: [(Int, LightBand)] = [(Int.min, .poor), (-1, .poor), (0, .poor), (39, .poor), (40, .fair), (57, .fair), (58, .good), (73, .good),
                                         (74, .great), (87, .great), (88, .epic), (100, .epic), (101, .epic), (Int.max, .epic)]
        for (score, band) in table { #expect(LightBand(score: score) == band, "\(score)") }
        #expect(LightBand.allCases.map { $0.scoreRange } == [0...39, 40...57, 58...73, 74...87, 88...100])
    }

    @Test func nightIsNeverTheCeilingForDaytimeAndAnOvercastDayIsCapped() {
        // The overcast ceiling applies to daytime windows only; a clear night is not a daytime score.
        let overcast = Self.conditions(total: 0.9, low: 0.1, mid: 0.4, high: 0.4)
        for kind in [LightWindowKind.goldenMorning, .goldenEvening, .blueMorning, .blueEvening] {
            #expect(WindowScorer.score(kind: kind, conditions: overcast, moon: nil).value < 58, "\(kind)")
        }
        let clearNight = WindowScorer.score(kind: .night, conditions: Self.conditions(total: 0.0), moon: MoonLight(altitude: -20, illumination: 0))
        let overcastGolden = WindowScorer.score(kind: .goldenEvening, conditions: overcast, moon: nil)
        #expect(clearNight.value > overcastGolden.value)   // and still the golden window's own score is what a sunset row shows
    }
}
