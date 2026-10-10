#if os(macOS)
import SwiftUI
import MapKit
import AppKit
import IterCore
import IterFeatures

/// The map's proxy for the selection binding, which is built outside the map's reader. Not state: nothing redraws on it.
/// It also remembers where the last click began (window space, top-left origin): MapKit reports a click on a pin about half
/// a second later, and the pointer may have moved on by then.
///
/// Shared by the Mac maps that let you move your own spots (Explore and Locations): `keepsSelection` is the rule "a click on
/// your selected pin keeps it selected", because MapKit deselects a selected pin when it is clicked and that click is the
/// first half of "click it, then drag it".
@MainActor
final class MapProxyBox {
    var proxy: MapProxy?
    private(set) var lastClick: (point: CGPoint, time: TimeInterval)?
    private var monitor: Any?

    init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            if let window = event.window {
                self?.lastClick = (CGPoint(x: event.locationInWindow.x, y: window.frame.height - event.locationInWindow.y), event.timestamp)
            }
            return event
        }
    }

    isolated deinit { if let monitor { NSEvent.removeMonitor(monitor) } }

    /// Whether the pointer is on the body of the pin whose tip is at `coordinate`, read in window space like the drag.
    func pointerIsOverPin(at coordinate: Coordinate) -> Bool {
        guard let proxy, let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let tip = proxy.convert(CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude), to: .global) else { return false }
        // The click that caused this decides when it is recent; the pointer may have moved on since.
        if let click = lastClick, ProcessInfo.processInfo.systemUptime - click.time < 1.5 {
            return PinDrag.isOnPin(pointer: click.point, tip: tip)
        }
        let mouse = NSEvent.mouseLocation
        return PinDrag.isOnPin(pointer: CGPoint(x: mouse.x - window.frame.minX, y: window.frame.maxY - mouse.y), tip: tip)
    }

    /// Whether the map's request to clear the selection should be ignored: it is a click on the selected pin and that pin is
    /// yours to move. A click on empty map (the pointer is over no pin) still clears it. `hoveredID` is the map's own hover,
    /// where it tracks one (not always, on a pitched map), so the pointer's place is checked too.
    func keepsSelection(writing new: String?, selectedID: String?, selectedCoordinate: Coordinate?, hoveredID: String? = nil,
                        selectedIsMovable: Bool) -> Bool {
        let over = selectedCoordinate.map { pointerIsOverPin(at: $0) } ?? false
        return PinDrag.keepsSelection(writing: new, selectedID: selectedID, hoveredID: over ? selectedID : hoveredID,
                                      selectedIsMovable: selectedIsMovable)
    }
}
#endif
