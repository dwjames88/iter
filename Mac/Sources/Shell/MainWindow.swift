import AppKit
import SwiftUI
import IterFeatures
import IterModel
import IterScreens

/// The main window: a real system sidebar, the detail for the route, and the window's sheets, alerts and import and export.
struct MainWindow: View {
    let shell: AppShell
    @State private var box: Lazy<WindowShell>
    @SceneStorage("iter.route") private var storedRoute = ""
    @SceneStorage("iter.inspectorShown") private var storedInspector = true
    @Environment(\.undoManager) private var undoManager

    private let fixedRoute: AppRoute?

    /// - Parameter route: opens on this route and skips restoration (tests and captures); nil follows `-IterSection`, then
    ///   what the scene restores.
    init(shell: AppShell, route: AppRoute? = nil, find: FindModel? = nil, makeConditions: (@MainActor (Place) -> ConditionsModel)? = nil) {
        self.shell = shell
        fixedRoute = route
        _box = State(initialValue: Lazy {
            WindowShell(shell: shell, initialRoute: route ?? MainWindow.launchRoute(shell), find: find, makeConditions: makeConditions)
        })
    }

    /// `-IterSection` (with `-IterSeedTrip` for `trip`) wins over what the scene restores.
    static func launchRoute(_ shell: AppShell) -> AppRoute? {
        let trips = shell.library.trips
        let first = trips.first { $0.name == SampleLibrary.tripName }?.id ?? trips.first?.id
        return AppRoute.forSection(shell.container.options.section, firstTripID: first)
    }

    var body: some View {
        let window = box.value
        NavigationSplitView {
            SidebarView(window: window)
                .navigationSplitViewColumnWidth(min: 280, ideal: 280, max: 320)
        } detail: {
            DetailView(window: window)
        }
        .navigationTitle(window.windowTitle)
        .frame(minWidth: 761, minHeight: 600)
        .focusedSceneValue(\.windowShell, window)
        .modifier(WindowSheets(shell: shell, window: window))
        .modifier(WindowFiles(window: window))
        .modifier(WindowAlerts(window: window))
        // Screens and sheets read these from the environment (sheets inherit from here, so this sits outside them).
        .environment(window.navigator)
        .environment(window.library)
        .environment(\.findMapStyle, shell.container.preferences.mapStyle)
        .onAppear { appear(window) }
        .onChange(of: undoManager) { window.library.undoManager = undoManager }
        .onChange(of: window.navigator.route) { storedRoute = window.route.stored }
        .onChange(of: window.inspectorShown) { storedInspector = window.inspectorShown }
        .onChange(of: window.library.trips) { window.validateRoute() }
        .onChange(of: window.library.placeFolders) { window.validateRoute() }
        .onChange(of: window.navigator.sheet) { if window.navigator.sheet == .importTrips { window.navigator.sheet = nil; window.beginImport() } }
        .onOpenURL { window.readImport(at: $0) }
        .task { await SmokeRun.runIfRequested(shell: shell, window: window) }
    }

    private func appear(_ window: WindowShell) {
        guard !window.hasAppeared else { return }
        window.library.undoManager = undoManager
        if shell.container.options.section == nil, fixedRoute == nil { window.restore(stored: storedRoute) }
        window.inspectorShown = storedInspector
        window.hasAppeared = true
    }
}

/// The window's sheets: the ones screens ask for through `AppNavigator.sheet`, and the recovery notice.
private struct WindowSheets: ViewModifier {
    let shell: AppShell
    let window: WindowShell

    func body(content: Content) -> some View {
        content
            .sheet(item: sheetBinding) { SheetContent(sheet: $0, window: window) }
            .sheet(isPresented: recoveryBinding) {
                if let info = window.recovery {
                    RecoveryNoticeView(backupFolder: info.backupFolder, skippedFiles: info.skippedFiles,
                                       showInFinder: { NSWorkspace.shared.activateFileViewerSelecting([info.backupFolder]) },
                                       dismiss: dismissRecovery)
                }
            }
    }

