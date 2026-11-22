import Foundation
import Testing
@testable import IterModel

private func place(curated: String? = nil, external: String? = nil) -> Place {
    Place(curatedID: curated, externalID: external, name: "Mesa Arch", locality: "Canyonlands, UT",
          coordinate: Coordinate(latitude: 38.389, longitude: -109.8677), timeZoneIdentifier: "America/Denver",
          category: .landscape, bestLight: [.midday, .sunrise], origin: .curated)
}

private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
    try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
}

@Suite struct RawValueStabilityTests {
    @Test func storedEnumsKeepTheirRawValues() {
        #expect(LightWindowKind.allCases.map(\.rawValue) == ["blueMorning", "goldenMorning", "goldenEvening", "blueEvening", "night"])
        #expect(LightIntent.allCases.map(\.rawValue) == ["sunrise", "sunset", "blueHour", "night"])
        #expect(BestLight.allCases.map(\.rawValue) == ["sunrise", "sunset", "blueHour", "night", "midday", "overcast"])
        #expect(PlaceCategory.allCases.map(\.rawValue) ==
                ["landscape", "astro", "architecture", "street", "coast", "wildlife", "desert", "waterfall", "forest", "urban"])
        #expect(PlaceOrigin.allCases.map(\.rawValue) == ["curated", "user", "appleMaps", "scout"])
        #expect(TransferTiming.allCases.map(\.rawValue) == ["morning", "eveningBefore"])
        #expect(FolderKind.allCases.map(\.rawValue) == ["trips", "locations"])
        #expect(StopKind.allCases.map(\.rawValue) == ["light", "lodging", "waypoint"])
        #expect(TimeZonePolicy.allCases.map(\.rawValue) == ["spot"])
        #expect(Verification.allCases.map(\.rawValue) == ["confirmed", "singleSource", "userPlaced"])
    }
}

@Suite struct PlaceTests {
    @Test func legacySpotIDIsCuratedSlugElseUUID() {
        #expect(place(curated: "mesa-arch").legacySpotID == "mesa-arch")
        let p = place(external: "I63A1")
        #expect(p.legacySpotID == p.id.uuidString)
        let both = place(curated: "mesa-arch", external: "X")
        #expect(both.legacySpotID == "mesa-arch")
    }

    @Test func defaultIntentAndSession() {
        #expect(place().defaultIntent == .sunrise)
        #expect(place().defaultSession == .goldenMorning)
        var p = place(); p.bestLight = [.midday]
        #expect(p.defaultIntent == .sunset && p.defaultSession == .goldenEvening)
        p.bestLight = [.night]
        #expect(p.defaultSession == .night)
        p.bestLight = [.blueHour]
        #expect(p.defaultSession == .blueEvening)
    }

    @Test func codableRoundTripKeepsEverything() throws {
        var p = place(curated: "mesa-arch", external: "ext")
        p.isSaved = true; p.folderID = UUID(); p.sortOrder = 2.5; p.isPinned = true
        p.pinnedAt = Date(timeIntervalSince1970: 1000); p.createdAt = Date(timeIntervalSince1970: 10); p.updatedAt = Date(timeIntervalSince1970: 20)
        p.sources = ["apple.mapkit", "wikipedia"]
        p.citations = [Citation(source: "wikipedia", url: URL(string: "https://en.wikipedia.org/wiki/Mesa_Arch"), title: "Mesa Arch",
                                retrievedAt: Date(timeIntervalSince1970: 5), licence: LicenceTag(key: "cc-by-sa", mayStore: true))]
        p.verification = .confirmed
        p.discoveredAt = Date(timeIntervalSince1970: 7)
        p.horizon = .flat
        #expect(try roundTrip(p) == p)
    }

