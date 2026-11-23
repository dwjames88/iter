import Foundation
import IterModel
import IterSources
import IterDiscovery

/// What a source is doing for the owner right now.
public enum SourceRowStatus: Equatable, Sendable {
    case enabled
    /// Switched off by the owner.
    case disabled
    /// Off until the owner turns it on (EUMETSAT, IEM radar: their terms have not been reviewed).
    case offByDefault
    /// Needs a key the owner has not added (never the case today: no source requires one).
    case needsKey
    /// Cannot be used at all, with the plain reason.
    case unavailable(String)
}

/// When a source toggle takes effect.
public enum ToggleTiming: Equatable, Sendable {
    /// The next search (Find rebuilds its engine from preferences each time).
    case nextSearch
    /// The next time Iter opens (the conditions registry reads its settings at launch).
    case nextLaunch
    /// The source is always used; there is nothing to switch.
    case never
}

/// One source in Settings ▸ Sources & Credits (and, for discovery sources, Settings ▸ Search).
public struct SourceRow: Equatable, Identifiable, Sendable {
    public var id: SourceID
    public var name: String
    public var operatorName: String
    public var tier: SourceTier
    /// The honest origin line: "Military-origin via NOAA Aviation Weather Center (military airfields)", "Government (NOAA NCEP)".
    public var originLabel: String
    /// True when any of the data comes from a military producer.
    public var isMilitaryOrigin: Bool
    /// What it supplies, in words ("Forecast, Observations").
    public var kinds: [String]
    public var coverage: String
    public var status: SourceRowStatus
    public var toggleTiming: ToggleTiming
    /// The attribution the credits screen prints in full, and its short form for a card.
    public var attributionShort: String
    public var attributionFull: String
    public var attributionURL: URL?
    public var termsURL: URL?
    /// The data kinds, for filtering to discovery sources.
    public var dataKinds: Set<DataKind>

    public var isToggleable: Bool { toggleTiming != .never }
    public var isOn: Bool { status == .enabled }
}

/// Something the app cannot supply, said plainly.
public struct NamedGap: Equatable, Identifiable, Sendable {
    public var id: String { title }
    public var title: String
    public var explanation: String
}

/// A source that takes an optional key.
public struct KeyRow: Equatable, Identifiable, Sendable {
    public var id: SourceID
    public var sourceName: String
    public var isRequired: Bool
    public var hasKey: Bool
}
