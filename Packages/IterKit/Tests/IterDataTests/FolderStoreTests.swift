import Foundation
import Testing
import SwiftData
import IterCore
@testable import IterData

@MainActor
private func place(_ f: Fixture, _ name: String) -> PlaceRecord {
    f.store.createUserSpot(name: name, coordinate: Coordinate(latitude: 38, longitude: -109), timeZoneIdentifier: "America/Denver")
}

@MainActor
private func trip(_ f: Fixture, _ name: String) -> TripRecord {
    f.store.createTrip(name: name, startDay: f.day, dayCount: 1)
}

/// Everything the folder features can change, as comparable strings.
@MainActor
private func dump(_ f: Fixture) -> [String] {
    let context = f.store.context
    let folders = ((try? context.fetch(FetchDescriptor<FolderRecord>())) ?? []).map {
        "F \($0.id) \($0.name) \($0.kindRaw) \($0.sortOrder) parent=\($0.parent?.id.uuidString ?? "-")"
    }
    let trips = ((try? context.fetch(FetchDescriptor<TripRecord>())) ?? []).map {
        "T \($0.id) \($0.name) folder=\($0.folder?.id.uuidString ?? "-") \($0.sortOrder) pinned=\($0.isPinned) at=\($0.pinnedAt != nil)"
    }
    let places = ((try? context.fetch(FetchDescriptor<PlaceRecord>())) ?? []).map {
        "P \($0.id) \($0.name) folder=\($0.folder?.id.uuidString ?? "-") \($0.sortOrder) saved=\($0.isSaved)"
    }
    return (folders + trips + places).sorted()
}

@MainActor
@Suite struct FolderTests {
    @Test func createRenameAndOrder() throws {
        let f = try Fixture()
        let b = f.store.createFolder(name: "B", kind: .trips)
        let a = f.store.createFolder(name: "A", kind: .trips)
        let loc = f.store.createFolder(name: "Loc", kind: .locations)
        // Appended in creation order (sort order), not alphabetical.
        #expect(f.store.folders(kind: .trips).map(\.name) == ["B", "A"])
        #expect(f.store.folders(kind: .locations).map(\.name) == ["Loc"])
        f.store.renameFolder(a, to: "Z")
        #expect(f.store.folder(id: a.id)?.name == "Z")
        #expect(f.store.folder(id: loc.id)?.kind == .locations)
        _ = b
    }

    @Test func equalSortOrderFallsBackToName() throws {
        let f = try Fixture()
        let b = f.store.createFolder(name: "b", kind: .trips)
        let a = f.store.createFolder(name: "a", kind: .trips)
        b.sortOrder = 0
        a.sortOrder = 0
        #expect(f.store.folders(kind: .trips).map(\.name) == ["a", "b"])
    }

    @Test func nestingLimitAndKinds() throws {
        let f = try Fixture()
        let root = f.store.createFolder(name: "Root", kind: .trips)
        let child = f.store.createFolder(name: "Child", kind: .trips, parent: root)
        #expect(child.parent?.id == root.id)
        #expect(f.store.subfolders(of: root).map(\.name) == ["Child"])
        #expect(f.store.folders(kind: .trips).map(\.name) == ["Root"])
        // A grandchild is refused: the folder becomes a root folder instead.
        let grand = f.store.createFolder(name: "Grand", kind: .trips, parent: child)
        #expect(grand.parent == nil)
        // A parent of the other kind is ignored.
        let other = f.store.createFolder(name: "Other", kind: .locations, parent: root)
        #expect(other.parent == nil)
        // Moves that break the rules are no-ops.
        let revision = f.store.revision
        f.store.moveFolder(root, to: child, index: nil)      // into its own child
        f.store.moveFolder(grand, to: child, index: nil)     // depth 2
        f.store.moveFolder(other, to: root, index: nil)      // cross kind
        f.store.moveFolder(root, to: root, index: nil)       // itself
        let withKids = f.store.createFolder(name: "WithKids", kind: .trips)
        f.store.createFolder(name: "Kid", kind: .trips, parent: withKids)
        let before = dump(f)
        f.store.moveFolder(withKids, to: root, index: nil)   // would make depth 2
        #expect(dump(f) == before)
        #expect(f.store.revision > revision)
        #expect(grand.parent == nil && other.parent == nil && root.parent == nil)
    }

