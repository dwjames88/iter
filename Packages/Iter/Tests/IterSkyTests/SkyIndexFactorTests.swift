import Foundation
import Testing
import IterModel
import IterAstro
@testable import IterSky

/// New in Phase 3: missing inputs, staleness, the 0...100 clamp, terrain, aerosol, fog, wind, the Milky Way, aurora,
/// Bortle and seeing, and the notes that say what was left out.

/// Scores `kind` on the standard fixed day with `w` everywhere, fetched `lead` hours before the window's middle and
/// scored at the fetch time (so the forecast is fresh unless `age` pushes `now` later).
private func window(_ kind: LightWindowKind, _ w: Wx, eph: FixedEphemeris = FixedEphemeris(), place: Place = makePlace(),
                    lead: Double = 12, age: TimeInterval = 0, ttl: TimeInterval = Freshness.defaultTTL,
                    tweak: (inout ForecastSkyInputs) -> Void = { _ in }) -> LightWindow {
    let engine = LightEngine(ephemeris: eph)
    let mid = engine.windows(for: place, on: testDay).first { $0.kind == kind }!.span.midpoint
    let fetched = mid.addingTimeInterval(-lead * 3600)
    var inputs = forecast(fetchedAt: fetched, ttl: ttl) { _ in w }
    tweak(&inputs)
    return engine.dayLight(for: place, on: testDay, inputs: inputs, now: fetched.addingTimeInterval(age)).window(kind)!
}

private func sky(_ kind: LightWindowKind, _ w: Wx, eph: FixedEphemeris = FixedEphemeris(), place: Place = makePlace(), lead: Double = 12,
                 age: TimeInterval = 0, ttl: TimeInterval = Freshness.defaultTTL, tweak: (inout ForecastSkyInputs) -> Void = { _ in }) -> SkyScore {
    window(kind, w, eph: eph, place: place, lead: lead, age: age, ttl: ttl, tweak: tweak).assessment.skyScore!
}

private func points(_ s: SkyScore, _ f: LightContributor.Factor) -> Int? { s.contributors.first { $0.factor == f }?.points }

// MARK: Missing inputs

@Suite struct MissingInputTests {
    @Test func noAerosolDropsTheFactorLowersConfidenceAndSaysSo() {
        let with = sky(.goldenEvening, Wx(aod: 0.2))
        let without = sky(.goldenEvening, Wx(aod: nil))
        #expect(points(with, .aerosol) == 4)
        #expect(points(without, .aerosol) == nil)
        #expect(!without.notes.contains(.missing(.aerosol)) == false)
        #expect(!with.notes.contains(.missing(.aerosol)))
        #expect(without.confidenceValue < with.confidenceValue)
        #expect(without.confidenceCauses.contains(.missingSecondary(.aerosol)))
        #expect(!without.inputs.contains { $0.input == .aerosol || $0.input == .smoke } && with.inputs.contains { $0.input == .aerosol })
    }

    @Test func smokeStandsInForAerosolAndIsNamed() {
        let s = sky(.goldenEvening, Wx(aod: nil, smoke: 20))
        #expect(points(s, .aerosol) == 4)
        #expect(s.inputs.contains { $0.input == .smoke } && !s.inputs.contains { $0.input == .aerosol })
        #expect(!s.notes.contains(.missing(.aerosol)))
    }

    @Test func noCloudLayersIsAMissingPrimaryInput() {
        let layers = sky(.goldenEvening, Wx())
        let flat = sky(.goldenEvening, Wx(low: nil, mid: nil, high: nil))
        #expect(flat.notes.contains(.missing(.cloudLayers)))
        #expect(flat.confidenceCauses.contains(.missingPrimary(.cloudLayers)))
        #expect(flat.confidenceValue < layers.confidenceValue - 0.4)
        #expect(flat.confidence < layers.confidence)
    }

    @Test func noPrecipitationAtAllIsMissingPrimary() {
        let s = sky(.blueEvening, Wx(rain: nil, mm: nil))
        #expect(s.notes.contains(.missing(.precipitation)) && s.confidenceCauses.contains(.missingPrimary(.precipitation)))
        #expect(points(s, .precipitation) == nil)
    }

    @Test func noHorizonIsASecondaryNoteOnGoldenAndBlueButNotNight() {
        for kind in [LightWindowKind.goldenMorning, .goldenEvening, .blueMorning, .blueEvening] {
            let s = sky(kind, Wx())
            #expect(s.notes.contains(.missing(.horizon)) && s.confidenceCauses.contains(.missingSecondary(.horizon)), "\(kind)")
            let flat = sky(kind, Wx(), place: makePlace(horizon: .flat))
            #expect(!flat.notes.contains(.missing(.horizon)) && flat.inputs.contains { $0.input == .horizon }, "\(kind)")
        }
        #expect(!sky(.night, Wx()).notes.contains(.missing(.horizon)))
    }

