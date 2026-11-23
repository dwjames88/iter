import Foundation
import IterModel
import IterSources
import Testing
@testable import IterDiscovery

@Suite("Learn From My Library")
struct LibraryProfileTests {
    func place(_ name: String, _ category: PlaceCategory, tags: [String] = [], pinned: Bool = false) -> Place {
        Place(name: name, coordinate: Coordinate(latitude: 36, longitude: -118), timeZoneIdentifier: "America/Los_Angeles",
              category: category, tags: tags, origin: .user, isSaved: true, isPinned: pinned)
    }

    /// Four waterfall-ish saves, one arch, a pinned viewpoint.
    var fixture: [Place] {
        [place("Hidden Falls", .waterfall), place("Mist Cascade", .waterfall), place("Rainbow Falls", .landscape),
         place("Mobius Arch", .desert), place("Quiet Overlook", .landscape, tags: ["overlook"], pinned: true)]
    }

    @Test func profileCountsKindsFromNamesTagsAndCategories() {
        let profile = LibraryProfile(savedPlaces: fixture, trips: [])
        #expect(!profile.isEmpty)
        #expect(profile.kindWeights[.waterfall] == 1)                       // the strongest kind is 1
        #expect(profile.kindWeights.values.allSatisfy { $0 > 0 && $0 <= 1 })
        #expect(profile.kindWeights[.arch]! > 0 && profile.kindWeights[.arch]! < 1)
        #expect(profile.kindWeights[.viewpoint]! > profile.kindWeights[.lighthouse] ?? 0)
        #expect(profile.kindWeights[.castle] == nil)
        #expect(profile.affinity(for: [.waterfall, .lake]) == 1)
        #expect(profile.affinity(for: [.castle]) == 0)
        #expect(profile.affinity(for: []) == 0)
    }

    @Test func tripStopsCountAsPlanning() {
        let stop = Stop(place: place("Hidden Falls", .waterfall), dayIndex: 0, session: .goldenMorning)
        let trip = Trip(name: "T", startDay: LocalDay(year: 2026, month: 5, day: 1), dayCount: 1, stops: [stop, stop, stop])
        let a = LibraryProfile(savedPlaces: [place("Old Arch", .desert), place("Other Arch", .desert), place("Bay Bridge", .architecture)], trips: [])
        let b = LibraryProfile(savedPlaces: [place("Old Arch", .desert), place("Other Arch", .desert), place("Bay Bridge", .architecture)], trips: [trip])
        #expect(a.kindWeights[.waterfall] == nil)
        #expect(b.kindWeights[.waterfall] == 1)
    }

    @Test func tooSmallALibraryLearnsNothing() {
        #expect(LibraryProfile(savedPlaces: Array(fixture.prefix(2)), trips: []).isEmpty)
        #expect(LibraryProfile(savedPlaces: [], trips: []).isEmpty)
        // Places of no mapped kind teach nothing either.
        #expect(LibraryProfile(savedPlaces: (0..<5).map { place("Spot \($0)", .street) }, trips: []).isEmpty)
    }

    // MARK: Ranking

    let anchor = Geo.lonePine
    func context(profile: LibraryProfile?) -> DiscoveryRanker.Context {
        DiscoveryRanker.Context(plan: QueryPlan(areaText: "x"), ordering: .popular, preferenceText: nil, library: [], anchor: anchor,
                                anchorIsUser: true, profile: profile)
    }
    func scored(_ name: String, kinds: [FeatureKind], photos: Int = 0, id: String) -> DiscoveryRanker.Scored {
        let c = candidate(name, 36.61, -118.06, kinds: kinds, source: osmID, externalID: id)
        return DiscoveryRanker.Scored(candidate: verified([c])[0], photoCount: photos, photos: [])
    }

