import Foundation
import Observation

/// A request to scroll the list to a day; `token` makes a repeat request for the same day a new value.
struct DayScrollRequest: Equatable {
    var day: Int
    var token: Int
}

/// What the trip builder's views share while one trip is open: the selected stop, the selected day, and the list's scroll
/// requests. One `@Observable` per trip, read property by property, so choosing a stop re-evaluates the list and the map
/// (and the pins and rows that really change) and not the header, the day strip or the card around them.
@MainActor @Observable
final class TripViewState {
    /// Who made the last selection, so the other surface follows without echoing: a pin tapped on the map scrolls the
    /// list to its row; a row chosen in the list pans the map to its pin.
    enum Source { case list, map, strip, script }

    var selection: UUID?
    /// The one selected day, shared by the day strip, the list and the map. nil: all days.
    var selectedDay: Int?
    var scrollRequest: DayScrollRequest?
    /// The row to bring into view after a selection on the map.
    var revealRow: UUID?
    @ObservationIgnored private(set) var selectionSource = Source.list

    init(day: Int?) { selectedDay = day }

    /// Selects a stop (nil: none) and remembers where the selection came from.
    func select(_ id: UUID?, from source: Source) {
        guard selection != id else { return }
        selectionSource = source
        selection = id
    }
}
