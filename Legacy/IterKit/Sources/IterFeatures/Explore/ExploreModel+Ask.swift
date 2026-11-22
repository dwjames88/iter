import Foundation
import IterCore
import IterServices

/// Ask in Explore: the search field's natural-language path. The engine is `ScoutModel`; this is the glue that gives it
/// the visible map region, turns its grounded suggestions into the Ask section (see `ExploreModel.buildDerived`) and
/// keeps the suggestions, cancel and reset rules in one place.
extension ExploreModel {
    /// The grounded suggestions of the current ask; empty unless it finished with results.
    var askSuggestions: [ScoutSuggestion] {
        if case .results(let found) = askModel.state { return found }
        return []
    }

    public var askState: ScoutState { askModel.state }
    /// The text that produced the current ask (the field may have been edited since).
    public var askSubmittedRequest: String { askModel.submittedRequest }
    public var isAsking: Bool { askModel.isRunning }
    public var askAvailability: ScoutAvailability { askModel.availability }
    /// The Ask section has something to draw: stages, a failure, or results.
    public var hasAskContent: Bool { askModel.state != .idle }

    /// What the field offers for its text: the Apple Maps row until its search is running or shown for that text, and
    /// (for request-like text only) the Ask row until an ask for that text is running or shown. Empty while the field
    /// is empty.
    public var searchSuggestions: [SearchSuggestion] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        let askBusy = askModel.isRunning || (askModel.state != .idle && askModel.submittedRequest == text)
        var mapsBusy = false
        switch searchState {
        case .searching(let q), .failed(let q), .finished(let q, _): mapsBusy = q == text
        case .idle: break
        }
        return SearchSuggestions.make(query: text, askAvailability: askAvailability,
                                      discoveryAvailable: app.discovery != nil && app.searchSettings.hasDiscoverySources).filter { suggestion in
            switch suggestion.kind {
            case .appleMaps: !mapsBusy
            case .ask: !askBusy
            }
        }
    }

    /// Runs one suggestion. An unavailable Ask does nothing.
    public func run(_ suggestion: SearchSuggestion) {
        switch suggestion.kind {
        case .appleMaps: searchAppleMaps()
        case .ask: if suggestion.isAvailable { ask() }
        }
    }

    /// Puts the field's text to the ask engine, with the map's visible region as the area. Replaces a running ask.
    public func ask() {
        closePanel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        cancelSearchHere()
        if askModel.isRunning { askModel.cancel() }
        askModel.request = text
        askModel.run(area: visibleRegion)
        resultSetChanged()
    }

    /// Stops a running ask. The field keeps its text.
    public func cancelAsk() {
        askModel.cancel()
        resultSetChanged()
    }

    /// Removes the Ask section (results or failure) without touching the field.
    public func dismissAsk() {
        askModel.reset()
        resultSetChanged()
    }

    /// "Search Apple Maps Instead": drops the ask and runs the ordinary search for the same text.
    public func searchAppleMapsInstead() {
        dismissAsk()
        searchAppleMaps()
    }
}
