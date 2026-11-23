import SwiftUI
import IterFeatures

// OWNER: W3 (screens). CONTRACT: the shell (W1) mounts these. Keep names and initialisers.

/// The map behind the sheet for the Find tab.
struct FindTabMap: View {
    let shell: IOSShell
    var body: some View { Color.clear }
}

/// The Find tab's root inside the sheet (the shell wraps it in `NavigationStack(path: $shell.findPath)`).
struct FindTabRoot: View {
    let shell: IOSShell
    var body: some View { Text(verbatim: "Find") }
}

struct TripsTabMap: View {
    let shell: IOSShell
    var body: some View { Color.clear }
}

struct TripsTabRoot: View {
    let shell: IOSShell
    var body: some View { Text(verbatim: "Trips") }
}

struct SavedTabMap: View {
    let shell: IOSShell
    var body: some View { Color.clear }
}

struct SavedTabRoot: View {
    let shell: IOSShell
    var body: some View { Text(verbatim: "Saved") }
}

/// What a phone tab's NavigationStack shows for a pushed route (the shell attaches it with `navigationDestination(for: PhoneRoute.self)`).
struct PhoneRouteDestination: View {
    let shell: IOSShell
    let route: PhoneRoute
    var body: some View { Text(verbatim: "\(route)") }
}

/// The iPad detail column for an app route (the sidebar is the shell's).
struct PadDetail: View {
    let shell: IOSShell
    let route: AppRoute
    var body: some View { Text(verbatim: "\(route)") }
}