    @Test func noWindDataIsMissingOnBlueAndNightOnly() {
        let w = Wx(wind: nil)
        #expect(sky(.blueEvening, w).notes.contains(.missing(.wind)))
        #expect(sky(.night, w).notes.contains(.missing(.wind)))
        #expect(!sky(.goldenEvening, w).notes.contains(.missing(.wind)))
    }

    @Test func totalCloudFromLayersAloneIsDerivedAndNoted() {
        let s = sky(.goldenEvening, Wx(total: nil, low: 0.1, mid: 0.5, high: 0.3))
        #expect(s.notes.contains(.missing(.cloudTotal)) && !s.inputs.contains { $0.input == .cloudTotal })
    }

    @Test func noCloudInformationAtAllIsUnavailableNotScored() {
        let w = window(.goldenEvening, Wx(total: nil, low: nil, mid: nil, high: nil))
        #expect(w.assessment == .unavailable(.noForecast([.notProvidedBySource])))
    }

    @Test func aForecastWithoutProvenanceCannotBeDatedSoItIsNotScored() {
        let w = window(.goldenEvening, Wx()) { $0.provenance = nil }
        #expect(w.assessment == .unavailable(.noForecast([.notProvidedBySource])))
    }

    @Test func fieldSourcesAndAgesAreReported() throws {
        let s = sky(.goldenEvening, Wx(), age: 3600) { $0.hourly?.fieldSources = [.cloudLow: "other.layers"] }
        let layers = try #require(s.inputs.first { $0.input == .cloudLayers })
        #expect(layers.source == "other.layers" && layers.age == 3600)
        let precip = try #require(s.inputs.first { $0.input == .precipitation })
        #expect(precip.source == testSource)
        let moonless = s.inputs.first { $0.input == .moon }
        #expect(moonless == nil)   // golden windows do not read the moon
        let night = sky(.night, Wx())
        #expect(night.inputs.first { $0.input == .moon }?.source == nil)
    }
}

// MARK: Staleness

@Suite struct StalenessTests {
    @Test func aForecastFourHoursOldWithAThreeHourTTLIsStaleAndLessConfident() {
        let fresh = sky(.goldenEvening, Wx(), age: 0)
        let stale = sky(.goldenEvening, Wx(), age: 4 * 3600)
        #expect(!fresh.isStale && stale.isStale)
        #expect(stale.age == 4 * 3600 && fresh.age == 0)
        #expect(stale.notes.contains(.stale(age: 4 * 3600)) && stale.confidenceCauses.contains(.stale(age: 4 * 3600)))
        #expect(!fresh.notes.contains { if case .stale = $0 { true } else { false } })
        #expect(fresh.confidence == .high && stale.confidence == .medium)
        #expect(abs((fresh.confidenceValue - stale.confidenceValue) - 0.5) < 1e-9)
        #expect(stale.value == fresh.value)   // staleness lowers trust, not the number
    }

    @Test func ttlIsPerForecast() {
        #expect(!sky(.goldenEvening, Wx(), age: 4 * 3600, ttl: 6 * 3600).isStale)
        #expect(sky(.goldenEvening, Wx(), age: 2 * 3600, ttl: 3600).isStale)
    }

    @Test func freshnessEdges() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let ttl = 3 * 3600.0
        #expect(Freshness.evaluate(fetchedAt: t0, ttl: ttl, now: t0) == .fresh(age: 0))
        #expect(Freshness.evaluate(fetchedAt: t0, ttl: ttl, now: t0.addingTimeInterval(ttl)) == .fresh(age: ttl))
        #expect(Freshness.evaluate(fetchedAt: t0, ttl: ttl, now: t0.addingTimeInterval(ttl + 1)) == .stale(age: ttl + 1))
        // A fetch time in the future is age zero, fresh.
        #expect(Freshness.evaluate(fetchedAt: t0.addingTimeInterval(60), ttl: ttl, now: t0) == .fresh(age: 0))
        #expect(Freshness.evaluate(fetchedAt: t0, ttl: 0, now: t0.addingTimeInterval(1)).isStale)
        #expect(Freshness.evaluate(fetchedAt: t0, ttl: ttl, now: t0.addingTimeInterval(9)).age == 9)
    }
}

// MARK: Source spread and lead time

@Suite struct SpreadAndLeadTests {
    @Test func anotherSourceFarFromThePrimaryCostsOneStepAndNamesTheSpread() {
        let agree = sky(.goldenEvening, Wx(total: 0.3)) { $0.spreadSeries = [forecast(fetchedAt: now0) { _ in Wx(total: 0.5) }.hourly!] }
        #expect(!agree.notes.contains { if case .sourceSpread = $0 { true } else { false } })
        let apart = sky(.goldenEvening, Wx(total: 0.3)) { $0.spreadSeries = [forecast(fetchedAt: now0) { _ in Wx(total: 0.7) }.hourly!] }
        #expect(apart.notes.contains(.sourceSpread(low: 0.3, high: 0.7)))
        #expect(apart.confidenceCauses.contains(.sourceSpread))
        #expect(apart.confidence == .medium && agree.confidence == .high)
    }

