import Testing
import IterCore
@testable import Iter

/// The legend lists exactly the engine's bands, worst to best, with the engine's score ranges.
@Suite struct ScoreLegendIOSTests {
    @Test func legendListsTheEnginesBandsInOrder() {
        let rows = ScoreLegend.bands
        #expect(rows.map(\.band) == LightBand.allCases)
        #expect(rows.map(\.band) == [.poor, .fair, .good, .great, .epic])
        for row in rows {
            #expect(row.range == row.band.scoreRange)
            #expect(LightBand(score: row.range.lowerBound) == row.band)
            #expect(LightBand(score: row.range.upperBound) == row.band)
        }
        // No gaps and no overlap between neighbours.
        for (a, b) in zip(rows, rows.dropFirst()) { #expect(a.range.upperBound + 1 == b.range.lowerBound) }
        #expect(rows.first?.range.lowerBound == 0 && rows.last?.range.upperBound == 100)
    }

    @Test func legendListsEveryWindowKind() {
        #expect(Set(ScoreLegend.windows) == Set(LightWindowKind.allCases))
        #expect(ScoreLegend.windows.count == LightWindowKind.allCases.count)
    }
}
