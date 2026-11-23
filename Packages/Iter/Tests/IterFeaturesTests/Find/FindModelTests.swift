import Foundation
import Testing
import IterModel
import IterSources
import IterAI
import IterDiscovery
@testable import IterFeatures

@MainActor
@Suite("FindModel: search")
struct FindModelSearchTests {
    @Test func suggestionsOfferAskOnlyForRequests() throws {
        let rig = try Rig()
        rig.model.text = "Mesa Arch"
        #expect(rig.model.suggestions.lookup == "Mesa Arch")
        #expect(rig.model.suggestions.ask == nil)
        rig.model.text = "waterfalls near Lone Pine at sunrise"
        #expect(rig.model.suggestions.ask == "waterfalls near Lone Pine at sunrise")
        rig.model.text = "waterfalls in Yosemite"
        #expect(rig.model.suggestions.feature?.feature == .waterfall)
        rig.model.text = "   "
        #expect(rig.model.suggestions == .none)
    }

    @Test func aDiscoveryRunStreamsPlacesAndFinishes() async throws {
        let rig = try Rig()
        await rig.search()
        #expect(rig.model.phase == .finished)
        #expect(rig.model.rows.count == 6)
        #expect(rig.model.rows.map(\.name).contains("Mesa Arch"))
        #expect(rig.model.area?.name != nil)
        #expect(rig.model.progress.isRunning == false)
        #expect(rig.model.progress.total > 0 && rig.model.progress.done == rig.model.progress.total)
    }

    @Test func basicSearchIsLabelledWhenThereIsNoModel() async throws {
        let rig = try Rig()
        await rig.search()
        #expect(rig.model.isBasicSearch)
        #expect(rig.model.planLabel == "Basic search: AI not set up")
        let ai = rig.model.chips.first { $0.role == .ai }
        #expect(ai?.state == .unavailable)
    }

    @Test func redditAndGoogleAppearAsUnavailableWithTheirReason() async throws {
        let rig = try Rig()
        await rig.search()
        let reddit = try #require(rig.model.chips.first { $0.sourceID == FixedSources.reddit })
        let google = try #require(rig.model.chips.first { $0.sourceID == FixedSources.google })
        #expect(reddit.state == .unavailable && reddit.reason == FixedSources.redditReason)
        #expect(google.state == .unavailable && google.reason == FixedSources.googleReason)
        // They are not counted as "sources done of total", and they sort after the sources that were asked.
        let asked = rig.model.chips.filter(\.isAsked).count
        #expect(rig.model.progress.total == asked)
        #expect(rig.model.chips.suffix(3).allSatisfy { !$0.isAsked })
    }

    @Test func citationsAndLicencesTravelWithResults() async throws {
        let rig = try Rig()
        await rig.search()
        let mesa = try #require(rig.model.rows.first { $0.name == "Mesa Arch" })
        #expect(mesa.verification == .confirmed)
        #expect(mesa.photo?.licenceName == "CC BY-SA 4.0")
        #expect(mesa.photo?.credit.contains("Wikimedia Commons") == true)
        rig.model.select(mesa.id)
        let card = try #require(rig.model.card)
        #expect(card.citations.count >= 2)
        #expect(card.citations.allSatisfy { $0.url != nil })
        #expect(card.photo?.licenceName == "CC BY-SA 4.0")
        let single = try #require(rig.model.rows.first { $0.verification == .singleSource })
        #expect(single.verificationLabel.hasPrefix("One source: "))
    }

    @Test func aSlowOldSearchNeverOverwritesANewerOne() async throws {
        let runner = ControlledRunner()
        let rig = try Rig(runner: runner)
        rig.model.text = "viewpoints near Slowtown"
        rig.model.askIter()
        rig.model.text = "viewpoints near Fasttown"
        rig.model.askIter()
        #expect(runner.requests.count == 2)
        let fresh = try await FindFixtures.engine().run(DiscoveryRequest(text: FindFixtures.query)).finishedResult()
        runner.send(.finished(fresh), to: 1)
        #expect(await waitUntil { rig.model.phase == .finished })
        let rows = rig.model.rows.map(\.name)
        // The old run answers late with something different; it must change nothing.
        var stale = fresh
        stale.places = Array(fresh.places.prefix(1))
        runner.send(.finished(stale), to: 0)
        runner.send(.partial(Array(fresh.places.prefix(1))), to: 0)
        try await Task.sleep(for: .milliseconds(80))
        #expect(rig.model.rows.map(\.name) == rows)
        #expect(rig.model.phase == .finished)
    }

