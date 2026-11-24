import SwiftUI
import IterModel
import IterGo
import IterGoActivity
import IterFeatures
import IterUI

/// The floating sheet's content for every phase (the shell mounts it in a system sheet over `GoMapLayer`; there is no
/// NavigationStack inside, so it only sets the title and toolbar). Top to bottom while a run is on: the undo banner, the
/// hero card (the glanceable part, visible at the medium detent), one calm permission row, alerts, conditions, data
/// freshness, and what is left of the schedule. Not running it is the start view; finished it is the summary.
public struct GoSheetContent: View {
    let snapshot: GoSnapshot
    let permissions: GoPermissions
    let now: Date
    let trips: [GoTripChoice]
    let actions: GoActions

    @AppStorage(GoNightView.key) private var night = false
    @State private var finishedDismissed = false
    @State private var confirmingEnd = false

    public init(snapshot: GoSnapshot, permissions: GoPermissions, now: Date, trips: [GoTripChoice], actions: GoActions) {
        self.snapshot = snapshot
        self.permissions = permissions
        self.now = now
        self.trips = trips
        self.actions = actions
    }

    public var body: some View {
        let screen = GoFlow.screen(for: snapshot.phase, finishedDismissed: finishedDismissed)
        content(screen)
            .navigationTitle(title(screen))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbar(screen) }
            .confirmationDialog("End this trip?", isPresented: $confirmingEnd, titleVisibility: .visible) {
                Button("End Trip", role: .destructive) { Task { await actions.end() } }
                Button("Keep Going", role: .cancel) {}
            } message: {
                Text("Iter stops tracking and shows what you shot.")
            }
            .preferredColorScheme(night ? .dark : nil)
            .onChange(of: snapshot.phase) { _, phase in if phase != .finished { finishedDismissed = false } }
    }

    private func title(_ screen: GoFlow.Screen) -> String {
        screen == .running && !snapshot.tripName.isEmpty ? snapshot.tripName : "Go"
    }

    @ViewBuilder private func content(_ screen: GoFlow.Screen) -> some View {
        switch screen {
        case .start:
            GoStartView(trips: trips, permissionStep: permissions.nextStep, actions: actions)
        case .finished:
            GoFinishedView(snapshot: snapshot, done: { finishedDismissed = true })
        case .running:
            running
        }
    }

    // MARK: Running

    private var running: some View {
        let step = permissions.nextStep
        let placement = step.map(GoFlow.permissionPlacement)
        let freshnessLeads = GoFlow.freshnessLeads(snapshot, now: now)
        return ScrollView {
            VStack(spacing: IterSpace.md) {
                if let undo = snapshot.undo, GoFlow.undoIsVisible(undo, now: now) {
                    GoUndoBanner(undo: undo, now: now, actions: actions)
                }
                if freshnessLeads { GoSections.freshness(snapshot: snapshot, now: now) }
                if let step, placement == .aboveHero { GoPermissionRow(step: step, actions: actions) }
                GoSections.hero(snapshot: snapshot, now: now, actions: actions)
                if let step, placement == .belowHero { GoPermissionRow(step: step, actions: actions) }
                GoSections.alerts(snapshot: snapshot, now: now)
                GoSections.conditions(snapshot: snapshot, now: now)
                if !freshnessLeads { GoSections.freshness(snapshot: snapshot, now: now) }
                GoScheduleSection(snapshot: snapshot, now: now)
            }
            .padding(.horizontal, IterSpace.lg)
            .padding(.bottom, IterSpace.lg)
        }
        // Content scrolls under the floating tab bar: the system's hard bottom edge keeps it from showing through (as in Find).
        .scrollEdgeEffectStyle(.hard, for: .bottom)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private func toolbar(_ screen: GoFlow.Screen) -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                if screen == .running {
                    if snapshot.phase == .paused {
                        Button { Task { await actions.resume() } } label: { Label("Resume Trip", systemImage: "play.fill") }
                    } else {
                        Button { Task { await actions.pause() } } label: { Label("Pause Trip", systemImage: "pause.fill") }
                    }
                    Button(role: .destructive) { confirmingEnd = true } label: { Label("End Trip", systemImage: "xmark.circle") }
                    Divider()
                }
                Toggle(isOn: $night) { Label("Dark for Night Shooting", systemImage: "moon.stars") }
            } label: {
                Label("Trip Options", systemImage: "ellipsis")
            }
        }
    }
}
