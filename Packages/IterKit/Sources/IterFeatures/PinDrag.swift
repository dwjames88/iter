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

    /// Whether a window-space point is on the body of a pin whose tip is at `tip`: the event unit stands on its tip, about
    /// 60 pt wide and 30 pt tall. The margins cover MapKit drawing a pin a few points off `proxy.convert`'s place under pitch
    /// and terrain (12 pt seen), and the tip dot below the tip.
    public static func isOnPin(pointer: CGPoint, tip: CGPoint) -> Bool {
        abs(pointer.x - tip.x) <= 36 && pointer.y >= tip.y - 48 && pointer.y <= tip.y + 12
    }
}
