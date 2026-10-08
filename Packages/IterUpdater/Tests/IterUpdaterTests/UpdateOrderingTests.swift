import Foundation
import Testing
@testable import IterUpdater

/// Build-number and marketing-version ordering as the updater applies it: never "update" to the same or an older build.
@Suite struct UpdateOrderingTests {
    private func app(_ v: String, _ build: Int) -> AppVersion { AppVersion(version: SemanticVersion(v)!, build: build) }

    private func item(_ v: String, _ build: Int, channel: String = "release", minOS: String = "14.0") -> UpdateItem {
        UpdateItem(version: SemanticVersion(v)!, build: build, channel: channel, minimumSystemVersion: minOS,
                   url: URL(string: "https://example.test/\(v).zip")!, length: 1, sha256: "00", edSignature: "AA==",
                   publishedAt: Date(timeIntervalSince1970: 0))
    }

    private let system = OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)

    @Test func buildsCompareAsNumbersNotText() {
        #expect(app("0.1.0", 12) > app("0.1.0", 9))
        #expect(app("0.10.0", 1) > app("0.9.0", 999))
        #expect(app("1.0.0", 1) > app("0.99.99", 999))
        #expect(app("0.1.0", 100) > app("0.1.0", 20))
    }

    @Test func missingBuildCountsAsZero() {
        let none = AppVersion(infoDictionary: ["CFBundleShortVersionString": "0.1.0"])
        #expect(none == app("0.1.0", 0))
        let text = AppVersion(infoDictionary: ["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "abc"])
        #expect(text?.build == 0)
        #expect(AppVersion(infoDictionary: ["CFBundleVersion": "5"]) == nil)
        // A build of any size beats a missing one.
        #expect(app("0.1.0", 1) > none!)
    }

    @Test func sameOrOlderBuildIsNeverOffered() {
        let feed = UpdateFeed(items: [item("0.1.0", 9), item("0.1.0", 12), item("0.0.9", 99)])
        #expect(feed.bestUpdate(newerThan: app("0.1.0", 12), channel: "release", system: system) == nil)
        #expect(feed.bestUpdate(newerThan: app("0.1.0", 13), channel: "release", system: system) == nil)
        #expect(feed.bestUpdate(newerThan: app("0.1.1", 1), channel: "release", system: system) == nil)
        #expect(feed.bestUpdate(newerThan: app("0.1.0", 9), channel: "release", system: system)?.build == 12)
    }

    @Test func newestWinsAcrossMinorBoundaries() {
        let feed = UpdateFeed(items: [item("0.9.0", 50), item("0.10.0", 1), item("0.2.0", 70)])
        #expect(feed.bestUpdate(newerThan: app("0.1.0", 1), channel: "release", system: system)?.version.description == "0.10.0")
    }

    @Test func minimumSystemVersionForms() {
        let old = OperatingSystemVersion(majorVersion: 14, minorVersion: 5, patchVersion: 1)
        #expect(item("1.0.0", 1, minOS: "14").isSupported(on: old))
        #expect(item("1.0.0", 1, minOS: "14.5.1").isSupported(on: old))
        #expect(!item("1.0.0", 1, minOS: "14.5.2").isSupported(on: old))
        #expect(!item("1.0.0", 1, minOS: "15").isSupported(on: old))
        #expect(!item("1.0.0", 1, minOS: "").isSupported(on: old))
        #expect(!item("1.0.0", 1, minOS: "14.x").isSupported(on: old))
        #expect(!item("1.0.0", 1, minOS: "1.2.3.4").isSupported(on: old))
    }

    @Test func missingOptionalFieldsDefault() throws {
        let json = """
        {"items":[{"version":"0.3.0","build":3,"url":"https://example.test/a.zip","length":10,"sha256":"aa",
        "edSignature":"AA==","publishedAt":"2026-10-06T12:00:00Z"}]}
        """
        let feed = try UpdateFeed.decode(Data(json.utf8))
        let only = try #require(feed.items.first)
        #expect(only.channel == "release" && only.notes.isEmpty && only.notesURL == nil && !only.notarized)
        #expect(feed.schemaVersion == UpdateFeed.schemaVersion)
        // A missing trust field is a feed error, never a half-trusted item.
        let noSignature = json.replacingOccurrences(of: "\"edSignature\":\"AA==\",", with: "")
        #expect(throws: UpdateError.self) { try UpdateFeed.decode(Data(noSignature.utf8)) }
    }

    @Test func sha256ComparisonIgnoresCaseButNotContent() throws {
        let dir = try TempDir()
        let file = dir.child("a.bin")
        try Data("hello".utf8).write(to: file)
        let hex = try UpdateVerifier.sha256Hex(ofFileAt: file)
        var it = item("1.0.0", 1)
        it.length = 5
        it.sha256 = hex.uppercased()
        // Hash passes, so the failure is the signature, not the hash or the length.
        #expect(throws: UpdateError.signatureInvalid) { try UpdateVerifier.verify(archive: file, against: it, publicKey: UpdateSigning.generateKeyPair().publicKey) }
        it.sha256 = String(hex.dropLast()) + (hex.last == "0" ? "1" : "0")
        #expect(throws: UpdateError.hashMismatch) { try UpdateVerifier.verify(archive: file, against: it, publicKey: UpdateSigning.generateKeyPair().publicKey) }
    }
}
