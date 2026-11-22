import Foundation
import Testing
import IterModel
import IterSources
@testable import IterSourcesLive

@Suite("NoSource slots")
struct NoSourceTests {
    let place = Coordinate(latitude: 36.5785, longitude: -118.2923)

    @Test func skyBrightnessAlwaysThrowsNoSource() async {
        let provider = NoSkyBrightnessProvider()
        await #expect(throws: SourceError.noSource) { try await provider.skyBrightness(at: place) }
        await #expect(throws: SourceError.noSource) { try await provider.skyBrightness(at: Coordinate(latitude: 0, longitude: 0)) }
        #expect(provider.descriptor.id == .noSkyBrightness)
        #expect(SourceError.noSource.noDataReason(source: provider.descriptor.id) == .notProvidedBySource)
    }

    @Test func seeingAlwaysThrowsNoSource() async {
        let provider = NoSeeingProvider()
        let span = TimeSpan(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 3600))
        await #expect(throws: SourceError.noSource) { try await provider.seeing(at: place, span: span) }
        #expect(provider.descriptor.id == .noSeeing)
        #expect(SourceError.noSource.noDataReason(source: provider.descriptor.id) == .notProvidedBySource)
    }
}
