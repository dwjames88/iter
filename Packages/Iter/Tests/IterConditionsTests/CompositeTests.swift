import Foundation
import Testing
import IterModel
import IterSources
import IterSky
@testable import IterConditions

@Suite("Composite forecast")
struct CompositeTests {
    private func state(_ d: SourceDescriptor, _ series: HourlySeries) -> CompositeInput {
        CompositeInput(descriptor: d, state: .fresh(Sourced(value: series, provenance: d.provenance(fetchedAt: t0, model: "M", issuedAt: t0, distanceKm: 2.1))))
    }

    @Test func eachFieldComesFromTheFirstSourceThatHasIt() {
        let first = TimeSpan(start: t0, end: t0.addingTimeInterval(3 * 3600))
        let all = TimeSpan(start: t0, end: t0.addingTimeInterval(6 * 3600))
        let noaa = state(noaaDescriptor, hourlySeries(clearRecipe, span: first))
        let met = state(metDescriptor, hourlySeries(metRecipe, span: all))
        let c = CompositeForecast.build([noaa, met], focus: first, smokeOnly: [], now: t0)!
        #expect(c.series.fieldSources[.cloudLow] == noaaDescriptor.id)
        #expect(c.series.fieldSources[.visibilityKm] == noaaDescriptor.id)
        // NOAA in this fake has no precipChance... it has; use a field only MET has: none. Check hours beyond NOAA come from MET.
        let late = c.series.hour(at: t0.addingTimeInterval(4 * 3600))
        #expect(late?.cloudLow == 0.2)
        #expect(late?.visibilityKm == nil)
        let cloud = c.fieldProvenance.first { $0.field == .cloudLow }
        #expect(cloud?.contributors == [noaaDescriptor.id, metDescriptor.id])
        #expect(cloud?.provenance.source == noaaDescriptor.id)
        #expect(c.comparison?.descriptor.id == metDescriptor.id)
        #expect(c.state.isFresh)
    }

    @Test func aFieldOnlyTheLesserSourceHasComesFromIt() {
        var noaaRecipe = clearRecipe
        noaaRecipe.precip = nil
        let span = TimeSpan(start: t0, end: t0.addingTimeInterval(3 * 3600))
        let c = CompositeForecast.build([state(noaaDescriptor, hourlySeries(noaaRecipe, span: span)),
                                         state(metDescriptor, hourlySeries(metRecipe, span: span))], focus: span, smokeOnly: [], now: t0)!
        #expect(c.series.fieldSources[.precipChance] == metDescriptor.id)
        #expect(c.series.fieldSources[.cloudTotal] == noaaDescriptor.id)
        #expect(c.fieldProvenance.first { $0.field == .precipChance }?.provenance.source == metDescriptor.id)
    }

    @Test func smokeOnlyOpticalDepthIsKeptApartFromAerosol() {
        let span = TimeSpan(start: t0, end: t0.addingTimeInterval(3 * 3600))
        let smoke = state(smokeDescriptor, hourlySeries(Recipe(smoke: 40, aod: 0.8), span: span))
        let met = state(metDescriptor, hourlySeries(metRecipe, span: span))
        let c = CompositeForecast.build([met, smoke], focus: span, smokeOnly: [.noaaHRRRSmoke], now: t0)!
        #expect(c.series.hours.allSatisfy { $0.aod550 == nil })
        #expect(c.series.fieldSources[.aod550] == nil)
        #expect(c.series.fieldSources[.smokeUgm3] == .noaaHRRRSmoke)
        #expect(c.smokeOpticalDepth?.values.count == 3)
        #expect(c.smokeOpticalDepth?.values.first?.value == 0.8)
    }

    @Test func aStaleSourceMakesTheCompositeStaleWithItsAge() {
        let span = TimeSpan(start: t0, end: t0.addingTimeInterval(3 * 3600))
        let met = CompositeInput(descriptor: metDescriptor, state: .stale(
            Sourced(value: hourlySeries(metRecipe, span: span), provenance: metDescriptor.provenance(fetchedAt: t0)), age: .seconds(7200)))
        let c = CompositeForecast.build([met], focus: span, smokeOnly: [], now: t0)!
        #expect(c.state.isStale)
        if case .stale(_, let age) = c.state { #expect(age == .seconds(7200)) }
    }

    @Test func nothingUsableGivesNoComposite() {
        let none = CompositeInput(descriptor: metDescriptor, state: .none([.offline(lastGood: nil)]))
        #expect(CompositeForecast.build([none], focus: TimeSpan(start: t0, end: t0), smokeOnly: [], now: t0) == nil)
    }
}
