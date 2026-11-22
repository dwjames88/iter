import Foundation
import Testing
import SwiftData
import IterCore
@testable import IterData

/// Folders used to nest one level. `IterStore.flattenFolders` (run when the store opens) makes every folder top level.
@MainActor
@Suite struct FolderFlattenTests {
    /// Builds a two-level tree the way an old store had it: the model's `parent` link set directly.
    private func nest(_ child: FolderRecord, under parent: FolderRecord) { child.parent = parent }

    @Test func flattensBothKindsKeepingContentsPinAndOrder() throws {
        let f = try Fixture()
        let s = f.store
        // Trips: A (pinned) { A1 (pinned), A2 }, B, C { C1 }
        let a = s.createFolder(name: "A", kind: .trips)
        let b = s.createFolder(name: "B", kind: .trips)
        let c = s.createFolder(name: "C", kind: .trips)
        let a1 = s.createFolder(name: "A1", kind: .trips)
        let a2 = s.createFolder(name: "A2", kind: .trips)
        let c1 = s.createFolder(name: "C1", kind: .trips)
        nest(a1, under: a); nest(a2, under: a); nest(c1, under: c)
        a1.sortOrder = 0; a2.sortOrder = 1; c1.sortOrder = 0
        s.setPinned(a, true); s.setPinned(a1, true)
        let pinnedAt = a1.pinnedAt
        let t = s.createTrip(name: "t", startDay: f.day, dayCount: 1)
        s.moveTrips([t], to: a1, index: nil)
        // Locations: L { L1 }
        let l = s.createFolder(name: "L", kind: .locations)
        let l1 = s.createFolder(name: "L1", kind: .locations)
        nest(l1, under: l)
        let p = s.createUserSpot(name: "p", coordinate: Coordinate(latitude: 38, longitude: -109), timeZoneIdentifier: "America/Denver")
        s.movePlaces([p], to: l1, index: nil)

        #expect(s.flattenFolders() == 4)

        #expect(s.folders(kind: .trips).map(\.name) == ["A", "A1", "A2", "B", "C", "C1"])
        #expect(s.folders(kind: .trips).map(\.sortOrder) == [0, 1, 2, 3, 4, 5])
        #expect(s.folders(kind: .locations).map(\.name) == ["L", "L1"])
        #expect(((try? s.context.fetch(FetchDescriptor<FolderRecord>())) ?? []).allSatisfy { $0.parent == nil && ($0.children ?? []).isEmpty })
        // Contents, pin state and kind survive.
        #expect(t.folder?.id == a1.id)
        #expect(p.folder?.id == l1.id)
        #expect(a1.isPinned && a1.pinnedAt == pinnedAt && a.isPinned && !a2.isPinned)
        #expect(s.pinnedFolders(kind: .trips).map(\.name) == ["A", "A1"])
        #expect(l1.kind == .locations && c1.kind == .trips)
        _ = b
    }

    @Test func idempotentAndKeepsSameNames() throws {
        let f = try Fixture()
        let s = f.store
        let a = s.createFolder(name: "Utah", kind: .trips)
        let dup = s.createFolder(name: "Utah", kind: .trips)
        let inner = s.createFolder(name: "Utah", kind: .trips)
        nest(inner, under: a)
        _ = dup
        #expect(s.flattenFolders() == 1)
        #expect(s.folders(kind: .trips).count == 3)   // no merging
        let before = s.folders(kind: .trips).map { "\($0.id) \($0.sortOrder) \($0.updatedAt)" }
        let revision = s.revision
        #expect(s.flattenFolders() == 0)
        #expect(s.folders(kind: .trips).map { "\($0.id) \($0.sortOrder) \($0.updatedAt)" } == before)
        #expect(s.revision == revision)
    }

    @Test func runsWhenTheStoreOpens() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "flatten-\(UUID().uuidString)/Iter.store")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var ids: (UUID, UUID)
        do {
            let store = IterStore(container: try IterSchema.makeContainer(url: url))
            let root = store.createFolder(name: "Root", kind: .trips)
            let kid = store.createFolder(name: "Kid", kind: .trips)
            kid.parent = root
            ids = (root.id, kid.id)
            try store.context.save()
        }
        let reopened = IterStore(container: try IterSchema.makeContainer(url: url))
        #expect(reopened.folders(kind: .trips).map(\.id) == [ids.0, ids.1])
        #expect(reopened.folder(id: ids.1)?.parent == nil)
    }

    @Test func undoNeverRecreatesNesting() throws {
        let f = try Fixture(undoable: true)
        let a = f.act { f.store.createFolder(name: "A", kind: .trips) }
        f.act { f.store.deleteFolder(a) }
        f.undo.undo()
        let restored = try #require(f.store.folders(kind: .trips).first)
        #expect(restored.name == "A" && restored.parent == nil)
    }
}
