import Foundation
import IterModel
import SwiftData
import Testing
@testable import IterStore

/// Everything the folder features can change, as comparable strings.
@MainActor
private func dump(_ f: StoreFixture) -> [String] {
    let context = f.store.context
    let folders = ((try? context.fetch(FetchDescriptor<FolderRecord>())) ?? []).map {
        "F \($0.id) \($0.name) \($0.kindRaw) \($0.sortOrder) pinned=\($0.isPinned) at=\($0.pinnedAt != nil)"
    }
    let trips = ((try? context.fetch(FetchDescriptor<TripRecord>())) ?? []).map {
        "T \($0.id) \($0.name) folder=\($0.folder?.id.uuidString ?? "-") \($0.sortOrder) pinned=\($0.isPinned) at=\($0.pinnedAt != nil)"
    }
    let places = ((try? context.fetch(FetchDescriptor<PlaceRecord>())) ?? []).map {
        "P \($0.id) \($0.name) folder=\($0.folder?.id.uuidString ?? "-") \($0.sortOrder) saved=\($0.isSaved) pinned=\($0.isPinned) at=\($0.pinnedAt != nil)"
    }
    return (folders + trips + places).sorted()
}

@MainActor
@Suite struct FolderRepositoryTests {
    @Test func createRenameAndOrder() throws {
        let f = try StoreFixture()
        let b = f.store.folders.create(name: "B", kind: .trips)
        let a = f.store.folders.create(name: "A", kind: .trips)
        let loc = f.store.folders.create(name: "Loc", kind: .locations)
        // Appended in creation order (sort order), not alphabetical.
        #expect(f.store.folders.list(kind: .trips).map(\.name) == ["B", "A"])
        #expect(f.store.folders.list(kind: .locations).map(\.name) == ["Loc"])
        f.store.folders.rename(a, to: "Z")
        #expect(f.store.folders.folder(id: a.id)?.name == "Z")
        #expect(f.store.folders.folder(id: loc.id)?.kind == .locations)
        #expect(f.store.folders.value(id: b.id)?.name == "B")
    }

    @Test func equalSortOrderFallsBackToName() throws {
        let f = try StoreFixture()
        let b = f.store.folders.create(name: "b", kind: .trips)
        let a = f.store.folders.create(name: "a", kind: .trips)
        b.sortOrder = 0
        a.sortOrder = 0
        #expect(f.store.folders.list(kind: .trips).map(\.name) == ["a", "b"])
    }

    @Test func foldersAreAlwaysTopLevel() throws {
        let f = try StoreFixture()
        let a = f.store.folders.create(name: "A", kind: .trips)
        let b = f.store.folders.create(name: "B", kind: .trips, trips: [])
        let loc = f.store.folders.create(name: "L", kind: .locations)
        #expect(a.parent == nil && b.parent == nil && loc.parent == nil)
        #expect(f.store.folders.list(kind: .trips).map(\.name) == ["A", "B"])
        #expect(f.store.folders.list(kind: .locations).map(\.name) == ["L"])
    }

    @Test func moveFolderReorders() throws {
        let f = try StoreFixture()
        _ = f.store.folders.create(name: "A", kind: .trips)
        _ = f.store.folders.create(name: "B", kind: .trips)
        let c = f.store.folders.create(name: "C", kind: .trips)
        f.store.folders.move(c, index: 0)
        #expect(f.store.folders.list(kind: .trips).map(\.name) == ["C", "A", "B"])
        f.store.folders.move(c, index: nil)
        #expect(f.store.folders.list(kind: .trips).map(\.name) == ["A", "B", "C"])
        let revision = f.store.revision
        f.store.folders.move(c, index: nil)   // already last: no-op
        #expect(f.store.revision == revision)
    }

