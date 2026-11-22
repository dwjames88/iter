import Foundation
import FoundationModels
import IterCore
import Testing
@testable import IterServices

@Suite("Scout grounding")
struct ScoutGroundingTests {
    func registry() async -> (ScoutRegistry, RegisteredPlace, RegisteredPlace) {
        let r = ScoutRegistry()
        let map = await r.register(Fixture.silverFalls)
        let cur = await r.registerCurated(Fixture.curatedSpot)
        return (r, map, cur)
    }

    @Test func unknownIDsAreDroppedAndOrderKept() async {
        let (r, map, cur) = await registry()
        let picks = [
            ResolvedPickInput(placeID: "m99", why: "invented", window: .sunrise),
            ResolvedPickInput(placeID: cur.id, why: "mossy", window: .any),
            ResolvedPickInput(placeID: "Silver Falls State Park", why: "by name, not ID", window: .sunrise),
            ResolvedPickInput(placeID: map.id, why: "fog pools", window: .sunrise),
        ]
        let out = ScoutGrounding.resolve(picks: picks, registry: await r.snapshot())
        #expect(out.map(\.spot.name) == ["Multnomah Falls", "Silver Falls State Park"])
    }

    @Test func duplicatesAreRemovedIncludingIDVariants() async {
        let (r, map, _) = await registry()
        let picks = [
            ResolvedPickInput(placeID: map.id, why: "first", window: .sunrise),
            ResolvedPickInput(placeID: " " + map.id.uppercased() + " ", why: "second", window: .night),
        ]
        let out = ScoutGrounding.resolve(picks: picks, registry: await r.snapshot())
        #expect(out.count == 1)
        #expect(out[0].why == "first")
    }

    @Test func provenanceAndOrigin() async {
        let (r, map, cur) = await registry()
        let out = ScoutGrounding.resolve(picks: [.init(placeID: map.id, why: "a", window: .any), .init(placeID: cur.id, why: "b", window: .any)],
                                         registry: await r.snapshot())
        #expect(out[0].provenance == .appleMaps)
        #expect(out[0].spot.origin == .scout)
        #expect(out[0].spot.id == "apple-1")
        #expect(out[0].spot.category == .landscape)
        #expect(out[1].provenance == .curated)
        #expect(out[1].spot == Fixture.curatedSpot)
    }

    @Test func coordinatesComeFromTheRegistryNotTheText() async {
        let (r, map, _) = await registry()
        let lying = ResolvedPickInput(placeID: map.id, why: "Actually at 10.0, 20.0 near Paris", window: .sunset)
        let out = ScoutGrounding.resolve(picks: [lying], registry: await r.snapshot())
        #expect(out[0].spot.coordinate == Fixture.silverFalls.coordinate)
        #expect(out[0].spot.name == "Silver Falls State Park")
    }

    @Test(arguments: [
        (ScoutWindow.sunrise, LightWindowKind.goldenMorning), (.sunset, .goldenEvening), (.blueHour, .blueEvening), (.night, .night),
    ])
    func windowMapping(window: ScoutWindow, kind: LightWindowKind) {
        #expect(ScoutGrounding.lightWindow(for: window) == kind)
    }

    @Test func anyWindowIsNil() {
        #expect(ScoutGrounding.lightWindow(for: .any) == nil)
    }

    @Test func driveSecondsAndTimeZoneFallbacks() async {
        let r = ScoutRegistry()
        let noZone = await r.register(Fixture.place("apple-9", "Mystery Overlook", lat: 45.0, lon: -122.0, zone: nil))
        await r.recordDrive(id: noZone.id, seconds: 4000)
        let pick = ResolvedPickInput(placeID: noZone.id, why: "x", window: .any)

        var out = ScoutGrounding.resolve(picks: [pick], registry: await r.snapshot(), fallbackTimeZone: TimeZone(identifier: "Europe/Paris")!)
        #expect(out[0].driveSeconds == 4000)
        #expect(out[0].spot.timeZoneIdentifier == "Europe/Paris")

        await r.setTimeZone(id: noZone.id, identifier: "America/Denver")
        out = ScoutGrounding.resolve(picks: [pick], registry: await r.snapshot(), fallbackTimeZone: TimeZone(identifier: "Europe/Paris")!)
        #expect(out[0].spot.timeZoneIdentifier == "America/Denver")
    }

    @Test func atMostEightSuggestions() async {
        let r = ScoutRegistry()
        var picks: [ResolvedPickInput] = []
        for i in 0..<12 {
            let p = await r.register(Fixture.place("id\(i)", "Place \(i)", lat: 45 + Double(i) * 0.01, lon: -122))
            picks.append(.init(placeID: p.id, why: "r", window: .any))
        }
        #expect(ScoutGrounding.resolve(picks: picks, registry: await r.snapshot()).count == 8)
    }

    @Test func categoryMapping() {
        #expect(ScoutGrounding.category(pointOfInterest: "MKPOICategoryBeach", name: "X") == .coast)
        #expect(ScoutGrounding.category(pointOfInterest: "MKPOICategoryNationalPark", name: "X") == .landscape)
        #expect(ScoutGrounding.category(pointOfInterest: nil, name: "Latourell Falls") == .waterfall)
        #expect(ScoutGrounding.category(pointOfInterest: nil, name: "Hoh Rain Forest") == .forest)
        #expect(ScoutGrounding.category(pointOfInterest: nil, name: "Somewhere") == .landscape)
    }

    @Test func registryReusesIDForTheSamePlace() async {
        let r = ScoutRegistry()
        let a = await r.register(Fixture.silverFalls)
        let b = await r.register(Fixture.silverFalls)
        let c = await r.register(Fixture.cannonBeach)
        #expect(a.id == "m1" && b.id == "m1" && c.id == "m2")
    }
}

@Suite("Scout availability and errors")
struct ScoutAvailabilityTests {
    @Test func availabilityMapping() {
        #expect(ScoutAvailabilityMapping.map(.available) == .available)
        #expect(ScoutAvailabilityMapping.map(.unavailable(.deviceNotEligible)) == .deviceNotEligible)
        #expect(ScoutAvailabilityMapping.map(.unavailable(.appleIntelligenceNotEnabled)) == .appleIntelligenceNotEnabled)
        #expect(ScoutAvailabilityMapping.map(.unavailable(.modelNotReady)) == .modelNotReady)
    }

    @Test func generationErrorMapping() {
        let ctx = LanguageModelSession.GenerationError.Context(debugDescription: "test")
        #expect(ScoutError.map(LanguageModelSession.GenerationError.exceededContextWindowSize(ctx)) == .contextTooLong)
        #expect(ScoutError.map(LanguageModelSession.GenerationError.guardrailViolation(ctx)) == .guardrail)
        #expect(ScoutError.map(LanguageModelSession.GenerationError.unsupportedLanguageOrLocale(ctx)) == .unsupportedLanguage)
        #expect(ScoutError.map(LanguageModelSession.GenerationError.assetsUnavailable(ctx)) == .unavailable(.modelNotReady))
        #expect(ScoutError.map(CancellationError()) == nil)
        if case .failed = ScoutError.map(LanguageModelSession.GenerationError.rateLimited(ctx)) {} else { Issue.record("rateLimited should map to failed") }
    }

    @Test func scoutReportsLiveAvailabilityConsistently() {
        let scout = AppleIntelligenceScout(search: FakeSearch(results: []), geocoder: FakeGeocoder(centre: nil), drives: nil, curated: [])
        #expect(scout.availability() == ScoutAvailabilityMapping.map(SystemLanguageModel.default.availability))
    }
}
