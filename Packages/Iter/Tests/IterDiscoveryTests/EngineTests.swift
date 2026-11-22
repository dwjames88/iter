import Foundation
import IterAI
import IterModel
import IterSources
import Testing
@testable import IterDiscovery

@Suite("Discovery engine, end to end")
struct EngineTests {
    // MARK: Lone Pine

    @Test func lonePineWithTheModel() async {
        let s = LonePineScenario()
        let model = s.model()
        let result = await s.engine(model: model).discover(DiscoveryRequest(text: LonePineScenario.query))

        #expect(result.planOrigin == .ai)
        #expect(result.plan.features == [.viewpoint])
        #expect(result.plan.areaText == "Lone Pine, California")
        #expect(result.failure == nil)
        let byName = Dictionary(uniqueKeysWithValues: result.places.map { ($0.name, $0) })
        #expect(byName["Whitney Portal Overlook"] != nil)
        #expect(byName["Scenic Lookout"] != nil)
        #expect(byName["Lone Pine Peak Viewpoint"] != nil)                       // a geotagged Wikipedia article about a viewpoint
        #expect(byName["Mobius Arch Overlook"] != nil)                          // named in text, located by the geocoder
        #expect(byName["Far Away View"] == nil)                                 // outside the area
        #expect(byName["Phantom Vista"] == nil)                                 // the model's name is not in its document
        #expect(!result.places.contains { $0.name.contains("Hidden Falls") })   // text coordinates are not places
        // Merge: OSM and MapKit agree on Alabama Hills Viewpoint, and the more precise OSM coordinate wins.
        let alabama = byName["Alabama Hills Viewpoint"]
        #expect(alabama?.sources.count == 2)
        #expect(alabama?.verification == .confirmed)
        #expect(alabama?.coordinate.source == osmID)
        #expect(alabama?.coordinate.value == s.osm.places[1].coordinate)
        #expect(byName["Mobius Arch Overlook"]?.coordinate.basis == .geocodedName)
        #expect(byName["Mobius Arch Overlook"]?.verification == .confirmed)
        #expect(byName["Scenic Lookout"]?.verification == .singleSource)
        // Photos only for the top N; counts landed.
        #expect(byName["Whitney Portal Overlook"]?.photoCount == 20)
        // Explanations and citations on every result.
        #expect(result.places.allSatisfy { $0.why != nil && !($0.why?.text.isEmpty ?? true) })
        #expect(byName["Whitney Portal Overlook"]?.why?.isModelWritten == true)
        #expect(result.places.allSatisfy { !$0.citations.isEmpty })
        #expect(result.places.allSatisfy { $0.citations.allSatisfy { $0.retrievedAt == testNow } })
        // The grounding invariant.
        assertGrounded(result.places, supplied: s.supplied)
        // The model never saw a coordinate.
        for p in model.prompts { #expect(!p.contains("36.59") && !p.contains("-118.12")) }
    }

    @Test func lonePineWithoutAppleIntelligence() async {
        let s = LonePineScenario()
        let model = s.model(available: false)
        let result = await s.engine(model: model).discover(DiscoveryRequest(text: LonePineScenario.query))

        #expect(result.planOrigin == .basic(reason: .appleIntelligenceNotEnabled))
        #expect(result.planOrigin.label == "Basic search: AI unavailable (Apple Intelligence is turned off)")
        #expect(result.plan.features == [.viewpoint] && result.plan.areaText == "Lone Pine, California")
        let ai = result.statuses.first { $0.source == FixedSources.ai }
        #expect(ai?.state == .unavailable("Basic search: AI unavailable (Apple Intelligence is turned off)"))
        // Structured results still come back, and deterministic extraction still finds the named overlook.
        let names = Set(result.places.map(\.name))
        #expect(names.isSuperset(of: ["Whitney Portal Overlook", "Alabama Hills Viewpoint", "Scenic Lookout", "Mobius Arch Overlook"]))
        #expect(result.places.allSatisfy { $0.why?.isModelWritten == false && !($0.why?.text.isEmpty ?? true) })
        #expect(model.prompts.isEmpty)                                          // the model was never called
        assertGrounded(result.places, supplied: s.supplied)
    }

    @Test func noModelAtAllIsTheSameAsUnavailable() async {
        let s = LonePineScenario()
        let result = await s.engine(model: nil).discover(DiscoveryRequest(text: LonePineScenario.query))
        #expect(result.planOrigin.isBasic)
        #expect(result.places.count >= 5)
        assertGrounded(result.places, supplied: s.supplied)
    }

    @Test func aFailingModelFallsBackToBasicSearchAndStillAnswers() async {
        let s = LonePineScenario()
        let model = s.model()
        model.set { $0.generateError = .generation("boom"); $0.respond = { _ in "99 nonsense" } }
        let result = await s.engine(model: model).discover(DiscoveryRequest(text: LonePineScenario.query))
        #expect(result.planOrigin == .basic(reason: nil))
        #expect(result.places.count >= 5)
        assertGrounded(result.places, supplied: s.supplied)
    }

    // MARK: Yosemite

    @Test func waterfallsInYosemiteStayInsideTheRealBoundary() async {
        let s = YosemiteScenario()
        let result = await s.engine(model: nil).discover(DiscoveryRequest(text: "waterfalls in Yosemite"))
        #expect(result.plan.features == [.waterfall] && result.plan.areaText == "Yosemite")
        #expect(result.area?.hasRealBoundary == true)
        #expect(result.area?.boundaryCitation?.title == "Yosemite National Park boundary")
        #expect(Set(result.places.map(\.name)) == ["Vernal Fall", "Nevada Fall"])   // box-only and distant falls are dropped
        for p in result.places { #expect(YosemiteScenario.triangle.contains(p.coordinate.value)) }
        assertGrounded(result.places, supplied: s.supplied)
        let osm = result.statuses.first { $0.source == osmID }
        #expect(osm?.state == .found(4))
        #expect(result.statuses.contains { $0.source == FakeBoundary().descriptor.id && $0.state == .found(1) })
    }

    @Test func yosemiteWithTheModelGivesTheSameResults() async {
        let s = YosemiteScenario()
        let model = FakeModel()
        model.set {
            $0.json["QueryPlanDTO"] = #"{"areaMode":"named","areaText":"Yosemite","features":["waterfall"],"windows":["goldenMorning"],"keywords":["misty"],"exclude":[]}"#
            $0.respond = { _ in "A waterfall in Yosemite." }
        }
        let result = await s.engine(model: model).discover(DiscoveryRequest(text: "waterfalls in Yosemite"))
        #expect(result.planOrigin == .ai)
        #expect(result.plan.windows == [.goldenMorning])
        #expect(Set(result.places.map(\.name)) == ["Vernal Fall", "Nevada Fall"])
        assertGrounded(result.places, supplied: s.supplied)
    }

    // MARK: Adversarial model

    @Test func anAdversarialModelCannotPutAPlaceWhereNoProviderSaidSo() async {
        var s = LonePineScenario()
        s.wikipedia.docs.append(doc("Fake guide", "Secret Falls (37.7512, -119.6234) lies at 36.5, -118.0. Another is Invented Point at latitude 37.0."))
        let model = FakeModel()
        model.set {
            $0.json["QueryPlanDTO"] = """
            {"areaMode":"named","areaText":"Lone Pine, California","features":["viewpoint","unicorn"],"windows":["night"],
             "maxDriveMinutes":90,"keywords":["37.7512","-119.6234","36.5, -118.0","moody"],"exclude":["37.1"]}
            """
            $0.json["ExtractionDTO"] = """
            {"places":[{"name":"Hidden Falls (37.7, -119.6)","documentIndex":0},
                       {"name":"Secret Falls (37.7512, -119.6234)","documentIndex":2,"featureHint":"waterfall"},
                       {"name":"Invented Point","documentIndex":2},
                       {"name":"Totally Made Up Falls","documentIndex":0},
                       {"name":"Mobius Arch Overlook","documentIndex":0}]}
            """
            $0.respond = { _ in "Hidden Falls at 37.7512, -119.6234 near Glacier Point." }
        }
        let result = await s.engine(model: model).discover(DiscoveryRequest(text: LonePineScenario.query))

        #expect(result.planOrigin == .ai)
        #expect(result.plan.keywords == ["moody"])                              // coordinate-like keywords never reach a source
        #expect(!result.plan.searchTerms.contains { $0.contains("37.") })
        assertGrounded(result.places, supplied: s.supplied)
        let near: (Double, Double) -> Bool = { lat, lon in result.places.contains { abs($0.coordinate.latitude - lat) < 0.01 && abs($0.coordinate.longitude - lon) < 0.01 } }
        #expect(!near(37.7, -119.6) && !near(37.7512, -119.6234) && !near(37.0, -118.0))
        let names = Set(result.places.map(\.name))
        #expect(!names.contains("Totally Made Up Falls") && !names.contains("Secret Falls") && !names.contains("Invented Point"))
        // The geocoder was never asked about an invented name or a number.
        for call in s.geocoder.log.calls { #expect(!call.contains("37.") && !call.contains("Totally")) }
        // The adversarial sentence failed the grounding checks, so every line is a template.
        #expect(result.places.allSatisfy { $0.why?.isModelWritten == false })
        #expect(result.places.allSatisfy { !($0.why?.text.contains("37.7512") ?? false) })
    }

    // MARK: Statuses

    @Test func perSourceStatusesAndFixedTextSources() async {
        var s = LonePineScenario()
        s.osm.script = Script(delay: .seconds(30))                           // times out
        s.poi.script = Script(error: .rateLimited(retryAfter: nil))          // fails
        s.wikipedia.script = Script(error: .offline)
        s.photos.script = Script(error: .http(status: 500, excerpt: nil))
        let result = await s.engine(model: nil).discover(DiscoveryRequest(text: LonePineScenario.query))
        func state(_ id: SourceID) -> SourceState? { result.statuses.first { $0.source == id }?.state }
        #expect(state(osmID) == .timedOut)
        #expect(state(.applePOI) == .failed(.rateLimited(retryAfter: nil)))
        #expect(state(wikiID) == .failed(.offline(lastGood: nil)))
        #expect(state(mapkitSearchID) == .found(1))
        #expect(state(s.photos.descriptor.id) == .failed(.sourceError(s.photos.descriptor.id, "HTTP 500")))
        #expect(state(FixedSources.reddit) == .unavailable(FixedSources.redditReason))
        #expect(state(FixedSources.google) == .unavailable(FixedSources.googleReason))
        #expect(FixedSources.redditReason == "needs your own Reddit API access; no free keyless access exists")
        #expect(FixedSources.googleReason == "Google Custom Search is closing to new users; not used")
        // Sources failed; the run did not.
        #expect(result.failure == nil)
        #expect(result.places.map(\.name).contains("Scenic Lookout"))
        assertGrounded(result.places, supplied: s.supplied)
        // The status line is readable.
        #expect(result.statuses.first { $0.source == FixedSources.reddit }?.summary.hasPrefix("Reddit: needs your own Reddit API access") == true)
    }

    @Test func aUserKeyTextProviderJoinsAndNoLongerShowsAsUnavailable() async {
        var s = LonePineScenario()
        let reddit = FakeText(descriptor: descriptor(FixedSources.reddit, "Reddit", kinds: [.textEvidence]), docs: [
            doc("r/photography thread", "Everyone loves Mobius Arch Overlook at dawn.", source: FixedSources.reddit),
        ])
        s.wikipedia.docs = []
        var providers = s.providers
        providers.textEvidence = [s.wikipedia, reddit]
        let engine = DiscoveryEngine(providers: providers, model: nil, clock: ManualSourceClock(now: testNow), configuration: fastConfig)
        let result = await engine.discover(DiscoveryRequest(text: LonePineScenario.query))
        #expect(result.statuses.first { $0.source == FixedSources.reddit }?.state == .found(1))
        let mobius = result.places.first { $0.name == "Mobius Arch Overlook" }
        #expect(mobius?.sources.contains(FixedSources.reddit) == true)
        #expect(mobius?.citations.first?.source == FixedSources.reddit)
        #expect(result.statuses.contains { $0.source == FixedSources.google })
    }

    @Test func providersOutsideTheirCoverageAreSkipped() async {
        var s = LonePineScenario()
        s.osm = FakeGazetteer(descriptor: descriptor(osmID, "OpenStreetMap", kinds: [.gazetteer],
                                                     coverage: .regions([GeoRegion(center: Coordinate(latitude: 48, longitude: 2), latitudeDelta: 4, longitudeDelta: 4)])),
                              places: s.osm.places)
        let result = await s.engine(model: nil).discover(DiscoveryRequest(text: LonePineScenario.query))
        #expect(result.statuses.first { $0.source == osmID }?.state == .skipped("outside its coverage"))
        #expect(s.osm.log.calls.isEmpty)
    }

    @Test func photosAreLookedUpOnlyForTheTopMergedCandidates() async {
        var s = LonePineScenario()
        s.osm.places = (0..<30).map { candidate("Overlook \($0)", 36.60 + Double($0) * 0.004, -118.10, kinds: [.viewpoint], source: osmID, externalID: "n/\($0)") }
        s.poi.places = []; s.search.answers = [:]; s.wikipedia.docs = []
        let result = await s.engine(model: nil).discover(DiscoveryRequest(text: LonePineScenario.query))
        #expect(result.places.count == 30)
        #expect(s.photos.log.calls.count == DiscoveryConfiguration().photoLookupCount)
        #expect(Set(s.photos.log.calls).count == 12)
        #expect(result.places.filter { $0.photoCount > 0 }.count == 12)
    }

    // MARK: Failures

    @Test func unresolvableAreasAreStatesNotCrashes() async {
        let s = LonePineScenario()
        let engine = s.engine(model: nil)
        let near = await engine.discover(DiscoveryRequest(text: "viewpoints near me"))
        #expect(near.failure == .area(.needsLocation) && near.places.isEmpty)
        let nowhere = await engine.discover(DiscoveryRequest(text: "viewpoints in Atlantis"))
        #expect(nowhere.failure == .area(.notFound("Atlantis")))
        let empty = await engine.discover(DiscoveryRequest(text: "   "))
        #expect(empty.failure == .emptyQuery)
        let map = await engine.discover(DiscoveryRequest(text: "viewpoints in this area"))
        #expect(map.failure == .area(.needsLocation))   // no map region: the parser reads it as "near me", which needs a location
    }

    @Test func nearMeUsesTheGivenLocationAndTheVisibleMapUsesTheRegion() async {
        let s = LonePineScenario()
        let engine = s.engine(model: nil)
        let near = await engine.discover(DiscoveryRequest(text: "viewpoints near me", currentLocation: Geo.lonePine))
        #expect(near.area?.basis == .currentLocation(radiusKm: AreaResolver.defaultNearMeRadiusKm))
        #expect(near.places.contains { $0.name == "Whitney Portal Overlook" })
        let region = GeoRegion(center: Geo.lonePine, latitudeDelta: 0.4, longitudeDelta: 0.4)
        let map = await engine.discover(DiscoveryRequest(text: "viewpoints in this area", mapRegion: region))
        #expect(map.area?.basis == .visibleMap)
        #expect(map.places.contains { $0.name == "Whitney Portal Overlook" })
        assertGrounded(near.places + map.places, supplied: s.supplied)
    }

    @Test func resultsCarryLibraryNoveltyAndTheOrdering() async {
        let s = LonePineScenario()
        let lib = [LibraryReference(name: "Whitney Portal Overlook", coordinate: s.osm.places[0].coordinate)]
        let unique = await s.engine(model: nil).discover(DiscoveryRequest(text: LonePineScenario.query, ordering: .unique, library: lib))
        let saved = unique.places.first { $0.name == "Whitney Portal Overlook" }
        #expect(saved?.rank.novelty.value == 0)
        #expect(unique.places.first?.name != "Whitney Portal Overlook")
        #expect(unique.places.allSatisfy { $0.distanceKm != nil })
        // Ranks are sorted by the requested ordering's score.
        let scores = unique.places.map { $0.rank.score(for: .unique) }
        #expect(scores == scores.sorted(by: >))
    }

    // MARK: Streaming and cancellation

    @Test func eventsStreamInOrder() async {
        let s = LonePineScenario()
        var kinds: [String] = []
        var finished: DiscoveryResult?
        var partialCounts: [Int] = []
        for await event in s.engine(model: s.model()).run(DiscoveryRequest(text: LonePineScenario.query)) {
            switch event {
            case .planReady: kinds.append("plan")
            case .areaResolved: kinds.append("area")
            case .statusChanged: kinds.append("status")
            case .partial(let p): kinds.append("partial"); partialCounts.append(p.count)
            case .finished(let r): kinds.append("finished"); finished = r
            }
        }
        #expect(kinds.first == "plan")
        #expect(kinds.firstIndex(of: "area")! > kinds.firstIndex(of: "plan")!)
        #expect(kinds.last == "finished")
        #expect(kinds.filter { $0 == "finished" }.count == 1)
        #expect(kinds.contains("partial") && kinds.contains("status"))
        #expect(kinds.firstIndex(of: "partial")! > kinds.firstIndex(of: "area")!)
        #expect(kinds.firstIndex(of: "partial")! < kinds.firstIndex(of: "finished")!)
        #expect(partialCounts.max()! <= finished!.places.count + 3)
        #expect(finished?.places.isEmpty == false)
    }

    @Test func cancellingTheConsumerCancelsProvidersAndSilencesTheStream() async {
        var sv = LonePineScenario()
        sv.osm.script = Script(delay: .seconds(60))
        sv.wikipedia.script = Script(delay: .seconds(60))
        let s = sv
        var config = fastConfig
        config.sourceTimeoutOverride = .seconds(120)
        let engine = DiscoveryEngine(providers: s.providers, model: nil, clock: ManualSourceClock(now: testNow), configuration: config)
        let received = EventCounter()
        let task = Task {
            for await event in engine.run(DiscoveryRequest(text: LonePineScenario.query)) { received.add(event) }
        }
        #expect(await waitUntil { s.osm.log.calls.count == 1 && s.wikipedia.log.calls.count == 1 })
        task.cancel()
        #expect(await waitUntil { s.osm.log.cancelledCount == 1 && s.wikipedia.log.cancelledCount == 1 })
        await task.value
        let count = received.count
        try? await Task.sleep(for: .milliseconds(150))
        #expect(received.count == count)
        #expect(!received.sawFinished)
    }

    @Test func endingTheStreamEarlyAlsoCancelsTheWork() async {
        var sv = LonePineScenario()
        sv.osm.script = Script(delay: .seconds(60))
        let s = sv
        var config = fastConfig
        config.sourceTimeoutOverride = .seconds(120)
        let engine = DiscoveryEngine(providers: s.providers, model: nil, clock: ManualSourceClock(now: testNow), configuration: config)
        for await event in engine.run(DiscoveryRequest(text: LonePineScenario.query)) {
            // A fast source has answered, so the slow one is in flight.
            if case .statusChanged(let st) = event, case .found = st.state, s.osm.log.calls.count == 1 { break }
        }
        #expect(await waitUntil { s.osm.log.cancelledCount == 1 })
    }

    @Test func cancellingDuringTheModelCallStopsIt() async {
        let s = LonePineScenario()
        let model = s.model()
        model.set { $0.delay = .seconds(60) }
        var config = fastConfig
        config.planTimeout = .seconds(120)
        let engine = DiscoveryEngine(providers: s.providers, model: model, clock: ManualSourceClock(now: testNow), configuration: config)
        let task = Task { await engine.discover(DiscoveryRequest(text: LonePineScenario.query)) }
        #expect(await waitUntil { model.prompts.count == 1 })
        task.cancel()
        _ = await task.value
        #expect(model.cancelledCount == 1)
        #expect(s.osm.log.calls.isEmpty)
    }

    @Test func explanationsRunAtMostTwoAtATime() async {
        let s = LonePineScenario()
        let model = s.model()
        model.set { $0.delay = .milliseconds(20) }
        let result = await s.engine(model: model).discover(DiscoveryRequest(text: LonePineScenario.query))
        #expect(model.respondPeak <= 2)
        #expect(model.respondPeak >= 1)
        #expect(result.places.count > 0)
    }

    @Test func aSlowPlanFallsBackToBasicSearchWithinTheTimeout() async {
        let s = LonePineScenario()
        let model = s.model()
        model.set { $0.delay = .seconds(60) }
        var config = fastConfig
        config.planTimeout = .milliseconds(100)
        let engine = DiscoveryEngine(providers: s.providers, model: model, clock: ManualSourceClock(now: testNow), configuration: config)
        let result = await engine.discover(DiscoveryRequest(text: LonePineScenario.query))
        #expect(result.planOrigin == .basic(reason: nil))
        #expect(result.places.count >= 5)
    }
}

final class EventCounter: Sendable {
    private let state = Mutex2()
    func add(_ e: DiscoveryEvent) { state.add(e) }
    var count: Int { state.count }
    var sawFinished: Bool { state.sawFinished }
}

import Synchronization
final class Mutex2: Sendable {
    private let s = Mutex<(count: Int, finished: Bool)>((0, false))
    func add(_ e: DiscoveryEvent) { s.withLock { st in st.count += 1; if case .finished = e { st.finished = true } } }
    var count: Int { s.withLock { $0.count } }
    var sawFinished: Bool { s.withLock { $0.finished } }
}
