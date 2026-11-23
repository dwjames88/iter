import SwiftUI
import IterFeatures
import IterModel
import IterScreens
import IterUI

/// The root of the iOS app: picks the phone or the pad layout and applies, once, everything both need (the environment,
/// the sharing flows, the launch behaviours).
struct IOSRoot: View {
    let shell: IOSShell
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase

    private var layout: ShellLayout {
        ShellLayout.resolve(isPad: UIDevice.current.userInterfaceIdiom == .pad, horizontalSizeClass: sizeClass)
    }

    var body: some View {
        Group {
            switch layout {
            case .phone:
                #if DEBUG
                if IOSLaunchSwitches.current.d6Probe { PhoneD6ProbeShell(shell: shell) } else { PhoneShell(shell: shell) }
                #else
                PhoneShell(shell: shell)
                #endif
            case .pad:
                PadShell(shell: shell)
            }
        }
        .environment(shell.navigator)
        .environment(shell.library)
        .environment(\.findMapStyle, shell.container.preferences.mapStyle)
        .environment(\.findShowsDaylight, shell.container.preferences.showDaylight)
        .onChange(of: shell.navigator.route) { _, route in
            guard let route else { return }
            shell.show(route)
            // On the phone the navigator only carries requests: clearing it lets the same route be asked for again.
            if layout == .phone { shell.navigator.route = nil }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await shell.go.sceneBecameActive() } }
        }
        .onOpenURL { shell.open($0) }
        .task {
            shell.presentRecoveryNoticeIfNeeded()
            if await shell.go.restoreAtLaunch() { shell.tab = .go }
        }
    }
}

/// The sheets, notices and sharing flows, applied to whatever view is on top (the phone's floating sheet or the pad's split
/// view): a sheet can only present from the topmost presented view.
struct ShellPresentations: ViewModifier {
    let shell: IOSShell

    func body(content: Content) -> some View {
        @Bindable var shell = shell
        content
            .sheet(item: appSheet) { sheet in
                AppSheetContent(shell: shell, sheet: sheet)
            }
            .sheet(isPresented: Binding(get: { shell.recovery != nil }, set: { if !$0 { shell.dismissRecoveryNotice() } })) {
                if let info = shell.recovery {
                    IOSRecoveryNoticeView(info: info) { shell.dismissRecoveryNotice() }
                }
            }
            .onChange(of: shell.navigator.sheet) { _, sheet in
                if sheet == .importTrips {
                    shell.navigator.sheet = nil
                    shell.sharing.beginImport()
                }
            }
            .sheet(isPresented: Binding(get: { shell.showsFirstRun && shell.recovery == nil },
                                        set: { if !$0 { shell.dismissFirstRun() } })) {
                FirstRunGuide { shell.dismissFirstRun() }
                    .presentationDetents([.large])
            }
            .sharingFlows(shell.sharing)
    }

    private var appSheet: Binding<AppSheet?> {
        Binding(get: { shell.navigator.sheet.flatMap { $0 == .importTrips ? nil : $0 } },
                set: { shell.navigator.sheet = $0 })
    }
}

/// The sheets any screen can ask for through `AppNavigator.sheet`, each in its own navigation stack.
struct AppSheetContent: View {
    let shell: IOSShell
    let sheet: AppSheet

    var body: some View {
        switch sheet {
        case .newTrip(let templateID, let firstPlace):
            NavigationStack {
                NewTripSheet(library: shell.library, templateID: templateID, firstPlace: firstPlace) { id in
                    shell.navigator.sheet = nil
                    shell.navigator.open(.trip(id))
                }
            }
            .presentationDetents([.large])
        case .changeDates(let tripID):
            NavigationStack { ChangeDatesSheet(model: shell.buildModel(for: tripID)) }
                .presentationDetents([.large])
        case .editPlace(let id):
            NavigationStack { PlaceEditorSheet(library: shell.library, placeID: id) }
        case .importTrips:
            EmptyView()
        }
    }
}

extension View {
    func shellPresentations(_ shell: IOSShell) -> some View { modifier(ShellPresentations(shell: shell)) }
}

/// The gear that opens Settings, added by the shell onto the Find, Trips and Saved roots.
struct SettingsToolbarButton: ToolbarContent {
    let shell: IOSShell

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { shell.showsSettings = true } label: { Label("Settings", systemImage: "gearshape") }
        }
    }
}

/// Settings as a sheet with Done (iPhone).
struct SettingsSheet: View {
    let shell: IOSShell

    /// `-IterSettings sources` opens Sources & Credits on top (simulator screenshots).
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            IOSSettingsScreen(shell: shell)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { shell.showsSettings = false } } }
                .navigationDestination(for: String.self) { pane in
                    if pane == "sources" { IOSSourcesSettings(model: shell.settings) }
                }
        }
        .onAppear {
            if let pane = shell.settingsLaunchPane, pane == "sources" { path = [pane] }
            shell.settingsLaunchPane = nil
        }
    }
}