    @Test func cancelStopsTheRunAndIgnoresLateEvents() async throws {
        let runner = ControlledRunner()
        let rig = try Rig(runner: runner)
        rig.model.text = FindFixtures.query
        rig.model.askIter()
        let status = SourceStatus(source: FindFixtures.osm, name: "OpenStreetMap (Overpass)", role: .gazetteer, state: .searching)
        runner.send(.statusChanged(status), to: 0)
        #expect(await waitUntil { rig.model.chips.count == 1 })
        rig.model.cancel()
        #expect(rig.model.phase == .cancelled)
        #expect(rig.model.progress.isRunning == false)
        // The row that was still searching is shown as stopped, not as a spinner that never ends.
        #expect(rig.model.chips.first?.state == .skipped)
        let fresh = try await FindFixtures.engine().run(DiscoveryRequest(text: FindFixtures.query)).finishedResult()
        runner.send(.finished(fresh), to: 0)
        try await Task.sleep(for: .milliseconds(60))
        #expect(rig.model.rows.isEmpty)
        #expect(rig.model.phase == .cancelled)
    }

    @Test func aHangingSourceNeverBlocksTheOthersAndShowsAsSlowThenDown() async throws {
        var config = FindFixtures.fastConfiguration
        config.sourceTimeoutOverride = .milliseconds(2500)
        let engine = FindFixtures.engine(gazetteer: .init(hangs: true), configuration: config)
        let rig = try Rig(runner: engine)
        rig.model.text = FindFixtures.query
        rig.model.askIter()
        // Apple Maps answers at once: results show while the Overpass-like source is still hanging.
        #expect(await waitUntil { !rig.model.rows.isEmpty })
        #expect(rig.model.phase == .discovering)
        #expect(await waitUntil { rig.model.chips.first { $0.sourceID == FindFixtures.osm }?.state == .slow })
        #expect(rig.model.chips.first { $0.sourceID == FindFixtures.osm }?.text.contains("slow") == true)
        #expect(rig.model.progress.isRunning)
        // Then it times out: marked down, the run finishes, the places that did arrive stay.
        #expect(await waitUntil(.seconds(6)) { rig.model.phase == .finished })
        let osm = try #require(rig.model.chips.first { $0.sourceID == FindFixtures.osm })
        #expect(osm.state == .down)
        #expect(rig.model.rows.contains { $0.name == "Mesa Arch" })
    }

    @Test func aFailedSourceIsDownWithItsReason() async throws {
        let engine = FindFixtures.engine(gazetteer: .init(error: .http(status: 504, excerpt: "Gateway Timeout")))
        let rig = try Rig(runner: engine)
        await rig.search()
        let osm = try #require(rig.model.chips.first { $0.sourceID == FindFixtures.osm })
        #expect(osm.state == .down)
        #expect(osm.reason?.isEmpty == false)
        #expect(rig.model.rows.isEmpty == false)
    }

    @Test func searchHereUsesTheVisibleRegionAndNeverMovesIt() async throws {
        let runner = ControlledRunner()
        let rig = try Rig(runner: runner)
        rig.model.searchHere()
        #expect(rig.model.notice != nil)
        #expect(runner.requests.isEmpty)
        let region = GeoRegion(center: FindFixtures.mesaArch, latitudeDelta: 0.4, longitudeDelta: 0.5)
        rig.model.mapRegion = region
        rig.model.text = "waterfalls in Yosemite"
        rig.model.searchHere()
        let request = try #require(runner.requests.last)
        #expect(request.mapRegion == region)
        #expect(request.text == "waterfalls in this area")
        #expect(rig.model.mapRegion == region)
        #expect(rig.model.notice == nil)
        rig.model.text = ""
        rig.model.searchHere()
        #expect(runner.requests.last?.text == "photo spots in this area")
    }

    @Test func featureSearchesGoThroughTheEngineOnReturn() async throws {
        let runner = ControlledRunner()
        let rig = try Rig(runner: runner)
        rig.model.text = "waterfalls in Yosemite"
        rig.model.submit()
        #expect(runner.requests.map(\.text) == ["waterfalls in Yosemite"])
        #expect(rig.model.phase == .discovering)
    }

    @Test func requestUsesPreferencesAndTheLibraryByNameOnly() async throws {
        let runner = ControlledRunner()
        let rig = try Rig(runner: runner)
        rig.preferences.ordering = .unique
        rig.preferences.resultCap = 12
        rig.preferences.preferenceText = "reflections"
        _ = rig.library.places.createUserSpot(name: "Secret Pond", coordinate: FindFixtures.moab, timeZoneIdentifier: "America/Denver")
        rig.model.text = "viewpoints near Moab"
        rig.model.askIter()
        let r = try #require(runner.requests.last)
        #expect(r.ordering == .unique && r.maxResults == 12 && r.preferenceText == "reflections")
        #expect(r.library.map(\.name) == ["Secret Pond"])
        #expect(r.currentLocation == FindFixtures.moab)
    }
}

extension AsyncStream where Element == DiscoveryEvent {
    /// The `finished` result of a run.
    func finishedResult() async throws -> DiscoveryResult {
        for await event in self { if case .finished(let r) = event { return r } }
        throw CancellationError()
    }
}
