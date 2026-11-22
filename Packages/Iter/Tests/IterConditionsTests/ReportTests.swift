import Foundation
import Testing
import IterModel
import IterSources
import IterSky
@testable import IterConditions

@Suite("Reports")
struct ReportTests {
    @Test func theBetterTierWinsEachFieldEvenWhenALesserTierRanksHigher() async {
        let clock = ManualSourceClock(now: t0)
        let user = makeDescriptor("test.user", name: "User key", tier: .userKey, kinds: [.forecast], ranks: [.forecast: 1])
        let env = makeEnv([FakeForecast(user, clock: clock, recipe: Recipe(cloudTotal: 0.9)),
                           FakeForecast(metDescriptor, clock: clock, recipe: metRecipe)], clock: clock)
        let place = makePlace()
        let r = await env.service.report(for: place, day: localDay(of: place), waitFor: .complete)
        #expect(r.forecast.value?.fieldSources[.cloudTotal] == metDescriptor.id)
        #expect(r.provenance(of: .cloudTotal)?.source == metDescriptor.id)
        #expect(r.tier == .complete)
        #expect(r.loading.isEmpty)
    }

    @Test func aUSOnlySourceDropsOutAtASwissPointAndTheGapIsNamed() async {
        let clock = ManualSourceClock(now: t0)
        let env = makeEnv([FakeForecast(noaaDescriptor, clock: clock, recipe: clearRecipe),
                           FakeForecast(metDescriptor, clock: clock, recipe: metRecipe), FakeNoSource()], clock: clock)
        let place = swissPlace()
        let r = await env.service.report(for: place, day: localDay(of: place), waitFor: .complete)
        #expect(r.forecast.value?.fieldSources[.cloudTotal] == metDescriptor.id)
        #expect(r.forecast.value?.fieldSources.values.contains(noaaDescriptor.id) == false)
        // MET has no visibility; the only source that does covers the US, so the gap says so.
        #expect(r.gap(.field(.visibilityKm))?.reasons == [.outsideCoverage])
        #expect(r.gap(.lightPollution)?.reasons == [.notProvidedBySource])
        #expect(r.gap(.seeing)?.reasons == [.notProvidedBySource])
        #expect(r.bortle == nil && r.seeing == nil)
        #expect(r.forecastInputs.bortle == nil && r.forecastInputs.seeing == nil)
    }

    @Test func outOfCoverageEverywhereIsNoDataNotANumber() async {
        let clock = ManualSourceClock(now: t0)
        let env = makeEnv([FakeForecast(noaaDescriptor, clock: clock, recipe: clearRecipe)], clock: clock)
        let place = swissPlace()
        let r = await env.service.report(for: place, day: localDay(of: place), waitFor: .complete)
        #expect(r.forecast.reasons == [.outsideCoverage])
        #expect(r.gap(.forecast)?.reasons == [.outsideCoverage])
        #expect(r.daylight.windows.allSatisfy { $0.score == nil })
    }

    @Test func quickThenRefinedChangesTheCloudSourceHonestly() async {
        let clock = ManualSourceClock(now: t0)
        let gate = HoldGate()
        let met = FakeForecast(metDescriptor, clock: clock, recipe: metRecipe)
        let noaa = FakeForecast(noaaDescriptor, clock: clock, recipe: clearRecipe, gate: gate)
        let env = makeEnv([noaa, met], clock: clock)
        let place = makePlace()
        var events: [SkyReport] = []
        for await r in env.service.reports(for: [ConditionsRequest(place: place, day: localDay(of: place))]) {
            events.append(r)
            if events.count == 1 { gate.open() }
        }
        let first = try! #require(events.first)
        let last = try! #require(events.last)
        #expect(first.tier == .quick)
        #expect(first.provenance(of: .cloudLow)?.source == metDescriptor.id)
        #expect(first.provenanceLines.first { $0.label == "Cloud layers" }?.text.contains("MET Norway") == true)
        #expect(first.loading.contains(.forecast(noaaDescriptor.id)))
        #expect(first.comparison == nil)
        #expect(last.tier == .complete)
        #expect(last.provenance(of: .cloudLow)?.source == noaaDescriptor.id)
        let line = last.provenanceLines.first { $0.label == "Cloud layers" }?.text ?? ""
        #expect(line.contains("NOAA HRRR") && !line.contains("MET Norway"))
        #expect(last.provenanceLines.contains { $0.label == "Compared with" && $0.text == "MET Norway" })
        #expect(last.comparison?.source == metDescriptor.id)
        #expect(last.forecastInputs.spreadSeries.count == 1)
        #expect(last.attributionKeys.contains(LicenceKey.noaaNCEP) && last.attributionKeys.contains(LicenceKey.metNorway))
        #expect(last.attributions.count == 2)
    }

