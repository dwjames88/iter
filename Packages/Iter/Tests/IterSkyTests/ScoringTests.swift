import Foundation
import Testing
import IterModel
import IterAstro
@testable import IterSky

private func score(_ kind: LightWindowKind, _ w: Wx, eph: FixedEphemeris = FixedEphemeris(), fetchedHoursBefore: Double? = nil) -> SkyScore? {
    let engine = LightEngine(ephemeris: eph)
    let spot = makePlace()
    let dl = engine.dayLight(for: spot, on: testDay, inputs: uniform(w, fetchedAt: now0), now: now0)
    return dl.window(kind)?.assessment.skyScore
}

@Suite struct GoldenScoring {
    @Test func overcastGoldenIsNeverGood() {
        let s = score(.goldenEvening, Wx(total: 0.95, low: 0.8, mid: 0.5, high: 0.5, rain: 0.2))!
        #expect(s.band < .good)
        #expect(s.value < 58)
        // Whatever the mid/high layers claim, thick overcast is capped.
        for mid in stride(from: 0.0, through: 1.0, by: 0.1) {
            for low in stride(from: 0.0, through: 1.0, by: 0.1) {
                let x = score(.goldenMorning, Wx(total: 0.9, low: low, mid: mid, high: mid, rain: 0))!
                #expect(x.band < .good, "low \(low) mid \(mid) scored \(x.value)")
            }
        }
    }

    @Test func heavyLowCloudIsPoor() {
        let s = score(.goldenEvening, Wx(total: 0.8, low: 0.85, mid: 0.2, high: 0.2))!
        #expect(s.band == .poor)
        #expect(s.contributors.first?.factor == .lowCloud)
        #expect(s.contributors.first?.effect == .hurts)
    }

    @Test func idealGoldenIsGreatOrEpic() {
        let s = score(.goldenEvening, Wx(total: 0.45, low: 0.05, mid: 0.4, high: 0.4, rain: 0, visibility: 25_000))!
        #expect(s.band >= .great)
    }

    @Test func bareSkyIsGoodNotEpic() {
        let s = score(.goldenEvening, Wx(total: 0.03, low: 0, mid: 0, high: 0, rain: 0, visibility: 30_000))!
        #expect(s.band == .good)
        #expect(s.contributors.contains { $0.factor == .clearSky })
    }

    @Test func scoreMovesSmoothly() {
        var last: Int?
        for c in stride(from: 0.0, through: 1.0, by: 0.02) {
            let v = score(.goldenEvening, Wx(total: max(c, 0.2), low: 0.1, mid: c, high: c))!.value
            if let last { #expect(abs(v - last) <= 5, "jump at \(c): \(last) -> \(v)") }
            last = v
        }
    }

    @Test func precipitationHurts() {
        let s = score(.goldenEvening, Wx(total: 0.5, low: 0.1, mid: 0.4, high: 0.4, rain: 0.7))!
        let p = s.contributors.first { $0.factor == .precipitation }
        #expect(p?.effect == .hurts)
        #expect((p?.points ?? 0) <= -15)
        let mild = score(.goldenEvening, Wx(total: 0.5, low: 0.1, mid: 0.4, high: 0.4, rain: 0.4))!
        #expect(mild.value > s.value)
    }

    @Test func lowVisibilityHurts() {
        let clear = score(.goldenEvening, Wx(visibility: 20_000))!
        let fog = score(.goldenEvening, Wx(visibility: 3_000))!
        #expect(fog.value <= clear.value - 10)
        #expect(fog.contributors.contains { $0.factor == .visibility && $0.effect == .hurts })
        // Haze (8 km) is soft for golden hour.
        let haze = score(.goldenEvening, Wx(visibility: 7_000))!
        #expect(clear.value - haze.value < 10)
    }

    @Test func goldenWithoutBonusForSpotBestLight() {
        // A spot that is "best at sunset" gets no boost: same weather, same score.
        let engine = LightEngine(ephemeris: FixedEphemeris())
        let f = uniform(Wx(), fetchedAt: now0)
        let a = engine.dayLight(for: makePlace(best: [.sunset]), on: testDay, inputs: f, now: now0)
        let b = engine.dayLight(for: makePlace(best: []), on: testDay, inputs: f, now: now0)
        #expect(a.windows.map(\.score) == b.windows.map(\.score))
    }
}

@Suite struct BlueAndNight {
    @Test func blueHourForgivesCloudButNotOvercast() {
        let partly = score(.blueEvening, Wx(total: 0.5, low: 0.1, mid: 0.4, high: 0.2))!
        let overcast = score(.blueEvening, Wx(total: 0.95, low: 0.8, mid: 0.5, high: 0.5))!
        #expect(partly.band >= .good)
        #expect(overcast.value < partly.value - 20)
    }

