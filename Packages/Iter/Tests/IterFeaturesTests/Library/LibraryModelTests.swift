import Foundation
import Synchronization
import Testing
import IterModel
import IterStore
@testable import IterFeatures

@MainActor
@Suite("Library model") struct LibraryModelTests {
    let day = LocalDay(year: 2027, month: 3, day: 11)   // the day after AppContainer.testNow in Mountain time

    @Test func rowsOfTheSampleLibrary() throws {
        let f = try LibraryFixture(seed: true)
        let m = f.model
        #expect(m.trips.map(\.name).contains(SampleLibrary.tripName))
        #expect(m.trips.count == 3)
        #expect(m.nextTrip?.name == SampleLibrary.tripName)
        #expect(m.pinnedTrips.map(\.name) == [SampleLibrary.tripName])
        let canyon = try #require(m.trips.first { $0.name == SampleLibrary.tripName })
        #expect(canyon.dayCount == 4 && canyon.stopCount == 9 && canyon.endDay == canyon.startDay.adding(days: 3))
        #expect(canyon.placeNames.count == 3)
        #expect(m.tripFolders.map(\.name) == [SampleLibrary.tripFolderName] && m.tripFolders[0].count == 1)
        #expect(m.placeFolders.map(\.name) == [SampleLibrary.placeFolderName] && m.placeFolders[0].count == 3)
        #expect(m.savedPlaces.count >= 5)
        #expect(m.pinnedPlaces.map(\.curatedID) == ["mesa-arch"])
        #expect(m.pinnedTripFolders.isEmpty && m.pinnedPlaceFolders.isEmpty)
        #expect(m.trips(in: m.tripFolders[0].id).map(\.name) == [SampleLibrary.scoutingTripName])
    }

    @Test func tripsSortUpcomingFirstThenPastNewestFirst() throws {
        let f = try LibraryFixture()
        let past = f.model.createTrip(name: "Old", startDay: LocalDay(year: 2026, month: 1, day: 1), dayCount: 2)
        let later = f.model.createTrip(name: "Later", startDay: LocalDay(year: 2027, month: 6, day: 1), dayCount: 2)
        let soon = f.model.createTrip(name: "Soon", startDay: day, dayCount: 3)
        let older = f.model.createTrip(name: "Older", startDay: LocalDay(year: 2025, month: 1, day: 1), dayCount: 1)
        #expect(f.model.trips.map(\.id) == [soon, later, past, older])
        #expect(f.model.nextTrip?.id == soon)
    }

    @Test func tripActionsWithUndoAndRedo() throws {
        let f = try LibraryFixture()
        let m = f.model
        f.library.actionName = { StoreActionNames.english($0) }
        let id = m.createTrip(name: "Draft", startDay: day, dayCount: 2)
        #expect(m.trips.map(\.name) == ["Draft"])
        #expect(f.undo.undoActionName == "New Trip")

        m.renameTrip(id, to: "Utah")
        #expect(m.trips.first?.name == "Utah")
        #expect(f.undo.undoActionName == "Rename Trip")
        f.undoStep(); m.refresh()
        #expect(m.trips.first?.name == "Draft")
        f.redoStep(); m.refresh()
        #expect(m.trips.first?.name == "Utah")

        m.setTripPinned(id, true)
        #expect(m.pinnedTrips.map(\.id) == [id])
        f.undoStep(); m.refresh()
        #expect(m.pinnedTrips.isEmpty)
        f.redoStep(); m.refresh()
        #expect(m.pinnedTrips.map(\.id) == [id])

        let copy = try #require(m.duplicateTrip(id))
        #expect(m.trips.count == 2 && copy != id)
        #expect(f.undo.undoActionName == "Duplicate Trip")
        f.undoStep(); m.refresh()
        #expect(m.trips.count == 1)
        f.redoStep(); m.refresh()
        #expect(m.trips.count == 2)

        m.deleteTrip(copy)
        #expect(m.trips.count == 1)
        #expect(f.undo.undoActionName == "Delete Trip")
        f.undoStep(); m.refresh()
        #expect(m.trips.count == 2)
    }

    @Test func createFromTemplate() throws {
        let f = try LibraryFixture()
        let id = try #require(f.model.createTrip(templateID: "canyon-country", startDay: day))
        #expect(f.model.tripRow(id: id)?.dayCount == 4 && f.model.tripRow(id: id)?.stopCount == 6)
        #expect(f.model.createTrip(templateID: "nowhere", startDay: day) == nil)
        f.undoStep(); f.model.refresh()
        #expect(f.model.trips.isEmpty)
    }