    @Test func deleteMovesContentsToUnfiled() throws {
        let f = try StoreFixture()
        let doomed = f.store.folders.create(name: "Doomed", kind: .trips)
        _ = f.store.folders.create(name: "Keep", kind: .trips)
        let t1 = f.ownTrip("t1"), t2 = f.ownTrip("t2")
        _ = f.ownTrip("loose")
        f.store.folders.moveTrips([t1, t2], to: doomed, index: nil)
        f.store.folders.delete(doomed)
        #expect(f.store.folders.folder(id: doomed.id) == nil)
        #expect(f.store.folders.list(kind: .trips).map(\.name) == ["Keep"])
        #expect(f.store.trips.trips(in: nil).map(\.name) == ["loose", "t1", "t2"])
        #expect(f.count(TripRecord.self) == 3)
    }

    @Test func deleteLocationFolderKeepsPlaces() throws {
        let f = try StoreFixture()
        let root = f.store.folders.create(name: "R", kind: .locations)
        let p1 = f.ownPlace("p1"), p2 = f.ownPlace("p2")
        f.store.folders.movePlaces([p1, p2], to: root, index: nil)
        #expect(f.store.places.savedPlaces(in: root).map(\.name) == ["p1", "p2"])
        f.store.folders.delete(root)
        #expect(p1.folder == nil && p2.folder == nil)
        #expect(f.count(PlaceRecord.self) == 2)
    }

    @Test func moveTripsOrderingAndIndex() throws {
        let f = try StoreFixture()
        let folder = f.store.folders.create(name: "F", kind: .trips)
        let a = f.ownTrip("a"), b = f.ownTrip("b"), c = f.ownTrip("c"), d = f.ownTrip("d")
        // New trips come first among the unfiled ones.
        #expect(f.store.trips.trips(in: nil).map(\.name) == ["d", "c", "b", "a"])
        f.store.folders.moveTrips([a, b], to: folder, index: nil)
        #expect(f.store.trips.trips(in: folder).map(\.name) == ["a", "b"])
        #expect(f.store.trips.trips(in: nil).map(\.name) == ["d", "c"])
        // Insert before the element at index (original-list coordinates).
        f.store.folders.moveTrips([c], to: folder, index: 1)
        #expect(f.store.trips.trips(in: folder).map(\.name) == ["a", "c", "b"])
        // Reorder within the folder: move "a" to the end, then "b" to the front.
        f.store.folders.moveTrips([a], to: folder, index: 3)
        #expect(f.store.trips.trips(in: folder).map(\.name) == ["c", "b", "a"])
        f.store.folders.moveTrips([b], to: folder, index: 0)
        #expect(f.store.trips.trips(in: folder).map(\.name) == ["b", "c", "a"])
        // Multiple moved at once keep the order given; an index past the end appends.
        f.store.folders.moveTrips([a, b], to: folder, index: 99)
        #expect(f.store.trips.trips(in: folder).map(\.name) == ["c", "a", "b"])
        // Back to unfiled at a position.
        f.store.folders.moveTrips([b], to: nil, index: 0)
        #expect(f.store.trips.trips(in: nil).map(\.name) == ["b", "d"])
        #expect(b.folder == nil)
        // Duplicates in the input are ignored; moving to the same place changes nothing.
        let before = dump(f)
        f.store.folders.moveTrips([c, c], to: folder, index: 0)
        #expect(dump(f) == before)
        _ = d
    }

    @Test func moveTripsRejectsLocationFolder() throws {
        let f = try StoreFixture()
        let loc = f.store.folders.create(name: "L", kind: .locations)
        let t = f.ownTrip("t")
        f.store.folders.moveTrips([t], to: loc, index: nil)
        #expect(t.folder == nil)
        let p = f.ownPlace("p")
        let tf = f.store.folders.create(name: "T", kind: .trips)
        f.store.folders.movePlaces([p], to: tf, index: nil)
        #expect(p.folder == nil)
        // create with a mismatched selection ignores it.
        let made = f.store.folders.create(name: "X", kind: .locations, trips: [t], places: [])
        #expect(made.trips?.isEmpty ?? true)
        #expect(t.folder == nil)
    }

