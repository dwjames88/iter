import Foundation
import IterModel
import IterSources
import Testing
@testable import IterDiscovery

@Suite("Ranking")
struct RankingTests {
    let anchor = Geo.lonePine

    func context(plan: QueryPlan = QueryPlan(areaText: "Lone Pine", features: [.waterfall]), ordering: DiscoveryOrdering = .popular,
                 preference: String? = nil, library: [LibraryReference] = []) -> DiscoveryRanker.Context {
        DiscoveryRanker.Context(plan: plan, ordering: ordering, preferenceText: preference, library: library, anchor: anchor, anchorIsUser: true)
    }

    func scored(_ c: PlaceCandidate, photos: Int = 0) -> DiscoveryRanker.Scored {
        DiscoveryRanker.Scored(candidate: verified([c])[0], photoCount: photos, photos: [])
    }

    /// A famous place (Wikipedia, many photos, mentions) and an obscure one.
    var famous: PlaceCandidate { candidate("Famous Falls", 36.61, -118.06, kinds: [.waterfall], source: wikiID, externalID: "1", mentions: 10) }
    var obscure: PlaceCandidate { candidate("Quiet Falls", 36.62, -118.07, kinds: [.waterfall], source: mapkitSearchID, externalID: "2") }

    @Test func popularPutsTheFamousFirstUniquePutsTheObscureFirst() {
        let items = [scored(obscure, photos: 0), scored(famous, photos: 60)]
        #expect(DiscoveryRanker.rank(items, context: context(ordering: .popular)).map(\.name) == ["Famous Falls", "Quiet Falls"])
        #expect(DiscoveryRanker.rank(items, context: context(ordering: .unique)).map(\.name) == ["Quiet Falls", "Famous Falls"])
        let mixed = DiscoveryRanker.rank(items, context: context(ordering: .mixed))
        #expect(Set(mixed.map(\.name)) == ["Famous Falls", "Quiet Falls"])
    }

    @Test func featureMatchPartIsVisible() {
        let waterfall = scored(famous)
        let lake = scored(candidate("Some Lake", 36.6, -118.0, kinds: [.lake], source: osmID, externalID: "9"))
        let unknown = scored(candidate("Mystery", 36.6, -118.0, kinds: [], source: mapkitSearchID))
        let ranked = DiscoveryRanker.rank([lake, unknown, waterfall], context: context())
        #expect(ranked[0].name == "Famous Falls")
        #expect(ranked[0].rank.featureMatch.value! > ranked[1].rank.featureMatch.value!)
        #expect(ranked[1].name == "Mystery")                                   // unknown kind scores above a known mismatch
        #expect(ranked[2].rank.featureMatch.value! < 0.3)
        #expect(!ranked[0].rank.featureMatch.note.isEmpty)
    }

    @Test func evidencePartCountsPhotosMentionsWikiAndAgreement() {
        let bare = DiscoveryRanker.evidence(scored(obscure))
        let rich = DiscoveryRanker.evidence(scored(famous, photos: 50))
        #expect(bare.value! < rich.value!)
        #expect(rich.note.contains("50 geotagged photos") && rich.note.contains("on Wikipedia") && rich.note.contains("10 mentions"))
    }

