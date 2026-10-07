import Foundation
import Testing
@testable import IterUpdater

@Suite("Signing and verification")
struct SigningTests {
    @Test func sha256KnownVector() throws {
        let dir = try TempDir()
        let file = dir.child("abc")
        try Data("abc".utf8).write(to: file)
        #expect(try UpdateVerifier.sha256Hex(ofFileAt: file) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func sha256StreamsAcrossChunkBoundaries() throws {
        let dir = try TempDir()
        let file = dir.child("big")
        let data = Data((0..<(2 * (1 << 20) + 17)).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        try data.write(to: file)
        // Cross-check against a one-shot digest from the system tool.
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
        process.arguments = ["-a", "256", file.path]
        process.standardOutput = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        #expect(try UpdateVerifier.sha256Hex(ofFileAt: file) == output.split(separator: " ").first.map(String.init))
    }

    @Test func signAndVerify() throws {
        let dir = try TempDir()
        let file = dir.child("a.zip")
        try Data("payload".utf8).write(to: file)
        let keys = UpdateSigning.generateKeyPair()
        let signature = try UpdateSigning.sign(fileAt: file, privateKey: keys.privateKey)
        try UpdateVerifier.verifySignature(fileAt: file, signature: signature, publicKey: keys.publicKey)
        #expect(try UpdateSigning.publicKey(forPrivateKey: keys.privateKey) == keys.publicKey)
        // Signatures are randomised, so check validity rather than equality.
        let again = try UpdateSigning.sign(data: Data("payload".utf8), privateKey: keys.privateKey)
        try UpdateVerifier.verifySignature(fileAt: file, signature: again, publicKey: keys.publicKey)
    }

    @Test func tamperedByteFails() throws {
        let dir = try TempDir()
        let file = dir.child("a.zip")
        try Data("payload".utf8).write(to: file)
        let keys = UpdateSigning.generateKeyPair()
        let signature = try UpdateSigning.sign(fileAt: file, privateKey: keys.privateKey)
        try Data("pAyload".utf8).write(to: file)
        #expect(throws: UpdateError.signatureInvalid) {
            try UpdateVerifier.verifySignature(fileAt: file, signature: signature, publicKey: keys.publicKey)
        }
    }

    @Test func wrongKeyFails() throws {
        let dir = try TempDir()
        let file = dir.child("a.zip")
        try Data("payload".utf8).write(to: file)
        let signer = UpdateSigning.generateKeyPair()
        let other = UpdateSigning.generateKeyPair()
        let signature = try UpdateSigning.sign(fileAt: file, privateKey: signer.privateKey)
        #expect(throws: UpdateError.signatureInvalid) {
            try UpdateVerifier.verifySignature(fileAt: file, signature: signature, publicKey: other.publicKey)
        }
    }

    @Test func malformedInputsFail() throws {
        let dir = try TempDir()
        let file = dir.child("a.zip")
        try Data("payload".utf8).write(to: file)
        let keys = UpdateSigning.generateKeyPair()
        #expect(throws: UpdateError.signatureInvalid) {
            try UpdateVerifier.verifySignature(fileAt: file, signature: "!!!not base64!!!", publicKey: keys.publicKey)
        }
        #expect(throws: UpdateError.signatureInvalid) {
            try UpdateVerifier.verifySignature(fileAt: file, signature: "AAAA", publicKey: keys.publicKey)
        }
        #expect(throws: UpdateError.blocked(.missingPublicKey)) {
            try UpdateVerifier.verifySignature(fileAt: file, signature: "AAAA", publicKey: "short")
        }
        #expect(throws: SigningKeyError.invalidPrivateKey) { try UpdateSigning.sign(data: Data(), privateKey: "nope") }
        #expect(throws: SigningKeyError.invalidPrivateKey) { try UpdateSigning.publicKey(forPrivateKey: "AAAA") }
    }

    @Test func verifyArchiveAgainstItem() throws {
        let dir = try TempDir()
        let file = dir.child("a.zip")
        try Data("payload".utf8).write(to: file)
        let keys = UpdateSigning.generateKeyPair()
        let good = try makeItem(for: file, version: "0.2.0", build: 2, privateKey: keys.privateKey)
        try UpdateVerifier.verify(archive: file, against: good, publicKey: keys.publicKey)

        var wrongLength = good
        wrongLength.length += 1
        #expect(throws: UpdateError.sizeMismatch(expected: good.length + 1, actual: good.length)) {
            try UpdateVerifier.verify(archive: file, against: wrongLength, publicKey: keys.publicKey)
        }

        var wrongHash = good
        wrongHash.sha256 = String(repeating: "0", count: 64)
        #expect(throws: UpdateError.hashMismatch) {
            try UpdateVerifier.verify(archive: file, against: wrongHash, publicKey: keys.publicKey)
        }

        var wrongSignature = good
        wrongSignature.edSignature = try UpdateSigning.sign(data: Data("other!!".utf8), privateKey: keys.privateKey)
        #expect(throws: UpdateError.signatureInvalid) {
            try UpdateVerifier.verify(archive: file, against: wrongSignature, publicKey: keys.publicKey)
        }

        var uppercaseHash = good
        uppercaseHash.sha256 = good.sha256.uppercased()
        try UpdateVerifier.verify(archive: file, against: uppercaseHash, publicKey: keys.publicKey)
    }
}