    @Test func movePlacesAndSavedPlacesInFolder() throws {
        let f = try StoreFixture()
        let root = f.store.folders.create(name: "R", kind: .locations)
        let other = f.store.folders.create(name: "S", kind: .locations)
        let p1 = f.ownPlace("b-place"), p2 = f.ownPlace("a-place"), p3 = f.ownPlace("c-place")
        f.store.folders.movePlaces([p1, p2, p3], to: root, index: nil)
        f.store.folders.movePlaces([p3], to: other, index: nil)
        #expect(f.store.places.savedPlaces(in: root).map(\.name) == ["b-place", "a-place"])
        #expect(f.store.places.savedPlaces(in: other).map(\.name) == ["c-place"])
        f.store.folders.movePlaces([p2], to: root, index: 0)
        #expect(f.store.places.savedPlaces(in: root).map(\.name) == ["a-place", "b-place"])
        f.store.folders.movePlaces([p1], to: nil, index: nil)
        #expect(p1.folder == nil)
        #expect(f.store.places.savedPlaces(in: root).map(\.name) == ["a-place"])
        // Unsaved non-own places are not listed.
        let curated = try #require(f.store.trips.addStop(f.spot("mesa-arch"), to: f.ownTrip("t"), day: 0).place)
        f.store.folders.movePlaces([curated], to: root, index: nil)
        #expect(!f.store.places.savedPlaces(in: root).contains { $0.id == curated.id })
    }

    @Test func pinning() throws {
        let f = try StoreFixture()
        let a = f.ownTrip("a"), b = f.ownTrip("b"), c = f.ownTrip("c")
        let folder = f.store.folders.create(name: "F", kind: .trips)
        f.store.folders.moveTrips([c], to: folder, index: nil)
        f.store.trips.setPinned(b, true)
        f.store.trips.setPinned(c, true)
        f.store.trips.setPinned(a, true)
        #expect(f.store.trips.pinned().map(\.name) == ["b", "c", "a"])
        #expect(c.folder?.id == folder.id)                              // keeps its folder
        #expect(f.store.trips.trips(in: folder).map(\.name) == ["c"])   // and is still listed in it
        #expect(b.pinnedAt != nil)
        f.store.trips.setPinned(c, false)
        #expect(c.pinnedAt == nil && !c.isPinned)
        #expect(f.store.trips.pinned().map(\.name) == ["b", "a"])
        let revision = f.store.revision
        f.store.trips.setPinned(c, false)
        #expect(f.store.revision == revision)
    }

    @Test func newAndImportedTripsComeFirstDuplicateFollowsOriginal() throws {
        let f = try StoreFixture()
        let a = f.ownTrip("a")
        let b = f.ownTrip("b")
        #expect(f.store.trips.trips(in: nil).map(\.name) == ["b", "a"])
        let file = try #require(f.store.exportV1(tripID: a.id))
        let imported = try #require(f.store.importAsCopy(.v1(file)).first)
        #expect(f.store.trips.trips(in: nil).first?.id == imported.id)
        let c = f.ownTrip("c")
        #expect(f.store.trips.trips(in: nil).first?.id == c.id)
        // Duplicate lands right after the original, in the same folder.
        let dup = f.store.trips.duplicate(a, name: "a2")
        let ids = f.store.trips.trips(in: nil).map(\.id)
        #expect(ids.firstIndex(of: dup.id) == ids.firstIndex(of: a.id)! + 1)
        let folder = f.store.folders.create(name: "F", kind: .trips)
        f.store.folders.moveTrips([a, b], to: folder, index: nil)
        let dup2 = f.store.trips.duplicate(a)
        #expect(f.store.trips.trips(in: folder).map(\.id) == [a.id, dup2.id, b.id])
        #expect(dup2.folder?.id == folder.id)
        // A trip made from a template also goes first.
        let sample = f.store.trips.create(from: TripTemplates.all[0], startDay: f.day)
        #expect(f.store.trips.trips(in: nil).first?.id == sample.id)
    }

