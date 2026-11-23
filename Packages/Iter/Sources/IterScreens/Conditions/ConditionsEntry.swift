import SwiftUI
import IterFeatures
import IterModel

// CONTRACT STUB (Phase 6 lead). The Conditions screens worker replaces the bodies; the type names and inits stay.

/// Every Conditions section for one place, stacked (when to go, outlook, windows, timeline, compass, hourly, now, alerts,
/// smoke, aurora, horizon, comparison, gaps, source lines). Scrolls itself. Used in the place card and the place page.
public struct ConditionsSections: View {
    let model: ConditionsModel
    public init(model: ConditionsModel) { self.model = model }
    public var body: some View { Text("Conditions") }
}

/// A compact summary (headline window with its score chip, when to go) for cards and lists.
public struct ConditionsSummary: View {
    let model: ConditionsModel
    public init(model: ConditionsModel) { self.model = model }
    public var body: some View { Text("Conditions summary") }
}

/// A place's own page (sidebar ▸ a saved place, or "Open Place Page" from a card or a stop): header (name, locality,
/// actions Save/Add to Trip/Edit/Open in Maps), facts (coordinates, MGRS, declination, elevation, walk-in), then
/// `ConditionsSections`. The Conditions worker owns it.
public struct PlacePageScreen: View {
    let place: Place
    let conditions: ConditionsModel
    let library: LibraryModel
    public init(place: Place, conditions: ConditionsModel, library: LibraryModel) {
        self.place = place; self.conditions = conditions; self.library = library
    }
    public var body: some View { Text(place.name).frame(maxWidth: .infinity, maxHeight: .infinity) }
}
