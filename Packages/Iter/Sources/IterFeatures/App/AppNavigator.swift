import Foundation
import Observation
import IterModel

/// A sheet or panel any screen can ask the shell to show.
public enum AppSheet: Hashable, Identifiable, Sendable {
    /// New Trip, optionally from a template id (`TripTemplates`), optionally adding a place as its first stop.
    case newTrip(templateID: String?, firstPlace: UUID?)
    /// Change Dates for a trip.
    case changeDates(tripID: UUID)
    /// The place editor (⌘E) for a saved or own place.
    case editPlace(UUID)
    /// The file importer for `.iter` files.
    case importTrips
    public var id: Self { self }
}

/// Cross-screen navigation and requests, shared by the Mac shell and the iOS shells. Screens read it from the environment
/// and ask; the shell owns presentation (sheets, focus, windows). Not persisted itself: the shell restores `route`.
@MainActor @Observable
public final class AppNavigator {
    /// What the detail area shows (the sidebar selection on the Mac).
    public var route: AppRoute?
    /// A sheet the shell should present.
    public var sheet: AppSheet?
    /// Bumped to ask the Find screen to focus its search field (⌘F).
    public private(set) var searchFocusRequest = 0
    /// Bumped to ask Find to run Search Here (⇧⌘F).
    public private(set) var searchHereRequest = 0
    /// Bumped to ask Find to enter Add Spot (drop a pin) mode (⇧⌘N).
    public private(set) var addSpotRequest = 0

    public init(route: AppRoute? = .find) { self.route = route }

    public func open(_ route: AppRoute) { self.route = route }
    public func present(_ sheet: AppSheet) { self.sheet = sheet }
    public func focusSearch() { route = .find; searchFocusRequest += 1 }
    public func searchHere() { route = .find; searchHereRequest += 1 }
    public func addSpot() { route = .find; addSpotRequest += 1 }
}
