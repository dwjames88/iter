import SwiftUI
import MapKit
import IterFeatures
import IterGoActivity
import IterGo
import IterScreens

// OWNER: W2 (Go). CONTRACT: the shell mounts these for the Go tab.

/// The map behind the sheet while the Go tab is selected: full screen, its bottom content inset by the sheet's height.
struct GoTabMap: View {
    let shell: IOSShell

    var body: some View {
        let model = shell.go.model
        GoMapLayer(snapshot: model.snapshot, routePath: model.routePath)
            .ignoresSafeArea()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: Self.inset(forSheet: shell.sheetHeight)).allowsHitTesting(false)
            }
    }

    /// The map's bottom inset: the sheet's height, but never more than the part of the screen it should keep clear.
    static func inset(forSheet height: CGFloat) -> CGFloat { min(max(height, 0), 460) }
}

/// The Go tab's root inside the sheet (the shell wraps it in a NavigationStack).
struct GoTabRoot: View {
    let shell: IOSShell

    var body: some View {
        GoTabContent(go: shell.go, consumesNavigation: true)
    }
}

/// The iPad detail for Go: the map with the Go content in a column beside it.
struct GoPadDetail: View {
    let shell: IOSShell

    var body: some View {
        HStack(spacing: 0) {
            GoTabMap(shell: shell)
            Divider()
            NavigationStack { GoTabContent(go: shell.go, consumesNavigation: true) }
                .frame(width: 400)
        }
    }
}

/// `GoSheetContent` bound to the model: the clock, the actions and the Apple Maps hand-off, as `GoRootView` does it.
struct GoTabContent: View {
    let go: GoController
    let consumesNavigation: Bool
    @Environment(\.openURL) private var openURL

    var body: some View {
        let model = go.model
        GoTabClock(perSecond: model.snapshot.undo != nil) { now in
            GoSheetContent(snapshot: model.snapshot, permissions: model.permissions, now: now, trips: go.trips,
                           actions: go.actions(navigate: { open($0) }, openSettings: { openAppSettings() }))
        }
        .onChange(of: model.pendingNavigation) { _, handoff in consume(handoff) }
        .onAppear { consume(model.pendingNavigation) }
    }

    private func consume(_ handoff: NavigationHandoff?) {
        guard consumesNavigation, let handoff else { return }
        open(handoff)
        go.model.consumeNavigation()
    }

    private func open(_ handoff: NavigationHandoff) {
        handoff.mapItem().openInMaps(launchOptions: handoff.launchOptions)
    }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}

/// Ticks `now`: every minute, or every second while an undo counts down.
struct GoTabClock<Content: View>: View {
    let perSecond: Bool
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        if perSecond {
            TimelineView(.periodic(from: .now, by: 1)) { content($0.date) }
        } else {
            TimelineView(.everyMinute) { content($0.date) }
        }
    }
}
