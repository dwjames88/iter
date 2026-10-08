import Foundation
import Testing
@testable import IterUpdater

let sampleFeedJSON = """
{
  "schemaVersion": 1,
  "futureTopLevelKey": {"anything": true},
  "items": [
    {
      "version": "0.2.0",
      "build": 412,
      "channel": "release",
      "minimumSystemVersion": "26.0",
      "url": "https://github.com/dwjames88/iter/releases/download/v0.2.0/Iter-0.2.0.zip",
      "length": 12345678,
      "sha256": "abc123",
      "edSignature": "c2ln",
      "publishedAt": "2026-10-06T12:00:00Z",
      "notarized": false,
      "notes": "Markdown release notes",
      "notesURL": "https://github.com/dwjames88/iter/releases/tag/v0.2.0",
      "unknownKey": 42
    }
  ]
}
"""

private func item(
    _ version: String, build: Int = 1, channel: String = "release", minOS: String = "26.0"
) -> UpdateItem {
    UpdateItem(
        version: SemanticVersion(version)!, build: build, channel: channel, minimumSystemVersion: minOS,
        url: URL(string: "https://example.test/\(version).zip")!, length: 1, sha256: "00", edSignature: "AA==",
        publishedAt: Date(timeIntervalSince1970: 0))
}

private let os26 = OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
private func current(_ v: String, build: Int = 1) -> AppVersion { AppVersion(version: SemanticVersion(v)!, build: build) }

@Suite("UpdateFeed")
struct UpdateFeedTests {
    @Test func decodesContractExampleAndIgnoresUnknownKeys() throws {
        let feed = try UpdateFeed.decode(Data(sampleFeedJSON.utf8))
        #expect(feed.schemaVersion == 1)
        let first = try #require(feed.items.first)
        #expect(first.version == SemanticVersion("0.2.0"))
        #expect(first.build == 412)
        #expect(first.length == 12_345_678)
        #expect(first.notesURL?.absoluteString == "https://github.com/dwjames88/iter/releases/tag/v0.2.0")
        #expect(first.publishedAt == (try Date.ISO8601FormatStyle().parse("2026-10-06T12:00:00Z")))
        #expect(first.id == "0.2.0+412")
        #expect(first.appVersion == current("0.2.0", build: 412))
    }

    @Test func newerSchemaStillDecodes() throws {
        let json = sampleFeedJSON.replacingOccurrences(of: "\"schemaVersion\": 1", with: "\"schemaVersion\": 7")
        #expect(try UpdateFeed.decode(Data(json.utf8)).schemaVersion == 7)
    }

    @Test func fractionalSecondDatesDecode() throws {
        let json = sampleFeedJSON.replacingOccurrences(of: "2026-10-06T12:00:00Z", with: "2026-10-06T12:00:00.250Z")
        #expect(try UpdateFeed.decode(Data(json.utf8)).items.count == 1)
    }

    @Test func garbageIsFeedInvalid() {
        #expect(throws: UpdateError.self) { try UpdateFeed.decode(Data("not json".utf8)) }
        #expect(throws: UpdateError.self) { try UpdateFeed.decode(Data(#"{"items":[{"version":"x"}]}"#.utf8)) }
    }

    private func mixedFeed(bad: String) -> Data {
        let good = String(sampleFeedJSON.dropFirst(sampleFeedJSON.range(of: "\"items\": [")!.upperBound.utf16Offset(in: sampleFeedJSON)))
            .replacingOccurrences(of: "\n  ]\n}", with: "")
        return Data("{\"schemaVersion\":1,\"items\":[\(bad),\(good)]}".utf8)
    }

    @Test(arguments: [
        #"{"version":"9.9.9","build":1,"url":"https://x.test/a.zip","length":1,"sha256":"00","publishedAt":"2026-10-06T12:00:00Z"}"#,
        #"{"version":"x.y","build":1,"url":"https://x.test/a.zip","length":1,"sha256":"00","edSignature":"AA==","publishedAt":"2026-10-06T12:00:00Z"}"#,
        #"{"version":"9.9.9","build":1,"url":"https://x.test/a.zip","length":"12","sha256":"00","edSignature":"AA==","publishedAt":"2026-10-06T12:00:00Z"}"#,
    ])
    func malformedItemIsSkippedAndValidOneOffered(bad: String) throws {
        let feed = try UpdateFeed.decode(mixedFeed(bad: bad))
        #expect(feed.items.count == 1)
        #expect(feed.skippedItems.map(\.index) == [0])
        #expect(feed.bestUpdate(newerThan: current("0.1.0"), channel: "release", system: os26)?.version == SemanticVersion("0.2.0"))
        #expect(throws: UpdateError.self) { try UpdateFeed.decodeStrict(mixedFeed(bad: bad)) }
    }

    @Test func allItemsMalformedThrows() {
        #expect(throws: UpdateError.self) { try UpdateFeed.decode(Data(#"{"items":[{"version":"x"},{}]}"#.utf8)) }
    }

