import Foundation
import Testing
import IterModel
@testable import IterStore

private func fullPlace(_ n: UInt8) -> Place {
    Place(id: uuid(n), curatedID: "slug-\(n)", externalID: "ext-\(n)", name: "Full \(n) 北極", locality: "Utah, US",
          coordinate: Coordinate(latitude: 38.7436, longitude: -109.4993), timeZoneIdentifier: "America/Denver",
          category: .astro, bestLight: [.night, .sunset], facing: 110, blurb: "blurb", notes: "notes\nline",
          walkInMinutes: 50, elevationMeters: 1480.5, popularity: 94, tags: ["a", "b"], origin: .scout, isSaved: true,
          folderID: uuid(77), sortOrder: 2.5, isPinned: true, pinnedAt: at(10), createdAt: at(1), updatedAt: at(20),
          sources: ["osm", "wikipedia"],
          citations: [Citation(source: "wikipedia", url: URL(string: "https://example.org/x"), title: "X", retrievedAt: at(3),
                               licence: LicenceTag(key: "cc-by-sa", mayStore: true)),
                      Citation(source: "osm", title: "No url", retrievedAt: at(4))],
          verification: .confirmed, discoveredAt: at(2),
          horizon: HorizonProfile(azimuthStepDegrees: 10, elevationsDegrees: (0..<36).map { Double($0) / 4 }))
}

private func fullTrip() -> Trip {
    let a = fullPlace(1), b = samplePlace(2)
    return Trip(id: uuid(50), name: "Full trip", startDay: LocalDay(year: 2026, month: 11, day: 21), dayCount: 3,
                stops: [
                    Stop(id: uuid(60), place: a, dayIndex: 0, session: .goldenEvening, setUpBufferMinutes: 35, note: "n",
                         driveNote: "d", dwellMinutes: 90, fixedArrival: LocalTime(hour: 7, minute: 5), kind: .lodging),
                    Stop(id: uuid(61), place: b, dayIndex: 2, session: .night, kind: .waypoint),
                    Stop(id: uuid(62), place: a, dayIndex: 2, session: .blueMorning),
                ], notes: "trip notes", transferTimings: [2: .eveningBefore], folderID: uuid(70), sortOrder: 3,
                isPinned: true, pinnedAt: at(8), createdAt: at(1), updatedAt: at(30), startPlaceID: uuid(2),
                timeZonePolicy: .spot)
}

@Suite("ITERFileV2")
struct ITERFileV2Tests {
    @Test func tripRoundTrip() throws {
        let trip = fullTrip()
        let file = ITERFileV2.trip(trip, exportedAt: Date(timeIntervalSince1970: 1_800_000_000.7))
        let data = try file.encoded()
        let back = try ITERFileV2.decode(data)
        #expect(back == file)
        #expect(back.kind == .trip && back.formatVersion == 2)
        #expect(back.trips == [trip])
        #expect(back.exportedAt == Date(timeIntervalSince1970: 1_800_000_000.7))
        #expect(back.places.map(\.id) == [uuid(1), uuid(2)], "trip places are carried, deduplicated")
        #expect(try back.encoded() == data, "encoding is stable")
    }

    @Test func libraryRoundTrip() throws {
        let folder = Folder(id: uuid(70), name: "Fall 🍂", kind: .trips, sortOrder: 1, createdAt: at(1), updatedAt: at(2),
                            isPinned: true, pinnedAt: at(3))
        let lone = fullPlace(9)
        let tombstones = [LibraryTombstone(entity: .trip, id: uuid(80), deletedAt: at(40)),
                          LibraryTombstone(entity: .place, id: uuid(81), deletedAt: at(41)),
                          LibraryTombstone(entity: .folder, id: uuid(82), deletedAt: at(42))]
        let file = ITERFileV2.library(trips: [fullTrip(), sampleTrip(3)], places: [lone, fullPlace(1)], folders: [folder],
                                      tombstones: tombstones, exportedAt: at(99))
        let back = try ITERFileV2.decode(file.encoded())
        #expect(back == file)
        #expect(back.kind == .library)
        #expect(back.trips == [fullTrip(), sampleTrip(3)])
        #expect(back.places == [lone, fullPlace(1), samplePlace(2)])
        #expect(back.folders == [folder])
        #expect(back.tombstones == tombstones)
    }