    @Test func disagreeingSourcesLowerConfidenceThroughTheSpreadSeries() async {
        let clock = ManualSourceClock(now: t0)
        let env = makeEnv([FakeForecast(noaaDescriptor, clock: clock, recipe: clearRecipe),
                           FakeForecast(metDescriptor, clock: clock, recipe: metRecipe)], clock: clock)
        let place = makePlace()
        let r = await env.service.report(for: place, day: localDay(of: place), waitFor: .complete)
        let scored = r.daylight.windows.compactMap { $0.assessment.skyScore }
        #expect(!scored.isEmpty)
        #expect(scored.contains { $0.confidenceCauses.contains(.sourceSpread) })
        #expect((r.comparison?.maxCloudDifference ?? 0) > 0.3)
    }

    @Test func hrrrOpticalDepthIsShownAsSmokeAndNeverScoredAsAerosol() async {
        let clock = ManualSourceClock(now: t0)
        let env = makeEnv([FakeForecast(metDescriptor, clock: clock, recipe: metRecipe),
                           FakeForecast(smokeDescriptor, clock: clock, recipe: Recipe(smoke: 40, aod: 0.8))], clock: clock)
        let place = makePlace()
        let r = await env.service.report(for: place, day: localDay(of: place), waitFor: .complete)
        #expect(r.forecast.value?.hours.allSatisfy { $0.aod550 == nil } == true)
        #expect(r.forecastInputs.hourly?.hours.allSatisfy { $0.aod550 == nil } == true)
        #expect(r.smoke.opticalDepth?.values.first?.value == 0.8)
        #expect(r.smoke.nearSurfaceMaxUgm3 == 40)
        #expect(r.smoke.nearSurfaceSource == .noaaHRRRSmoke)
        let used = r.daylight.windows.compactMap { $0.assessment.skyScore }.flatMap(\.inputs).map(\.input)
        #expect(used.contains(.smoke))
        #expect(!used.contains(.aerosol))
        #expect(r.provenanceLines.contains { $0.label == "Smoke" && $0.text.contains("HRRR smoke") })
        #expect(r.provenanceLines.contains { $0.label == "Smoke optical depth" })
        #expect(!r.provenanceLines.contains { $0.label.contains("Aerosol") })
    }

    @Test func provenanceLineNamesSourceRunAndGridPoint() async {
        let clock = ManualSourceClock(now: t0)
        let env = makeEnv([FakeForecast(noaaDescriptor, clock: clock, recipe: clearRecipe)], clock: clock)
        let place = makePlace()
        let r = await env.service.report(for: place, day: localDay(of: place), waitFor: .complete)
        let line = r.provenanceLines.first { $0.label == "Cloud layers" }?.line
        #expect(line == "Cloud layers: NOAA HRRR, run 12Z, 2.1 km grid point")
    }

    @Test func aPastDayHasNoForecastAndNothingIsFetched() async {
        let clock = ManualSourceClock(now: t0)
        let met = FakeForecast(metDescriptor, clock: clock, recipe: metRecipe)
        let env = makeEnv([met], clock: clock)
        let place = makePlace()
        let r = await env.service.report(for: place, day: localDay(of: place).adding(days: -2), waitFor: .complete)
        #expect(met.callCount == 0)
        #expect(r.forecast.value == nil)
        #expect(r.tier == .complete)
    }

    @Test func horizonIsUsedByTheReportWhenAProviderExists() async {
        let clock = ManualSourceClock(now: t0)
        let terrain = FakeTerrain(clock: clock)
        let env = makeEnv([FakeForecast(metDescriptor, clock: clock, recipe: metRecipe), terrain], clock: clock)
        let place = makePlace()
        let r = await env.service.report(for: place, day: localDay(of: place), waitFor: .complete)
        #expect(r.horizon.value != nil)
        #expect(r.forecastInputs.horizon != nil)
        #expect(terrain.fetches.value == 1)
    }
}