    private var sheetBinding: Binding<AppSheet?> {
        Binding(get: { window.navigator.sheet.flatMap { $0 == .importTrips ? nil : $0 } },
                set: { window.navigator.sheet = $0 })
    }

    private var recoveryBinding: Binding<Bool> {
        Binding(get: { window.recovery != nil }, set: { if !$0 { dismissRecovery() } })
    }

    private func dismissRecovery() {
        guard window.recovery != nil else { return }
        window.recovery = nil
        shell.container.markRecoveryNoticeShown()
    }
}

/// Import Trip… and Export…: the system open and save panels.
private struct WindowFiles: ViewModifier {
    let window: WindowShell

    func body(content: Content) -> some View {
        @Bindable var w = window
        content
            .fileImporter(isPresented: $w.showsImporter, allowedContentTypes: [.iterTrip, .json]) { window.chooseImport($0) }
            .fileExporter(isPresented: $w.showsExporter, document: window.exportDocument, contentType: .iterTrip,
                          defaultFilename: window.exportName) { window.finishExport($0) }
    }
}

/// The import choice, the outcome alert and the Debug reset confirmation.
private struct WindowAlerts: ViewModifier {
    let window: WindowShell

    func body(content: Content) -> some View {
        @Bindable var w = window
        content
            .confirmationDialog(pendingTitle, isPresented: pendingBinding, titleVisibility: .visible, presenting: window.pendingImport) { pending in
                Button("Import") { window.performImport(pending, asCopy: false) }
                Button("Import as Copy") { window.performImport(pending, asCopy: true) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Import merges with what you have, and the newer edit of a trip wins. Import as Copy adds everything as new trips and leaves yours alone.")
            }
            .alert(window.notice?.title ?? "", isPresented: noticeBinding, presenting: window.notice) { _ in
                Button("OK") {}
            } message: { Text($0.message) }
            .alert("Delete All Trips and Places?", isPresented: $w.showsResetConfirmation) {
                Button("Delete Everything", role: .destructive) { window.resetAllData() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This can't be undone.") }
    }

    private var pendingBinding: Binding<Bool> {
        Binding(get: { window.pendingImport != nil }, set: { if !$0 { window.pendingImport = nil } })
    }

    private var pendingTitle: String { "Import \"\(window.pendingImport?.name ?? "Trip")\"?" }

    private var noticeBinding: Binding<Bool> {
        Binding(get: { window.notice != nil }, set: { if !$0 { window.notice = nil } })
    }
}

/// The sheets any screen can ask for through `AppNavigator.sheet`.
struct SheetContent: View {
    let sheet: AppSheet
    let window: WindowShell

    var body: some View {
        switch sheet {
        case .newTrip(let templateID, let firstPlace):
            NewTripSheet(library: window.library, templateID: templateID, firstPlace: firstPlace) { id in
                window.navigator.sheet = nil
                window.navigator.open(.trip(id))
            }
        case .changeDates(let tripID):
            ChangeDatesHost(window: window, tripID: tripID)
        case .editPlace(let id):
            PlaceEditorSheet(library: window.library, placeID: id)
        case .importTrips:
            EmptyView()
        }
    }
}

/// Change Dates needs a Build model for its trip: the open one when it is the same trip, else one of its own.
private struct ChangeDatesHost: View {
    let window: WindowShell
    let tripID: UUID
    @State private var box: Lazy<BuildModel>

    init(window: WindowShell, tripID: UUID) {
        self.window = window
        self.tripID = tripID
        _box = State(initialValue: Lazy {
            if let open = window.currentBuild, open.tripID == tripID { return open }
            return window.container.makeBuildModel(tripID: tripID)
        })
    }

    var body: some View {
        ChangeDatesSheet(model: box.value)
    }
}
