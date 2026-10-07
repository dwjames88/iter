import Foundation
import Testing
import IterUpdater
@testable import IterReleaseKit

@Suite("FeedBuilder")
struct FeedBuilderTests {
    private func makeItem(_ version: String, build: Int = 1) -> UpdateItem {
        UpdateItem(
            version: SemanticVersion(version)!, build: build, url: URL(string: "https://example.test/\(version).zip")!,
            length: 1, sha256: "00", edSignature: "AA==", publishedAt: Date(timeIntervalSince1970: 0))
    }

    @Test func itemMeasuresArchive() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("FeedBuilderTests-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("abc".utf8).write(to: file)
        let item = try FeedBuilder.item(
            archive: file, version: SemanticVersion("0.2.0")!, build: 412, url: URL(string: "https://example.test/a.zip")!,
            signature: "c2ln", publishedAt: Date(timeIntervalSince1970: 0), notes: "n")
        #expect(item.length == 3)
        #expect(item.sha256 == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(item.channel == "release")
        #expect(item.minimumSystemVersion == "26.0")
        #expect(item.notarized == false)
        #expect(item.notesURL == nil)
    }

    @Test func mergeWithoutPreviousIsSingleItem() {
        #expect(FeedBuilder.merge(makeItem("0.1.0"), into: nil).items.map(\.version) == [SemanticVersion("0.1.0")!])
    }

    @Test func mergePrepends() {
        let previous = UpdateFeed(items: [makeItem("0.2.0"), makeItem("0.1.0")])
        let merged = FeedBuilder.merge(makeItem("0.3.0"), into: previous)
        #expect(merged.items.map(\.version.description) == ["0.3.0", "0.2.0", "0.1.0"])
    }

    @Test func mergeDedupesSameVersion() {
        let previous = UpdateFeed(items: [makeItem("0.2.0", build: 5), makeItem("0.1.0")])
        let merged = FeedBuilder.merge(makeItem("0.2.0", build: 6), into: previous)
        #expect(merged.items.map(\.version.description) == ["0.2.0", "0.1.0"])
        #expect(merged.items.first?.build == 6)
    }

    @Test func mergedFeedRoundTrips() throws {
        let merged = FeedBuilder.merge(makeItem("0.3.0"), into: UpdateFeed(items: [makeItem("0.2.0")]))
        #expect(try UpdateFeed.decode(merged.encoded()) == merged)
    }
}