    @Test func foldersAndDragMoves() throws {
        let f = try LibraryFixture()
        let m = f.model
        let a = m.createTrip(name: "A", startDay: day, dayCount: 1)
        let b = m.createTrip(name: "B", startDay: day.adding(days: 1), dayCount: 1)
        let c = m.createTrip(name: "C", startDay: day.adding(days: 2), dayCount: 1)
        let folder = m.createFolder(name: "Utah", kind: .trips, containing: [a])
        #expect(m.tripFolders.first?.count == 1 && m.tripRow(id: a)?.folderID == folder)
        // Drag two trips into the folder at the front.
        m.moveTrips([b, c], to: folder, index: 0)
        #expect(m.tripFolders.first?.count == 3)
        #expect(f.library.trips.trips(in: f.library.folders.folder(id: folder)).map(\.id) == [b, c, a])
        f.undoStep(); m.refresh()
        #expect(m.tripFolders.first?.count == 1)
        f.redoStep(); m.refresh()
        #expect(m.tripFolders.first?.count == 3)
        // Out to unfiled.
        m.moveTrips([a], to: nil)
        #expect(m.tripRow(id: a)?.folderID == nil && m.tripFolders.first?.count == 2)
        // A trip cannot go into a places folder.
        let places = m.createFolder(name: "Spots", kind: .locations)
        m.moveTrips([a], to: places)
        #expect(m.tripRow(id: a)?.folderID == nil)

        m.renameFolder(folder, to: "Utah 2027")
        #expect(m.tripFolders.first?.name == "Utah 2027")
        m.setFolderPinned(folder, true)
        #expect(m.pinnedTripFolders.map(\.id) == [folder])
        f.undoStep(); m.refresh()
        #expect(m.pinnedTripFolders.isEmpty)
        m.deleteFolder(folder)
        #expect(m.tripFolders.isEmpty && m.tripRow(id: b)?.folderID == nil && m.trips.count == 3)
        f.undoStep(); m.refresh()
        #expect(m.tripFolders.count == 1 && m.tripRow(id: b)?.folderID == folder)
    }

    @Test func placesSaveEditMovePinDelete() throws {
        let f = try LibraryFixture()
        let m = f.model
        let arch = try #require(CuratedSpots.spot(id: "delicate-arch"))
        let falls = try #require(CuratedSpots.spot(id: "multnomah-falls"))
        m.savePlace(arch); m.savePlace(falls)
        #expect(m.savedPlaces.count == 2 && m.isSaved(arch))
        f.undoStep(); m.refresh()
        #expect(m.savedPlaces.count == 1)
        f.redoStep(); m.refresh()
        #expect(m.savedPlaces.count == 2)

        let own = m.createPlace(name: "Roadside Pull-Off", coordinate: Coordinate(latitude: 38.6, longitude: -109.6), timeZoneIdentifier: "America/Denver")
        #expect(m.placeRow(id: own)?.origin == .user)
        var edit = try #require(m.placeEdit(id: own))
        #expect(m.editsFacts(id: own))
        #expect(!m.editPlace(id: own, edit))   // no change, no undo step
        edit.name = "Dawn Pull-Off"; edit.notes = "Park on the gravel."; edit.isPinned = true
        #expect(m.editPlace(id: own, edit))
        #expect(m.placeRow(id: own)?.name == "Dawn Pull-Off" && m.pinnedPlaces.map(\.id) == [own])
        f.undoStep(); m.refresh()
        #expect(m.placeRow(id: own)?.name == "Roadside Pull-Off" && m.pinnedPlaces.isEmpty)

        // A curated place's facts are the catalogue's.
        let curated = try #require(m.savedPlaces.first { $0.curatedID == "delicate-arch" })
        #expect(!m.editsFacts(id: curated.id))

        let folder = m.createFolder(name: "Arches", kind: .locations, containing: [curated.id])
        #expect(m.placeFolders.first?.count == 1)
        let other = try #require(m.savedPlaces.first { $0.curatedID == "multnomah-falls" })
        m.movePlaces([other.id, own], to: folder, index: 0)
        #expect(m.placeFolders.first?.count == 3)
        #expect(m.places(in: folder).count == 3)
        m.setPlacePinned(other.id, true)
        #expect(m.pinnedPlaces.map(\.id) == [other.id])

        m.deletePlace(own)
        #expect(m.placeRow(id: own) == nil)
        f.undoStep(); m.refresh()
        #expect(m.placeRow(id: own) != nil)
        m.unsavePlace(falls)
        #expect(m.placeRow(id: other.id) == nil)
    }