    @Test func ownersPreferenceTextBoostsMatchingPlacesWithoutTheModel() {
        let lake = scored(candidate("Alpine Lake", 36.6, -118.0, kinds: [.lake], source: osmID, externalID: "1"))
        let falls = scored(candidate("Cold Falls", 36.6, -118.0, kinds: [.waterfall], source: osmID, externalID: "2"))
        let plan = QueryPlan(areaText: "x")   // no feature request, so only the preference separates them
        let liked = DiscoveryRanker.rank([falls, lake], context: context(plan: plan, preference: "I love shooting lakes and reflections"))
        #expect(liked.first?.name == "Alpine Lake")
        #expect(liked[0].rank.preference.value! > liked[1].rank.preference.value!)
        #expect(liked[0].rank.preference.note.contains("lake"))
        // Words in the snippet or name count too.
        let snip = scored(candidate("Plain Spot", 36.6, -118.0, kinds: [], source: osmID, externalID: "3", snippet: "Known for reflections at dawn."))
        #expect(DiscoveryRanker.preference(snip.candidate, text: "reflections").value! > 0)
        // No text: the part says so and has no value.
        #expect(DiscoveryRanker.preference(snip.candidate, text: nil).value == nil)
        #expect(DiscoveryRanker.preference(snip.candidate, text: "   ").value == nil)
        let (kinds, words) = DiscoveryRanker.preferenceTerms("Hot springs, waterfalls and moody mountains")
        #expect(kinds == [.hotSpring, .waterfall, .peak])
        #expect(words.contains("moody"))
    }

    @Test func lightSuitIsNilAndSaysSoWhenNoFacingIsKnown() {
        let p = DiscoveryRanker.place(from: scored(famous), context: context())
        #expect(p.rank.lightSuit.value == nil)
        #expect(p.rank.lightSuit.note.contains("No facing"))
    }

    @Test func reachabilityFallsWithDistance() {
        let near = DiscoveryRanker.reachability(distanceKm: 5, anchorIsUser: true)
        let far = DiscoveryRanker.reachability(distanceKm: 200, anchorIsUser: true)
        #expect(near.value! > far.value!)
        #expect(far.note.contains("200 km") && far.note.contains("you"))
        #expect(DiscoveryRanker.reachability(distanceKm: 3, anchorIsUser: false).note.contains("area"))
    }

    @Test func noveltyAgainstTheLibrary() {
        let c = verified([candidate("Mobius Arch", 36.61, -118.12, kinds: [.arch], source: osmID, externalID: "1")])[0]
        #expect(DiscoveryRanker.novelty(c, library: []).value == nil)
        #expect(DiscoveryRanker.novelty(c, library: [LibraryReference(name: "Mobius Arch")]).value == 0)                                    // same name
        #expect(DiscoveryRanker.novelty(c, library: [LibraryReference(name: "Elsewhere", coordinate: c.coordinate.value)]).value == 0)       // same spot
        let close = LibraryReference(name: "Near Rock", coordinate: Coordinate(latitude: 36.62, longitude: -118.12), featureKinds: [.peak])  // ~1.1 km
        #expect(DiscoveryRanker.novelty(c, library: [close]).value == 0.6)
        let far = LibraryReference(name: "Far Peak", coordinate: Coordinate(latitude: 38, longitude: -118), featureKinds: [.peak])
        #expect(DiscoveryRanker.novelty(c, library: [far]).value == 1)
        let sameKind = LibraryReference(name: "Far Arch", coordinate: Coordinate(latitude: 38, longitude: -118), featureKinds: [.arch])
        #expect(DiscoveryRanker.novelty(c, library: [sameKind]).value == 0.85)
        // An already-saved place sinks under .unique.
        let saved = scored(famous), fresh = scored(obscure)
        let unique = DiscoveryRanker.rank([fresh, saved], context: context(ordering: .unique, library: [LibraryReference(name: "Famous Falls")]))
        #expect(unique.first?.name == "Quiet Falls")
    }

    @Test func rankingIsDeterministicWhateverTheInputOrder() {
        let items = (0..<8).map { scored(candidate("Place \($0)", 36.6 + Double($0) * 0.01, -118.1, kinds: [.waterfall], source: osmID, externalID: "\($0)")) }
        let reference = DiscoveryRanker.rank(items, context: context()).map(\.id)
        for _ in 0..<10 { #expect(DiscoveryRanker.rank(items.shuffled(), context: context()).map(\.id) == reference) }
    }

    @Test func missingPartsAreLeftOutOfTheScoreNotCountedAsZero() {
        let part = RankPart(value: nil, note: "n")
        let all = RankBreakdown(featureMatch: RankPart(value: 1, note: ""), evidence: part, preference: part, lightSuit: part, reachability: part, novelty: part)
        #expect(all.score(for: .popular) == 1)
        let none = RankBreakdown(featureMatch: part, evidence: part, preference: part, lightSuit: part, reachability: part, novelty: part)
        #expect(none.score(for: .mixed) == 0)
    }
}

@Suite("Explainer")
struct ExplainerTests {
    let plan = QueryPlan(areaText: "Yosemite", features: [.waterfall])

