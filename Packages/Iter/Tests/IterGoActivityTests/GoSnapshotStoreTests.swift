import Foundation
import Testing
import IterGoActivity

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func tempDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("iter-snapshot-\(UUID().uuidString)", isDirectory: true)
}

@Test func appGroupStoreRoundTripsInADirectory() throws {
    let dir = tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = AppGroupSnapshotStore(directory: dir)
    #expect(store.read() == nil)
    let s = GoSnapshot(generatedAt: t0, tripID: UUID(), tripName: "Utah", runID: nil, phase: .armed, remainingCount: 4)
    try store.write(s)
    #expect(store.read() == s)
    #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("go-snapshot.json").path))
    let s2 = GoSnapshot.idle(at: t0.addingTimeInterval(5))
    try store.write(s2)
    #expect(store.read() == s2)
}

@Test func storeToleratesCorruptAndNewerFiles() throws {
    let dir = tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let store = AppGroupSnapshotStore(directory: dir)
    try Data("not json".utf8).write(to: store.fileURL)
    #expect(store.read() == nil)

    var newer = GoSnapshot.idle(at: t0)
    newer.version = GoSnapshot.currentVersion + 1
    try JSONEncoder().encode(newer).write(to: store.fileURL)
    #expect(store.read() == nil)

    try Data("{\"version\": 99, \"somethingNew\": [1,2]}".utf8).write(to: store.fileURL)
    #expect(store.read() == nil)
}

@Test func appGroupConstants() {
    #expect(AppGroupSnapshotStore.groupIdentifier == "group.com.dwjames.iter")
    #expect(AppGroupSnapshotStore.fileName == "go-snapshot.json")
}

@Test func inMemoryStoreKeepsTheLastWrite() throws {
    let store = InMemorySnapshotStore()
    #expect(store.read() == nil)
    try store.write(.idle(at: t0))
    #expect(store.read() == .idle(at: t0))
    #expect(store.writeCount == 1)
}