    @Test func leadTimeUsesTheModelRunWhenKnown() {
        // Fetched at the window but the run was 40 hours before: past the 36-hour limit.
        let mid = LightEngine(ephemeris: FixedEphemeris()).windows(for: makePlace(), on: testDay).first { $0.kind == .goldenEvening }!.span.midpoint
        let issued = mid.addingTimeInterval(-40 * 3600)
        let s = sky(.goldenEvening, Wx()) { $0.provenance?.issuedAt = issued }
        #expect(abs(s.leadHours - 40) < 1e-6 && s.forecastIssuedAt == issued)
        #expect(s.confidence == .medium)
        #expect(s.confidenceCauses.contains { if case .leadTime = $0 { true } else { false } })
    }

    @Test func confidenceValueIsContinuousBehindTheLevel() {
        let near = sky(.goldenEvening, Wx(), lead: 12), far = sky(.goldenEvening, Wx(), lead: 100)
        #expect(near.confidenceValue > 0.85 && near.confidenceValue <= 1)
        #expect(far.confidenceValue < 0.1)
        for s in [near, far] { #expect(ConfidenceModel.level(forValue: s.confidenceValue * 2) == s.confidence) }
    }
}

// MARK: The 0...100 clamp

@Suite struct ClampTests {
    @Test func aTerribleWindowReachesZeroNotFive() throws {
        let worst = Wx(total: 1, low: 1, mid: 1, high: 1, rain: 1, visibility: 0)
        for kind in LightWindowKind.allCases {
            let s = sky(kind, worst, eph: FixedEphemeris(moonAltitude: 60, illumination: 1))
            #expect(s.value == 0 && s.band == .poor, "\(kind)")
            #expect(s.notes.contains(.clampedLow) && !s.notes.contains(.clampedHigh), "\(kind)")
            // The bars still add up (to the raw score, which is below zero).
            #expect(60 + s.contributors.reduce(0) { $0 + $1.points } < 0, "\(kind)")
        }
    }

    @Test func aPerfectWindowCapsAtOneHundredAndSaysSo() throws {
        // A real sky for the core: July at 40 N on the prime meridian, the sun far below, the moon down.
        let place = makePlace(lat: 40, lon: 0)
        let july = LocalDay(year: 2026, month: 7, day: 15)
        let eph = FixedEphemeris(sunPosition: { _ in SkyPosition(altitude: -30, azimuth: 0) })
        let engine = LightEngine(ephemeris: eph)
        let fetched = FixedEphemeris.at(july, 6)
        let inputs = forecast(day: july, fetchedAt: fetched) { _ in Wx(total: 0, low: 0, mid: 0, high: 0, visibility: 25_000) }
        var perfect = inputs
        perfect.bortle = 1
        perfect.seeing = 1.0
        let s = try #require(engine.dayLight(for: place, on: july, inputs: perfect, now: fetched).window(.night)?.assessment.skyScore)
        #expect(s.value == 100 && s.band == .epic)
        #expect(s.notes.contains(.clampedHigh) && !s.notes.contains(.clampedLow))
        #expect(60 + s.contributors.reduce(0) { $0 + $1.points } == 101)
        #expect(points(s, .milkyWay) == 4 && points(s, .lightPollution) == 6 && points(s, .seeing) == 3)
        // Without the Bortle and seeing terms the same night is below the cap and unclamped.
        let plain = try #require(engine.dayLight(for: place, on: july, inputs: inputs, now: fetched).window(.night)?.assessment.skyScore)
        #expect(plain.value == 92 && !plain.notes.contains(.clampedHigh))
    }