    @Test func rowsRefreshFromTheStoreWithoutAnExplicitCall() async throws {
        let f = try LibraryFixture()
        #expect(f.model.trips.isEmpty)
        f.undo.beginUndoGrouping()
        f.library.trips.create(name: "Made Elsewhere", startDay: day, dayCount: 1)   // not through the model
        f.undo.endUndoGrouping()
        await f.settle()
        #expect(f.model.trips.map(\.name) == ["Made Elsewhere"])
        f.undoStep()
        await f.settle()
        #expect(f.model.trips.isEmpty)
    }

    @Test func anUnchangedRebuildDoesNotInvalidateAReader() async throws {
        let f = try LibraryFixture()
        f.model.createTrip(name: "Stable", startDay: day, dayCount: 1)
        let fired = Mutex(0)
        withObservationTracking { _ = f.model.pinnedPlaces } onChange: { fired.withLock { $0 += 1 } }
        f.model.renameTrip(f.model.trips[0].id, to: "Renamed")   // revision moves, pinned places do not
        await f.settle()
        #expect(fired.withLock { $0 } == 0)
        withObservationTracking { _ = f.model.trips } onChange: { fired.withLock { $0 += 1 } }
        f.model.renameTrip(f.model.trips[0].id, to: "Renamed Again")
        #expect(fired.withLock { $0 } == 1)
    }

    @Test func exportRoundTripAndImportMergeAndCopy() throws {
        let source = try LibraryFixture(seed: true)
        let exported = try source.model.exportLibrary()
        #expect(exported.suggestedFileName == "Iter Library.iter")

        // Into an empty library: everything is new.
        let target = try LibraryFixture()
        let first = try target.model.importLibrary(exported.data)
        #expect(first.formatVersion == 2 && !first.asCopy && first.tripsAdded == 3 && first.foldersAdded == 2)
        #expect(target.model.trips.count == 3 && target.model.tripFolders.count == 1 && target.model.placeFolders.count == 1)
        #expect(target.model.pinnedTrips.map(\.name) == [SampleLibrary.tripName])
        target.undoStep(); target.model.refresh()
        #expect(target.model.trips.isEmpty)
        target.redoStep(); target.model.refresh()
        #expect(target.model.trips.count == 3)

        // Again: merge by id changes nothing.
        let again = try target.model.importLibrary(exported.data)
        #expect(again.isEmpty && target.model.trips.count == 3)

        // As a copy: a second set of trips.
        let copy = try target.model.importLibrary(exported.data, asCopy: true)
        #expect(copy.asCopy && copy.tripsAdded == 3)
        #expect(target.model.trips.count == 6)

        // One trip.
        let id = try #require(source.model.trips.first { $0.name == SampleLibrary.scoutingTripName }?.id)
        let one = try #require(try source.model.exportTrip(id))
        #expect(one.suggestedFileName == "Moab Recon.iter")
    }

    @Test func importsV1DocumentsAsNewTrips() throws {
        let f = try LibraryFixture()
        let dir = Fixtures.root.appending(path: "documents", directoryHint: .isDirectory)
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { $0.pathExtension == "iter" }
        #expect(files.count == 4)
        for url in files {
            let summary = try f.model.importLibrary(Data(contentsOf: url))
            #expect(summary.formatVersion == 1 && summary.asCopy && summary.tripsAdded == 1)
        }
        #expect(f.model.trips.count == 4)
        #expect(f.model.trips.map(\.name).contains("Utah / Arches: Day trip?"))
        // The same v1 file again is a second copy (no ids to merge by).
        _ = try f.model.importLibrary(Data(contentsOf: files[0]))
        #expect(f.model.trips.count == 5)
        f.undoStep(); f.model.refresh()
        #expect(f.model.trips.count == 4)
    }

    @Test func aNonIterFileThrows() throws {
        let f = try LibraryFixture()
        #expect(throws: ITERFileError.self) { try f.model.importLibrary(Data("not json".utf8)) }
        #expect(f.model.trips.isEmpty)
    }
}