    @Test func subSecondDatesRoundTripExactly() throws {
        func ms(_ n: Int) -> Date { Date(timeIntervalSince1970: 1_800_000_000 + Double(n) / 1000) }
        var place = samplePlace(1)
        place.createdAt = ms(123); place.updatedAt = ms(456); place.pinnedAt = ms(789); place.discoveredAt = ms(1)
        var trip = sampleTrip(2)
        trip.createdAt = ms(5_007); trip.updatedAt = ms(5_999); trip.pinnedAt = ms(12_345)
        let folder = Folder(id: uuid(5), name: "F", createdAt: ms(1), updatedAt: ms(2), pinnedAt: ms(3))
        let tomb = LibraryTombstone(entity: .trip, id: uuid(9), deletedAt: ms(31_415))
        let file = ITERFileV2.library(trips: [trip], places: [place], folders: [folder], tombstones: [tomb], exportedAt: ms(42))
        let data = try file.encoded()
        #expect(String(decoding: data, as: UTF8.self).contains(".456Z"))
        let back = try ITERFileV2.decode(data)
        // Exact Double equality is not promised through ISO text; the bound is one millisecond, so compare the
        // integer millisecond of each date.
        func milli(_ d: Date?) -> Int? { d.map { Int(($0.timeIntervalSince1970 * 1000).rounded()) } }
        let (p, t, f, k) = (back.places[0], back.trips[0], back.folders[0], back.tombstones[0])
        #expect([milli(p.createdAt), milli(p.updatedAt), milli(p.pinnedAt), milli(p.discoveredAt)]
                == [milli(place.createdAt), milli(place.updatedAt), milli(place.pinnedAt), milli(place.discoveredAt)])
        #expect([milli(t.createdAt), milli(t.updatedAt), milli(t.pinnedAt)]
                == [milli(trip.createdAt), milli(trip.updatedAt), milli(trip.pinnedAt)])
        #expect([milli(f.createdAt), milli(f.updatedAt), milli(f.pinnedAt)]
                == [milli(folder.createdAt), milli(folder.updatedAt), milli(folder.pinnedAt)])
        #expect(milli(k.deletedAt) == milli(tomb.deletedAt))
        #expect(milli(back.exportedAt) == milli(ms(42)))
        // A decoded file re-encodes to the same bytes, and re-decodes to equal values.
        #expect(try back.encoded() == data)
        #expect(try ITERFileV2.decode(back.encoded()) == back)
    }

    @Test func wholeSecondDatesStillDecode() throws {
        let json = #"{"formatVersion": 2, "exportedAt": "2026-01-01T00:00:00Z", "folders": [{"id": "\#(uuid(1).uuidString)", "name": "F", "updatedAt": "2026-01-01T00:00:01.250Z"}]}"#
        let file = try ITERFileV2.decode(Data(json.utf8))
        #expect(file.exportedAt == Date(timeIntervalSince1970: 1_767_225_600))
        #expect(file.folders[0].updatedAt == Date(timeIntervalSince1970: 1_767_225_601.25))
    }

    @Test func everyPlaceFieldSurvives() throws {
        let place = fullPlace(4)
        let back = try ITERFileV2.decode(ITERFileV2.library(trips: [], places: [place], folders: [], tombstones: [],
                                                            exportedAt: at(0)).encoded())
        #expect(back.places == [place])
        #expect(back.places[0].horizon?.elevationsDegrees.count == 36)
        #expect(back.places[0].citations[0].licence == LicenceTag(key: "cc-by-sa", mayStore: true))
    }

    @Test func newerDuplicatePlaceWins() {
        let older = samplePlace(1, updated: 5, name: "Old"), newer = samplePlace(1, updated: 9, name: "New")
        let trip = sampleTrip(1, places: [older])
        let file = ITERFileV2.library(trips: [trip], places: [newer], folders: [], tombstones: [], exportedAt: at(0))
        #expect(file.places == [newer])
    }

    @Test func toleratesUnknownAndMissingKeys() throws {
        let json = """
        {"formatVersion": 2, "futureThing": [1,2], "kind": "library",
         "trips": [{"id": "\(uuid(1).uuidString)", "name": "T", "startDay": "2026-11-21", "extra": true,
                    "stops": [{"id": "\(uuid(3).uuidString)", "placeID": "\(uuid(2).uuidString)", "dayIndex": 0,
                               "session": "night", "unknown": 1}]}],
         "places": [{"id": "\(uuid(2).uuidString)", "name": "P", "timeZoneIdentifier": "UTC", "category": "coast",
                     "coordinate": {"latitude": 1, "longitude": 2, "altitude": 3}}]}
        """
        let file = try ITERFileV2.decode(Data(json.utf8))
        let trip = try #require(file.trips.first)
        #expect(trip.dayCount == 1 && trip.notes == "" && trip.updatedAt == .distantPast && trip.timeZonePolicy == .spot)
        #expect(trip.stops[0].setUpBufferMinutes == 20 && trip.stops[0].kind == .light && trip.stops[0].dwellMinutes == 0)
        #expect(file.places[0].popularity == 50 && file.places[0].origin == .user && file.places[0].sources.isEmpty)
        #expect(file.tombstones.isEmpty && file.folders.isEmpty)
    }

    @Test func unknownTombstoneEntityIsDropped() throws {
        let json = """
        {"formatVersion": 2, "tombstones": [{"entity": "gizmo", "id": "\(uuid(1).uuidString)", "deletedAt": "2026-01-01T00:00:00Z"},
                                            {"entity": "trip", "id": "\(uuid(2).uuidString)", "deletedAt": "2026-01-01T00:00:00Z"}]}
        """
        let file = try ITERFileV2.decode(Data(json.utf8))
        #expect(file.tombstones.map(\.entity) == [.trip])
    }

    @Test func missingPlaceReferenceIsCorrupt() {
        let json = """
        {"formatVersion": 2, "trips": [{"id": "\(uuid(1).uuidString)", "name": "T", "startDay": "2026-11-21",
          "stops": [{"id": "\(uuid(3).uuidString)", "placeID": "\(uuid(2).uuidString)", "dayIndex": 0, "session": "night"}]}]}
        """
        #expect(throws: ITERFileError.corrupt) { try ITERFileV2.decode(Data(json.utf8)) }
    }

    @Test func badStartDayAndGarbageAreCorrupt() {
        #expect(throws: ITERFileError.corrupt) { try ITERFileV2.decode(Data("nope".utf8)) }
        let json = #"{"formatVersion": 2, "trips": [{"id": "\#(uuid(1).uuidString)", "name": "T", "startDay": "2026-02-30"}]}"#
        #expect(throws: ITERFileError.corrupt) { try ITERFileV2.decode(Data(json.utf8)) }
    }

    @Test func dispatch() throws {
        let v2 = try ITERFileV2.trip(sampleTrip(1), exportedAt: at(0)).encoded()
        guard case .v2 = try ITERFile.read(v2) else { Issue.record("expected v2"); return }
        let v1 = try ITERFileV1(trip: sampleTrip(1), exportedAt: at(0)).encoded()
        guard case .v1(let file) = try ITERFile.read(v1) else { Issue.record("expected v1"); return }
        #expect(file.plan.name == "Trip 1")
        #expect(throws: ITERFileError.unsupportedVersion(3)) { try ITERFile.read(Data(#"{"formatVersion": 3}"#.utf8)) }
        #expect(throws: ITERFileError.unsupportedVersion(0)) { try ITERFile.read(Data(#"{"formatVersion": 0}"#.utf8)) }
        #expect(throws: ITERFileError.corrupt) { try ITERFile.read(Data("{}".utf8)) }
    }

    @Test func v1FileFromOldFixturesReadsThroughDispatch() throws {
        for url in DocFixtures.files() {
            guard case .v1 = try ITERFile.read(Data(contentsOf: url)) else { Issue.record("not v1: \(url.lastPathComponent)"); continue }
        }
    }
}