    @Test func contributorsSumToTheValueWhenNotClamped() {
        for kind in LightWindowKind.allCases {
            let s = sky(kind, Wx(total: 0.4, low: 0.2, mid: 0.4, high: 0.5, rain: 0.2, visibility: 9_000, aod: 0.4, rh: 95, wind: 9))
            #expect(!s.notes.contains(.clampedLow) && !s.notes.contains(.clampedHigh))
            #expect(60 + s.contributors.reduce(0) { $0 + $1.points } == s.value, "\(kind)")
        }
    }
}

// MARK: Aerosol and smoke

@Suite struct AerosolTests {
    @Test func lightAerosolHelpsGoldenAndHeavyHurts() {
        func aerosol(_ aod: Double?, smoke: Double? = nil, kind: LightWindowKind = .goldenEvening) -> Int? {
            points(sky(kind, Wx(aod: aod, smoke: smoke)), .aerosol)
        }
        #expect(aerosol(0.02) == nil)                 // clean air: no term
        #expect(aerosol(0.15) == 4 && aerosol(0.3) == 4)
        #expect(aerosol(0.6) == -10)
        #expect(aerosol(1.0) == -20 && aerosol(2.5) == -20)
        #expect(aerosol(nil, smoke: 20) == 4)
        #expect(aerosol(nil, smoke: 150) == -20)
        #expect(aerosol(0.2, kind: .blueEvening) == 4 && aerosol(0.6, kind: .blueMorning) == -10)
        // AOD wins when both are present.
        #expect(aerosol(0.6, smoke: 20) == -10)
        let light = sky(.goldenEvening, Wx(aod: 0.2)), heavy = sky(.goldenEvening, Wx(aod: 0.9))
        #expect(light.value > heavy.value + 15)
    }

    @Test func atNightAerosolOnlyEverHurtsAndGetsWorse() {
        var last = 1
        for aod in stride(from: 0.0, through: 1.5, by: 0.1) {
            let p = points(sky(.night, Wx(aod: aod)), .aerosol) ?? 0
            #expect(p <= 0 && p <= last, "aod \(aod)")
            last = p
        }
        #expect(points(sky(.night, Wx(aod: 1.2)), .aerosol) == -14)
        #expect(points(sky(.night, Wx(aod: nil, smoke: 150)), .aerosol) == -14)
    }
}

// MARK: Fog, humidity, wind

@Suite struct AirTests {
    @Test func aTightDewpointSpreadWithLightWindFlagsFogOnMorningsOnly() {
        let damp = Wx(wind: 1.0, temp: 6, dew: 5)
        for kind in [LightWindowKind.blueMorning, .goldenMorning] {
            let s = sky(kind, damp)
            #expect(s.flags.contains(.fogPossible), "\(kind)")
            #expect(!s.contributors.contains { $0.factor == .fog })   // a flag, not a score term
        }
        #expect(!sky(.goldenEvening, damp).flags.contains(.fogPossible))
        #expect(!sky(.goldenMorning, Wx(wind: 5, temp: 6, dew: 5)).flags.contains(.fogPossible))
        #expect(!sky(.goldenMorning, Wx(wind: 1, temp: 12, dew: 5)).flags.contains(.fogPossible))
        // Humidity alone will do.
        #expect(sky(.blueMorning, Wx(rh: 97, wind: 1)).flags.contains(.fogPossible))
        // And the flag adds no points.
        #expect(sky(.goldenMorning, damp).value == sky(.goldenMorning, Wx(wind: 1.0)).value)
    }

    @Test func fogWithLowVisibilityIsAlreadyInTheVisibilityFactor() {
        let s = sky(.goldenMorning, Wx(visibility: 1_500, wind: 1, temp: 6, dew: 5))
        #expect(s.flags.contains(.fogPossible) && s.contributors.contains { $0.factor == .visibility && $0.effect == .hurts })
    }

    @Test func nightHumidityAboveNinetyCostsUpToFour() {
        #expect(points(sky(.night, Wx(rh: 85)), .humidity) == nil)
        #expect(points(sky(.night, Wx(rh: 95)), .humidity) == -2)
        #expect(points(sky(.night, Wx(rh: 100)), .humidity) == -4)
        #expect(points(sky(.goldenEvening, Wx(rh: 100)), .humidity) == nil)
        #expect(sky(.night, Wx(rh: nil)).notes.contains(.missing(.humidity)))
    }

    @Test func strongWindFlagsLongExposuresOnBlueAndNight() {
        let calm = sky(.night, Wx(wind: 3))
        #expect(!calm.flags.contains(.longExposureWind) && points(calm, .wind) == nil)
        let breezy = sky(.night, Wx(wind: 9)), gusty = sky(.blueEvening, Wx(wind: 4, gust: 14)), gale = sky(.night, Wx(wind: 16))
        #expect(breezy.flags.contains(.longExposureWind) && gusty.flags.contains(.longExposureWind))
        #expect((points(breezy, .wind) ?? 0) <= -2 && (points(breezy, .wind) ?? 0) >= -3)
        #expect(points(gusty, .wind) != nil && (points(gale, .wind) ?? 0) == -6)
        // Golden windows are not penalised for wind.
        let golden = sky(.goldenEvening, Wx(wind: 20, gust: 30))
        #expect(!golden.flags.contains(.longExposureWind) && points(golden, .wind) == nil)
    }
}

// MARK: Terrain

@Suite struct TerrainTests {
    /// The sun descending linearly through the evening golden window (+6 to -0.833 degrees) toward the west.
    static let evening = FixedEphemeris(sunPosition: { t in
        let h = t.timeIntervalSince(testDay.start(in: utc)) / 3600
        let f = (h - 17.5) / (18.333 - 17.5)
        return SkyPosition(altitude: 6 - f * 6.833, azimuth: 270)
    })
    /// The sun climbing through the morning golden window (-0.833 to +6 degrees) toward the east.
    static let morning = FixedEphemeris(sunPosition: { t in
        let h = t.timeIntervalSince(testDay.start(in: utc)) / 3600
        let f = (h - 6.2) / (7.0 - 6.2)
        return SkyPosition(altitude: -0.833 + f * 6.833, azimuth: 90)
    })

