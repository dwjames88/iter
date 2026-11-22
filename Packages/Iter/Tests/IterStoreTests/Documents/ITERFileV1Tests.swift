import Foundation
import Testing
import UniformTypeIdentifiers
import IterModel
@testable import IterStore

@Suite("ITERFileV1")
struct ITERFileV1Tests {
    @Test func fixturesExist() {
        #expect(DocFixtures.documentsFolder != nil, "Fixtures/documents is missing from the test bundle")
        #expect(DocFixtures.files().count >= 4, "expected the 4 old-encoder documents under Fixtures/documents")
        #expect(DocFixtures.files(in: "older-shape").count >= 2, "Fixtures/documents/older-shape is missing or empty")
    }

    @Test(arguments: DocFixtures.files())
    func byteIdenticalReencode(url: URL) throws {
        let original = try Data(contentsOf: url)
        let file = try ITERFileV1.decode(original)
        #expect(try file.encoded() == original, "re-encode differs for \(url.lastPathComponent)")

        // decode -> model -> v1 -> encode loses nothing v1 carries.
        let trip = file.trip(makeID: IDSequence().make)
        let viaModel = ITERFileV1(trip: trip, exportedAt: file.exportedAt)
        #expect(try viaModel.encoded() == original, "model round trip differs for \(url.lastPathComponent)")
    }

    /// Older files lack keys the encoder always writes, so they are not byte-identical; they must decode with empty values
    /// and then reach a fixed point (re-encoded once, they are stable and survive the model round trip).
    @Test(arguments: DocFixtures.files(in: "older-shape"))
    func olderShapeReachesAFixedPoint(url: URL) throws {
        let file = try ITERFileV1.decode(Data(contentsOf: url))
        let once = try file.encoded()
        #expect(try ITERFileV1.decode(once).encoded() == once)
        let viaModel = ITERFileV1(trip: file.trip(makeID: IDSequence().make), exportedAt: file.exportedAt)
        #expect(try viaModel.encoded() == once)
    }

    @Test func olderShapeDecodesWithEmptyValues() throws {
        let files = DocFixtures.files(in: "older-shape")
        try #require(!files.isEmpty, "Fixtures/documents/older-shape is missing or empty")
        for url in files {
            let file = try ITERFileV1.decode(Data(contentsOf: url))
            #expect(file.plan.transferTimings.isEmpty, "\(url.lastPathComponent)")
            #expect(file.plan.stops.allSatisfy { $0.driveNote.isEmpty })
        }
    }

    @Test func fixtureContentMapsToModel() throws {
        let url = try #require(DocFixtures.files().first { $0.lastPathComponent.hasPrefix("Utah") })
        let trip = try ITERFileV1.decode(Data(contentsOf: url)).trip(makeID: IDSequence().make)
        let place = try #require(trip.stops.first?.place)
        #expect(place.curatedID == "delicate-arch")
        #expect(place.id == IDSequence(start: 1).make())
        #expect(!place.isSaved)
        #expect(place.legacySpotID == "delicate-arch")
    }

    @Test func rejectsOtherVersions() throws {
        let data = Data(#"{"formatVersion": 99, "exportedAt": "2026-01-01T00:00:00Z"}"#.utf8)
        #expect(throws: ITERFileError.unsupportedVersion(99)) { try ITERFileV1.decode(data) }
    }

    @Test func rejectsGarbage() {
        #expect(throws: ITERFileError.corrupt) { try ITERFileV1.decode(Data("not json".utf8)) }
        #expect(throws: ITERFileError.corrupt) { try ITERFileV1.decode(Data(#"{"formatVersion": 1}"#.utf8)) }
        #expect(throws: ITERFileError.corrupt) { try ITERFileV1.decode(Data()) }
    }

    @Test func v2FileIsUnsupportedForV1() throws {
        let v2 = try ITERFileV2.trip(sampleTrip(1), exportedAt: at(0)).encoded()
        #expect(throws: ITERFileError.unsupportedVersion(2)) { try ITERFileV1.decode(v2) }
    }

    @Test func dayCountClampedAndTolerantFields() throws {
        let json = """
        {"formatVersion":1,"exportedAt":"2026-01-01T00:00:00Z","trip":{"id":"\(uuid(1).uuidString)","name":"T",
         "startDay":{"year":2026,"month":1,"day":2},"dayCount":0,"stops":[],"notes":""}}
        """
        let file = try ITERFileV1.decode(Data(json.utf8))
        #expect(file.plan.dayCount == 1)
        #expect(file.plan.transferTimings.isEmpty)
    }

    @Test func importMappingRules() {
        func spot(_ id: String, _ origin: PlaceOrigin) -> ITERFileV1.SpotDTO {
            ITERFileV1.SpotDTO(id: id, name: id, locality: "", coordinate: Coordinate(latitude: 1, longitude: 2),
                               timeZoneIdentifier: "UTC", category: .coast, bestLight: [], facing: nil, blurb: "", notes: "",
                               walkInMinutes: nil, elevationMeters: nil, popularity: 50, tags: [], origin: origin)
        }
        let keep = uuid(9)
        let dto = ITERFileV1.TripDTO(id: uuid(1), name: "T", startDay: LocalDay(year: 2026, month: 1, day: 1), dayCount: 1,
                                     stops: [("slug", PlaceOrigin.curated), (keep.uuidString, .user), ("mk-77", .appleMaps),
                                             ("slug", .curated)].enumerated().map { i, s in
            ITERFileV1.StopDTO(id: uuid(UInt8(20 + i)), spot: spot(s.0, s.1), dayIndex: 0, session: .night,
                               setUpBufferMinutes: 20, note: "", driveNote: "")
        }, notes: "", transferTimings: [:])
        var file = ITERFileV1(trip: Trip(name: "x", startDay: LocalDay(year: 2026, month: 1, day: 1), dayCount: 1),
                              exportedAt: at(0))
        file.plan = dto
        let ids = IDSequence()
        let places = file.trip(makeID: ids.make, stamp: at(5)).stops.map(\.place)
        #expect(places[0].curatedID == "slug" && places[0].id == IDSequence(start: 1).make() && !places[0].isSaved)
        #expect(places[1].id == keep && places[1].isSaved && places[1].externalID == nil && places[1].curatedID == nil)
        #expect(places[2].externalID == "mk-77" && places[2].curatedID == nil && !places[2].isSaved)
        #expect(places[3].id == places[0].id, "the same spot id in one file is one place")
        #expect(places[0].createdAt == at(5) && places[0].updatedAt == at(5))
    }

    @Test func exportTruncatesToWholeSeconds() throws {
        let file = ITERFileV1(trip: sampleTrip(1), exportedAt: Date(timeIntervalSince1970: 1_800_000_000.9))
        #expect(file.exportedAt == Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test func fileNames() {
        #expect(ITERFileInfo.suggestedFileName(forTripNamed: "Utah / Arches: Day trip?") == "Utah Arches Day trip.iter")
        #expect(ITERFileInfo.suggestedFileName(forTripNamed: " .. ") == "Trip.iter")
    }

    @Test func utType() {
        #expect(UTType.iterTrip.identifier == "com.dwjames.iter.trip")
    }
}

@Suite("Fixture folders")
struct FixtureFolderTests {
    @Test func olderShapeFolderIsNotEmpty() {
        #expect(!DocFixtures.files(in: "older-shape").isEmpty, "Fixtures/documents/older-shape is missing or empty")
    }
}