    @Test func moveFolderReorderAndNest() throws {
        let f = try Fixture()
        let a = f.store.createFolder(name: "A", kind: .trips)
        let b = f.store.createFolder(name: "B", kind: .trips)
        let c = f.store.createFolder(name: "C", kind: .trips)
        f.store.moveFolder(c, to: nil, index: 0)
        #expect(f.store.folders(kind: .trips).map(\.name) == ["C", "A", "B"])
        f.store.moveFolder(c, to: nil, index: nil)
        #expect(f.store.folders(kind: .trips).map(\.name) == ["A", "B", "C"])
        f.store.moveFolder(b, to: a, index: nil)
        #expect(f.store.folders(kind: .trips).map(\.name) == ["A", "C"])
        #expect(f.store.subfolders(of: a).map(\.name) == ["B"])
        f.store.moveFolder(b, to: nil, index: 1)
        #expect(f.store.folders(kind: .trips).map(\.name) == ["A", "B", "C"])
        #expect(f.store.subfolders(of: a).isEmpty)
    }

    @Test func deleteMovesContentsUp() throws {
        let f = try Fixture()
        let root = f.store.createFolder(name: "Root", kind: .trips)
        let sub = f.store.createFolder(name: "Sub", kind: .trips, parent: root)
        let t1 = trip(f, "t1")
        let t2 = trip(f, "t2")
        let t3 = trip(f, "t3")
        f.store.moveTrips([t1], to: root, index: nil)
        f.store.moveTrips([t2, t3], to: sub, index: nil)
        f.store.deleteFolder(sub)
        #expect(f.store.folder(id: sub.id) == nil)
        #expect(f.store.trips(in: root).map(\.name) == ["t1", "t2", "t3"])
        // Deleting a root folder: subfolders become roots, trips become unfiled (after existing unfiled trips).
        let sub2 = f.store.createFolder(name: "Sub2", kind: .trips, parent: root)
        let loose = trip(f, "loose")
        f.store.deleteFolder(root)
        #expect(f.store.folders(kind: .trips).map(\.name) == ["Sub2"])
        #expect(sub2.parent == nil)
        #expect(f.store.trips(in: nil).map(\.name) == ["loose", "t1", "t2", "t3"])
        #expect(f.count(TripRecord.self) == 4)
        _ = loose
    }

    @Test func deleteLocationFolderKeepsPlaces() throws {
        let f = try Fixture()
        let root = f.store.createFolder(name: "R", kind: .locations)
        let sub = f.store.createFolder(name: "S", kind: .locations, parent: root)
        let p1 = place(f, "p1")
        let p2 = place(f, "p2")
        f.store.movePlaces([p1], to: root, index: nil)
        f.store.movePlaces([p2], to: sub, index: nil)
        f.store.deleteFolder(sub)
        #expect(f.store.savedPlaces(in: root).map(\.name) == ["p1", "p2"])
        f.store.deleteFolder(root)
        #expect(p1.folder == nil && p2.folder == nil)
        #expect(f.count(PlaceRecord.self) == 2)
    }

    @Test func moveTripsOrderingAndIndex() throws {
        let f = try Fixture()
        let folder = f.store.createFolder(name: "F", kind: .trips)
        let a = trip(f, "a"), b = trip(f, "b"), c = trip(f, "c"), d = trip(f, "d")
        // New trips come first among the unfiled ones.
        #expect(f.store.trips(in: nil).map(\.name) == ["d", "c", "b", "a"])
        f.store.moveTrips([a, b], to: folder, index: nil)
        #expect(f.store.trips(in: folder).map(\.name) == ["a", "b"])
        #expect(f.store.trips(in: nil).map(\.name) == ["d", "c"])
        // Insert before the element at index (original-list coordinates).
        f.store.moveTrips([c], to: folder, index: 1)
        #expect(f.store.trips(in: folder).map(\.name) == ["a", "c", "b"])
        // Reorder within the folder: move "a" to the end, then "b" to the front.
        f.store.moveTrips([a], to: folder, index: 3)
        #expect(f.store.trips(in: folder).map(\.name) == ["c", "b", "a"])
        f.store.moveTrips([b], to: folder, index: 0)
        #expect(f.store.trips(in: folder).map(\.name) == ["b", "c", "a"])
        // Multiple moved at once keep the order given; an index past the end appends.
        f.store.moveTrips([a, b], to: folder, index: 99)
        #expect(f.store.trips(in: folder).map(\.name) == ["c", "a", "b"])
        // Back to unfiled at a position.
        f.store.moveTrips([b], to: nil, index: 0)
        #expect(f.store.trips(in: nil).map(\.name) == ["b", "d"])
        #expect(b.folder == nil)
        // Duplicates in the input are ignored; moving to the same place changes nothing.
        let before = dump(f)
        f.store.moveTrips([c, c], to: folder, index: 0)
        #expect(dump(f) == before)
        _ = d
    }

