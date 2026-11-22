import Foundation
import IterModel
import IterSources
import Testing
@testable import IterDiscovery

/// A gazetteer whose answer and speed depend on the area: "Slowtown" answers late, anywhere else at once.
struct AreaAwareGazetteer: GazetteerProvider {
    var descriptor = IterDiscoveryTests.descriptor(osmID, "OpenStreetMap", kinds: [.gazetteer])
    var log = CallLog()
    func candidates(in area: DiscoveryArea, features: Set<FeatureKind>, limit: Int) async throws -> [PlaceCandidate] {
        let slow = area.name?.lowercased().contains("slow") == true
        log.record(slow ? "slow" : "fast")
        if slow {
            do { try await Task.sleep(for: .milliseconds(400)) } catch { log.noteCancelled(); throw SourceError.cancelled }
        }
        let c = area.region.center
        return [PlaceCandidate(name: slow ? "Slow Place" : "Fast Place", coordinate: c, featureKinds: [.viewpoint], source: osmID, externalID: slow ? "1" : "2",
                               citations: [citation(osmID, "x")])]
    }
}

@MainActor
@Suite("DiscoverySearch controller")
struct SearchControllerTests {
    func engine(_ g: AreaAwareGazetteer) -> DiscoveryEngine {
        let geo = FakeGeocoder(answers: [
            "slowtown": [GeocodeResult(name: "Slowtown", coordinate: Coordinate(latitude: 36, longitude: -118))],
            "fasttown": [GeocodeResult(name: "Fasttown", coordinate: Coordinate(latitude: 37, longitude: -119))],
        ])
        return DiscoveryEngine(providers: DiscoveryProviders(geocoders: [geo], gazetteers: [g]), model: nil,
                               clock: ManualSourceClock(now: testNow), configuration: fastConfig)
    }

    @Test func exposesPhaseAndResults() async {
        let search = DiscoverySearch(engine: engine(AreaAwareGazetteer()))
        #expect(search.phase == .idle)
        search.search(DiscoveryRequest(text: "viewpoints in Fasttown"))
        #expect(search.phase == .planning)
        #expect(await waitUntilMain { search.phase == .finished })
        #expect(search.places.map(\.name) == ["Fast Place"])
        #expect(search.plan?.features == [.viewpoint])
        #expect(search.planOrigin?.isBasic == true)
        #expect(search.basicSearchLabel == "Basic search: AI not set up")
        #expect(search.area?.basis == .box(radiusKm: 30, reason: "town"))
        #expect(search.statuses.contains { $0.source == FixedSources.reddit })
    }

    @Test func aSlowOldSearchCannotOverwriteANewerOne() async {
        let g = AreaAwareGazetteer()
        let search = DiscoverySearch(engine: engine(g))
        search.search(DiscoveryRequest(text: "viewpoints in Slowtown"))
        #expect(await waitUntilMain { g.log.calls == ["slow"] })
        let first = search.generation
        search.search(DiscoveryRequest(text: "viewpoints in Fasttown"))
        #expect(search.generation == first + 1)
        #expect(await waitUntilMain { search.phase == .finished })
        #expect(search.places.map(\.name) == ["Fast Place"])
        // Give the old run every chance to land late.
        try? await Task.sleep(for: .milliseconds(600))
        #expect(search.places.map(\.name) == ["Fast Place"])
        #expect(search.plan?.areaText == "Fasttown")
        #expect(g.log.cancelledCount == 1)            // and the old run was cancelled, not left running
    }

    @Test func cancelStopsTheRunAndIgnoresLateEvents() async {
        let g = AreaAwareGazetteer()
        let search = DiscoverySearch(engine: engine(g))
        search.search(DiscoveryRequest(text: "viewpoints in Slowtown"))
        #expect(await waitUntilMain { g.log.calls == ["slow"] })
        search.cancel()
        #expect(search.phase == .cancelled)
        try? await Task.sleep(for: .milliseconds(600))
        #expect(search.places.isEmpty && search.phase == .cancelled)
    }

    @Test func aRunThatCannotSearchEndsFailedWithAReadableReason() async {
        let search = DiscoverySearch(engine: engine(AreaAwareGazetteer()))
        search.search(DiscoveryRequest(text: "viewpoints near me"))
        #expect(await waitUntilMain { if case .failed = search.phase { true } else { false } })
        #expect(search.phase == .failed("Iter needs your location to search near you."))
        #expect(search.places.isEmpty)
    }
}
