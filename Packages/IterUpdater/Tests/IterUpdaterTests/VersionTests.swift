import Foundation
import Testing
@testable import IterUpdater

@Suite("SemanticVersion")
struct SemanticVersionTests {
    @Test(arguments: [
        ("1.2.3", 1, 2, 3, [String]()),
        ("v1.2.3", 1, 2, 3, []),
        ("V2.0.0", 2, 0, 0, []),
        ("1", 1, 0, 0, []),
        ("1.2", 1, 2, 0, []),
        ("1.2.3-beta.1", 1, 2, 3, ["beta", "1"]),
        ("1.0.0-rc.1+build.5", 1, 0, 0, ["rc", "1"]),
        ("1.2.3+meta", 1, 2, 3, []),
        ("  0.1.0 \n", 0, 1, 0, []),
    ])
    func parsesValid(_ text: String, _ major: Int, _ minor: Int, _ patch: Int, _ pre: [String]) {
        let version = SemanticVersion(text)
        #expect(version == SemanticVersion(major: major, minor: minor, patch: patch, prerelease: pre))
    }

    @Test(arguments: ["", "v", "a.b.c", "1.2.3.4", "1..2", "1.2.x", "-1.0.0", "1.0.0-", "1.0.0-beta..1", "1.0.0-01", "1.0.0-be ta", "99999999999999999999.0.0"])
    func rejectsInvalid(_ text: String) {
        #expect(SemanticVersion(text) == nil)
    }

    @Test func descriptionRoundTrips() {
        #expect(SemanticVersion("v1.2")!.description == "1.2.0")
        #expect(SemanticVersion("1.0.0-beta.2+x")!.description == "1.0.0-beta.2")
    }

    @Test func precedenceOfCore() {
        #expect(SemanticVersion("0.9.9")! < SemanticVersion("1.0.0")!)
        #expect(SemanticVersion("1.2.3")! < SemanticVersion("1.10.0")!)
        #expect(SemanticVersion("2.0.0")! > SemanticVersion("1.99.99")!)
        #expect(SemanticVersion("1.0")! == SemanticVersion("1.0.0")!)
        #expect(SemanticVersion("1.0.0+a")! == SemanticVersion("1.0.0+b")!)
    }

    @Test func prereleasePrecedenceChainFromSemVerSpec() {
        let chain = ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2",
                     "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0"].map { SemanticVersion($0)! }
        for (lower, higher) in zip(chain, chain.dropFirst()) {
            #expect(lower < higher, "\(lower) should be below \(higher)")
            #expect(!(higher < lower))
        }
    }

    @Test func numericIdentifiersRankBelowAlphanumeric() {
        #expect(SemanticVersion("1.0.0-1")! < SemanticVersion("1.0.0-a")!)
        #expect(SemanticVersion("1.0.0-2")! < SemanticVersion("1.0.0-10")!)
        #expect(SemanticVersion("1.0.0-alpha.1")! < SemanticVersion("1.0.0-alpha.a")!)
    }

    @Test func codableAsString() throws {
        let data = try JSONEncoder().encode(["v": SemanticVersion("1.2.3-beta.1")!])
        #expect(String(decoding: data, as: UTF8.self) == #"{"v":"1.2.3-beta.1"}"#)
        let decoded = try JSONDecoder().decode([String: SemanticVersion].self, from: data)
        #expect(decoded["v"] == SemanticVersion("1.2.3-beta.1"))
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([String: SemanticVersion].self, from: Data(#"{"v":"nope"}"#.utf8)) }
    }
}

@Suite("AppVersion")
struct AppVersionTests {
    @Test func buildBreaksTies() {
        let v = SemanticVersion("1.0.0")!
        #expect(AppVersion(version: v, build: 5) < AppVersion(version: v, build: 6))
        #expect(AppVersion(version: SemanticVersion("0.9.9")!, build: 999) < AppVersion(version: v, build: 1))
        #expect(AppVersion(version: v, build: 3).description == "1.0.0 (3)")
    }

    @Test func infoDictionaryParsing() {
        let ok = AppVersion(infoDictionary: ["CFBundleShortVersionString": "0.2.0", "CFBundleVersion": "412"])
        #expect(ok == AppVersion(version: SemanticVersion("0.2.0")!, build: 412))
        #expect(AppVersion(infoDictionary: ["CFBundleShortVersionString": "0.2.0", "CFBundleVersion": "abc"])?.build == 0)
        #expect(AppVersion(infoDictionary: ["CFBundleShortVersionString": "0.2.0"])?.build == 0)
        #expect(AppVersion(infoDictionary: ["CFBundleVersion": "3"]) == nil)
    }

    @Test func readsInfoPlistFromDisk() throws {
        let dir = try TempDir()
        let app = try makeBundle(in: dir.url, version: "3.1.4", build: 15)
        #expect(AppVersion(infoPlistAt: app) == AppVersion(version: SemanticVersion("3.1.4")!, build: 15))
        #expect(AppVersion(infoPlistAt: dir.child("Missing.app")) == nil)
    }
}
