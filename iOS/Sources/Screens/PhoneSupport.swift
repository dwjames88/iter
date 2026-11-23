import SwiftUI
import IterFeatures
import IterConditions
import IterModel
import IterSky
import IterStore
import IterScreens

// Shared helpers of the iPhone and iPad screens (OWNER: W3).

/// How far the maps inset their content from the bottom: the sheet's height, never more than this (at full height the sheet
/// hides the map anyway, and the camera should not be squeezed to nothing).
enum PhoneMapInset {
    static let ceiling: CGFloat = 460
    static func bottom(sheetHeight: CGFloat) -> CGFloat { max(0, min(sheetHeight, ceiling)) }
}

extension IOSShell {
    /// The bottom inset the maps use right now.
    var mapBottomInset: CGFloat { PhoneMapInset.bottom(sheetHeight: sheetHeight) }

    /// The path of a tab's navigation stack.
    func appendRoute(_ route: PhoneRoute, to tab: PhoneTab) {
        switch tab {
        case .find: findPath.append(route)
        case .trips: tripsPath.append(route)
        case .saved: savedPath.append(route)
        case .go: break
        }
    }

    /// Pushes an app route onto the stack of the tab it came from (so Back returns to the list), or shows it the shell's way when
    /// the route is a whole destination (Find, All Trips, Saved Places).
    func push(_ route: AppRoute, from tab: PhoneTab) {
        switch route {
        case .trip(let id): appendRoute(.trip(id), to: tab == .go ? .trips : tab)
        case .tripFolder(let id): appendRoute(.tripFolder(id), to: .trips)
        case .placeFolder(let id): appendRoute(.placeFolder(id), to: .saved)
        case .place(let id): appendRoute(.place(id), to: tab == .go ? .saved : tab)
        case .find, .allTrips, .savedPlaces: show(route)
        }
    }

    /// The score the All Trips hero chip shows for a stop's window: the report Conditions already has (shared store), else a
    /// background request and nil until it lands. The same closure as the Mac's `WindowShell.lightScore`.
    var lightScore: @MainActor @Sendable (Place, LocalDay, LightWindowKind) -> Int? {
        let store = container.conditions
        return { place, day, kind in
            if let report = store.report(for: place.id, day: day) {
                return report.daylight.windows.first { $0.kind == kind }?.score
            }
            Task { @MainActor in store.request(place, day: day, priority: .background) }
            return nil
        }
    }
}

extension View {
    /// What the shared screens read from the environment: navigator, library and the map style.
    func iterShellEnvironment(_ shell: IOSShell) -> some View {
        environment(shell.navigator)
            .environment(shell.library)
            .environment(\.findMapStyle, shell.container.preferences.mapStyle)
            .environment(\.findShowsDaylight, shell.container.preferences.showDaylight)
    }
}

/// The trip the Find tab adds places to, after "Add Stop" in the Trip Builder: the trip and the zero-based day. Cleared by Done.
@MainActor @Observable
final class FindAddTarget {
    static let shared = FindAddTarget()
    var tripID: UUID?
    var day = 0
    /// The name of the last place added, for the banner's confirmation.
    var lastAdded: String?

    func set(tripID: UUID, day: Int) {
        self.tripID = tripID
        self.day = day
        lastAdded = nil
    }

    func clear() {
        tripID = nil
        lastAdded = nil
    }
}