    @Test func moveTripsRejectsLocationFolder() throws {
        let f = try Fixture()
        let loc = f.store.createFolder(name: "L", kind: .locations)
        let t = trip(f, "t")
        f.store.moveTrips([t], to: loc, index: nil)
        #expect(t.folder == nil)
        let p = place(f, "p")
        let tf = f.store.createFolder(name: "T", kind: .trips)
        f.store.movePlaces([p], to: tf, index: nil)
        #expect(p.folder == nil)
        // createFolder with a mismatched selection ignores it.
        let made = f.store.createFolder(name: "X", kind: .locations, trips: [t], places: [])
        #expect(made.trips?.isEmpty ?? true)
        #expect(t.folder == nil)
    }

    @Test func movePlacesAndSavedPlacesInFolder() throws {
        let f = try Fixture()
        let root = f.store.createFolder(name: "R", kind: .locations)
        let sub = f.store.createFolder(name: "S", kind: .locations, parent: root)
        let p1 = place(f, "b-place"), p2 = place(f, "a-place"), p3 = place(f, "c-place")
        f.store.movePlaces([p1, p2], to: root, index: nil)
        f.store.movePlaces([p3], to: sub, index: nil)
        #expect(f.store.savedPlaces(in: root).map(\.name) == ["b-place", "a-place", "c-place"])
        #expect(f.store.savedPlaces(in: sub).map(\.name) == ["c-place"])
        f.store.movePlaces([p2], to: root, index: 0)
        #expect(f.store.savedPlaces(in: root).map(\.name) == ["a-place", "b-place", "c-place"])
        f.store.movePlaces([p1], to: nil, index: nil)
        #expect(p1.folder == nil)
        #expect(f.store.savedPlaces(in: root).map(\.name) == ["a-place", "c-place"])
        // Unsaved non-user places are not listed.
        let curated = f.store.addStop(f.spot("mesa-arch"), to: trip(f, "t"), day: 0).place!
        f.store.movePlaces([curated], to: root, index: nil)
        #expect(!f.store.savedPlaces(in: root).contains { $0.id == curated.id })
    }

    @Test func pinning() throws {
        let f = try Fixture()
        let a = trip(f, "a"), b = trip(f, "b"), c = trip(f, "c")
        let folder = f.store.createFolder(name: "F", kind: .trips)
        f.store.moveTrips([c], to: folder, index: nil)
        f.store.setPinned(b, true)
        Thread.sleep(forTimeInterval: 0.01)
        f.store.setPinned(c, true)
        Thread.sleep(forTimeInterval: 0.01)
        f.store.setPinned(a, true)
        #expect(f.store.pinnedTrips().map(\.name) == ["b", "c", "a"])
        #expect(c.folder?.id == folder.id)                       // keeps its folder
        #expect(f.store.trips(in: folder).map(\.name) == ["c"])  // and is still listed in it
        #expect(b.pinnedAt != nil)
        f.store.setPinned(c, false)
        #expect(c.pinnedAt == nil && !c.isPinned)
        #expect(f.store.pinnedTrips().map(\.name) == ["b", "a"])
        let revision = f.store.revision
        f.store.setPinned(c, false)
        #expect(f.store.revision == revision)
    }

    @Test func newAndImportedTripsComeFirstDuplicateFollowsOriginal() throws {
        let f = try Fixture()
        let a = trip(f, "a")
        let b = trip(f, "b")
        #expect(f.store.trips(in: nil).map(\.name) == ["b", "a"])
        let imported = f.store.importTrip(f.store.document(for: a))
        #expect(f.store.trips(in: nil).first?.id == imported.id)
        let c = trip(f, "c")
        #expect(f.store.trips(in: nil).first?.id == c.id)
        // Duplicate lands right after the original, in the same folder.
        let dup = f.store.duplicateTrip(a, name: "a2")
        let ids = f.store.trips(in: nil).map(\.id)
        #expect(ids.firstIndex(of: dup.id) == ids.firstIndex(of: a.id)! + 1)
        let folder = f.store.createFolder(name: "F", kind: .trips)
        f.store.moveTrips([a, b], to: folder, index: nil)
        let dup2 = f.store.duplicateTrip(a)
        #expect(f.store.trips(in: folder).map(\.id) == [a.id, dup2.id, b.id])
        #expect(dup2.folder?.id == folder.id)
        // The sample trip also goes first.
        let sample = f.store.seedSampleTrip(startDay: f.day)
        #expect(f.store.trips(in: nil).first?.id == sample.id)
        _ = dup
    }