    @Test func emptyItemsIsValidAndOffersNothing() throws {
        let feed = try UpdateFeed.decode(Data(#"{"schemaVersion":1,"items":[]}"#.utf8))
        #expect(feed.items.isEmpty && feed.skippedItems.isEmpty)
    }

    @Test func missingOrWrongItemsThrows() {
        #expect(throws: UpdateError.self) { try UpdateFeed.decode(Data(#"{"schemaVersion":1}"#.utf8)) }
        #expect(throws: UpdateError.self) { try UpdateFeed.decode(Data(#"{"items":{"a":1}}"#.utf8)) }
        #expect(throws: UpdateError.self) { try UpdateFeed.decode(Data("[]".utf8)) }
    }

    @Test func repositoryAppcastDecodesWithTwoItems() throws {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        let feed = try UpdateFeed.decode(Data(contentsOf: url.appending(path: "updates/appcast.json")))
        #expect(feed.items.count == 2)
        #expect(feed.skippedItems.isEmpty)
    }

    @Test func roundTrip() throws {
        let feed = UpdateFeed(items: [item("0.3.0", build: 5), item("0.2.0")])
        let data = try feed.encoded()
        #expect(data.last == 0x0A)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"version\" : \"0.3.0\""))
        #expect(text.contains("1970-01-01T00:00:00Z"))
        #expect(!text.contains("\\/"))
        #expect(try UpdateFeed.decode(data) == feed)
    }

    @Test func emptyFeedHasNoUpdate() {
        #expect(UpdateFeed(items: []).bestUpdate(newerThan: current("0.1.0"), channel: "release", system: os26) == nil)
    }

    @Test func newestWins() {
        let feed = UpdateFeed(items: [item("0.2.0"), item("0.4.0"), item("0.3.0")])
        #expect(feed.bestUpdate(newerThan: current("0.1.0"), channel: "release", system: os26)?.version == SemanticVersion("0.4.0"))
    }

    @Test func notNewerIsNotOffered() {
        let feed = UpdateFeed(items: [item("0.2.0", build: 4)])
        #expect(feed.bestUpdate(newerThan: current("0.2.0", build: 4), channel: "release", system: os26) == nil)
        #expect(feed.bestUpdate(newerThan: current("0.3.0"), channel: "release", system: os26) == nil)
        // Same marketing version, higher build counts as newer.
        #expect(feed.bestUpdate(newerThan: current("0.2.0", build: 3), channel: "release", system: os26) != nil)
    }

    @Test func prereleaseIsOlderThanFinal() {
        let feed = UpdateFeed(items: [item("1.0.0-rc.1")])
        #expect(feed.bestUpdate(newerThan: current("1.0.0"), channel: "release", system: os26) == nil)
    }

    @Test func channelIsolation() {
        let feed = UpdateFeed(items: [item("0.9.0", channel: "beta"), item("0.2.0", channel: "release")])
        #expect(feed.bestUpdate(newerThan: current("0.1.0"), channel: "release", system: os26)?.version == SemanticVersion("0.2.0"))
        #expect(feed.bestUpdate(newerThan: current("0.1.0"), channel: "beta", system: os26)?.version == SemanticVersion("0.9.0"))
        #expect(feed.bestUpdate(newerThan: current("0.1.0"), channel: "nightly", system: os26) == nil)
    }

    @Test func minimumSystemVersion() {
        let feed = UpdateFeed(items: [item("0.3.0", minOS: "27.0"), item("0.2.0", minOS: "26.0")])
        #expect(feed.bestUpdate(newerThan: current("0.1.0"), channel: "release", system: os26)?.version == SemanticVersion("0.2.0"))
        let os27 = OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)
        #expect(feed.bestUpdate(newerThan: current("0.1.0"), channel: "release", system: os27)?.version == SemanticVersion("0.3.0"))
        let os2601 = OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 1)
        #expect(UpdateFeed(items: [item("0.2.0", minOS: "26.0.1")]).bestUpdate(newerThan: current("0.1.0"), channel: "release", system: os26) == nil)
        #expect(UpdateFeed(items: [item("0.2.0", minOS: "26.0.1")]).bestUpdate(newerThan: current("0.1.0"), channel: "release", system: os2601) != nil)
        #expect(UpdateFeed(items: [item("0.2.0", minOS: "26")]).bestUpdate(newerThan: current("0.1.0"), channel: "release", system: os26) != nil)
        #expect(UpdateFeed(items: [item("0.2.0", minOS: "garbage")]).bestUpdate(newerThan: current("0.1.0"), channel: "release", system: os26) == nil)
    }

    @Test func skippedVersionIsHiddenButNewerOneIsNot() {
        let feed = UpdateFeed(items: [item("0.3.0"), item("0.2.0")])
        let skip = SemanticVersion("0.3.0")
        #expect(feed.bestUpdate(newerThan: current("0.1.0"), channel: "release", system: os26, skipping: skip)?.version == SemanticVersion("0.2.0"))
        let newer = UpdateFeed(items: [item("0.4.0"), item("0.3.0")])
        #expect(newer.bestUpdate(newerThan: current("0.1.0"), channel: "release", system: os26, skipping: skip)?.version == SemanticVersion("0.4.0"))
    }
}