    @Test func decodesWithNewKeysMissing() throws {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111","name":"Old","coordinate":{"latitude":1,"longitude":2},
         "timeZoneIdentifier":"UTC","category":"coast"}
        """
        let p = try JSONDecoder().decode(Place.self, from: Data(json.utf8))
        #expect(p.name == "Old" && p.category == .coast && p.popularity == 50)
        #expect(p.sources.isEmpty && p.citations.isEmpty && p.verification == nil && p.horizon == nil && p.discoveredAt == nil)
        #expect(!p.isSaved && p.folderID == nil && p.curatedID == nil)
    }
}

@Suite struct LocalTimeTests {
    @Test func isoRoundTrip() {
        let t = LocalTime(iso: "06:05")
        #expect(t == LocalTime(hour: 6, minute: 5) && t?.iso == "06:05")
        #expect(LocalTime(iso: "23:59")?.minutesSinceMidnight == 1439)
        #expect(LocalTime(hour: 0, minute: 0).iso == "00:00")
    }

    @Test func rejectsBadInput() {
        for bad in ["", "24:00", "12:60", "9:05", "09:5", "0905", "12:00:00", "ab:cd", "-1:30", "12:", ":30", "１２:３０"] {
            #expect(LocalTime(iso: bad) == nil, "\(bad)")
        }
    }

    @Test func codableIsAString() throws {
        let data = try JSONEncoder().encode([LocalTime(hour: 7, minute: 30)])
        #expect(String(decoding: data, as: UTF8.self) == "[\"07:30\"]")
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([LocalTime].self, from: Data("[\"25:00\"]".utf8)) }
    }
}

@Suite struct TripTests {
    private func trip() -> Trip {
        let p = place(curated: "mesa-arch")
        let s1 = Stop(place: p, dayIndex: 0, session: .goldenMorning, dwellMinutes: 45, fixedArrival: LocalTime(hour: 5, minute: 30),
                      kind: .waypoint)
        let s2 = Stop(place: p, dayIndex: 1, session: .night)
        return Trip(name: "Utah", startDay: LocalDay(year: 2026, month: 10, day: 5), dayCount: 0, stops: [s1, s2], notes: "n",
                    transferTimings: [1: .eveningBefore], folderID: UUID(), sortOrder: 3, isPinned: true,
                    pinnedAt: Date(timeIntervalSince1970: 9), createdAt: Date(timeIntervalSince1970: 1),
                    updatedAt: Date(timeIntervalSince1970: 2), startPlaceID: UUID())
    }

    @Test func helpers() {
        let t = trip()
        #expect(t.dayCount == 1)
        #expect(t.transferTiming(intoDay: 0) == .morning && t.transferTiming(intoDay: 1) == .eveningBefore && t.transferTiming(intoDay: 2) == .morning)
        #expect(t.stops(onDay: 1).count == 1)
        #expect(t.day(2).iso == "2026-10-07")
        #expect(t.timeZonePolicy == .spot)
    }

    @Test func codableRoundTrip() throws {
        let t = trip()
        #expect(try roundTrip(t) == t)
        let s = t.stops[0]
        #expect(try roundTrip(s) == s)
    }

    @Test func decodesWithNewKeysMissing() throws {
        let p = try String(decoding: JSONEncoder().encode(place()), as: UTF8.self)
        let stop = """
        {"id":"22222222-2222-2222-2222-222222222222","place":\(p),"dayIndex":0,"session":"night","setUpBufferMinutes":15,"note":"x"}
        """
        let s = try JSONDecoder().decode(Stop.self, from: Data(stop.utf8))
        #expect(s.driveNote == "" && s.dwellMinutes == 0 && s.fixedArrival == nil && s.kind == .light && s.setUpBufferMinutes == 15)
        let trip = """
        {"id":"33333333-3333-3333-3333-333333333333","name":"T","startDay":{"year":2026,"month":1,"day":2},"dayCount":2,
         "stops":[\(stop)],"notes":""}
        """
        let t = try JSONDecoder().decode(Trip.self, from: Data(trip.utf8))
        #expect(t.transferTimings.isEmpty && t.startPlaceID == nil && t.timeZonePolicy == .spot && !t.isPinned && t.folderID == nil)
        #expect(t.stops.count == 1)
    }
}

@Suite struct FolderTests {
    @Test func roundTripAndDefaults() throws {
        let f = Folder(name: "Utah", kind: .locations, sortOrder: 1, createdAt: Date(timeIntervalSince1970: 3),
                       updatedAt: Date(timeIntervalSince1970: 4), isPinned: true, pinnedAt: Date(timeIntervalSince1970: 5))
        #expect(try roundTrip(f) == f)
        let min = try JSONDecoder().decode(Folder.self, from: Data(#"{"id":"44444444-4444-4444-4444-444444444444","name":"A"}"#.utf8))
        #expect(min.kind == .trips && !min.isPinned && min.sortOrder == 0)
    }
}

@Suite struct DrivingTests {
    @Test func estimateIsLabelled() {
        let a = Coordinate(latitude: 0, longitude: 0), b = Coordinate(latitude: 0, longitude: 1)
        let leg = Leg.estimate(from: a, to: b)
        #expect(leg.isEstimate && leg.path == [a, b])
        #expect(abs(leg.meters - a.distance(to: b) * 1.3) < 1e-6)
        #expect(abs(leg.seconds - leg.meters / (70_000.0 / 3600.0)) < 1e-6)
        let route = Route(legs: [leg, Leg(from: b, to: a, seconds: 10, meters: 20, isEstimate: false)])
        #expect(route.isEstimate && route.seconds == leg.seconds + 10 && route.meters == leg.meters + 20)
    }
}

@Suite struct ProvenanceTests {
    private let prov = Provenance(source: "open-meteo", fetchedAt: Date(timeIntervalSince1970: 100), licence: LicenceTag(key: "cc-by", mayStore: true))

    @Test func sourceTierOrdering() {
        #expect(SourceTier.military < .government && SourceTier.government < .openData && SourceTier.openData < .userKey
                && SourceTier.userKey < .device)
        #expect(SourceTier.allCases.sorted() == SourceTier.allCases)
        #expect(SourceTier.military.rawValue == 0 && SourceTier.device.rawValue == 4)
    }

    @Test func sourceIDEncodesAsAString() throws {
        let data = try JSONEncoder().encode(["a": SourceID("apple.mapkit")])
        #expect(String(decoding: data, as: UTF8.self) == #"{"a":"apple.mapkit"}"#)
        #expect(SourceID(rawValue: "x") == "x")
    }

    @Test func dataStateHelpers() throws {
        let fresh = DataState.fresh(Sourced(value: 42, provenance: prov))
        let stale = DataState.stale(Sourced(value: 7, provenance: prov), age: .seconds(3600))
        let none = DataState<Int>.none([.outsideCoverage, .needsKey("k")])
        #expect(fresh.value == 42 && fresh.isFresh && fresh.provenance == prov)
        #expect(stale.value == 7 && !stale.isFresh && stale.isStale)
        #expect(none.value == nil && none.provenance == nil && !none.isFresh && none.reasons.count == 2)
        for s in [fresh, stale, none] { #expect(try roundTrip(s) == s) }
        #expect(fresh != stale)
        #expect(Set([fresh, fresh, none]).count == 2)
    }

    @Test func noDataReasonCodable() throws {
        for r in [NoDataReason.outsideCoverage, .needsKey("k"), .offline(lastGood: Date(timeIntervalSince1970: 1)), .rateLimited(retryAfter: nil),
                  .sourceError("s", "boom"), .notProvidedBySource, .appleIntelligenceUnavailable] {
            #expect(try roundTrip(r) == r)
        }
    }
}

@Suite struct WeatherTests {
    @Test func hourlyFieldsAreOptionalAndIndexable() {
        let h = HourlyConditions(time: Date(timeIntervalSince1970: 0), cloudLow: 0.2, windMs: 4)
        #expect(h.cloudTotal == nil && h[.cloudLow] == 0.2 && h[.windMs] == 4)
        #expect(Set(h.presentFields) == [.cloudLow, .windMs])
        #expect(HourlyField.allCases.count == 17)
    }

    @Test func seriesKeepsPerFieldSources() throws {
        let t0 = Date(timeIntervalSince1970: 3600 * 10)
        let s = HourlySeries(hours: [HourlyConditions(time: t0, cloudTotal: 0.5), HourlyConditions(time: t0.addingTimeInterval(3600), smokeUgm3: 9)],
                             fieldSources: [.cloudTotal: "open-meteo", .smokeUgm3: "cams"])
        #expect(s.source(of: .smokeUgm3) == "cams" && s.source(of: .pm25) == nil)
        #expect(try roundTrip(s) == s)
        #expect(s.hour(at: t0.addingTimeInterval(1800))?.cloudTotal == 0.5)
        #expect(s.hour(at: t0.addingTimeInterval(3601))?.smokeUgm3 == 9)
        #expect(s.hour(at: t0.addingTimeInterval(-1)) == nil)
    }

    @Test func skyInputsRoundTrip() throws {
        let now = Date(timeIntervalSince1970: 500)
        let inputs = SkyInputs(coordinate: Coordinate(latitude: 1, longitude: 2), hourly: HourlySeries(hours: [HourlyConditions(time: now)]),
                               observation: WeatherObservation(time: now, stationName: "KXYZ"), nowcast: [NowcastStep(time: now, precipMmPerHour: 1)],
                               horizon: .flat, bortle: 3)
        #expect(try roundTrip(inputs) == inputs)
    }

    @Test func horizonLookupInterpolatesAndWraps() {
        var e = Array(repeating: 0.0, count: 72)
        e[0] = 10; e[71] = 20; e[1] = 0
        let h = HorizonProfile(elevationsDegrees: e)
        #expect(h.elevation(atAzimuth: 0) == 10)
        #expect(h.elevation(atAzimuth: 360) == 10 && h.elevation(atAzimuth: 720) == 10)
        #expect(h.elevation(atAzimuth: 355) == 20)
        #expect(h.elevation(atAzimuth: -5) == 20)
        // Between the last sample (355°, 20) and the first (360° = 0°, 10): halfway is 15.
        #expect(abs(h.elevation(atAzimuth: 357.5) - 15) < 1e-9)
        #expect(abs(h.elevation(atAzimuth: 2.5) - 5) < 1e-9)
        #expect(h.isVisible(altitude: 12, azimuth: 0) && !h.isVisible(altitude: 5, azimuth: 0))
        #expect(HorizonProfile(elevationsDegrees: []).elevation(atAzimuth: 90) == 0)
        #expect(HorizonProfile.flat.elevationsDegrees.count == 72)
    }
}

@Suite struct DiscoveryValueTests {
    @Test func candidateRoundTripAndMissingKeys() throws {
        let c = PlaceCandidate(name: "Delicate Arch", coordinate: Coordinate(latitude: 38.74, longitude: -109.5), elevationMeters: 1500,
                               featureKinds: [.arch], source: "osm", externalID: "node/1", citations: [
                                   Citation(source: "osm", title: "OSM", retrievedAt: Date(timeIntervalSince1970: 1))], mentionCount: 4, snippet: "s")
        #expect(try roundTrip(c) == c)
        #expect(c.id == "osm:node/1")
        let min = try JSONDecoder().decode(PlaceCandidate.self, from: Data(#"{"name":"X","source":"osm"}"#.utf8))
        #expect(min.coordinate == nil && min.featureKinds.isEmpty && min.mentionCount == 0 && min.id == "osm:X@none")
    }
}