    @Test func tripsKeepsAllTripsBehaviour() throws {
        let f = try Fixture()
        let a = trip(f, "a")
        let folder = f.store.createFolder(name: "F", kind: .trips)
        f.store.moveTrips([a], to: folder, index: nil)
        _ = trip(f, "b")
        #expect(f.store.trips().count == 2)
    }

    @Test func unsaveClearsFolderAndResetClearsFolders() throws {
        let f = try Fixture()
        let spot = f.spot("mesa-arch")
        f.store.setSaved(spot, true)
        let folder = f.store.createFolder(name: "L", kind: .locations)
        let saved = f.store.savedPlaces().first!
        f.store.movePlaces([saved], to: folder, index: nil)
        // Keep the place alive through a trip so unsaving does not delete it.
        f.store.addStop(spot, to: trip(f, "t"), day: 0)
        f.store.setSaved(spot, false)
        let kept = f.store.place(id: saved.id)
        #expect(kept != nil && kept?.folder == nil && kept?.isSaved == false)
        f.store.createFolder(name: "T", kind: .trips)
        f.store.resetAllData()
        #expect(f.count(FolderRecord.self) == 0)
        #expect(f.store.folders(kind: .trips).isEmpty)
    }

    @Test func newFolderWithSelection() throws {
        let f = try Fixture()
        let a = trip(f, "a"), b = trip(f, "b")
        let folder = f.store.createFolder(name: "Sel", kind: .trips, trips: [a, b])
        #expect(f.store.trips(in: folder).map(\.name) == ["a", "b"])
        let p = place(f, "p")
        let loc = f.store.createFolder(name: "LSel", kind: .locations, places: [p])
        #expect(f.store.savedPlaces(in: loc).map(\.name) == ["p"])
    }
}

