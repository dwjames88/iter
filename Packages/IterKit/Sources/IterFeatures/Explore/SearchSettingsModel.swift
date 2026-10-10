import Foundation
import Observation
import IterCore
import IterServices

/// The user's choices for Explore's search: what they like to shoot, which sources are searched, how results are
/// ordered, and the optional Google credentials. Everything but the Google credentials is kept in `UserDefaults`
/// under keys that start with "IterSearch"; the credentials live only in the Keychain (`DiscoveryKeyStore`).
/// Apple Maps is always searched and cannot be turned off.
@MainActor
@Observable
public final class SearchSettingsModel {
    public static let promptPrefixKey = "IterSearchPromptPrefix"
    public static let enabledSourcesKey = "IterSearchEnabledSources"
    public static let preferenceKey = "IterSearchPreference"
    public static let maxResultsKey = "IterSearchMaxResults"
    public static let learnsFromLibraryKey = "IterSearchLearnsFromLibrary"

    /// The sources the user can switch, in the order a settings screen lists them. Apple Maps is not among them.
    public static let toggleableSources: [DiscoverySourceID] = [.openStreetMap, .wikipedia, .wikivoyage, .reddit, .google]

    /// "What I like to shoot", in the user's words. Multi-line; applied to every Ask and Discovery prompt.
    public var promptPrefix: String {
        didSet { if promptPrefix != oldValue { defaults.set(promptPrefix, forKey: Self.promptPrefixKey) } }
    }

    /// The switchable sources that are on. Never contains `.appleMaps`.
    public private(set) var enabledSources: Set<DiscoverySourceID>

    public var preference: DiscoveryPreference {
        didSet { if preference != oldValue { defaults.set(preference.rawValue, forKey: Self.preferenceKey) } }
    }

    /// Clamped to `DiscoverySettings.maxResultsRange`.
    public var maxResults: Int {
        didSet {
            let clamped = Self.clamp(maxResults)
            if clamped != maxResults { maxResults = clamped; return }
            if maxResults != oldValue { defaults.set(maxResults, forKey: Self.maxResultsKey) }
        }
    }

    /// Opt-in: a short summary of what you pin and add goes into the prompts (never leaves the device).
    public var learnsFromLibrary: Bool {
        didSet { if learnsFromLibrary != oldValue { defaults.set(learnsFromLibrary, forKey: Self.learnsFromLibraryKey) } }
    }

    /// Both Google halves are stored. Observable; refreshed by `setGoogle` and `removeGoogle`.
    public private(set) var hasGoogleKey: Bool
    /// The stored engine id (not secret) so a settings screen can show it. The key itself is never exposed.
    public private(set) var googleEngineID: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let keys: any DiscoveryKeyStore

    public init(defaults: UserDefaults = .standard, keys: any DiscoveryKeyStore) {
        self.defaults = defaults
        self.keys = keys
        promptPrefix = defaults.string(forKey: Self.promptPrefixKey) ?? ""
        if let stored = defaults.array(forKey: Self.enabledSourcesKey) as? [String] {
            enabledSources = Set(stored.compactMap(DiscoverySourceID.init(rawValue:))).subtracting([.appleMaps])
        } else {
            enabledSources = DiscoverySourceID.keyless
        }
        preference = defaults.string(forKey: Self.preferenceKey).flatMap(DiscoveryPreference.init(rawValue:)) ?? .mixed
        maxResults = defaults.object(forKey: Self.maxResultsKey) == nil ? 20 : Self.clamp(defaults.integer(forKey: Self.maxResultsKey))
        learnsFromLibrary = defaults.object(forKey: Self.learnsFromLibraryKey) == nil ? true : defaults.bool(forKey: Self.learnsFromLibraryKey)
        hasGoogleKey = keys.hasGoogleCredentials
        googleEngineID = keys.googleEngineID
    }

    private static func clamp(_ n: Int) -> Int {
        min(DiscoverySettings.maxResultsRange.upperBound, max(DiscoverySettings.maxResultsRange.lowerBound, n))
    }

    // MARK: Sources

    public func isEnabled(_ source: DiscoverySourceID) -> Bool {
        source == .appleMaps || enabledSources.contains(source)
    }

    /// Turns a source on or off. Apple Maps stays on.
    public func setEnabled(_ source: DiscoverySourceID, _ enabled: Bool) {
        guard source != .appleMaps else { return }
        if enabled { enabledSources.insert(source) } else { enabledSources.remove(source) }
        defaults.set(enabledSources.map(\.rawValue).sorted(), forKey: Self.enabledSourcesKey)
    }

    /// At least one source besides Apple Maps is on, so discovery has something to ask.
    public var hasDiscoverySources: Bool { !enabledSources.isEmpty }

    /// The trimmed prefix, or nil when it is empty (for "Using: ..." in the Ask row).
    public var activePromptPrefix: String? {
        let trimmed = promptPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: Google

    /// Stores the user's own Programmable Search key and engine id in the Keychain and switches Google on.
    public func setGoogle(key: String, engineID: String) throws {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let engine = engineID.trimmingCharacters(in: .whitespacesAndNewlines)
        try keys.setGoogleAPIKey(key)
        try keys.setGoogleEngineID(engine)
        refreshGoogle()
        if hasGoogleKey { setEnabled(.google, true) }
    }

    /// Deletes both halves from the Keychain and switches Google off.
    public func removeGoogle() throws {
        try keys.removeGoogleCredentials()
        refreshGoogle()
        setEnabled(.google, false)
    }

    private func refreshGoogle() {
        hasGoogleKey = keys.hasGoogleCredentials
        googleEngineID = keys.googleEngineID
    }

    // MARK: Discovery

    /// The value discovery takes. Apple Maps is always included. `tasteSummary` comes from `TasteSummary.make`, and
    /// is dropped here when the user turned library learning off.
    public func discoverySettings(tasteSummary: String? = nil) -> DiscoverySettings {
        DiscoverySettings(enabledSources: enabledSources.union([.appleMaps]), preference: preference, maxResults: maxResults,
                          promptPrefix: promptPrefix, tasteSummary: learnsFromLibrary ? tasteSummary : nil)
    }
}
