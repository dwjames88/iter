import Foundation
import SwiftData
import Testing
@testable import IterStore

/// Folders used to nest one level. `FolderFlatten.flattenFolders` (run when the store opens) makes every folder top level.
@Suite struct FolderFlattenTests {
    final class Fixture {
        let container: ModelContainer
        let context: ModelContext
        init() throws {
            container = try IterStoreSchema.makeInMemoryContainer()
            context = ModelContext(container)
        }
        @discardableResult
        func folder(_ name: String, _ kind: String = "trips", sort: Double = 0, under parent: FolderRecord? = nil) -> FolderRecord {
            let f = FolderRecord()
            f.name = name
            f.kindRaw = kind
            f.sortOrder = sort
            context.insert(f)
            f.parent = parent
            return f
        }
        func ordered(_ kind: String) throws -> [FolderRecord] {
            try context.fetch(FetchDescriptor<FolderRecord>()).filter { $0.kindRaw == kind }.sorted(by: FolderFlatten.folderOrder)
        }
    }

    @Test func flattensBothKindsKeepingContentsPinAndOrder() throws {
        let f = try Fixture()
        // Trips: A (pinned) { A1 (pinned), A2 }, B, C { C1 }
        let a = f.folder("A", sort: 0), b = f.folder("B", sort: 1), c = f.folder("C", sort: 2)
        let a1 = f.folder("A1", sort: 0, under: a), a2 = f.folder("A2", sort: 1, under: a), c1 = f.folder("C1", sort: 0, under: c)
        a.isPinned = true; a1.isPinned = true
        let pinnedAt = Date(timeIntervalSinceReferenceDate: 1234)
        a1.pinnedAt = pinnedAt
        let trip = TripRecord()
        f.context.insert(trip)
        trip.folder = a1
        // Locations: L { L1 }
        let l = f.folder("L", "locations"), l1 = f.folder("L1", "locations", under: l)
        let place = PlaceRecord()
        f.context.insert(place)
        place.folder = l1
        try f.context.save()

        let now = Date(timeIntervalSinceReferenceDate: 5000)
        #expect(try FolderFlatten.flattenFolders(in: f.context, now: now) == 4)

        #expect(try f.ordered("trips").map(\.name) == ["A", "A1", "A2", "B", "C", "C1"])
        #expect(try f.ordered("trips").map(\.sortOrder) == [0, 1, 2, 3, 4, 5])
        #expect(try f.ordered("locations").map(\.name) == ["L", "L1"])
        let all = try f.context.fetch(FetchDescriptor<FolderRecord>())
        #expect(all.allSatisfy { $0.parent == nil && ($0.children ?? []).isEmpty })
        // Contents, pin state and kind survive; flattened folders are stamped, the others are not.
        #expect(trip.folder?.id == a1.id)
        #expect(place.folder?.id == l1.id)
        #expect(a1.isPinned && a1.pinnedAt == pinnedAt && a.isPinned && !a2.isPinned)
        #expect(a1.updatedAt == now && a2.updatedAt == now && c1.updatedAt == now && l1.updatedAt == now)
        #expect(a.updatedAt != now && b.updatedAt != now)
    }

    @Test func idempotentAndKeepsSameNames() throws {
        let f = try Fixture()
        let a = f.folder("Utah"), dup = f.folder("Utah"), inner = f.folder("Utah", under: a)
        _ = (dup, inner)
        #expect(try FolderFlatten.flattenFolders(in: f.context) == 1)
        let first = try f.ordered("trips")
        #expect(first.count == 3)   // no merging
        let before = first.map { "\($0.id) \($0.sortOrder) \($0.updatedAt)" }
        #expect(try FolderFlatten.flattenFolders(in: f.context, now: Date(timeIntervalSinceReferenceDate: 9)) == 0)
        #expect(try f.ordered("trips").map { "\($0.id) \($0.sortOrder) \($0.updatedAt)" } == before)
    }

    @Test func aParentCycleDoesNotLoopForever() throws {
        let f = try Fixture()
        let x = f.folder("X"), y = f.folder("Y", under: x)
        x.parent = y
        #expect(try FolderFlatten.flattenFolders(in: f.context) == 2)
        #expect(try f.ordered("trips").count == 2)
    }

    @Test func surviveARealStoreReopen() throws {
        let dir = try TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "Iter.store")
        let ids: (UUID, UUID)
        do {
            let context = ModelContext(try IterStoreSchema.makeContainer(url: url))
            let root = FolderRecord(), kid = FolderRecord()
            root.name = "Root"; kid.name = "Kid"
            context.insert(root); context.insert(kid)
            kid.parent = root
            ids = (root.id, kid.id)
            try context.save()
        }
        let reopened = ModelContext(try IterStoreSchema.makeContainer(url: url))
        #expect(try FolderFlatten.flattenFolders(in: reopened) == 1)
        let folders = try reopened.fetch(FetchDescriptor<FolderRecord>()).sorted(by: FolderFlatten.folderOrder)
        #expect(folders.map(\.id) == [ids.0, ids.1])
        #expect(folders.allSatisfy { $0.parent == nil })
    }
}