    func place() -> DiscoveredPlace {
        let c = verified([candidate("Vernal Fall", 36.61, -118.06, kinds: [.waterfall], source: osmID, externalID: "1", mentions: 3)])[0]
        return DiscoveryRanker.place(from: DiscoveryRanker.Scored(candidate: c, photoCount: 12, photos: []),
                                     context: DiscoveryRanker.Context(plan: plan, ordering: .mixed, preferenceText: nil, library: [], anchor: Geo.lonePine, anchorIsUser: false))
    }

    func explainer(_ model: FakeModel?) -> PlaceExplainer {
        PlaceExplainer(model: model, timeout: .seconds(1), sourceNames: [osmID: "OpenStreetMap"], areaName: "Yosemite", plan: plan)
    }

    @Test func numberGroundingCheck() {
        let facts = "Geotagged photos nearby: 12\nDistance: 14 km"
        #expect(PlaceExplainer.numbersAreGrounded(output: "Has 12 geotagged photos nearby.", facts: facts))
        #expect(!PlaceExplainer.numbersAreGrounded(output: "Has 120 photos nearby.", facts: facts))
        #expect(!PlaceExplainer.numbersAreGrounded(output: "Sits at 37.7, -119.6.", facts: facts))
        #expect(PlaceExplainer.numbersAreGrounded(output: "No numbers here.", facts: facts))
    }

    @Test func nameGroundingCheck() {
        let facts = "Name: Vernal Fall\nArea: Yosemite\nSources: OpenStreetMap"
        #expect(PlaceExplainer.namesAreGrounded(output: "Vernal Fall in Yosemite is a waterfall.", facts: facts))
        #expect(PlaceExplainer.namesAreGrounded(output: "A waterfall near Yosemite. It is mapped by OpenStreetMap.", facts: facts))
        #expect(!PlaceExplainer.namesAreGrounded(output: "A waterfall near Glacier Point.", facts: facts))
        #expect(!PlaceExplainer.namesAreGrounded(output: "A waterfall like Bridalveil.", facts: facts))
    }

    @Test func groundedModelLineIsUsed() async {
        let model = FakeModel()
        model.set { $0.respond = { _ in "A waterfall in Yosemite with 12 geotagged photos nearby." } }
        let why = await explainer(model).explain(place())
        #expect(why.isModelWritten)
        #expect(why.text == "A waterfall in Yosemite with 12 geotagged photos nearby.")
        // It was built from the place's facts only.
        let prompt = model.prompts.first ?? ""
        #expect(prompt.contains("Name: Vernal Fall") && prompt.contains("Geotagged photos nearby: 12"))
        #expect(!prompt.contains("36.61") && !prompt.contains("-118.06"))
    }

    @Test func ungroundedLinesFallBackToTheTemplate() async {
        let model = FakeModel()
        for bad in ["A waterfall with 99 photos nearby.", "Better than Bridalveil Fall in Yosemite.", "", "Line one.\nLine two."] {
            model.set { [bad] in $0.respond = { _ in bad } }
            let why = await explainer(model).explain(place())
            #expect(!why.isModelWritten, "\(bad)")
            #expect(why.text.contains("Waterfall in Yosemite"))
            #expect(why.text.contains("12 geotagged photos nearby"))
        }
        let none = await explainer(nil).explain(place())
        #expect(!none.isModelWritten && !none.text.isEmpty)
    }
}
