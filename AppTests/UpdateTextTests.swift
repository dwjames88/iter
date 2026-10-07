import Foundation
import Testing
import IterUpdater
@testable import Iter

@Suite struct UpdateTextTests {
    static let blockers: [InstallBlocker] = [.sandboxed, .translocated, .notWritable(path: "/Applications/Iter.app"), .missingPublicKey]

    static let errors: [UpdateError] = [
        .feedUnavailable("x"), .feedInvalid("x"), .noUpdateURL, .sizeMismatch(expected: 1, actual: 2), .hashMismatch,
        .signatureInvalid, .archiveInvalid("x"), .bundleMismatch("x"), .codeSignatureInvalid("x"),
        .blocked(.sandboxed), .installFailed("x"), .cancelled,
    ]

    @Test func everyBlockerHasASentence() {
        for blocker in Self.blockers {
            let text = UpdateText.message(for: blocker)
            #expect(!text.isEmpty)
            #expect(text.hasSuffix("."))
        }
    }

    @Test func everyErrorHasASentence() {
        for error in Self.errors {
            let text = UpdateText.message(for: error)
            #expect(!text.isEmpty)
            #expect(text.hasSuffix("."))
        }
        #expect(!UpdateText.message(for: URLError(.badURL) as Error).isEmpty)
    }

    @Test func blockedErrorUsesTheBlockerSentence() {
        #expect(UpdateText.message(for: UpdateError.blocked(.translocated)) == UpdateText.message(for: InstallBlocker.translocated))
    }

    @Test func notWritableNamesTheFolder() {
        #expect(UpdateText.message(for: InstallBlocker.notWritable(path: "/Applications/Iter.app")).contains("“Applications”"))
        #expect(UpdateText.message(for: InstallBlocker.notWritable(path: "/Volumes/Tools")).contains("“Tools”"))
    }

    @Test func versionTextFormats() {
        #expect(VersionText.full(short: "0.1.0", build: "412", commit: "abc1234", includesCommit: false) == "Version 0.1.0 (412)")
        #expect(VersionText.full(short: "0.1.0", build: "0", commit: "", includesCommit: true) == "Version 0.1.0 (dev)")
        #expect(VersionText.full(short: "0.1.0", build: "412", commit: "abc1234", includesCommit: true) == "Version 0.1.0 (412) · abc1234")
        #expect(VersionText.full(short: "0.1.0", build: "0", commit: "abc1234", includesCommit: true) == "Version 0.1.0 (dev) · abc1234")
        #expect(VersionText.plain(short: "0.2.0", build: "7") == "0.2.0 (7)")
    }

    @MainActor @Test func releaseNotesRenderAsMarkdown() {
        let text = UpdateWindowView.notes("**Fixed** a crash.\n- one\n- two")
        #expect(String(text.characters).contains("Fixed a crash."))
        #expect(String(text.characters).contains("- two"))
    }
}
