import Foundation
import CoreGraphics

/// The arithmetic of dragging your own pin, kept apart from the view so it can be tested.
///
/// Everything is in one space (the window's): the point under the pointer keeps its offset from the pin's tip, so the pin
/// does not jump to the cursor, and the drop point is the tip, never the lifted drawing.
public enum PinDrag {
    /// How far a pin rises while it is held, in points. Only the drawing rises; the coordinate is the tip's.
    public static let liftPoints: CGFloat = 5

    /// Where the pointer is relative to the tip when the drag starts.
    public static func grab(pointer: CGPoint, tip: CGPoint) -> CGSize {
        CGSize(width: pointer.x - tip.x, height: pointer.y - tip.y)
    }

    /// Where the tip is now: the pointer less the grab offset. Convert this point, not the pointer, to the coordinate.
    public static func tipPoint(pointer: CGPoint, grab: CGSize) -> CGPoint {
        CGPoint(x: pointer.x - grab.width, y: pointer.y - grab.height)
    }

    /// Whether the map's request to clear the selection should be ignored. MapKit deselects a selected pin when it is
    /// clicked; for a pin you can move that click is the first half of "click it, then drag it", so the selection stays.
    /// A click on empty map (the pointer is over no pin) still clears it.
    public static func keepsSelection(writing newValue: String?, selectedID: String?, hoveredID: String?, selectedIsMovable: Bool) -> Bool {
        newValue == nil && selectedID != nil && hoveredID == selectedID && selectedIsMovable
    }
}
