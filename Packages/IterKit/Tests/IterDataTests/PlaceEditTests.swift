import Foundation
import Testing
import SwiftData
import IterCore
@testable import IterData

@MainActor
@Suite struct PlaceEditTests {
    private func mine(_ f: Fixture) -> PlaceRecord {
        f.store.createUserSpot(name: "Secret pond", locality: "Near Bishop", coordinate: Coordinate(latitude: 37.3, longitude: -118.4),
                               timeZoneIdentifier: "America/Los_Angeles", category: .landscape, bestLight: [.sunrise],
                               notes: "Gate code 1234", walkInMinutes: 15)
    }

    @Test func anOwnSpotEditsEveryFieldInOneStep() throws {
        let f = try Fixture(undoable: true)
        let place = f.act { mine(f) }
        let folder = f.act { f.store.createFolder(name: "Eastern Sierra", kind: .locations) }
        var edit = PlaceEdit(place)
        edit.name = "Pond"; edit.locality = "Bishop, CA"; edit.notes = "Gate is open"; edit.category = .coast
        edit.bestLight = [.sunset, .night]; edit.tags = ["reflection", "quiet"]; edit.walkInMinutes = nil
        edit.coordinate = Coordinate(latitude: 37.31, longitude: -118.41); edit.timeZoneIdentifier = "America/Denver"
        edit.folderID = folder.id; edit.isPinned = true
        #expect(f.act { f.store.editPlace(place, edit) })
        #expect(place.name == "Pond" && place.locality == "Bishop, CA" && place.notes == "Gate is open")
        #expect(place.category == .coast && place.bestLight == [.sunset, .night] && place.tags == ["reflection", "quiet"])
        #expect(place.walkInMinutes == nil && place.latitude == 37.31 && place.timeZoneIdentifier == "America/Denver")
        #expect(place.folder?.id == folder.id && place.isPinned && place.pinnedAt != nil)
        #expect(f.store.pinnedPlaces().map(\.id) == [place.id])
        #expect(f.store.savedPlaces(in: folder).map(\.id) == [place.id])
    }

    @Test func undoRestoresEverythingInOneStepAndRedoReapplies() throws {
        let f = try Fixture(undoable: true)
        let place = f.act { mine(f) }
        let before = PlaceEdit(place)
        var edit = before
        edit.name = "Pond"; edit.notes = "New"; edit.coordinate = Coordinate(latitude: 10, longitude: 20); edit.isPinned = true
        f.act { f.store.editPlace(place, edit) }
        f.undo.undo()
        let restored = try #require(f.store.place(id: place.id))
        #expect(PlaceEdit(restored) == before)
        #expect(!restored.isPinned && restored.pinnedAt == nil)
        f.undo.redo()
        #expect(PlaceEdit(try #require(f.store.place(id: place.id))) == edit)
    }

    @Test func anEditThatChangesNothingIsNotAnUndoStep() throws {
        let f = try Fixture(undoable: true)
        let place = f.act { mine(f) }
        let revision = f.store.revision
        f.undo.removeAllActions()
        #expect(!f.undo.canUndo)
        #expect(!f.act { f.store.editPlace(place, PlaceEdit(place)) })
        #expect(f.store.revision == revision && f.undo.undoActionName.isEmpty)
    }

    @Test func aSavedCuratedSpotKeepsYourTextButNotAnyCatalogueFact() throws {
        let f = try Fixture(undoable: true)
        let curated = f.spot("mesa-arch")
        f.act { f.store.setSaved(curated, true) }
        let record = try #require(f.store.editableRecord(for: curated))
        var edit = PlaceEdit(record)
        edit.name = "My Arch"; edit.locality = "Moab"; edit.notes = "Bring a 24mm"; edit.isPinned = true
        // These are the catalogue's: the store leaves them alone rather than ignoring them silently in the UI.
        edit.coordinate = Coordinate(latitude: 1, longitude: 2); edit.category = .urban; edit.bestLight = [.night]
        edit.tags = ["x"]; edit.walkInMinutes = 1
        #expect(f.act { f.store.editPlace(record, edit) })
        #expect(record.name == "My Arch" && record.notes == "Bring a 24mm" && record.isPinned)
        #expect(record.coordinate == curated.coordinate && record.category == curated.category)
        #expect(record.bestLight == curated.bestLight && record.tags == curated.tags && record.walkInMinutes == curated.walkInMinutes)
        #expect(record.spot.id == "mesa-arch" && record.spot.name == "My Arch")
        #expect(f.store.current(curated).name == "My Arch")
    }

    @Test func aCuratedEditSurvivesAddingTheSpotToATrip() throws {
        let f = try Fixture()
        let curated = f.spot("mesa-arch")
        f.store.setSaved(curated, true)
        let record = try #require(f.store.editableRecord(for: curated))
        var edit = PlaceEdit(record)
        edit.name = "My Arch"; edit.notes = "Bring a 24mm"
        f.store.editPlace(record, edit)
        let trip = f.store.createTrip(name: "T", startDay: f.day, dayCount: 1)
        f.store.addStop(curated, to: trip, day: 0)
        let after = try #require(f.store.editableRecord(for: curated))
        #expect(after.name == "My Arch" && after.notes == "Bring a 24mm")
    }

    @Test func aSearchResultThatIsNotSavedIsNotEditable() throws {
        let f = try Fixture()
        let spot = Spot(id: "I63803AE6A1C5C9A1", name: "Overlook", locality: "UT", coordinate: Coordinate(latitude: 38, longitude: -110),
                        timeZoneIdentifier: "America/Denver", category: .landscape, origin: .appleMaps)
        #expect(f.store.editableRecord(for: spot) == nil)
        f.store.setSaved(spot, true)
        let record = try #require(f.store.editableRecord(for: spot))
        var edit = PlaceEdit(record)
        edit.name = "Overlook Point"; edit.coordinate = Coordinate(latitude: 38.5, longitude: -110.5)
        f.store.editPlace(record, edit)
        #expect(f.store.current(spot).name == "Overlook Point" && f.store.current(spot).coordinate.latitude == 38.5)
    }

    @Test func aTripFolderCannotHoldAPlace() throws {
        let f = try Fixture()
        let place = mine(f)
        let tripFolder = f.store.createFolder(name: "Trips", kind: .trips)
        var edit = PlaceEdit(place)
        edit.folderID = tripFolder.id
        #expect(!f.store.editPlace(place, edit))
        #expect(place.folder == nil)
    }

    @Test func theEditIsOnDiskInAFreshContainer() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("iter-edit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("iter.store")
        let id: UUID
        do {
            let store = IterStore(container: try IterSchema.makeContainer(url: url))
            let place = store.createUserSpot(name: "A", coordinate: Coordinate(latitude: 1, longitude: 2), timeZoneIdentifier: "UTC")
            id = place.id
            var edit = PlaceEdit(place)
            edit.name = "Edited"; edit.notes = "n"; edit.tags = ["t"]; edit.coordinate = Coordinate(latitude: 3, longitude: 4); edit.isPinned = true
            store.editPlace(place, edit)
        }
        let reopened = IterStore(container: try IterSchema.makeContainer(url: url))
        let place = try #require(reopened.place(id: id))
        #expect(place.name == "Edited" && place.notes == "n" && place.tags == ["t"] && place.latitude == 3 && place.longitude == 4 && place.isPinned)
    }
}