    @Test func tripsKeepsAllTripsBehaviour() throws {
        let f = try StoreFixture()
        let a = f.ownTrip("a")
        let folder = f.store.folders.create(name: "F", kind: .trips)
        f.store.folders.moveTrips([a], to: folder, index: nil)
        _ = f.ownTrip("b")
        #expect(f.store.trips.all().count == 2)
    }

    @Test func unsaveClearsFolder() throws {
        let f = try StoreFixture()
        let spot = f.spot("mesa-arch")
        f.store.places.setSaved(spot, true)
        let folder = f.store.folders.create(name: "L", kind: .locations)
        let saved = f.store.places.savedPlaces().first!
        f.store.folders.movePlaces([saved], to: folder, index: nil)
        // Keep the place alive through a trip so unsaving does not delete it.
        f.store.trips.addStop(spot, to: f.ownTrip("t"), day: 0)
        f.store.places.setSaved(spot, false)
        let kept = f.store.places.place(id: saved.id)
        #expect(kept != nil && kept?.folder == nil && kept?.isSaved == false)
    }

    @Test func newFolderWithSelection() throws {
        let f = try StoreFixture()
        let a = f.ownTrip("a"), b = f.ownTrip("b")
        let folder = f.store.folders.create(name: "Sel", kind: .trips, trips: [a, b])
        #expect(f.store.trips.trips(in: folder).map(\.name) == ["a", "b"])
        let p = f.ownPlace("p")
        let loc = f.store.folders.create(name: "LSel", kind: .locations, places: [p])
        #expect(f.store.places.savedPlaces(in: loc).map(\.name) == ["p"])
    }

    @Test func pinFolderAndPlace() throws {
        let f = try StoreFixture()
        let a = f.store.folders.create(name: "A", kind: .locations)
        let b = f.store.folders.create(name: "B", kind: .locations)
        let t = f.store.folders.create(name: "T", kind: .trips)
        let p = f.ownPlace("p")
        #expect(f.store.folders.pinned(kind: .locations).isEmpty && f.store.places.pinned().isEmpty)
        f.store.folders.setPinned(b, true)
        f.store.folders.setPinned(a, true)
        f.store.folders.setPinned(t, true)
        f.store.places.setPinned(p, true)
        // Pin order, per kind.
        #expect(f.store.folders.pinned(kind: .locations).map(\.name) == ["B", "A"])
        #expect(f.store.folders.pinned(kind: .trips).map(\.name) == ["T"])
        #expect(f.store.places.pinned().map(\.name) == ["p"])
        f.store.folders.setPinned(b, false)
        #expect(f.store.folders.pinned(kind: .locations).map(\.name) == ["A"])
        #expect(b.pinnedAt == nil)
        // A pinned place that is no longer saved (and is not an own place) drops out.
        let saved = f.ownPlace("u")
        saved.origin = .curated
        saved.isSaved = false
        f.store.places.setPinned(saved, true)
        #expect(f.store.places.pinned().map(\.name) == ["p"])
    }

    @Test func movePlaceToFolderAndBack() throws {
        let f = try StoreFixture()
        let folder = f.store.folders.create(name: "F", kind: .locations)
        let p = f.ownPlace("p"), q = f.ownPlace("q")
        f.store.folders.movePlaces([p, q], to: folder, index: nil)
        #expect(f.store.places.savedPlaces(in: folder).count == 2)
        f.store.folders.movePlaces([p], to: nil, index: nil)
        #expect(f.store.places.savedPlaces(in: folder).map(\.name) == ["q"])
        #expect(p.folder == nil)
    }
}

