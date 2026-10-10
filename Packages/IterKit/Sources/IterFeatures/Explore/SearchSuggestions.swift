import Foundation
import IterCore

/// One thing the search field offers to do with its text.
public struct SearchSuggestion: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        /// Look the text up as a place on Apple Maps.
        case appleMaps(query: String)
        /// Put the text to the ask engine (Apple Intelligence). `availability` is what the engine reports now.
        case ask(query: String, availability: ScoutAvailability)
    }

    public var kind: Kind
    /// The suggestion Return runs: the first of the list.
    public var isTop: Bool
    /// Set on the Apple Maps row when the text reads "<feature> in <area>" and Discovery will answer it too, so the
    /// app can label the row "Mountains in Glacier National Park" and mention the sources.
    public var featureQuery: FeatureAreaQuery?

    public init(kind: Kind, isTop: Bool, featureQuery: FeatureAreaQuery? = nil) {
        self.kind = kind
        self.isTop = isTop
        self.featureQuery = featureQuery
    }

    public var id: String {
        switch kind {
        case .appleMaps: "appleMaps"
        case .ask: "ask"
        }
    }

    public var query: String {
        switch kind {
        case .appleMaps(let query), .ask(let query, _): query
        }
    }

    /// False only for an Ask the device cannot run (Apple Intelligence off, not eligible, not ready, not in the build).
    public var isAvailable: Bool {
        if case .ask(_, let availability) = kind { return availability == .available }
        return true
    }

    /// Why the Ask cannot run; nil when it can, and always nil for Apple Maps.
    public var unavailableReason: ScoutAvailability? {
        if case .ask(_, let availability) = kind, availability != .available { return availability }
        return nil
    }
}

/// What Explore's one search field offers for its text. Pure.
///
/// - Empty (or blank) text: nothing.
/// - Always an Apple Maps row first (`isTop`): Return runs the local search for any text.
/// - An Ask row after it only when the text reads like a request (`SearchIntent.classify`); place-like text
///   ("Mesa Arch", "Great Smoky Mountains National Park") gets none. An Ask that cannot run stays in the list,
///   flagged unavailable. The Ask is never the top row.
public enum SearchSuggestions {
    /// `discoveryAvailable`: an engine is present and a Discovery source is on; then a "<feature> in <area>" text marks
    /// the top row with its parsed query (it runs as a feature search).
    public static func make(query: String, askAvailability: ScoutAvailability, discoveryAvailable: Bool = false) -> [SearchSuggestion] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        let feature = discoveryAvailable ? SearchIntent.featureQuery(text) : nil
        var list = [SearchSuggestion(kind: .appleMaps(query: text), isTop: true, featureQuery: feature)]
        if SearchIntent.classify(text) == .ask {
            list.append(SearchSuggestion(kind: .ask(query: text, availability: askAvailability), isTop: false))
        }
        return list
    }
}
