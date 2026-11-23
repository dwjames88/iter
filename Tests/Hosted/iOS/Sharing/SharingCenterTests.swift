import Foundation
import Testing
import IterFeatures
import IterStore
@testable import Iter

@MainActor
@Suite struct SharingCenterTests {
    private func shell(seed: Bool) throws -> IOSShell { IOSShell(container: try AppContainer.test(seed: seed)) }

    private func scratchFolder(_ name: String? = nil) throws -> URL {
        var dir = FileManager.default.temporaryDirectory.appendingPathComponent("IterSharingTests-\(UUID().uuidString)", isDirectory: true)
        if let name { dir = dir.appendingPathComponent(name, isDirectory: true) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func aV2FileMergesAndTheInboxCopyIsDeleted() throws {
        let mac = try shell(seed: true), phone = try shell(seed: false)
        let file = try mac.library.exportLibrary()
        let url = try scratchFolder("Inbox").appendingPathComponent("Iter Library.iter")
        try file.data.write(to: url)

        #expect(phone.sharing.open(url))
        #expect(!FileManager.default.fileExists(atPath: url.path))       // the Inbox copy is gone
        let pending = try #require(phone.sharing.pending)
        #expect(!pending.isV1 && pending.name == "Iter Library")
        #expect(phone.library.trips.isEmpty)

        phone.sharing.perform(pending, asCopy: false)
        #expect(phone.sharing.pending == nil)
        #expect(phone.library.trips.count == mac.library.trips.count)
        let notice = try #require(phone.sharing.notice)
        #expect(notice.title == "Import Finished" && notice.message.hasPrefix("Added 3 trips"))
    }

    @Test func importAsCopyAddsNewTrips() throws {
        let mac = try shell(seed: true), phone = try shell(seed: false)
        let url = try scratchFolder().appendingPathComponent("Trips.iter")
        try mac.library.exportLibrary().data.write(to: url)
        #expect(phone.sharing.open(url))
        phone.sharing.perform(try #require(phone.sharing.pending), asCopy: true)
        #expect(phone.library.trips.count == 3)
        #expect(phone.library.trips.allSatisfy { row in mac.library.tripRow(id: row.id) == nil })
        #expect(FileManager.default.fileExists(atPath: url.path))        // not an Inbox copy: left alone
    }

    @Test func aV1FileIsOfferedOnlyAsACopy() throws {
        let root = try #require(ProcessInfo.processInfo.environment["ITER_REPO_ROOT"], "scripts/test-ios.sh sets ITER_REPO_ROOT")
        let fixture = URL(fileURLWithPath: root).appendingPathComponent("Packages/Iter/Tests/IterStoreTests/Fixtures/documents/Utah Arches Day trip.iter")
        let phone = try shell(seed: false)
        let copyOfFixture = try scratchFolder().appendingPathComponent(fixture.lastPathComponent)
        try FileManager.default.copyItem(at: fixture, to: copyOfFixture)
        #expect(phone.sharing.open(copyOfFixture))
        let pending = try #require(phone.sharing.pending)
        #expect(pending.isV1)
        phone.sharing.perform(pending, asCopy: true)
        #expect(phone.library.trips.count == 1)
        #expect(phone.sharing.notice?.message.hasSuffix("Everything came in as new copies.") == true)
    }

    @Test func otherFilesAreNotOurs() throws {
        let phone = try shell(seed: false)
        let url = try scratchFolder().appendingPathComponent("photo.jpg")
        try Data([1, 2, 3]).write(to: url)
        #expect(!phone.sharing.open(url))
        #expect(phone.sharing.pending == nil)
        #expect(!phone.sharing.open(URL(string: "https://example.com/a.iter")!))
    }

    @Test func aBrokenIterFileSaysSo() throws {
        let phone = try shell(seed: false)
        let url = try scratchFolder().appendingPathComponent("Broken.iter")
        try Data("not json".utf8).write(to: url)
        #expect(phone.sharing.open(url))
        phone.sharing.perform(try #require(phone.sharing.pending), asCopy: false)
        #expect(phone.sharing.notice?.title == "Couldn't Import Trip")
        #expect(phone.library.trips.isEmpty)
    }

    @Test func theShareItemBuildsALazyV2File() async throws {
        let mac = try shell(seed: true)
        let id = try #require(mac.library.trips.first?.id)
        let item = IterFileExport(fileName: "x.iter") { [library = mac.library] in try? library.exportTrip(id) }
        let file = try #require(item.build())
        guard case .v2 = try ITERFile.read(file.data) else { Issue.record("not v2"); return }
    }
}
