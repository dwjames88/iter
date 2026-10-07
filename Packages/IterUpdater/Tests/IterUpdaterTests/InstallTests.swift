import Darwin
import Foundation
import Synchronization
import Testing
@testable import IterUpdater

/// Real zips, real `ditto`, real swaps inside a temp directory.
@Suite("Bundle install")
struct InstallTests {
    let keys = UpdateSigning.generateKeyPair()

    private struct Fixture {
        let dir: TempDir
        let installedApp: URL      // the "running" v1 bundle
        let archive: URL
        let item: UpdateItem
        let updater: Updater
    }

    private func fixture(
        v2Identifier: String = "studio.test.iter", v2Version: String = "0.2.0", itemVersion: String = "0.2.0",
        requireSignature: Bool = false, publicKey: String?? = nil
    ) throws -> Fixture {
        let dir = try TempDir()
        let apps = dir.child("Applications")
        let staging = dir.child("staging")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let v1 = try makeBundle(in: apps, version: "0.1.0", build: 1, extraFile: "old.txt")
        let v2 = try makeBundle(in: staging, identifier: v2Identifier, version: v2Version, build: 2, extraFile: "new.txt")
        let marker = v2.appendingPathComponent("Contents/Resources/new.txt")
        let value = Array("0081;00000000;Test;".utf8)
        #expect(setxattr(marker.path, "com.apple.quarantine", value, value.count, 0, 0) == 0)

        let archive = dir.child("Iter-0.2.0.zip")
        try zip(v2, to: archive)
        let item = try makeItem(for: archive, version: itemVersion, build: 2, privateKey: keys.privateKey)
        let updater = makeUpdater(
            bundle: v1, publicKey: publicKey ?? keys.publicKey, requireSignature: requireSignature,
            workDirectory: dir.child("work"))
        return Fixture(dir: dir, installedApp: v1, archive: archive, item: item, updater: updater)
    }

    private func installedVersion(_ f: Fixture) -> AppVersion? { AppVersion(infoPlistAt: f.installedApp) }

    @Test func swapsBundleStripsQuarantineAndCleansUp() async throws {
        let f = try fixture()
        let staged = Mutex<[URL]>([])
        let result = try await f.updater.install(archive: f.archive, item: f.item) { dir in staged.withLock { $0.append(dir) } }

        #expect(result.path == f.installedApp.path)
        #expect(installedVersion(f) == AppVersion(version: SemanticVersion("0.2.0")!, build: 2))
        let resources = f.installedApp.appendingPathComponent("Contents/Resources")
        #expect(FileManager.default.fileExists(atPath: resources.appendingPathComponent("new.txt").path))
        #expect(!FileManager.default.fileExists(atPath: resources.appendingPathComponent("old.txt").path))
        #expect(!anyQuarantine(in: f.installedApp))
        for dir in staged.withLock({ $0 }) {
            #expect(!FileManager.default.fileExists(atPath: dir.path), "replacement dir left behind")
        }
        #expect(staged.withLock { $0.count } == 1)
        let siblings = try FileManager.default.contentsOfDirectory(atPath: f.installedApp.deletingLastPathComponent().path)
        #expect(siblings == ["Iter.app"])
    }

    @Test func quarantineIsRestoredByExtractionSoStrippingIsReal() throws {
        // Guards the test above: if ditto stopped round-tripping xattrs the assertion there would be vacuous.
        let f = try fixture()
        let out = f.dir.child("probe")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try runTool("/usr/bin/ditto", ["-x", "-k", f.archive.path, out.path])
        #expect(anyQuarantine(in: out))
    }

