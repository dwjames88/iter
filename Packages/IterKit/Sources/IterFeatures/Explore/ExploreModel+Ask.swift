import Foundation
import IterCore
import IterServices

/// Ask in Explore: the search field's natural-language path. The engine is `ScoutModel`; this is the glue that gives it
/// the visible map region, turns its grounded suggestions into the Ask section (see `ExploreModel.buildDerived`) and
/// keeps the offer, cancel and reset rules in one place.
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

    /// The "Ask Iter…" row is offered when the field has text and no ask is running or shown for that text.
    public var offersAsk: Bool {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !askModel.isRunning else { return false }
        return askModel.state == .idle || askModel.submittedRequest != text
    }

    /// Puts the field's text to the ask engine, with the map's visible region as the area. Replaces a running ask.
    public func ask() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
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
        askMode = false
        dismissAsk()
        searchAppleMaps()
    }
}
