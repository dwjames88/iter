import Foundation
import IterModel
import SwiftData
import Testing
@testable import IterStore

@MainActor
@Suite struct PlaceEditTests {
    private func mine(_ f: StoreFixture) -> PlaceRecord {
        f.store.places.createUserSpot(
            name: "Secret pond", locality: "Near Bishop", coordinate: Coordinate(latitude: 37.3, longitude: -118.4),
            timeZoneIdentifier: "America/Los_Angeles", category: .landscape, bestLight: [.sunrise],
            notes: "Gate code 1234", walkInMinutes: 15)
    }

    @Test func anOwnSpotEditsEveryFieldInOneStep() throws {
        let f = try StoreFixture(undoable: true)
        let place = f.act { mine(f) }
        let folder = f.act { f.store.folders.create(name: "Eastern Sierra", kind: .locations) }
        var edit = PlaceEdit(place)
        edit.name = "Pond"; edit.locality = "Bishop, CA"; edit.notes = "Gate is open"; edit.category = .coast
        edit.bestLight = [.sunset, .night]; edit.tags = ["reflection", "quiet"]; edit.walkInMinutes = nil
        edit.coordinate = Coordinate(latitude: 37.31, longitude: -118.41); edit.timeZoneIdentifier = "America/Denver"
        edit.folderID = folder.id; edit.isPinned = true
        #expect(f.act { f.store.places.editPlace(place, edit) })
        #expect(place.name == "Pond" && place.locality == "Bishop, CA" && place.notes == "Gate is open")
        #expect(place.category == .coast && place.bestLight == [.sunset, .night] && place.tags == ["reflection", "quiet"])
        #expect(place.walkInMinutes == nil && place.latitude == 37.31 && place.timeZoneIdentifier == "America/Denver")
        #expect(place.folder?.id == folder.id && place.isPinned && place.pinnedAt != nil)
        #expect(f.store.places.pinned().map(\.id) == [place.id])
        #expect(f.store.places.savedPlaces(in: folder).map(\.id) == [place.id])
    }

    @Test func undoRestoresEverythingInOneStepAndRedoReapplies() throws {
        let f = try StoreFixture(undoable: true)
        let place = f.act { mine(f) }
        let before = PlaceEdit(place)
        var edit = before
        edit.name = "Pond"; edit.notes = "New"; edit.coordinate = Coordinate(latitude: 10, longitude: 20); edit.isPinned = true
        _ = f.act { f.store.places.editPlace(place, edit) }
        f.undo.undo()
        let restored = try #require(f.store.places.place(id: place.id))
        #expect(PlaceEdit(restored) == before)
        #expect(!restored.isPinned && restored.pinnedAt == nil)
        f.undo.redo()
        #expect(PlaceEdit(try #require(f.store.places.place(id: place.id))) == edit)
    }

    @Test func anEditThatChangesNothingIsNotAnUndoStep() throws {
        let f = try StoreFixture(undoable: true)
        let place = f.act { mine(f) }
        let revision = f.store.revision
        f.undo.removeAllActions()
        #expect(!f.undo.canUndo)
        #expect(!f.act { f.store.places.editPlace(place, PlaceEdit(place)) })
        #expect(f.store.revision == revision && f.undo.undoActionName.isEmpty)
    }

    @Test func aSavedCuratedSpotKeepsYourTextButNotAnyCatalogueFact() throws {
        let f = try StoreFixture(undoable: true)
        let curated = f.spot("mesa-arch")
        f.act { f.store.places.setSaved(curated, true) }
        let record = try #require(f.store.places.editableRecord(for: curated))
        var edit = PlaceEdit(record)
        edit.name = "My Arch"; edit.locality = "Moab"; edit.notes = "Bring a 24mm"; edit.isPinned = true
        // These are the catalogue's: the store leaves them alone rather than ignoring them silently in the UI.
        edit.coordinate = Coordinate(latitude: 1, longitude: 2); edit.category = .urban; edit.bestLight = [.night]
        edit.tags = ["x"]; edit.walkInMinutes = 1
        #expect(f.act { f.store.places.editPlace(record, edit) })
        #expect(record.name == "My Arch" && record.notes == "Bring a 24mm" && record.isPinned)
        #expect(record.coordinate == curated.coordinate && record.category == curated.category)
        #expect(record.bestLight == curated.bestLight && record.tags == curated.tags && record.walkInMinutes == curated.walkInMinutes)
        #expect(record.curatedID == "mesa-arch" && record.value().name == "My Arch")
        #expect(f.store.places.current(curated).name == "My Arch")
    }

    @Test func aCuratedEditSurvivesAddingTheSpotToATrip() throws {
        let f = try StoreFixture()
        let curated = f.spot("mesa-arch")
        f.store.places.setSaved(curated, true)
        let record = try #require(f.store.places.editableRecord(for: curated))
        var edit = PlaceEdit(record)
        edit.name = "My Arch"; edit.notes = "Bring a 24mm"
        f.store.places.editPlace(record, edit)
        let trip = f.store.trips.create(name: "T", startDay: f.day, dayCount: 1)
        f.store.trips.addStop(curated, to: trip, day: 0)
        let after = try #require(f.store.places.editableRecord(for: curated))
        #expect(after.name == "My Arch" && after.notes == "Bring a 24mm")
    }