@MainActor
@Suite struct FolderUndoTests {
    /// Runs `setup` (not undoable), then `change` as one undo group; checks undo restores the exact prior state,
    /// the name, and that redo re-applies.
    private func verify(_ expected: StoreAction, setup: (Fixture) -> Void = { _ in }, change: (Fixture) -> Void,
                        sourceLocation: SourceLocation = #_sourceLocation) throws {
        let f = try Fixture()
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
            let root = f.store.createFolder(name: "Root", kind: .trips)
            _ = root
        }
        try verify(.createFolder, setup: { f in f.store.createFolder(name: "R", kind: .trips) }) { f in
            f.store.createFolder(name: "Sub", kind: .trips, parent: f.store.folders(kind: .trips)[0])
        }
    }

    @Test func newFolderWithSelection() throws {
        var ids: [UUID] = []
        try verify(.newFolderWithSelection, setup: { f in
            let a = trip(f, "a"), b = trip(f, "b")
            ids = [a.id, b.id]
        }) { f in
            f.store.createFolder(name: "S", kind: .trips, trips: ids.compactMap { f.store.trip(id: $0) })
        }
        try verify(.newFolderWithSelection, setup: { f in _ = place(f, "p") }) { f in
            f.store.createFolder(name: "S", kind: .locations, places: f.store.savedPlaces())
        }
    }

    @Test func renameFolder() throws {
        try verify(.renameFolder, setup: { f in f.store.createFolder(name: "Old", kind: .trips) }) { f in
            f.store.renameFolder(f.store.folders(kind: .trips)[0], to: "New")
        }
    }

    @Test func deleteFolderWithEverything() throws {
        try verify(.deleteFolder, setup: { f in
            let root = f.store.createFolder(name: "Root", kind: .trips)
            let sub = f.store.createFolder(name: "Sub", kind: .trips, parent: root)
            f.store.createFolder(name: "Sub2", kind: .trips, parent: root)
            let a = trip(f, "a"), b = trip(f, "b"), c = trip(f, "c")
            f.store.moveTrips([a], to: root, index: nil)
            f.store.moveTrips([b, c], to: sub, index: nil)
            _ = trip(f, "loose")
        }) { f in
            f.store.deleteFolder(f.store.folders(kind: .trips)[0])
        }
        try verify(.deleteFolder, setup: { f in
            let root = f.store.createFolder(name: "R", kind: .locations)
            let sub = f.store.createFolder(name: "S", kind: .locations, parent: root)
            f.store.movePlaces([place(f, "p1")], to: root, index: nil)
            f.store.movePlaces([place(f, "p2")], to: sub, index: nil)
        }) { f in
            f.store.deleteFolder(f.store.subfolders(of: f.store.folders(kind: .locations)[0])[0])
        }
    }

    @Test func moveFolder() throws {
        try verify(.moveFolder, setup: { f in
            f.store.createFolder(name: "A", kind: .trips)
            f.store.createFolder(name: "B", kind: .trips)
            f.store.createFolder(name: "C", kind: .trips)
        }) { f in
            let folders = f.store.folders(kind: .trips)
            f.store.moveFolder(folders[2], to: folders[0], index: nil)
        }
        try verify(.moveFolder, setup: { f in
            f.store.createFolder(name: "A", kind: .trips)
            f.store.createFolder(name: "B", kind: .trips)
        }) { f in
            f.store.moveFolder(f.store.folders(kind: .trips)[1], to: nil, index: 0)
        }
    }

    @Test func moveTrips() throws {
        try verify(.moveTrips, setup: { f in
            let folder = f.store.createFolder(name: "F", kind: .trips)
            let a = trip(f, "a"), b = trip(f, "b"), c = trip(f, "c")
            f.store.moveTrips([a, b], to: folder, index: nil)
            _ = c
        }) { f in
            let folder = f.store.folders(kind: .trips)[0]
            let c = f.store.trips(in: nil)[0]
            f.store.moveTrips([c], to: folder, index: 1)
        }
        try verify(.moveTrips, setup: { f in
            let folder = f.store.createFolder(name: "F", kind: .trips)
            f.store.moveTrips([trip(f, "a"), trip(f, "b")], to: folder, index: nil)
        }) { f in
            let folder = f.store.folders(kind: .trips)[0]
            f.store.moveTrips(Array(f.store.trips(in: folder).prefix(1)), to: nil, index: nil)
        }
    }

    @Test func movePlaces() throws {
        try verify(.movePlaces, setup: { f in
            let folder = f.store.createFolder(name: "F", kind: .locations)
            f.store.movePlaces([place(f, "a")], to: folder, index: nil)
            _ = place(f, "b")
        }) { f in
            let folder = f.store.folders(kind: .locations)[0]
            let b = f.store.savedPlaces().first { $0.folder == nil }!
            f.store.movePlaces([b], to: folder, index: 0)
        }
        try verify(.movePlaces, setup: { f in
            let folder = f.store.createFolder(name: "F", kind: .locations)
            f.store.movePlaces([place(f, "a")], to: folder, index: nil)
        }) { f in
            f.store.movePlaces(f.store.savedPlaces(), to: nil, index: nil)
        }
    }

    @Test func pinAndUnpin() throws {
        try verify(.pinTrip, setup: { f in _ = trip(f, "a") }) { f in
            f.store.setPinned(f.store.trips()[0], true)
        }
        try verify(.unpinTrip, setup: { f in f.store.setPinned(trip(f, "a"), true) }) { f in
            f.store.setPinned(f.store.trips()[0], false)
        }
    }

    @Test func existingActionsRestoreFolderState() throws {
        // Unsaving clears the folder; undo puts it back.
        try verify(.setSaved, setup: { f in
            let spot = f.spot("mesa-arch")
            f.store.setSaved(spot, true)
            f.store.addStop(spot, to: trip(f, "t"), day: 0)
            let folder = f.store.createFolder(name: "L", kind: .locations)
            f.store.movePlaces([f.store.savedPlaces()[0]], to: folder, index: nil)
        }) { f in
            f.store.setSaved(f.spot("mesa-arch"), false)
        }
        // Deleting a filed, pinned trip and undoing restores folder, order and pin.
        try verify(.deleteTrip, setup: { f in
            let folder = f.store.createFolder(name: "F", kind: .trips)
            let a = trip(f, "a"), b = trip(f, "b")
            f.store.moveTrips([a, b], to: folder, index: nil)
            f.store.setPinned(a, true)
        }) { f in
            f.store.deleteTrip(f.store.trips(in: f.store.folders(kind: .trips)[0])[0])
        }
        // Duplicate renumbers siblings; undo restores their order.
        try verify(.duplicateTrip, setup: { f in
            let folder = f.store.createFolder(name: "F", kind: .trips)
            f.store.moveTrips([trip(f, "a"), trip(f, "b")], to: folder, index: nil)
        }) { f in
            f.store.duplicateTrip(f.store.trips(in: f.store.folders(kind: .trips)[0])[0])
        }
        // A new trip goes first and undo removes it.
        try verify(.createTrip, setup: { f in _ = trip(f, "a") }) { f in
            f.store.createTrip(name: "n", startDay: f.day, dayCount: 1)
        }
    }
}