    static func ridge(_ degrees: Double, around azimuth: Double) -> HorizonProfile {
        var e = Array(repeating: 0.0, count: 72)
        for i in 0..<72 where abs(Double(i) * 5 - azimuth) <= 20 { e[i] = degrees }
        return HorizonProfile(elevationsDegrees: e)
    }

    @Test func aWesternRidgeEndsTheGoldenEveningEarly() throws {
        let flatWindow = window(.goldenEvening, Wx(), eph: Self.evening, place: makePlace(horizon: .flat))
        #expect(flatWindow.effectiveSpan == nil)
        let flatScore = try #require(flatWindow.assessment.skyScore)
        #expect(!flatScore.contributors.contains { $0.factor == .terrain } && !flatScore.notes.contains { if case .terrainEndsWindowEarly = $0 { true } else { false } })

        let ridged = window(.goldenEvening, Wx(), eph: Self.evening, place: makePlace(horizon: Self.ridge(3, around: 270)))
        let eff = try #require(ridged.effectiveSpan)
        #expect(eff.start == ridged.span.start && eff.end < ridged.span.end)
        // The sun reaches 3 degrees (2.17 above the sunset altitude) 56% of the way down.
        let expectedEnd = ridged.span.start.addingTimeInterval(ridged.span.duration * (6 - 2.167) / 6.833)
        #expect(abs(eff.end.timeIntervalSince(expectedEnd)) < 90)
        let s = try #require(ridged.assessment.skyScore)
        let lost = ridged.span.duration - eff.duration
        #expect(s.notes.contains { if case .terrainEndsWindowEarly(let by) = $0 { abs(by - lost) < 1 } else { false } })
        let terrain = try #require(s.contributors.first { $0.factor == .terrain })
        #expect(terrain.effect == .hurts && terrain.points < -10 && terrain.points > -20)
        #expect(abs(terrain.value - lost / ridged.span.duration) < 1e-9)
        #expect(s.value < flatScore.value - 10)
        #expect(!s.notes.contains(.missing(.horizon)))
    }

    @Test func aTallRidgeTakesTheWholeWindow() throws {
        let w = window(.goldenEvening, Wx(), eph: Self.evening, place: makePlace(horizon: Self.ridge(8, around: 270)))
        let eff = try #require(w.effectiveSpan)
        #expect(eff.duration == 0 && eff.start == w.span.start)
        #expect(points(try #require(w.assessment.skyScore), .terrain) == -30)
    }

    @Test func aRidgeInTheOtherDirectionChangesNothing() {
        let w = window(.goldenEvening, Wx(), eph: Self.evening, place: makePlace(horizon: Self.ridge(8, around: 90)))
        #expect(w.effectiveSpan == nil)
    }

    @Test func anEasternRidgeStartsTheGoldenMorningLate() throws {
        let w = window(.goldenMorning, Wx(), eph: Self.morning, place: makePlace(horizon: Self.ridge(3, around: 90)))
        let eff = try #require(w.effectiveSpan)
        #expect(eff.end == w.span.end && eff.start > w.span.start)
        let s = try #require(w.assessment.skyScore)
        #expect((points(s, .terrain) ?? 0) < -10)
    }

    @Test func effectiveSpanIsKnownEvenWithoutAForecast() throws {
        let engine = LightEngine(ephemeris: Self.evening)
        let place = makePlace(horizon: Self.ridge(3, around: 270))
        let dl = engine.dayLight(for: place, on: testDay, inputs: nil, now: now0)
        let ge = try #require(dl.window(.goldenEvening))
        #expect(ge.assessment == .unavailable(.notLoaded) && ge.effectiveSpan != nil)
        // The standalone helper agrees.
        #expect(ForecastSkyIndex.effectiveSpan(kind: .goldenEvening, span: ge.span, place: place, ephemeris: Self.evening) == ge.effectiveSpan)
        #expect(ForecastSkyIndex.effectiveSpan(kind: .night, span: ge.span, place: place, ephemeris: Self.evening) == nil)
    }

    @Test func theInputsHorizonWinsOverThePlaces() throws {
        let place = makePlace(horizon: .flat)
        let w = window(.goldenEvening, Wx(), eph: Self.evening, place: place) { $0.horizon = Self.ridge(3, around: 270) }
        #expect(w.effectiveSpan != nil)
    }

