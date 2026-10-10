import Foundation
import IterCore
import IterData

/// What a map needs from the model behind it to let you move your own spots: Explore's model and `OwnPinDragModel` (the
/// Locations maps) both provide it, and one view modifier (`ownPinDrag`) drives it on both platforms.
@MainActor
public protocol PinDragHost: AnyObject {
    /// The pin being carried and where it is now; nil when none is.
    var dragging: (id: String, coordinate: Coordinate)? { get }
    /// Only your own spots move.
    func canMove(_ id: String) -> Bool
    /// Starts carrying a pin (selecting it without moving the camera). False when it cannot move now.
    @discardableResult func beginDrag(_ id: String) -> Bool
    func drag(to coordinate: Coordinate)
    /// The drop: `commit` stores the carried-to coordinate, otherwise the pin goes back.
    func endDrag(commit: Bool)
    /// Where to draw a pin: the carried coordinate while it is carried, else the stored one.
    func displayCoordinate(for id: String, stored: Coordinate) -> Coordinate
}

/// Moving your own spots on a map that lists saved spots (the Locations maps). The ids are spot ids, which for your own
/// spots are their place record ids. Nothing is stored until the drop; the drop is one "Move Spot" undo step and the
/// spot's forecast is fetched again so its score follows the pin.
@Observable @MainActor
public final class OwnPinDragModel: PinDragHost {
    @ObservationIgnored private let app: AppModel
    /// Called with the pin's id when a drag begins: the map selects the pin (without moving its camera).
    @ObservationIgnored public var onBegin: ((String) -> Void)?
    public private(set) var dragging: (id: String, coordinate: Coordinate)?
    @ObservationIgnored private var origin: Coordinate?

    public init(app: AppModel, onBegin: ((String) -> Void)? = nil) {
        self.app = app
        self.onBegin = onBegin
    }

    public func canMove(_ id: String) -> Bool {
        guard let uuid = UUID(uuidString: id), let place = app.store.place(id: uuid) else { return false }
        return place.origin == .user
    }

    @discardableResult
    public func beginDrag(_ id: String) -> Bool {
        guard dragging == nil, canMove(id), let uuid = UUID(uuidString: id), let place = app.store.place(id: uuid) else { return false }
        origin = place.coordinate
        dragging = (id, place.coordinate)
        onBegin?(id)
        return true
    }

    public func drag(to coordinate: Coordinate) {
        guard let current = dragging else { return }
        dragging = (current.id, coordinate)
    }

    public func endDrag(commit: Bool) {
        guard let current = dragging else { return }
        let before = origin
        dragging = nil
        origin = nil
        guard commit, current.coordinate != before, app.store.moveSpot(id: current.id, to: current.coordinate),
              let uuid = UUID(uuidString: current.id), let place = app.store.place(id: uuid) else { return }
        app.spotSaved(place.spot)
    }

    public func displayCoordinate(for id: String, stored: Coordinate) -> Coordinate {
        if let dragging, dragging.id == id { return dragging.coordinate }
        return stored
    }
}