@MainActor
@Suite struct FolderUndoTests {
    /// Runs `setup` (not undoable), then `change` as one undo group; checks undo restores the exact prior state,
    /// the name, and that redo re-applies.
    private func verify(_ expected: StoreAction, setup: (StoreFixture) -> Void = { _ in }, change: (StoreFixture) -> Void,
                        sourceLocation: SourceLocation = #_sourceLocation) throws {
        let f = try StoreFixture()
        setup(f)
        f.store.undoManager = f.undo
        f.store.actionName = { $0.rawValue }
        let before = dump(f)
        f.act { change(f) }
        let after = dump(f)
        #expect(after != before, sourceLocation: sourceLocation)
        #expect(f.undo.undoActionName == expected.rawValue, sourceLocation: sourceLocation)
        f.undo.undo()
        #expect(dump(f) == before, sourceLocation: sourceLocation)
        #expect(f.undo.redoActionName == expected.rawValue, sourceLocation: sourceLocation)
        f.undo.redo()
        #expect(dump(f) == after, sourceLocation: sourceLocation)
        f.undo.undo()
        #expect(dump(f) == before, sourceLocation: sourceLocation)
    }

    @Test func createFolder() throws {
        try verify(.createFolder) { f in
            _ = f.store.folders.create(name: "Root", kind: .trips)
        }
        try verify(.createFolder, setup: { f in f.store.folders.create(name: "R", kind: .trips) }) { f in
            f.store.folders.create(name: "Second", kind: .trips)
        }
    }

    @Test func newFolderWithSelection() throws {
        var ids: [UUID] = []
        try verify(.newFolderWithSelection, setup: { f in
            ids = [f.ownTrip("a").id, f.ownTrip("b").id]
        }) { f in
            f.store.folders.create(name: "S", kind: .trips, trips: ids.compactMap { f.store.trips.trip(id: $0) })
        }
        try verify(.newFolderWithSelection, setup: { f in _ = f.ownPlace("p") }) { f in
            f.store.folders.create(name: "S", kind: .locations, places: f.store.places.savedPlaces())
        }
    }

    @Test func pinUndoes() throws {
        try verify(.pinFolder, setup: { f in f.store.folders.create(name: "A", kind: .locations) }) { f in
            f.store.folders.setPinned(f.store.folders.list(kind: .locations)[0], true)
        }
        try verify(.pinPlace, setup: { f in _ = f.ownPlace("p") }) { f in
            f.store.places.setPinned(f.store.places.savedPlaces()[0], true)
        }
    }

    @Test func renameFolder() throws {
        try verify(.renameFolder, setup: { f in f.store.folders.create(name: "Old", kind: .trips) }) { f in
            f.store.folders.rename(f.store.folders.list(kind: .trips)[0], to: "New")
        }
    }

    @Test func deleteFolderWithEverything() throws {
        try verify(.deleteFolder, setup: { f in
            let root = f.store.folders.create(name: "Root", kind: .trips)
            f.store.folders.create(name: "Other", kind: .trips)
            f.store.folders.moveTrips([f.ownTrip("a"), f.ownTrip("b")], to: root, index: nil)
            _ = f.ownTrip("loose")
        }) { f in
            f.store.folders.delete(f.store.folders.list(kind: .trips)[0])
        }
        try verify(.deleteFolder, setup: { f in
            let root = f.store.folders.create(name: "R", kind: .locations)
            f.store.folders.movePlaces([f.ownPlace("p1"), f.ownPlace("p2")], to: root, index: nil)
        }) { f in
            f.store.folders.delete(f.store.folders.list(kind: .locations)[0])
        }
    }

    @Test func moveFolder() throws {
        try verify(.moveFolder, setup: { f in
            f.store.folders.create(name: "A", kind: .trips)
            f.store.folders.create(name: "B", kind: .trips)
            f.store.folders.create(name: "C", kind: .trips)
        }) { f in
            f.store.folders.move(f.store.folders.list(kind: .trips)[2], index: 0)
        }
    }