    @Test func perfectNightIsGreatOrEpic() {
        let s = score(.night, Wx(total: 0.02, low: 0, mid: 0, high: 0, visibility: 30_000))!
        #expect(s.band >= .great)
        #expect(s.contributors.contains { $0.factor == .darkSky && $0.effect == .helps })
    }

    @Test func brightMoonUpHurtsNight() {
        let dark = score(.night, Wx(total: 0.05), eph: FixedEphemeris(moonAltitude: -20, illumination: 1))!
        let bright = score(.night, Wx(total: 0.05), eph: FixedEphemeris(moonAltitude: 45, illumination: 1))!
        let thin = score(.night, Wx(total: 0.05), eph: FixedEphemeris(moonAltitude: 45, illumination: 0.08))!
        #expect(bright.value < dark.value - 25)
        #expect(thin.value >= dark.value - 2)
        #expect(bright.contributors.contains { $0.factor == .moonlight && $0.effect == .hurts })
    }

    @Test func cloudyNightIsPoor() {
        #expect(score(.night, Wx(total: 0.8))!.band == .poor)
    }

    @Test func nightDoesNotLiftTheSunsetHeadline() {
        // Regression: a perfect night on a rainy, overcast evening.
        let engine = LightEngine(ephemeris: FixedEphemeris())
        let f = forecast(fetchedAt: now0) { date in
            let hour = date.timeIntervalSince(testDay.start(in: utc)) / 3600
            if hour >= 20 { return Wx(total: 0.0, low: 0, mid: 0, high: 0, rain: 0, visibility: 30_000) }
            return Wx(total: 0.95, low: 0.8, mid: 0.4, high: 0.4, rain: 0.8, visibility: 8_000)
        }
        let dl = engine.dayLight(for: makePlace(), on: testDay, inputs: f, now: now0)
        #expect(dl.window(.night)!.score! >= 80)
        let sunset = dl.headline(for: .sunset)!
        #expect(sunset.kind == .goldenEvening)
        #expect(sunset.score! < 40)
        #expect(sunset.assessment.skyScore!.band <= .fair)
    }
}

@Suite struct Availability {
    @Test func missingForecastIsNeverANumber() {
        let engine = LightEngine(ephemeris: FixedEphemeris())
        let a = engine.dayLight(for: makePlace(), on: testDay, inputs: nil, now: now0)
        #expect(a.windows.count == 5)
        for w in a.windows {
            #expect(w.assessment == .unavailable(.notLoaded))
            #expect(w.score == nil)
        }
        let b = engine.dayLight(for: makePlace(), on: testDay, inputs: nil, unavailable: [.needsKey("k")], now: now0)
        for w in b.windows { #expect(w.assessment == .unavailable(.noForecast([.needsKey("k")]))) }
        let c = engine.dayLight(for: makePlace(), on: testDay, inputs: nil, unavailable: [.sourceError("k", "x"), .offline(lastGood: nil)], now: now0)
        for w in c.windows { #expect(w.assessment == .unavailable(.noForecast([.sourceError("k", "x"), .offline(lastGood: nil)]))) }
    }

    @Test func beyondHorizonIsScoredByPersistenceAtLowestConfidence() {
        let engine = LightEngine(ephemeris: FixedEphemeris())
        let f = uniform(Wx(), fetchedAt: now0)   // covers day -1 to day +1
        let far = testDay.adding(days: 10)
        let dl = engine.dayLight(for: makePlace(), on: far, inputs: f, now: now0)
        for w in dl.windows {
            let score = w.assessment.skyScore
            #expect(score?.confidence == .low)
            #expect(score?.notes.contains(.persistence) == true)
            #expect(score.map { $0.range == ConfidenceModel.range(value: $0.value, confidence: .low) } == true)
            #expect((score?.leadHours ?? 0) > 200)
        }
        let partial = engine.dayLight(for: makePlace(), on: testDay, inputs: f, now: now0)
        #expect(partial.windows.allSatisfy { $0.score != nil })
        #expect(partial.windows.allSatisfy { $0.assessment.skyScore?.notes.contains(.persistence) == false })
    }

    /// Adapted: the old test carried the daily-summary note and ScoreNote order; there is no resolution now, so it checks
    /// that persistence keeps the other notes, that notes come out in `SkyNote.sortKey` order without duplicates, and that
    /// a series with no hours means beyond the horizon.
    @Test func persistenceKeepsOtherNotesAndNoHoursMeansBeyondHorizon() {
        let engine = LightEngine(ephemeris: FixedEphemeris())
        let noLayers = uniform(Wx(total: 0.5, low: nil, mid: nil, high: nil), fetchedAt: now0)
        let far = engine.dayLight(for: makePlace(), on: testDay.adding(days: 9), inputs: noLayers, now: now0)
        let notes = far.windows.compactMap { $0.assessment.skyScore?.notes }
        #expect(!notes.isEmpty)
        #expect(notes.allSatisfy { $0.contains(.persistence) && $0.contains(.stale(age: $0.staleAge ?? -1)) == ($0.staleAge != nil) })
        #expect(far.windows.filter { $0.kind != .night }.allSatisfy { $0.assessment.skyScore?.notes.contains(.missing(.cloudLayers)) == true })
        #expect(notes.allSatisfy { n in n.map(\.sortKey) == n.map(\.sortKey).sorted() && Set(n).count == n.count })
        var empty = uniform(Wx(), fetchedAt: now0)
        empty.hourly?.hours = []
        let none = engine.dayLight(for: makePlace(), on: testDay, inputs: empty, now: now0)
        for w in none.windows { #expect(w.assessment == .unavailable(.beyondHorizon)) }
    }

    @Test func windowInProgressBeforeTheFirstHourIsScored() {
        let engine = LightEngine(ephemeris: FixedEphemeris())
        let spot = makePlace()
        // The forecast starts at 06:30 on test day; the blue-morning window (05:40 to 06:12) midpoint is before it, and it
        // has not ended at 05:50.
        var f = uniform(Wx(), fetchedAt: FixedEphemeris.at(testDay, 5.5))
        let kept = f.hourly!.hours.filter { $0.time >= FixedEphemeris.at(testDay, 6.5) }
        f.hourly?.hours = kept
        let now = FixedEphemeris.at(testDay, 5.8)
        let dl = engine.dayLight(for: spot, on: testDay, inputs: f, now: now)
        let blue = dl.window(.blueMorning)!
        let score = blue.assessment.skyScore
        #expect(score != nil)
        #expect(score?.notes.contains(.persistence) == false)
        // Ended window stays "in the past".
        let later = engine.dayLight(for: spot, on: testDay, inputs: f, now: FixedEphemeris.at(testDay, 6.4))
        #expect(later.window(.blueMorning)!.assessment == .unavailable(.inThePast))
    }

    @Test func coveredDaysAndOutlookDayCount() {
        let engine = LightEngine(ephemeris: FixedEphemeris())
        // Eight whole UTC days from the start of testDay (like a daily-summary source's range).
        let start = testDay.start(in: utc)
        let hours = (0..<(8 * 24)).map { i in
            HourlyConditions(time: start.addingTimeInterval(Double(i) * 3600), cloudTotal: 0.3, precipChance: 0, visibilityKm: 20,
                             tempC: 12, rhPercent: 50, windMs: 1.4)
        }
        let f = ForecastSkyInputs(hourly: HourlySeries(hours: hours), provenance: provenance(fetchedAt: start))
        #expect(f.hourly!.coveredDays(from: testDay, in: utc) == 8)
        #expect(f.hourly!.coveredDays(from: testDay.adding(days: 6), in: utc) == 2)
        #expect(f.hourly!.coveredDays(from: testDay.adding(days: 20), in: utc) == 0)
        var none = f
        none.hourly?.hours = []
        #expect(none.hourly!.coveredDays(from: testDay, in: utc) == 0)
        let spot = makePlace()
        #expect(engine.outlookDayCount(for: spot, from: testDay, inputs: f, max: 10) == 8)
        #expect(engine.outlookDayCount(for: spot, from: testDay, inputs: f, max: 5) == 5)
        #expect(engine.outlookDayCount(for: spot, from: testDay.adding(days: 30), inputs: f, max: 10) == 1)
        #expect(engine.outlookDayCount(for: spot, from: testDay, inputs: nil, max: 10) == 10)
        #expect(engine.outlookDayCount(for: spot, from: testDay, inputs: none, max: 10) == 10)
    }

    @Test func windowsInThePast() {
        let engine = LightEngine(ephemeris: FixedEphemeris())
        let f = uniform(Wx(), fetchedAt: now0)
        let now = FixedEphemeris.at(testDay, 18.5)   // after golden evening, during blue evening
        let dl = engine.dayLight(for: makePlace(), on: testDay, inputs: f, now: now)
        #expect(dl.window(.blueMorning)!.assessment == .unavailable(.inThePast))
        #expect(dl.window(.goldenEvening)!.assessment == .unavailable(.inThePast))
        #expect(dl.window(.blueEvening)!.score != nil)
        #expect(dl.window(.night)!.score != nil)
        // The past wins over a missing forecast.
        let none = engine.dayLight(for: makePlace(), on: testDay, inputs: nil, now: now)
        #expect(none.window(.goldenEvening)!.assessment == .unavailable(.inThePast))
        #expect(none.window(.night)!.assessment == .unavailable(.notLoaded))
    }
}

@Suite struct ConfidenceAndContributors {
    private func scoreAt(lead hours: Double, layers: Bool = true, kind: LightWindowKind = .goldenEvening) -> SkyScore {
        let engine = LightEngine(ephemeris: FixedEphemeris())
        let mid = engine.windows(for: makePlace(), on: testDay).first { $0.kind == kind }!.span.midpoint
        let fetched = mid.addingTimeInterval(-hours * 3600)
        let w = layers ? Wx(total: 0.5, low: 0.1, mid: 0.4, high: 0.4) : Wx(total: 0.5, low: nil, mid: nil, high: nil)
        let f = forecast(fetchedAt: fetched) { _ in w }
        return engine.dayLight(for: makePlace(), on: testDay, inputs: f, now: fetched).window(kind)!.assessment.skyScore!
    }

    @Test func confidenceFallsWithLead() {
        let near = scoreAt(lead: 12), mid = scoreAt(lead: 50), far = scoreAt(lead: 100)
        #expect(near.confidence == .high)
        #expect(mid.confidence == .medium)
        #expect(far.confidence == .low)
        #expect(near.range.count == 1)
        #expect(near.range == near.value...near.value)
        #expect(mid.range.count > near.range.count)
        #expect(far.range.count > mid.range.count)
        #expect(mid.range == max(0, mid.value - 8)...min(100, mid.value + 8))
        #expect(abs(far.leadHours - 100) < 0.01)
        #expect(near.source == testSource)
    }

    @Test func rangeIsClamped() {
        let r = ConfidenceModel.range(value: 95, confidence: .low)
        #expect(r == 80...100)
        #expect(ConfidenceModel.range(value: 5, confidence: .medium) == 0...13)
    }

    @Test func missingLayersDropOneStep() {
        #expect(scoreAt(lead: 12, layers: false).confidence == .medium)
        #expect(scoreAt(lead: 50, layers: false).confidence == .low)
        #expect(scoreAt(lead: 100, layers: false).confidence == .low)
        // The total-cloud fallback names its factor.
        #expect(scoreAt(lead: 12, layers: false).contributors.contains { $0.factor == .totalCloud })
        // Night does not use layers, so it keeps its confidence.
        #expect(scoreAt(lead: 12, layers: false, kind: .night).confidence == .high)
    }

    @Test func fetchedAtIsCopied() {
        let s = score(.blueEvening, Wx())!
        #expect(s.forecastFetchedAt == now0)
    }

    @Test func contributorsSortedAndNonEmpty() {
        let cases: [(LightWindowKind, Wx)] = [
            (.goldenEvening, Wx(total: 0.6, low: 0.5, mid: 0.4, high: 0.3, rain: 0.5, visibility: 6000)),
            (.goldenMorning, Wx(total: 0.02, low: 0, mid: 0, high: 0)),
            (.blueMorning, Wx(total: 0.9, low: 0.9, mid: 0.1, high: 0.1, rain: 0.2)),
            (.night, Wx(total: 0.3, rain: 0.1)),
            (.goldenEvening, Wx(total: 0.7, low: nil, mid: nil, high: nil)),
        ]
        for (kind, wx) in cases {
            let s = score(kind, wx, eph: FixedEphemeris(moonAltitude: 30, illumination: 0.7))!
            #expect(!s.contributors.isEmpty)
            let mags = s.contributors.map { abs($0.points) }
            #expect(mags == mags.sorted(by: >), "\(kind)")
            // Unclamped scores equal the baseline plus the contributors.
            #expect(s.value == 60 + s.contributors.reduce(0) { $0 + $1.points } || s.value == 0 || s.value == 100)
        }
    }
}

@Suite struct Calibration {
    @Test func epicIsRare() {
        let engine = LightEngine(ephemeris: FixedEphemeris())
        var rng = SeededRNG(seed: 20261005)
        var scores: [Int] = []
        for i in 0..<400 {
            let day = LocalDay(year: 2026, month: 10, day: 1).adding(days: i % 7)
            // A varied week: clear, partly cloudy, broken, overcast, rain.
            let regime = Double.random(in: 0..<1, using: &rng)
            let wx: Wx
            switch regime {
            case ..<0.15: wx = Wx(total: .random(in: 0...0.12, using: &rng), low: .random(in: 0...0.05, using: &rng), mid: .random(in: 0...0.08, using: &rng), high: .random(in: 0...0.1, using: &rng))
            case ..<0.45:
                let low = Double.random(in: 0...0.25, using: &rng), mid = Double.random(in: 0...0.7, using: &rng), high = Double.random(in: 0...0.7, using: &rng)
                wx = Wx(total: min(1, max(low, mid, high) + .random(in: 0...0.15, using: &rng)), low: low, mid: mid, high: high)
            case ..<0.7:
                let low = Double.random(in: 0.1...0.7, using: &rng), mid = Double.random(in: 0.2...1, using: &rng), high = Double.random(in: 0...1, using: &rng)
                wx = Wx(total: min(1, max(low, mid, high) + .random(in: 0...0.2, using: &rng)), low: low, mid: mid, high: high, rain: .random(in: 0...0.4, using: &rng))
            default:
                let low = Double.random(in: 0.5...1, using: &rng)
                wx = Wx(total: .random(in: 0.8...1, using: &rng), low: low, mid: .random(in: 0.3...1, using: &rng), high: .random(in: 0...1, using: &rng),
                        rain: .random(in: 0.2...0.9, using: &rng), visibility: .random(in: 4000...15000, using: &rng))
            }
            var w = wx
            w.visibility = regime >= 0.7 ? wx.visibility : .random(in: 8000...32000, using: &rng)
            let f = uniform(w, fetchedAt: FixedEphemeris.at(day.adding(days: -1), 12), day: day)
            let now = FixedEphemeris.at(day.adding(days: -1), 12)
            let dl = engine.dayLight(for: makePlace("s\(i)"), on: day, inputs: f, now: now)
            for kind in [LightWindowKind.goldenMorning, .goldenEvening] {
                if let s = dl.window(kind)?.score { scores.append(s) }
            }
        }
        let epic = scores.filter { LightBand(score: $0) == .epic }.count
        let bands = Set(scores.map { LightBand(score: $0) })
        #expect(Double(epic) / Double(scores.count) <= 0.10, "epic \(epic) of \(scores.count)")
        #expect(bands.count >= 4, "bands \(bands)")
    }
}

@Suite struct Geometry {
    @Test func standardDayHasFiveWindowsInOrder() {
        let engine = LightEngine(ephemeris: FixedEphemeris())
        let w = engine.windows(for: makePlace(), on: testDay)
        #expect(w.map(\.kind) == [.blueMorning, .goldenMorning, .goldenEvening, .blueEvening, .night])
        let night = w.last!.span
        #expect(night.duration == 3 * 3600)
        #expect(zip(w, w.dropFirst()).allSatisfy { $0.span.start <= $1.span.start })
    }

    @Test func nightEndsAtNextDawnIfSooner() {
        var eph = FixedEphemeris()
        eph.sun = { d in
            var s = FixedEphemeris.standardDay(d)
            s.astronomicalDawn = FixedEphemeris.at(d, -1.5)   // short night: next dawn 22:30 the evening before
            return s
        }
        let night = LightEngine(ephemeris: eph).windows(for: makePlace(), on: testDay).first { $0.kind == .night }!
        #expect(night.span.end == FixedEphemeris.at(testDay.adding(days: 1), -1.5))
        #expect(night.span.duration < 3 * 3600)
    }

    @Test func highLatitudeWinterGoldenFallsBackToNoon() {
        var eph = FixedEphemeris()
        eph.sun = { d in
            SunEvents(day: d, kind: .normal, solarNoon: FixedEphemeris.at(d, 12),
                      civilDawn: FixedEphemeris.at(d, 8.5), sunrise: FixedEphemeris.at(d, 9.5),
                      sunset: FixedEphemeris.at(d, 14.5), civilDusk: FixedEphemeris.at(d, 15.5))
        }
        let w = LightEngine(ephemeris: eph).windows(for: makePlace(), on: testDay)
        let gm = w.first { $0.kind == .goldenMorning }!.span
        let ge = w.first { $0.kind == .goldenEvening }!.span
        #expect(gm.start == FixedEphemeris.at(testDay, 9.5) && gm.end == FixedEphemeris.at(testDay, 12))
        #expect(ge.start == FixedEphemeris.at(testDay, 12) && ge.end == FixedEphemeris.at(testDay, 14.5))
        #expect(!w.contains { $0.kind == .night })
        #expect(w.map(\.kind) == [.blueMorning, .goldenMorning, .goldenEvening, .blueEvening])
    }

    @Test func polarDayAndNightHaveNoWindows() {
        for kind in [SunEvents.DayKind.polarDay, .polarNight] {
            var eph = FixedEphemeris()
            eph.sun = { d in SunEvents(day: d, kind: kind, solarNoon: FixedEphemeris.at(d, 12)) }
            let engine = LightEngine(ephemeris: eph)
            #expect(engine.windows(for: makePlace(), on: testDay).isEmpty)
            let dl = engine.dayLight(for: makePlace(), on: testDay, inputs: nil, now: now0)
            #expect(dl.windows.isEmpty)
            #expect(dl.headline(for: .sunset) == nil)
        }
    }

    @Test func summerWithoutAstronomicalDuskHasNoNight() {
        var eph = FixedEphemeris()
        eph.sun = { d in
            var s = FixedEphemeris.standardDay(d)
            s.astronomicalDusk = nil
            s.astronomicalDawn = nil
            return s
        }
        let w = LightEngine(ephemeris: eph).windows(for: makePlace(), on: testDay)
        #expect(!w.contains { $0.kind == .night })
        #expect(w.count == 4)
    }

    @Test func missingSunriseDropsMorningWindows() {
        var eph = FixedEphemeris()
        eph.sun = { d in var s = FixedEphemeris.standardDay(d); s.sunrise = nil; return s }
        let kinds = LightEngine(ephemeris: eph).windows(for: makePlace(), on: testDay).map(\.kind)
        #expect(kinds == [.goldenEvening, .blueEvening, .night])
    }
}

@Suite struct Outlook {
    @Test func outlookAndBestUpcoming() {
        let engine = LightEngine(ephemeris: FixedEphemeris())
        let start = testDay
        // Day 2 has the best sunset; day 1 is overcast; the night of day 0 is perfect but must not matter.
        let f = forecast(day: start, fetchedAt: now0, days: 4) { date in
            let d = start.start(in: utc).distance(to: date) / 86400
            switch Int(d.rounded(.down)) {
            case 2: return Wx(total: 0.45, low: 0.05, mid: 0.4, high: 0.4, rain: 0, visibility: 25_000)
            case 1: return Wx(total: 0.95, low: 0.8, mid: 0.4, high: 0.4, rain: 0.5)
            default: return Wx(total: 0.3, low: 0.2, mid: 0.2, high: 0.2)
            }
        }
        let days = engine.outlook(for: makePlace(), from: start, days: 4, inputs: f, now: now0)
        #expect(days.count == 4)
        #expect(days.map(\.day) == (0..<4).map { start.adding(days: $0) })
        let best = engine.bestUpcoming(for: makePlace(), intent: .sunset, from: start, days: 4, inputs: f, now: now0)
        #expect(best?.day == start.adding(days: 2))
        #expect(best?.window.kind == .goldenEvening)
        // Without a forecast there is nothing to recommend.
        #expect(engine.bestUpcoming(for: makePlace(), intent: .sunset, from: start, days: 4, inputs: nil, now: now0) == nil)
        #expect(engine.outlook(for: makePlace(), from: start, days: 0, inputs: f, now: now0).isEmpty)
    }

    @Test func tiesGoToTheEarlierDay() {
        let engine = LightEngine(ephemeris: FixedEphemeris())
        let f = forecast(day: testDay, fetchedAt: now0, days: 3) { _ in Wx() }
        let best = engine.bestUpcoming(for: makePlace(), intent: .sunset, from: testDay, days: 3, inputs: f, now: now0)
        #expect(best?.day == testDay)
    }

    @Test func moonPhaseIsFilled() {
        let engine = LightEngine(ephemeris: FixedEphemeris(illumination: 0.4))
        let dl = engine.dayLight(for: makePlace(), on: testDay, inputs: nil, now: now0)
        #expect(dl.moonPhase.illumination == 0.4)
        #expect(dl.sun.kind == .normal)
        #expect(dl.timeZoneIdentifier == "UTC")
    }
}

/// Optional precipitation and visibility, layers on contributors and notes.
@Suite struct ProviderGaps {
    private func scoreAt(_ w: Wx, _ kind: LightWindowKind = .goldenEvening, lead hours: Double = 12, model: String? = nil) -> SkyScore {
        let engine = LightEngine(ephemeris: FixedEphemeris())
        let mid = engine.windows(for: makePlace(), on: testDay).first { $0.kind == kind }!.span.midpoint
        let fetched = mid.addingTimeInterval(-hours * 3600)
        let f = forecast(fetchedAt: fetched, model: model) { _ in w }
        return engine.dayLight(for: makePlace(), on: testDay, inputs: f, now: fetched).window(kind)!.assessment.skyScore!
    }

    private let partly = Wx(total: 0.5, low: 0.1, mid: 0.4, high: 0.4)

    @Test func amountBasedPrecipitationHurtsAndNotes() {
        var dry = partly; dry.rain = nil; dry.mm = 0
        var wet = partly; wet.rain = nil; wet.mm = 2
        let d = scoreAt(dry), w = scoreAt(wet)
        #expect(w.value < d.value)
        let p = w.contributors.first { $0.factor == .precipitation }
        #expect(p?.effect == .hurts)
        #expect(p?.points == -40)
        #expect(w.notes.contains(.precipitationFromAmount))
        #expect(d.notes.contains(.precipitationFromAmount))
        // A chance, when present, wins and adds no note.
        var both = wet; both.rain = 0
        #expect(!scoreAt(both).notes.contains(.precipitationFromAmount))
    }

    @Test func amountCurve() {
        #expect(WindowScorer.interp(0, WindowScorer.precipitationAmount) == 0)
        #expect(WindowScorer.interp(0.2, WindowScorer.precipitationAmount) == -4)
        #expect(WindowScorer.interp(2, WindowScorer.precipitationAmount) == -40)
        #expect(WindowScorer.interp(10, WindowScorer.precipitationAmount) == -40)
    }

    @Test func neitherChanceNorAmountOmitsFactor() {
        var w = partly; w.rain = nil; w.mm = nil
        let s = scoreAt(w)
        #expect(!s.contributors.contains { $0.factor == .precipitation })
        #expect(!s.notes.contains(.precipitationFromAmount))
    }

    @Test func missingVisibilityIsOmittedWithNote() {
        var w = partly; w.visibility = nil
        let s = scoreAt(w)
        #expect(!s.contributors.contains { $0.factor == .visibility })
        #expect(s.notes.contains(.missing(.visibility)))
        #expect(!scoreAt(partly).notes.contains(.missing(.visibility)))
        // Poor visibility would otherwise have hurt.
        var fog = partly; fog.visibility = 2_000
        #expect(scoreAt(fog).value < s.value)
    }

    @Test func layersAreCarriedOnCloudContributors() {
        let s = scoreAt(partly)
        let expected = CloudLayers(low: 0.1, mid: 0.4, high: 0.4)
        #expect(s.contributors.first { $0.factor == .midHighCloud }?.layers == expected)
        #expect(s.contributors.first { $0.factor == .lowCloud }?.layers == expected)
        #expect(s.contributors.filter { $0.factor == .precipitation || $0.factor == .visibility }.allSatisfy { $0.layers == nil })
        let blue = scoreAt(partly, .blueEvening)
        #expect(blue.contributors.first { $0.factor == .midHighCloud }?.layers == expected)
        let flat = scoreAt(Wx(total: 0.5, low: nil, mid: nil, high: nil))
        #expect(flat.contributors.allSatisfy { $0.layers == nil })
        #expect(flat.notes.contains(.missing(.cloudLayers)))
        #expect(!s.notes.contains(.missing(.cloudLayers)))
    }

    @Test func notesAreOrderedAndUnique() {
        var w = Wx(total: 0.5, low: nil, mid: nil, high: nil)
        w.rain = nil; w.mm = 0.3; w.visibility = nil
        let s = scoreAt(w)
        // Order is SkyNote.sortKey: missing inputs in SkyInput order, then the precipitation note.
        #expect(s.notes == [.missing(.cloudLayers), .missing(.visibility), .missing(.horizon), .precipitationFromAmount])
        #expect(Set(s.notes).count == s.notes.count)
    }

    @Test func modelIsCopied() {
        #expect(scoreAt(partly, model: "GFS").model == "GFS")
        #expect(scoreAt(partly).model == nil)
    }

    @Test(arguments: [LightWindowKind.goldenMorning, .goldenEvening])
    func overcastGoldenStaysBelowGood(kind: LightWindowKind) {
        for asChance in [true, false] {
            for visibility in [30_000.0, nil] {
                var w = Wx(total: 0.95, low: 0.5, mid: 0.4, high: 0.4)
                w.rain = asChance ? 0.0 : nil
                w.mm = asChance ? nil : 0
                w.visibility = visibility
                for lead in [6.0, 30, 60, 100] {
                    let s = scoreAt(w, kind, lead: lead)
                    #expect(s.band < .good && s.value <= 56, "chance \(asChance) vis \(String(describing: visibility)) lead \(lead): \(s.value)")
                }
            }
        }
    }
}

extension Array where Element == SkyNote {
    /// The age of the first stale note, for assertions.
    var staleAge: TimeInterval? {
        for n in self { if case .stale(let a) = n { return a } }
        return nil
    }
}