    @Test func identifierMismatchIsRejected() async throws {
        let f = try fixture(v2Identifier: "evil.app")
        await #expect(throws: UpdateError.bundleMismatch("identifier evil.app is not studio.test.iter")) {
            try await f.updater.install(archive: f.archive, item: f.item)
        }
        #expect(installedVersion(f)?.version == SemanticVersion("0.1.0"))
    }

    @Test func versionMismatchIsRejected() async throws {
        // A genuine old archive replayed under a newer number in the feed.
        let f = try fixture(itemVersion: "0.3.0")
        await #expect(throws: UpdateError.bundleMismatch("version 0.2.0 is not 0.3.0")) {
            try await f.updater.install(archive: f.archive, item: f.item)
        }
        #expect(installedVersion(f)?.version == SemanticVersion("0.1.0"))
    }

    @Test func buildMismatchIsRejected() async throws {
        var f = try fixture()
        f = Fixture(dir: f.dir, installedApp: f.installedApp, archive: f.archive,
                    item: { var i = f.item; i.build = 9; i.edSignature = f.item.edSignature; return i }(), updater: f.updater)
        await #expect(throws: UpdateError.bundleMismatch("build 2 is not 9")) {
            try await f.updater.install(archive: f.archive, item: f.item)
        }
        #expect(installedVersion(f)?.version == SemanticVersion("0.1.0"))
    }

    @Test func twoAppsInArchiveIsRejected() async throws {
        let f = try fixture()
        let container = f.dir.child("two")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        try makeBundle(in: container, name: "A.app", version: "0.2.0", build: 2)
        try makeBundle(in: container, name: "B.app", version: "0.2.0", build: 2)
        let archive = f.dir.child("two.zip")
        try zip(container, to: archive, keepParent: false)
        let item = try makeItem(for: archive, version: "0.2.0", build: 2, privateKey: keys.privateKey)
        await #expect(throws: UpdateError.archiveInvalid("Expected exactly one top-level .app, found 2 item(s).")) {
            try await f.updater.install(archive: archive, item: item)
        }
        #expect(installedVersion(f)?.version == SemanticVersion("0.1.0"))
    }

    @Test func garbageArchiveIsRejected() async throws {
        let f = try fixture()
        let archive = f.dir.child("junk.zip")
        try Data("this is not a zip".utf8).write(to: archive)
        let item = try makeItem(for: archive, version: "0.2.0", build: 2, privateKey: keys.privateKey)
        await #expect {
            try await f.updater.install(archive: archive, item: item)
        } throws: { error in
            if case UpdateError.archiveInvalid = error { return true }
            return false
        }
        #expect(installedVersion(f)?.version == SemanticVersion("0.1.0"))
    }

    @Test func tamperedArchiveFailsBeforeExtraction() async throws {
        let f = try fixture()
        var bytes = try Data(contentsOf: f.archive)
        bytes[bytes.count / 2] ^= 0xFF
        try bytes.write(to: f.archive)
        await #expect(throws: UpdateError.hashMismatch) { try await f.updater.install(archive: f.archive, item: f.item) }
        #expect(installedVersion(f)?.version == SemanticVersion("0.1.0"))
    }

    @Test func wrongKeyFailsSignature() async throws {
        let f = try fixture(publicKey: .some(UpdateSigning.generateKeyPair().publicKey))
        await #expect(throws: UpdateError.signatureInvalid) { try await f.updater.install(archive: f.archive, item: f.item) }
        #expect(installedVersion(f)?.version == SemanticVersion("0.1.0"))
    }

    @Test func blockersRefuseInstall() async throws {
        let f = try fixture(publicKey: .some(nil))
        await #expect(throws: UpdateError.blocked(.missingPublicKey)) { try await f.updater.install(archive: f.archive, item: f.item) }
        #expect(installedVersion(f)?.version == SemanticVersion("0.1.0"))
    }

    @Test func unsignedBundleIsRejectedWhenSignatureRequired() async throws {
        let f = try fixture(requireSignature: true)
        await #expect {
            try await f.updater.install(archive: f.archive, item: f.item)
        } throws: { error in
            if case UpdateError.codeSignatureInvalid = error { return true }
            return false
        }
        #expect(installedVersion(f)?.version == SemanticVersion("0.1.0"))
    }

    @Test func adHocSignedBundleInstallsWhenSignatureRequired() async throws {
        let dir = try TempDir()
        let apps = dir.child("Applications"), staging = dir.child("staging")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let v1 = try makeBundle(in: apps, version: "0.1.0", build: 1)
        let v2 = try makeBundle(in: staging, version: "0.2.0", build: 2, executable: URL(fileURLWithPath: "/usr/bin/true"))
        try runTool("/usr/bin/codesign", ["-s", "-", "--force", v2.path])
        let archive = dir.child("Iter-0.2.0.zip")
        try zip(v2, to: archive)
        let item = try makeItem(for: archive, version: "0.2.0", build: 2, privateKey: keys.privateKey)
        let updater = makeUpdater(bundle: v1, publicKey: keys.publicKey, requireSignature: true, workDirectory: dir.child("work"))

        _ = try await updater.install(archive: archive, item: item)
        #expect(AppVersion(infoPlistAt: v1)?.version == SemanticVersion("0.2.0"))
        // A signed bundle modified after signing must fail validation.
        let tampered = dir.child("tampered")
        try FileManager.default.createDirectory(at: tampered, withIntermediateDirectories: true)
        try runTool("/usr/bin/ditto", [v1.path, tampered.appendingPathComponent("Iter.app").path])
        let plist = tampered.appendingPathComponent("Iter.app/Contents/Info.plist")
        try (try Data(contentsOf: plist) + Data("\n".utf8)).write(to: plist)
        let tamperedZip = dir.child("t.zip")
        try zip(tampered.appendingPathComponent("Iter.app"), to: tamperedZip)
        let tamperedItem = try makeItem(for: tamperedZip, version: "0.2.0", build: 2, privateKey: keys.privateKey)
        await #expect {
            try await updater.install(archive: tamperedZip, item: tamperedItem)
        } throws: { error in
            if case UpdateError.codeSignatureInvalid = error { return true }
            return false
        }
    }

    @Test func cleanUpRemovesWorkDirectory() throws {
        let f = try fixture()
        let work = f.updater.configuration.workDirectory
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: work.appendingPathComponent("a.zip"))
        f.updater.cleanUp()
        #expect(!FileManager.default.fileExists(atPath: work.path))
    }

    @Test func relauncherStartsDetachedShell() throws {
        // Waits on a pid that is already gone, so `open` runs immediately; the target is a nonexistent path so
        // nothing launches. We only assert the shell starts without throwing.
        try Relauncher.relaunch(appAt: URL(fileURLWithPath: "/nonexistent/Iter.app"), waitingFor: 1_999_999, hidden: true)
    }
}
