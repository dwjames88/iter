import Foundation
import IterModel

/// What the user (and the key vault) decided about sources.
public struct SourceSettings: Sendable {
    /// Sources the user switched off. Wins over everything else.
    public var disabled: Set<SourceID>
    /// Sources that are off by default (`enabledByDefault == false`) and the user switched on.
    public var enabledOverrides: Set<SourceID>
    /// Whether a key for the source is present (the key vault).
    public var hasKey: @Sendable (SourceID) -> Bool

    public init(disabled: Set<SourceID> = [], enabledOverrides: Set<SourceID> = [],
                hasKey: @escaping @Sendable (SourceID) -> Bool = { _ in false }) {
        self.disabled = disabled
        self.enabledOverrides = enabledOverrides
        self.hasKey = hasKey
    }

    public func isEnabled(_ d: SourceDescriptor) -> Bool {
        !disabled.contains(d.id) && (d.enabledByDefault || enabledOverrides.contains(d.id))
    }

    /// False only for a `.required` key that is missing.
    public func keySatisfied(_ d: SourceDescriptor) -> Bool {
        if case .required(let id) = d.key { return hasKey(id) }
        return true
    }
}

/// Chooses providers for a kind of data at a place: supported, covering, enabled, keyed; best first.
public struct SourceRegistry: Sendable {
    public let sources: [any SourceDescribing]
    public let settings: SourceSettings

    public init(sources: [any SourceDescribing], settings: SourceSettings = SourceSettings()) {
        self.sources = sources
        self.settings = settings
    }

    /// Descriptors in preference order: tier (military first), then the descriptor's rank for `kind`, then id.
    public func descriptors(kind: DataKind, at point: Coordinate) -> [SourceDescriptor] {
        Self.rank(sources.map(\.descriptor), kind: kind, at: point, settings: settings)
    }

    /// The matching providers in the same order.
    public func candidates(kind: DataKind, at point: Coordinate) -> [any SourceDescribing] {
        let order = descriptors(kind: kind, at: point).map(\.id)
        return order.compactMap { id in sources.first { $0.descriptor.id == id } }
    }

    /// The matching providers that are also a `P`, in preference order.
    public func providers<P>(_: P.Type, kind: DataKind, at point: Coordinate) -> [P] {
        candidates(kind: kind, at: point).compactMap { $0 as? P }
    }

    /// Why sources that support `kind` were dropped, without repeats: `.outsideCoverage` when an enabled source does not
    /// cover the point, `.needsKey` for an enabled covering source missing its required key. Sources the user turned
    /// off, or that are off by default, are not gaps. When no source supports `kind` at all: `.notProvidedBySource`.
    public func gaps(kind: DataKind, at point: Coordinate) -> [NoDataReason] {
        let supporting = sources.map(\.descriptor).filter { $0.kinds.contains(kind) }
        if supporting.isEmpty { return [.notProvidedBySource] }
        var out: [NoDataReason] = []
        func add(_ r: NoDataReason) { if !out.contains(r) { out.append(r) } }
        for d in supporting where settings.isEnabled(d) {
            if !d.coverage.contains(point) {
                add(.outsideCoverage)
            } else if !settings.keySatisfied(d), case .required(let id) = d.key {
                add(.needsKey(id))
            }
        }
        return out
    }

    /// The pure selection and ordering used by `descriptors(kind:at:)`.
    public static func rank(_ descriptors: [SourceDescriptor], kind: DataKind, at point: Coordinate,
                            settings: SourceSettings) -> [SourceDescriptor] {
        descriptors
            .filter { $0.kinds.contains(kind) && $0.coverage.contains(point) && settings.isEnabled($0) && settings.keySatisfied($0) }
            .sorted {
                if $0.tier != $1.tier { return $0.tier < $1.tier }
                let (a, b) = ($0.rank(for: kind), $1.rank(for: kind))
                if a != b { return a < b }
                return $0.id < $1.id
            }
    }
}