    @Test func aSkylineTowardTheBlueHourSunCostsAFew() throws {
        let toward = FixedEphemeris(sunPosition: { _ in SkyPosition(altitude: -3, azimuth: 270) })
        let tall = sky(.blueEvening, Wx(), eph: toward, place: makePlace(horizon: Self.ridge(10, around: 270)))
        let low = sky(.blueEvening, Wx(), eph: toward, place: makePlace(horizon: Self.ridge(4, around: 270)))
        let away = sky(.blueEvening, Wx(), eph: toward, place: makePlace(horizon: Self.ridge(10, around: 90)))
        #expect(points(tall, .terrain) == -4 && tall.contributors.first { $0.factor == .terrain }?.value == 10)
        #expect(points(low, .terrain) == nil && points(away, .terrain) == nil)
        #expect(tall.value == low.value - 4)
        #expect(window(.blueEvening, Wx(), eph: toward, place: makePlace(horizon: Self.ridge(10, around: 270))).effectiveSpan == nil)
    }

    @Test func realSunsetOverAFlatHorizonIsUnchanged() {
        // The refracted sun reaches 0 degrees a little before the geometric sunset; a level horizon must not count that.
        let engine = LightEngine(ephemeris: Astronomy())
        let denver = makePlace(lat: 39.74, lon: -104.99, zone: "America/Denver", horizon: .flat)
        for day in [LocalDay(year: 2026, month: 3, day: 8), LocalDay(year: 2026, month: 6, day: 21), LocalDay(year: 2026, month: 12, day: 21)] {
            let dl = engine.dayLight(for: denver, on: day, inputs: nil, now: day.start(in: denver.timeZone))
            for w in dl.windows where w.kind.isGolden { #expect(w.effectiveSpan == nil, "\(day) \(w.kind)") }
        }
    }
}

// MARK: Milky Way and aurora

@Suite struct NightSkyTests {
    /// 40 N on the prime meridian in mid-July: the core is up for the fixed 20:10 to 23:10 night.
    static let place = makePlace(lat: 40, lon: 0)
    static let july = LocalDay(year: 2026, month: 7, day: 15)

    static func night(moonAltitude: Double, _ w: Wx = Wx(total: 0.05), place: Place = place,
                      tweak: (inout ForecastSkyInputs) -> Void = { _ in }) -> SkyScore {
        let eph = FixedEphemeris(moonAltitude: moonAltitude, sunPosition: { _ in SkyPosition(altitude: -30, azimuth: 0) })
        let fetched = FixedEphemeris.at(july, 6)
        var inputs = forecast(day: july, fetchedAt: fetched) { _ in w }
        tweak(&inputs)
        return LightEngine(ephemeris: eph).dayLight(for: place, on: july, inputs: inputs, now: fetched).window(.night)!.assessment.skyScore!
    }

    @Test func theCoreEarnsItsBonusOnlyWithTheMoonDown() throws {
        let down = Self.night(moonAltitude: -30)
        let up = Self.night(moonAltitude: 30)
        #expect(points(down, .milkyWay) == 4)
        #expect(points(up, .milkyWay) == nil)
        let flagDown = try #require(down.flags.compactMap { f -> (TimeSpan?, Double)? in
            if case .milkyWayCore(let best, let alt) = f { return (best, alt) } else { return nil } }.first)
        #expect(flagDown.0 != nil && flagDown.1 > 10)
        // Up in the dark but with the moon above the horizon: flagged, no best window, no bonus.
        let upFlag = up.flags.first { if case .milkyWayCore = $0 { true } else { false } }
        guard case .milkyWayCore(let upBest, _)? = upFlag else {
            Issue.record("the core should be flagged while the moon is up")
            return
        }
        #expect(upBest == nil)
        #expect(down.inputs.contains { $0.input == .galacticCentre })
    }

    @Test func noFlagWhenTheSunNeverGetsLowEnough() {
        // The default fixed sun sits 10 degrees up, so the core is never in astronomical dark.
        let eph = FixedEphemeris()
        let fetched = FixedEphemeris.at(Self.july, 6)
        let inputs = forecast(day: Self.july, fetchedAt: fetched) { _ in Wx(total: 0.05) }
        let s = LightEngine(ephemeris: eph).dayLight(for: Self.place, on: Self.july, inputs: inputs, now: fetched).window(.night)!.assessment.skyScore!
        #expect(!s.flags.contains { if case .milkyWayCore = $0 { true } else { false } } && points(s, .milkyWay) == nil)
    }

