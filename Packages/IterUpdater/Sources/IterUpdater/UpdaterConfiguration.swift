import Foundation

public struct UpdaterConfiguration: Sendable {
    public var feedURL: URL
    public var publicKey: String?
    public var channel: String
    public var bundleURL: URL
    public var bundleIdentifier: String
    public var currentVersion: AppVersion
    /// Where downloads live. Default: `Caches/<bundle id>/Updates`.
    public var workDirectory: URL
    public var requireValidCodeSignature: Bool

    public init(
        feedURL: URL, publicKey: String?, channel: String = "release", bundleURL: URL,
        bundleIdentifier: String, currentVersion: AppVersion, workDirectory: URL? = nil,
        requireValidCodeSignature: Bool = true
    ) {
        self.feedURL = feedURL
        self.publicKey = publicKey
        self.channel = channel
        self.bundleURL = bundleURL
        self.bundleIdentifier = bundleIdentifier
        self.currentVersion = currentVersion
        self.workDirectory = workDirectory ?? Self.defaultWorkDirectory(bundleIdentifier: bundleIdentifier)
        self.requireValidCodeSignature = requireValidCodeSignature
    }

    static func defaultWorkDirectory(bundleIdentifier: String) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
    }

    /// Reads IterUpdateFeedURL (UserDefaults wins over Info.plist, for local testing), IterUpdatePublicKey and
    /// IterUpdateChannel. Nil when the bundle has no usable feed URL, identifier or version.
    public static func fromBundle(_ bundle: Bundle = .main, defaults: UserDefaults = .standard) -> UpdaterConfiguration? {
        let info = bundle.infoDictionary ?? [:]
        let feedString = nonEmpty(defaults.string(forKey: "IterUpdateFeedURL")) ?? nonEmpty(info["IterUpdateFeedURL"] as? String)
        guard let feedString, let feedURL = URL(string: feedString), feedURL.scheme != nil,
              let identifier = bundle.bundleIdentifier,
              let version = AppVersion(bundle: bundle) else { return nil }
        return UpdaterConfiguration(
            feedURL: feedURL,
            publicKey: nonEmpty(info["IterUpdatePublicKey"] as? String),
            channel: nonEmpty(defaults.string(forKey: "IterUpdateChannel")) ?? "release",
            bundleURL: bundle.bundleURL,
            bundleIdentifier: identifier,
            currentVersion: version
        )
    }

    private static func nonEmpty(_ string: String?) -> String? {
        guard let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