@Suite("CheckSchedule")
struct CheckScheduleTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func neverCheckedIsDue() {
        #expect(CheckSchedule().isDue(lastCheck: nil, now: now))
    }

    @Test func intervalBoundaries() {
        let schedule = CheckSchedule()
        #expect(!schedule.isDue(lastCheck: now.addingTimeInterval(-23 * 3600), now: now))
        #expect(schedule.isDue(lastCheck: now.addingTimeInterval(-24 * 3600), now: now))
        #expect(schedule.isDue(lastCheck: now.addingTimeInterval(-48 * 3600), now: now))
    }

    @Test func clockMovedBackIsDue() {
        let schedule = CheckSchedule()
        #expect(schedule.isDue(lastCheck: now.addingTimeInterval(2 * 3600), now: now))
        // A small skew is tolerated.
        #expect(!schedule.isDue(lastCheck: now.addingTimeInterval(1800), now: now))
    }

    @Test func customInterval() {
        let schedule = CheckSchedule(interval: 600)
        #expect(!schedule.isDue(lastCheck: now.addingTimeInterval(-599), now: now))
        #expect(schedule.isDue(lastCheck: now.addingTimeInterval(-600), now: now))
    }
}

@Suite("InstallBlockers")
struct InstallBlockerTests {
    private let key = UpdateSigning.generateKeyPair().publicKey

    private func blockers(bundle: URL, key: String?, env: [String: String] = [:]) -> [InstallBlocker] {
        InstallEnvironment.blockers(bundleURL: bundle, publicKey: key, environment: env)
    }

    @Test func cleanEnvironmentHasNone() throws {
        let dir = try TempDir()
        let app = try makeBundle(in: dir.url, version: "0.1.0", build: 1)
        #expect(blockers(bundle: app, key: key).isEmpty)
    }

    @Test func sandboxEnvironmentVariable() throws {
        let dir = try TempDir()
        let app = try makeBundle(in: dir.url, version: "0.1.0", build: 1)
        #expect(blockers(bundle: app, key: key, env: ["APP_SANDBOX_CONTAINER_ID": "x"]) == [.sandboxed])
    }

    @Test func translocatedPath() throws {
        let dir = try TempDir()
        let parent = dir.child("AppTranslocation/ABC/d")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let app = try makeBundle(in: parent, version: "0.1.0", build: 1)
        #expect(blockers(bundle: app, key: key) == [.translocated])
    }

    @Test func unwritableParentDirectory() throws {
        let dir = try TempDir()
        let app = try makeBundle(in: dir.url, version: "0.1.0", build: 1)
        chmod(dir.url.path, 0o555)
        defer { chmod(dir.url.path, 0o755) }
        guard geteuid() != 0 else { return }
        #expect(blockers(bundle: app, key: key) == [.notWritable(path: dir.url.path)])
    }

    @Test func missingOrInvalidKey() throws {
        let dir = try TempDir()
        let app = try makeBundle(in: dir.url, version: "0.1.0", build: 1)
        #expect(blockers(bundle: app, key: nil) == [.missingPublicKey])
        #expect(blockers(bundle: app, key: "") == [.missingPublicKey])
        #expect(blockers(bundle: app, key: "not base64!") == [.missingPublicKey])
        #expect(blockers(bundle: app, key: Data(repeating: 1, count: 31).base64EncodedString()) == [.missingPublicKey])
    }

    @Test func updaterExposesBlockers() throws {
        let dir = try TempDir()
        let app = try makeBundle(in: dir.url, version: "0.1.0", build: 1)
        let updater = makeUpdater(bundle: app, publicKey: nil, workDirectory: dir.child("work"))
        #expect(updater.installBlockers(environment: [:]) == [.missingPublicKey])
    }

    @Test func descriptionsAreReadable() {
        #expect(InstallBlocker.notWritable(path: "/x").debugDescription.contains("/x"))
        #expect(UpdateError.blocked(.sandboxed).debugDescription.contains("sandboxed"))
        #expect(UpdateError.sizeMismatch(expected: 2, actual: 1).debugDescription.contains("1"))
    }
}