    @Test func auroraIsFlaggedByProbabilityOrByKpForTheLatitude() throws {
        let tromso = makePlace(lat: 69.65, lon: 18.96)
        func flag(_ s: SkyScore) -> (Double?, Double?)? {
            for f in s.flags { if case .aurora(let p, let k) = f { return (p, k) } }
            return nil
        }
        let step = AuroraOutlook.KpStep(time: FixedEphemeris.at(Self.july, 18), value: 5)
        // Probability at least 10% flags it anywhere.
        let byP = Self.night(moonAltitude: -30, place: Self.place) { $0.aurora = AuroraOutlook(probabilityPercent: 12) }
        #expect(flag(byP)?.0 == 12)
        let lowP = Self.night(moonAltitude: -30, place: Self.place) { $0.aurora = AuroraOutlook(probabilityPercent: 4) }
        #expect(flag(lowP) == nil && lowP.inputs.contains { $0.input == .aurora })
        // Kp 5 clears the bar at 52 N (threshold 5) but not at 40 N (threshold 7).
        let mid = makePlace(lat: 52, lon: 0)
        let byKp = Self.night(moonAltitude: -30, place: mid) { $0.aurora = AuroraOutlook(kp: [step]) }
        #expect(flag(byKp)?.1 == 5)
        let south = Self.night(moonAltitude: -30, place: Self.place) { $0.aurora = AuroraOutlook(kp: [step]) }
        #expect(flag(south) == nil)
        // The arctic: Kp 2 is enough.
        let arctic = Self.night(moonAltitude: -30, place: tromso) { $0.aurora = AuroraOutlook(kp: [.init(time: step.time, value: 2)]) }
        #expect(flag(arctic)?.1 == 2)
        // A Kp step that does not overlap the window is ignored.
        let early = AuroraOutlook.KpStep(time: FixedEphemeris.at(Self.july, 0), value: 9)
        #expect(flag(Self.night(moonAltitude: -30, place: mid) { $0.aurora = AuroraOutlook(kp: [early]) }) == nil)
        // It is a flag, not a score term.
        #expect(byP.value == lowP.value)
        #expect(ForecastSkyIndex.auroraKpThreshold(latitude: -67) == 2 && ForecastSkyIndex.auroraKpThreshold(latitude: 10) == 9)
    }

    @Test func noAuroraOutlookIsANoteOnlyAtHighLatitude() {
        let high = Self.night(moonAltitude: -30, place: makePlace(lat: 52, lon: 0))
        #expect(high.notes.contains(.missing(.aurora)) && high.confidenceCauses.contains(.missingSecondary(.aurora)))
        let low = Self.night(moonAltitude: -30, place: Self.place)
        #expect(!low.notes.contains(.missing(.aurora)))
        let southern = Self.night(moonAltitude: -30, place: makePlace(lat: -46, lon: 0))
        #expect(southern.notes.contains(.missing(.aurora)))
    }

    @Test func lightPollutionAndSeeingAreNotedWhenAbsentAndNeverDefaulted() {
        let s = sky(.night, Wx())
        #expect(s.notes.contains(.missing(.lightPollution)) && s.notes.contains(.missing(.seeing)))
        #expect(s.confidenceCauses.contains(.missingSecondary(.lightPollution)) && s.confidenceCauses.contains(.missingSecondary(.seeing)))
        #expect(points(s, .lightPollution) == nil && points(s, .seeing) == nil)
        // Only night asks.
        let golden = sky(.goldenEvening, Wx())
        #expect(!golden.notes.contains(.missing(.lightPollution)) && !golden.notes.contains(.missing(.seeing)))
    }

    @Test func aSuppliedBortleClassMovesTheNightScore() {
        func night(_ b: Double?) -> SkyScore { sky(.night, Wx()) { $0.bortle = b } }
        let none = night(nil), dark = night(1), suburban = night(6), city = night(9)
        #expect(points(dark, .lightPollution) == 6 && points(night(3), .lightPollution) == 3)
        #expect(points(suburban, .lightPollution) == -5 && points(city, .lightPollution) == -14)
        #expect(points(night(4), .lightPollution) == nil)
        #expect(dark.value == none.value + 6 && city.value == none.value - 14)
        #expect(!dark.notes.contains(.missing(.lightPollution)) && dark.inputs.contains { $0.input == .lightPollution })
        #expect(dark.confidenceValue > none.confidenceValue)
        #expect(none.notes.contains(.missing(.lightPollution)))
    }

    @Test func aSuppliedSeeingMovesTheNightScoreToo() {
        func night(_ s: Double?) -> SkyScore { sky(.night, Wx()) { $0.seeing = s } }
        #expect(points(night(1.2), .seeing) == 3 && points(night(5), .seeing) == -4 && points(night(2.5), .seeing) == nil)
        #expect(!night(1.2).notes.contains(.missing(.seeing)))
    }

