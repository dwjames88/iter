import Darwin
import Foundation
import Security

/// Unpacks a verified archive, validates the bundle inside, and swaps it in for the running one.
enum Installer {
    static let replacementPrefix = "NSIRD_"

    static func install(
        archive: URL, bundleURL: URL, bundleIdentifier: String, item: UpdateItem,
        requireValidCodeSignature: Bool, replacementObserver: (@Sendable (URL) -> Void)? = nil
    ) async throws -> URL {
        let fm = FileManager.default

        // The replacement directory must be on the same volume as the bundle so the swap is atomic.
        let replacementDir: URL
        do {
            replacementDir = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: bundleURL, create: true)
        } catch {
            throw UpdateError.installFailed("Cannot create a staging folder: \(error.localizedDescription)")
        }
        replacementObserver?(replacementDir)
        defer { try? fm.removeItem(at: replacementDir) }

        let extracted = replacementDir.appendingPathComponent("extracted", isDirectory: true)
        try fm.createDirectory(at: extracted, withIntermediateDirectories: true)
        let newBundle = try await extract(archive: archive, into: extracted, logDirectory: replacementDir)

        try validateIdentity(of: newBundle, bundleIdentifier: bundleIdentifier, item: item)
        if requireValidCodeSignature { try checkCodeSignature(at: newBundle) }
        try stripQuarantine(at: newBundle)

        do {
            let installed = try fm.replaceItemAt(bundleURL, withItemAt: newBundle)
            return installed ?? bundleURL
        } catch {
            throw UpdateError.installFailed("Cannot replace the app: \(error.localizedDescription)")
        }
    }

    /// Removes staging folders a crashed or killed process left behind. Only this program's own names are
    /// touched, and only ones idle for a minute, so another app's folders and an install in flight are safe.
    static func removeLeftoverReplacementDirectories(for bundleURL: URL) {
        let fm = FileManager.default
        guard let probe = try? fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: bundleURL, create: true) else { return }
        let parent = probe.deletingLastPathComponent()
        try? fm.removeItem(at: probe)
        let prefix = "\(replacementPrefix)\(ProcessInfo.processInfo.processName)_"
        let cutoff = Date(timeIntervalSinceNow: -60)
        for name in (try? fm.contentsOfDirectory(atPath: parent.path)) ?? [] where name.hasPrefix(prefix) {
            let url = parent.appendingPathComponent(name)
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff { try? fm.removeItem(at: url) }
        }
    }

    // MARK: Steps

    private static func extract(archive: URL, into directory: URL, logDirectory: URL) async throws -> URL {
        let log = logDirectory.appendingPathComponent("ditto.log")
        let status: Int32
        do {
            status = try await run("/usr/bin/ditto", ["-x", "-k", archive.path, directory.path], stderrTo: log)
        } catch {
            throw UpdateError.installFailed("Cannot run ditto: \(error.localizedDescription)")
        }
        guard status == 0 else {
            let message = (try? String(contentsOf: log, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw UpdateError.archiveInvalid(message.isEmpty ? "ditto exited with status \(status)" : message)
        }
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        // Resource-fork litter is not content.
        let content = entries.filter { $0 != "__MACOSX" && $0 != ".DS_Store" }
        let apps = content.filter { $0.hasSuffix(".app") }
        guard apps.count == 1, content.count == 1 else {
            throw UpdateError.archiveInvalid("Expected exactly one top-level .app, found \(content.count) item(s).")
        }
        return directory.appendingPathComponent(apps[0], isDirectory: true)
    }

    /// Read from disk, not `Bundle(url:)`, which can hand back a cached Info.plist.
    private static func validateIdentity(of bundle: URL, bundleIdentifier: String, item: UpdateItem) throws {
        guard let info = AppVersion.readInfoDictionary(ofBundleAt: bundle) else {
            throw UpdateError.archiveInvalid("The app has no readable Info.plist.")
        }
        let identifier = info["CFBundleIdentifier"] as? String
        guard identifier == bundleIdentifier else {
            throw UpdateError.bundleMismatch("identifier \(identifier ?? "(none)") is not \(bundleIdentifier)")
        }
        let short = info["CFBundleShortVersionString"] as? String
        guard let short, SemanticVersion(short) == item.version else {
            throw UpdateError.bundleMismatch("version \(short ?? "(none)") is not \(item.version)")
        }
        let build = (info["CFBundleVersion"] as? String).flatMap { Int($0) } ?? (info["CFBundleVersion"] as? Int)
        guard build == item.build else {
            throw UpdateError.bundleMismatch("build \(build.map(String.init) ?? "(none)") is not \(item.build)")
        }
    }

    private static func checkCodeSignature(at bundle: URL) throws {
        var code: SecStaticCode?
        var status = SecStaticCodeCreateWithPath(bundle as CFURL, [], &code)
        guard status == errSecSuccess, let code else { throw UpdateError.codeSignatureInvalid(describe(status)) }
        // Team is deliberately not pinned (Ed25519 is the trust anchor), only that the bundle is intact.
        let flags = SecCSFlags(rawValue: UInt32(kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode))
        status = SecStaticCodeCheckValidity(code, flags, nil)
        guard status == errSecSuccess else { throw UpdateError.codeSignatureInvalid(describe(status)) }
    }

    private static func describe(_ status: OSStatus) -> String {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)"
    }

    /// Clears `com.apple.quarantine` on the bundle and everything in it, without following symlinks.
    /// A missing attribute (ENOATTR) is the normal case.
    static func stripQuarantine(at root: URL) throws {
        let fm = FileManager.default
        var paths = [root.path]
        paths += ((try? fm.subpathsOfDirectory(atPath: root.path)) ?? []).map { root.appendingPathComponent($0).path }
        for path in paths where removexattr(path, "com.apple.quarantine", XATTR_NOFOLLOW) != 0 {
            let code = errno
            if code == ENOATTR || code == ENOTSUP { continue }
            throw UpdateError.installFailed("Cannot clear quarantine on \(path): \(String(cString: strerror(code)))")
        }
    }

    // MARK: Process

    private static func run(_ path: String, _ arguments: [String], stderrTo log: URL) async throws -> Int32 {
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let errHandle = try FileHandle(forWritingTo: log)
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = errHandle
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
            try? errHandle.close()
        }
    }
}
