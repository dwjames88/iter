import Foundation

/// Checks the feed, downloads and verifies an update, and swaps the bundle. Holds only immutable state, so it
/// can be shared freely across tasks.
public final class Updater: Sendable {
    public let configuration: UpdaterConfiguration
    private let session: URLSession

    public init(configuration: UpdaterConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    public func installBlockers(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [InstallBlocker] {
        InstallEnvironment.blockers(
            bundleURL: configuration.bundleURL, publicKey: configuration.publicKey, environment: environment)
    }

    /// The newest applicable update, or nil when up to date.
    /// Throws `feedUnavailable` (network, HTTP status) or `feedInvalid` (undecodable JSON).
    public func checkForUpdate(skipping: SemanticVersion? = nil) async throws -> UpdateItem? {
        let feed = try await Downloader.fetchFeed(from: configuration.feedURL, session: session)
        return feed.bestUpdate(
            newerThan: configuration.currentVersion, channel: configuration.channel, skipping: skipping)
    }

    /// Downloads into `workDirectory` and verifies length, SHA-256 and the Ed25519 signature.
    /// `progress` gets 0...1, or -1 when the server did not send a length (then a final 1). A file that fails
    /// verification is deleted. Throws `blocked(.missingPublicKey)`, `feedUnavailable` (network or HTTP status),
    /// `sizeMismatch`, `hashMismatch`, `signatureInvalid`, `cancelled`.
    public func downloadAndVerify(_ item: UpdateItem, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let key = configuration.publicKey, InstallEnvironment.isValidPublicKey(key) else {
            throw UpdateError.blocked(.missingPublicKey)
        }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: configuration.workDirectory, withIntermediateDirectories: true)
        } catch {
            throw UpdateError.installFailed("Cannot create \(configuration.workDirectory.path)")
        }
        let destination = configuration.workDirectory.appendingPathComponent("Iter-\(item.version)-\(item.build).zip")
        try? fm.removeItem(at: destination)
        try await Downloader.download(item.url, to: destination, session: session, progress: progress)
        do {
            try UpdateVerifier.verify(archive: destination, against: item, publicKey: key)
        } catch {
            try? fm.removeItem(at: destination)
            throw error
        }
        return destination
    }

    /// Re-verifies the archive (it sat on disk since the download), extracts it next to the bundle, validates it
    /// against `item` and swaps it in. Returns the installed bundle URL. Throws `blocked`, the verification errors
    /// above, `archiveInvalid`, `bundleMismatch`, `codeSignatureInvalid` or `installFailed`. The old bundle is
    /// untouched unless every check passed.
    public func install(archive: URL, item: UpdateItem) async throws -> URL {
        try await install(archive: archive, item: item, replacementObserver: nil)
    }

    func install(archive: URL, item: UpdateItem, replacementObserver: (@Sendable (URL) -> Void)?) async throws -> URL {
        if let blocker = installBlockers().first { throw UpdateError.blocked(blocker) }
        guard let key = configuration.publicKey else { throw UpdateError.blocked(.missingPublicKey) }
        try UpdateVerifier.verify(archive: archive, against: item, publicKey: key)
        return try await Installer.install(
            archive: archive, bundleURL: configuration.bundleURL, bundleIdentifier: configuration.bundleIdentifier,
            item: item, requireValidCodeSignature: configuration.requireValidCodeSignature,
            replacementObserver: replacementObserver)
    }

    /// Removes downloads and staging folders. Safe to call at launch.
    public func cleanUp() {
        try? FileManager.default.removeItem(at: configuration.workDirectory)
        Installer.removeLeftoverReplacementDirectories(for: configuration.bundleURL)
    }
}
