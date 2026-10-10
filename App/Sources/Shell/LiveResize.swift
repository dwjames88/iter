import SwiftUI
import AppKit

/// Whether the main window is in a live resize (the user is dragging its edge). One flag, written twice per drag (start and
/// end), so views can hold what is expensive to re-lay-out while it is true and apply the new size once at the end.
/// `MainWindowConfigurator` sets it from the window's `willStartLiveResize` and `didEndLiveResize` notifications; the
/// `-IterResizeScript` posts the same two notifications around its sweep.
@MainActor @Observable
final class LiveResize {
    static let shared = LiveResize()
    private(set) var isActive = false

    func begin() { if !isActive { isActive = true } }
    func end() { if isActive { isActive = false } }
}
