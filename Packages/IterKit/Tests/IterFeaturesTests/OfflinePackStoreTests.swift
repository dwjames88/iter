import Foundation
import Testing
import IterCore
@testable import IterFeatures

@Suite struct OfflinePackStoreTests {
    func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "iter-packs-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func pack(_ id: UUID, images: [String] = []) -> OfflinePack {
        let infos = images.map {
            OfflinePack.Image(fileName: $0, spotID: "s", source: .satellite, coordinate: Coordinate(latitude: 1, longitude: 2),
                              pointWidth: 10, pointHeight: 10, scale: 2)
        }
        return OfflinePack(tripID: id, savedAt: Date(timeIntervalSince1970: 1), tripUpdatedAt: Date(timeIntervalSince1970: 0),
                           spots: [], forecasts: [:], legs: [], images: infos, failures: [])
    }

    @Test func corruptOrForeignPacksReadAsNilWithoutCrashing() throws {
        let dir = try root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = OfflinePackStore(root: dir)
        let id = UUID()
        for junk in ["", "{", "[]", "null", "{\"version\":1}", String(repeating: "\u{0}", count: 64)] {
            try Data(junk.utf8).write(to: dir.appending(path: "\(id.uuidString).json"))
            #expect(store.read(id) == nil, "junk \(junk.debugDescription)")
        }
        // A pack filed under the wrong trip, or from a future version, is not trusted.
        let other = UUID()
        try store.write(pack(other), images: [:])
        try FileManager.default.copyItem(at: dir.appending(path: "\(other.uuidString).json"), to: dir.appending(path: "\(id.uuidString).json.tmp"))
        try? FileManager.default.removeItem(at: dir.appending(path: "\(id.uuidString).json"))
        try FileManager.default.moveItem(at: dir.appending(path: "\(id.uuidString).json.tmp"), to: dir.appending(path: "\(id.uuidString).json"))
        #expect(store.read(id) == nil)
        var future = pack(id)
        future.version = OfflinePack.currentVersion + 1
        try JSONEncoder().encode(future).write(to: dir.appending(path: "\(id.uuidString).json"))
        #expect(store.read(id) == nil)
        #expect(store.readImage(id, fileName: "missing.png") == nil)
        // Odd folder contents do not break listing.
        try Data().write(to: dir.appending(path: "notes.txt"))
        #expect(store.packIDs() == [id, other].sorted { $0.uuidString < $1.uuidString })
    }

    @Test func writeLeavesNoTemporaryFilesAndDropsUnlistedImages() throws {
        let dir = try root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = OfflinePackStore(root: dir)
        let id = UUID()
        try store.write(pack(id, images: ["a.png", "b.png"]), images: ["a.png": Data([1]), "b.png": Data([2])])
        try store.write(pack(id, images: ["a.png"]), images: [:])
        #expect(store.read(id)?.imageKeys == ["a.png"])
        #expect(store.readImage(id, fileName: "a.png") == Data([1]))
        #expect(store.readImage(id, fileName: "b.png") == nil)
        let all = try FileManager.default.subpathsOfDirectory(atPath: dir.path)
        #expect(!all.contains { $0.contains(".tmp") || $0.contains("sb-") })
    }

    @Test func deleteRemovesEverythingForOneTripOnly() throws {
        let dir = try root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = OfflinePackStore(root: dir)
        let a = UUID(), b = UUID()
        try store.write(pack(a, images: ["x.png"]), images: ["x.png": Data([9])])
        try store.write(pack(b), images: [:])
        store.delete(a)
        #expect(store.read(a) == nil && store.readImage(a, fileName: "x.png") == nil)
        #expect(store.packIDs() == [b])
    }
}