    @Test func boostIsBoundedAndOnlyForMatchingKinds() {
        let profile = LibraryProfile(savedPlaces: fixture, trips: [])
        let falls = scored("Plain Falls", kinds: [.waterfall], id: "1")
        let castle = scored("Plain Castle", kinds: [.castle], id: "2")
        let off = DiscoveryRanker.rank([falls, castle], context: context(profile: nil))
        let on = DiscoveryRanker.rank([falls, castle], context: context(profile: profile))
        for ordering in DiscoveryOrdering.allCases {
            for p in on {
                let base = off.first { $0.name == p.name }!.rank.score(for: ordering)
                let boosted = p.rank.score(for: ordering)
                #expect(boosted >= base)
                #expect(boosted <= min(1, base * (1 + LibraryProfile.maximumBoost)) + 1e-12)
            }
        }
        let fallsOn = on.first { $0.name == "Plain Falls" }!, castleOn = on.first { $0.name == "Plain Castle" }!
        #expect(fallsOn.rank.libraryAffinity == 1)
        #expect(castleOn.rank.libraryAffinity == 0)
        #expect(castleOn.rank.score(for: .popular) == off.first { $0.name == "Plain Castle" }!.rank.score(for: .popular))
    }

    @Test func boostCanReorderCloseCallsButNotBeyondItsBound() {
        let profile = LibraryProfile(savedPlaces: fixture, trips: [])
        // Same evidence: the matching kind wins when the owner saves it.
        let items = [scored("A Castle", kinds: [.castle], id: "1"), scored("B Falls", kinds: [.waterfall], id: "2")]
        #expect(DiscoveryRanker.rank(items, context: context(profile: nil)).map(\.name) == ["A Castle", "B Falls"])      // by name
        #expect(DiscoveryRanker.rank(items, context: context(profile: profile)).map(\.name) == ["B Falls", "A Castle"])
        // A much better-evidenced place is not overtaken by a 12% nudge.
        let famous = scored("Z Castle", kinds: [.castle], photos: 60, id: "3")
        #expect(DiscoveryRanker.rank(items + [famous], context: context(profile: profile)).first?.name == "Z Castle")
    }

    @Test func noProfileEmptyProfileAndAnEngineWithoutOneAreIdentical() async {
        let items = [scored("A Castle", kinds: [.castle], id: "1"), scored("B Falls", kinds: [.waterfall], photos: 9, id: "2"),
                     scored("C Lake", kinds: [.lake], photos: 3, id: "3")]
        let none = DiscoveryRanker.rank(items, context: context(profile: nil))
        let empty = DiscoveryRanker.rank(items, context: context(profile: LibraryProfile(kindWeights: [:])))
        #expect(none == empty)
        for ordering in DiscoveryOrdering.allCases {
            #expect(zip(none, empty).allSatisfy { $0.rank.score(for: ordering).bitPattern == $1.rank.score(for: ordering).bitPattern })
        }
        // Whole engine.
        let s = LonePineScenario()
        let request = DiscoveryRequest(text: LonePineScenario.query)
        let plain = await s.engine(model: nil).discover(request)
        let emptyEngine = await s.engine(model: nil).with(libraryProfile: LibraryProfile(kindWeights: [:])).discover(request)
        #expect(plain.places.map(\.id) == emptyEngine.places.map(\.id))
        #expect(plain.places.map { $0.rank.score(for: .mixed) } == emptyEngine.places.map { $0.rank.score(for: .mixed) })
    }

    @Test func theProfileNeverReachesAProviderOrTheModel() async {
        let profile = LibraryProfile(savedPlaces: fixture + [place("Secret Cabin Hideout", .waterfall, tags: ["private-note"])], trips: [])
        func run(_ profile: LibraryProfile?) async -> (calls: [String], prompts: [String], places: [String]) {
            let s = LonePineScenario()
            let model = s.model()
            let result = await s.engine(model: model).with(libraryProfile: profile).discover(DiscoveryRequest(text: LonePineScenario.query))
            let calls = [s.geocoder.log, s.osm.log, s.poi.log, s.search.log, s.wikipedia.log, s.photos.log].flatMap(\.calls)
            return (calls, model.prompts, result.places.map(\.name))
        }
        let without = await run(nil), with = await run(profile)
        #expect(!with.calls.isEmpty && !with.prompts.isEmpty)
        #expect(with.calls == without.calls)                 // identical provider requests
        #expect(with.prompts == without.prompts)             // identical model prompts
        let everything = (with.calls + with.prompts).joined(separator: "\n").lowercased()
        #expect(!everything.contains("secret") && !everything.contains("private-note") && !everything.contains("hidden falls"))
        #expect(Set(with.places) == Set(without.places))
    }
}
