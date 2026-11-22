import Foundation
import IterCore
import Testing
@testable import IterServices

/// More edges of the hard rule: only registry IDs come back, and everything shown comes from the registry.
@Suite("Scout grounding edges")
struct ScoutGroundingEdgeTests {
    @Test func emptyAndWhitespaceIDsAreDropped() async {
        let r = ScoutRegistry()
        _ = await r.register(Fixture.silverFalls)
        let picks = ["", "   ", "\n", "m", "m0", "c:", "c:nope"].map { ResolvedPickInput(placeID: $0, why: "x", window: .any) }
        #expect(ScoutGrounding.resolve(picks: picks, registry: await r.snapshot()).isEmpty)
    }

    @Test func emptyRegistryYieldsNothing() {
        let picks = [ResolvedPickInput(placeID: "m1", why: "x", window: .any)]
        #expect(ScoutGrounding.resolve(picks: picks, registry: [:]).isEmpty)
    }

    @Test func curatedIDsMatchWhateverTheModelDoesToTheCase() async {
        let r = ScoutRegistry()
        let cur = await r.registerCurated(Fixture.curatedSpot)
        for variant in [cur.id.uppercased(), " " + cur.id + " ", cur.id.capitalized] {
            let out = ScoutGrounding.resolve(picks: [.init(placeID: variant, why: "x", window: .any)], registry: await r.snapshot())
            #expect(out.map(\.spot) == [Fixture.curatedSpot], "variant \(variant)")
        }
    }

    @Test func aMapIDCannotReachAnotherRunsPlaces() async {
        // Registries are per run: an ID from one run means nothing in another.
        let a = ScoutRegistry(), b = ScoutRegistry()
        let placeA = await a.register(Fixture.silverFalls)
        let out = ScoutGrounding.resolve(picks: [.init(placeID: placeA.id, why: "x", window: .any)], registry: await b.snapshot())
        #expect(out.isEmpty)
    }

    @Test func reasonsAreTrimmedAndCapped() async {
        let r = ScoutRegistry()
        let place = await r.register(Fixture.silverFalls)
        let long = "  " + String(repeating: "a", count: 1000) + "  "
        let out = ScoutGrounding.resolve(picks: [.init(placeID: place.id, why: long, window: .any)], registry: await r.snapshot())
        #expect(out[0].why.count == ScoutGrounding.maximumReasonLength)
        #expect(!out[0].why.hasPrefix(" "))
    }

    @Test func manyPlacesOnlyProduceTheCap() async {
        let r = ScoutRegistry()
        var ids: [String] = []
        for i in 0..<20 {
            var result = Fixture.silverFalls
            result.id = "apple-extra-\(i)"
            ids.append(await r.register(result).id)
        }
        let picks = ids.map { ResolvedPickInput(placeID: $0, why: "x", window: .any) }
        #expect(ScoutGrounding.resolve(picks: picks, registry: await r.snapshot()).count == ScoutGrounding.maximumSuggestions)
    }
}