    @Test func moveTrips() throws {
        try verify(.moveTrips, setup: { f in
            let folder = f.store.folders.create(name: "F", kind: .trips)
            let a = f.ownTrip("a"), b = f.ownTrip("b")
            _ = f.ownTrip("c")
            f.store.folders.moveTrips([a, b], to: folder, index: nil)
        }) { f in
            let folder = f.store.folders.list(kind: .trips)[0]
            f.store.folders.moveTrips([f.store.trips.trips(in: nil)[0]], to: folder, index: 1)
        }
        try verify(.moveTrips, setup: { f in
            let folder = f.store.folders.create(name: "F", kind: .trips)
            f.store.folders.moveTrips([f.ownTrip("a"), f.ownTrip("b")], to: folder, index: nil)
        }) { f in
            let folder = f.store.folders.list(kind: .trips)[0]
            f.store.folders.moveTrips(Array(f.store.trips.trips(in: folder).prefix(1)), to: nil, index: nil)
        }
    }

    @Test func movePlaces() throws {
        try verify(.movePlaces, setup: { f in
            let folder = f.store.folders.create(name: "F", kind: .locations)
            f.store.folders.movePlaces([f.ownPlace("a")], to: folder, index: nil)
            _ = f.ownPlace("b")
        }) { f in
            let folder = f.store.folders.list(kind: .locations)[0]
            let b = f.store.places.savedPlaces().first { $0.folder == nil }!
            f.store.folders.movePlaces([b], to: folder, index: 0)
        }
        try verify(.movePlaces, setup: { f in
            let folder = f.store.folders.create(name: "F", kind: .locations)
            f.store.folders.movePlaces([f.ownPlace("a")], to: folder, index: nil)
        }) { f in
            f.store.folders.movePlaces(f.store.places.savedPlaces(), to: nil, index: nil)
        }
    }

    @Test func pinAndUnpin() throws {
        try verify(.pinTrip, setup: { f in _ = f.ownTrip("a") }) { f in
            f.store.trips.setPinned(f.store.trips.all()[0], true)
        }
        try verify(.unpinTrip, setup: { f in f.store.trips.setPinned(f.ownTrip("a"), true) }) { f in
            f.store.trips.setPinned(f.store.trips.all()[0], false)
        }
    }

    @Test func existingActionsRestoreFolderState() throws {
        // Unsaving clears the folder; undo puts it back.
        try verify(.setSaved, setup: { f in
            let spot = f.spot("mesa-arch")
            f.store.places.setSaved(spot, true)
            f.store.trips.addStop(spot, to: f.ownTrip("t"), day: 0)
            let folder = f.store.folders.create(name: "L", kind: .locations)
            f.store.folders.movePlaces([f.store.places.savedPlaces()[0]], to: folder, index: nil)
        }) { f in
            f.store.places.setSaved(f.spot("mesa-arch"), false)
        }
        // Deleting a filed, pinned trip and undoing restores folder, order and pin.
        try verify(.deleteTrip, setup: { f in
            let folder = f.store.folders.create(name: "F", kind: .trips)
            let a = f.ownTrip("a"), b = f.ownTrip("b")
            f.store.folders.moveTrips([a, b], to: folder, index: nil)
            f.store.trips.setPinned(a, true)
        }) { f in
            f.store.trips.delete(f.store.trips.trips(in: f.store.folders.list(kind: .trips)[0])[0])
        }
        // Duplicate renumbers siblings; undo restores their order.
        try verify(.duplicateTrip, setup: { f in
            let folder = f.store.folders.create(name: "F", kind: .trips)
            f.store.folders.moveTrips([f.ownTrip("a"), f.ownTrip("b")], to: folder, index: nil)
        }) { f in
            f.store.trips.duplicate(f.store.trips.trips(in: f.store.folders.list(kind: .trips)[0])[0])
        }
        // A new trip goes first and undo removes it.
        try verify(.createTrip, setup: { f in _ = f.ownTrip("a") }) { f in
            f.store.trips.create(name: "n", startDay: f.day, dayCount: 1)
        }
    }
}