    @Test func aSearchResultThatIsNotSavedIsNotEditable() throws {
        let f = try StoreFixture()
        let spot = f.mapsPlace()
        #expect(f.store.places.editableRecord(for: spot) == nil)
        f.store.places.setSaved(spot, true)
        let record = try #require(f.store.places.editableRecord(for: spot))
        var edit = PlaceEdit(record)
        edit.name = "Overlook Point"; edit.coordinate = Coordinate(latitude: 38.5, longitude: -110.5)
        f.store.places.editPlace(record, edit)
        #expect(f.store.places.current(spot).name == "Overlook Point" && f.store.places.current(spot).coordinate.latitude == 38.5)
    }

    @Test func aTripFolderCannotHoldAPlace() throws {
        let f = try StoreFixture()
        let place = mine(f)
        let tripFolder = f.store.folders.create(name: "Trips", kind: .trips)
        var edit = PlaceEdit(place)
        edit.folderID = tripFolder.id
        #expect(!f.store.places.editPlace(place, edit))
        #expect(place.folder == nil)
    }

    @Test func theEditIsOnDiskInAFreshContainer() throws {
        let dir = try TestSupport.makeTempDirectory("iter-edit")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("iter.store")
        let id: UUID
        do {
            let store = LibraryStore(container: try IterStoreSchema.makeContainer(url: url))
            let place = store.places.createUserSpot(name: "A", coordinate: Coordinate(latitude: 1, longitude: 2), timeZoneIdentifier: "UTC")
            id = place.id
            var edit = PlaceEdit(place)
            edit.name = "Edited"; edit.notes = "n"; edit.tags = ["t"]; edit.coordinate = Coordinate(latitude: 3, longitude: 4); edit.isPinned = true
            store.places.editPlace(place, edit)
            store.flush()
        }
        let reopened = LibraryStore(container: try IterStoreSchema.makeContainer(url: url))
        let place = try #require(reopened.places.place(id: id))
        #expect(place.name == "Edited" && place.notes == "n" && place.tags == ["t"] && place.latitude == 3 && place.longitude == 4 && place.isPinned)
    }

    @Test func provenanceSettersWriteAndSkipNoOps() throws {
        let f = try StoreFixture()
        let place = mine(f)
        let citation = Citation(source: "osm", title: "Pond", retrievedAt: Date(timeIntervalSince1970: 1_700_000_000))
        f.store.places.setSources(place, to: ["osm", "wikidata"])
        f.store.places.setCitations(place, to: [citation])
        f.store.places.setVerification(place, to: .confirmed, discoveredAt: Date(timeIntervalSince1970: 1_700_000_100))
        f.store.places.setHorizon(place, to: HorizonProfile(azimuthStepDegrees: 45, elevationsDegrees: [0, 1, 2]))
        let value = place.value()
        #expect(value.sources == ["osm", "wikidata"] && value.citations == [citation] && value.verification == .confirmed)
        #expect(value.discoveredAt == Date(timeIntervalSince1970: 1_700_000_100) && value.horizon?.elevationsDegrees == [0, 1, 2])
        let revision = f.store.revision
        f.store.places.setSources(place, to: ["osm", "wikidata"])
        f.store.places.setVerification(place, to: .confirmed)
        #expect(f.store.revision == revision)
        f.store.places.setCitations(place, to: [])
        f.store.places.setHorizon(place, to: nil)
        f.store.places.setVerification(place, to: nil)
        #expect(place.citationsJSON == "" && place.horizonJSON == "" && place.verificationRaw == "")
    }
}

@MainActor
@Suite struct MoveSpotTests {
    private let here = Coordinate(latitude: 37.0, longitude: -118.0)
    private let there = Coordinate(latitude: 37.01, longitude: -118.02)

    @Test func movingASpotStoresExactlyTheGivenCoordinateAndUndoes() throws {
        let f = try StoreFixture(undoable: true)
        f.store.actionName = { $0.rawValue }
        let mine = f.act { f.store.places.createUserSpot(name: "Pond", coordinate: here, timeZoneIdentifier: "America/Los_Angeles") }
        f.act { f.store.places.moveSpot(mine, to: there) }
        #expect(mine.coordinate == there)
        #expect(f.undo.undoActionName == "moveSpot")
        f.undo.undo()
        #expect(mine.coordinate == here)
        f.undo.redo()
        #expect(mine.coordinate == there)
    }

    @Test func movingBySpotIDOnlyMovesYourOwn() throws {
        let f = try StoreFixture()
        let mine = f.store.places.createUserSpot(name: "Pond", coordinate: here, timeZoneIdentifier: "America/Los_Angeles")
        #expect(f.store.places.moveSpot(id: mine.id.uuidString, to: there))
        #expect(mine.coordinate == there)
        #expect(!f.store.places.moveSpot(id: "mesa-arch", to: there))
        #expect(!f.store.places.moveSpot(id: UUID().uuidString, to: there))
        f.store.places.setSaved(f.spot("mesa-arch"), true)
        let curated = try #require(f.store.places.savedPlaces().first { $0.origin == .curated })
        f.store.places.moveSpot(curated, to: there)
        #expect(curated.coordinate != there)
    }

    @Test func movingToTheSamePlaceIsNotAnEdit() throws {
        let f = try StoreFixture(undoable: true)
        let mine = f.act { f.store.places.createUserSpot(name: "Pond", coordinate: here, timeZoneIdentifier: "America/Los_Angeles") }
        let revision = f.store.revision
        f.act { f.store.places.moveSpot(mine, to: here) }
        #expect(f.store.revision == revision)
    }
}
