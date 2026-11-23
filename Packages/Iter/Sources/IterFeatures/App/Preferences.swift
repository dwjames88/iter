import Foundation
import Observation
import IterModel
import IterDiscovery

/// The owner's preferences, observable per property and backed by a `UserDefaults` suite that the composition root
/// chooses (the standard one for the app, a throwaway suite for tests and render copies). Keys never hold secrets:
/// API keys live in `KeyVault` (Keychain) only.
@MainActor @Observable
public final class Preferences {
    @ObservationIgnored private let defaults: UserDefaults

    /// "What I Like to Shoot": free text matched by words in discovery ranking, never sent to a source.
    public var preferenceText: String { didSet { defaults.set(preferenceText, forKey: Keys.preferenceText) } }
    /// Popular, Unique or Mixed.
    public var ordering: DiscoveryOrdering { didSet { defaults.set(ordering.rawValue, forKey: Keys.ordering) } }
    /// Most results a Find returns.
    public var resultCap: Int { didSet { defaults.set(resultCap, forKey: Keys.resultCap) } }
    /// Sources the owner switched off in Settings ▸ Search or Sources & Credits.
    public var disabledSources: Set<SourceID> {
        didSet { defaults.set(disabledSources.map(\.rawValue).sorted(), forKey: Keys.disabledSources) }
    }
    /// Sources that are off by default (EUMETSAT, IEM radar) and the owner switched on.
    public var enabledOverrides: Set<SourceID> {
        didSet { defaults.set(enabledOverrides.map(\.rawValue).sorted(), forKey: Keys.enabledOverrides) }
    }
    /// Map style raw value (the shell maps it to MapKit: "hybrid" default, "standard", "imagery").
    public var mapStyle: String { didSet { defaults.set(mapStyle, forKey: Keys.mapStyle) } }
    /// The day and night line on zoomed-out maps.
    public var showDaylight: Bool { didSet { defaults.set(showDaylight, forKey: Keys.showDaylight) } }

    public enum Keys {
        public static let preferenceText = "IterPreferenceText"
        public static let ordering = "IterDiscoveryOrdering"
        public static let resultCap = "IterResultCap"
        public static let disabledSources = "IterDisabledSources"
        public static let enabledOverrides = "IterEnabledSourceOverrides"
        public static let mapStyle = "IterMapStyle"
        public static let showDaylight = "IterShowDaylight"
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        preferenceText = defaults.string(forKey: Keys.preferenceText) ?? ""
        ordering = defaults.string(forKey: Keys.ordering).flatMap(DiscoveryOrdering.init(rawValue:)) ?? .mixed
        let cap = defaults.integer(forKey: Keys.resultCap)
        resultCap = cap > 0 ? cap : 40
        disabledSources = Set((defaults.stringArray(forKey: Keys.disabledSources) ?? []).map { SourceID(rawValue: $0) })
        enabledOverrides = Set((defaults.stringArray(forKey: Keys.enabledOverrides) ?? []).map { SourceID(rawValue: $0) })
        mapStyle = defaults.string(forKey: Keys.mapStyle) ?? "hybrid"
        showDaylight = defaults.object(forKey: Keys.showDaylight) as? Bool ?? true
    }

    /// A throwaway in-memory suite (tests, previews, render copies).
    public static func ephemeral() -> Preferences {
        let name = "iter.ephemeral.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return Preferences(defaults: d)
    }
}