    @Test func transparencyIsEstimatedFromAerosolHumidityAndHighCloud() throws {
        let clear = sky(.night, Wx(high: 0.0, aod: 0.02, rh: 40))
        let murky = sky(.night, Wx(high: 0.8, aod: 0.8, rh: 95))
        let t1 = try #require(clear.transparency), t2 = try #require(murky.transparency)
        #expect(t1 > 0.9 && t2 < 0.3 && t1 > t2)
        #expect(clear.notes.contains(.transparencyFromProxy))
        // No aerosol figure and no proxy; golden windows have none.
        let none = sky(.night, Wx(aod: nil))
        #expect(none.transparency == nil && !none.notes.contains(.transparencyFromProxy))
        #expect(sky(.goldenEvening, Wx()).transparency == nil)
    }
}

// MARK: Geometry additions

@Suite struct GeometryAdditionTests {
    @Test func aSpringForwardDayInDenverLandsInTheRightLocalHours() throws {
        let engine = LightEngine(ephemeris: Astronomy())
        let denver = makePlace("denver", lat: 39.74, lon: -104.99, zone: "America/Denver")
        let day = LocalDay(year: 2026, month: 3, day: 8)
        #expect(day.adding(days: 1).start(in: denver.timeZone).timeIntervalSince(day.start(in: denver.timeZone)) == 23 * 3600)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = denver.timeZone
        func minutes(_ d: Date) -> Int { let c = cal.dateComponents([.hour, .minute], from: d); return c.hour! * 60 + c.minute! }
        let sunrise = try #require(engine.sessionWindow(for: denver, kind: .goldenMorning, on: day)).start
        let sunset = try #require(engine.sessionWindow(for: denver, kind: .goldenEvening, on: day)).end
        // MDT: sunrise about 07:22, sunset about 18:59. Had the clock stayed on MST they would read 06:22 and 17:59.
        #expect((7 * 60 + 5...7 * 60 + 40).contains(minutes(sunrise)), "sunrise at \(minutes(sunrise))")
        #expect((18 * 60 + 40...19 * 60 + 15).contains(minutes(sunset)), "sunset at \(minutes(sunset))")
        let night = try #require(engine.sessionWindow(for: denver, kind: .night, on: day))
        #expect((19 * 60...21 * 60 + 30).contains(minutes(night.start)))
        #expect(LocalDay(night.start, in: denver.timeZone) == day)
    }

    @Test func sessionWindowMatchesWindowsAndIsNilWhenTheSunDoesNotMakeOne() {
        let engine = LightEngine(ephemeris: Astronomy())
        let tromso = makePlace("tromso", lat: 69.65, lon: 18.96, zone: "Europe/Oslo")
        let midsummer = LocalDay(year: 2026, month: 6, day: 21), midwinter = LocalDay(year: 2026, month: 12, day: 21)
        for kind in LightWindowKind.allCases {
            #expect(engine.sessionWindow(for: tromso, kind: kind, on: midwinter) == engine.windows(for: tromso, on: midwinter).first { $0.kind == kind }?.span)
        }
        #expect(engine.sessionWindow(for: tromso, kind: .blueEvening, on: midsummer) == nil)
        #expect(engine.sessionWindow(for: tromso, kind: .goldenEvening, on: midsummer) != nil)
        #expect(engine.sessionWindow(for: tromso, kind: .goldenEvening, on: midwinter) == nil)
        #expect(engine.sessionWindow(for: tromso, kind: .blueMorning, on: midwinter) != nil)
    }

    @Test func theModelSkyInputsConvenienceCarriesHourlyHorizonAndBortle() {
        let hours = [HourlyConditions(time: now0, cloudTotal: 0.2)]
        let model = SkyInputs(coordinate: Coordinate(latitude: 40, longitude: -110), hourly: HourlySeries(hours: hours), horizon: .flat, bortle: 3)
        let aurora = AuroraOutlook(probabilityPercent: 1)
        let f = ForecastSkyInputs(model, provenance: provenance(fetchedAt: now0), ttl: 600, aurora: aurora)
        #expect(f.hourly?.hours == hours && f.horizon == .flat && f.bortle == 3 && f.seeing == nil)
        #expect(f.ttl == 600 && f.aurora == aurora && f.spreadSeries.isEmpty && f.provenance?.fetchedAt == now0)
        #expect(ForecastSkyInputs().ttl == 3 * 3600)
    }

    @Test func scoresAndWindowsRoundTripThroughCodable() throws {
        let engine = LightEngine(ephemeris: FixedEphemeris())
        let inputs = uniform(Wx(aod: 0.2), fetchedAt: now0)
        let dl = engine.dayLight(for: makePlace(horizon: .flat), on: testDay, inputs: inputs, now: now0)
        let data = try JSONEncoder().encode(dl)
        #expect(try JSONDecoder().decode(DayLight.self, from: data) == dl)
    }
}
