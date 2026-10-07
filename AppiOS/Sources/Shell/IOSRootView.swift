import SwiftUI
import IterCore
import IterData
import IterFeatures

/// The scene root: one `AppNavigation` (the same type the Mac window uses, so every shared view can call `show` and `open`),
/// one Explore model, the undo manager, `.iter` import, and the shell for the current width: the tab bar on iPhone and in
/// compact width, the split view with the sidebar on iPad.
struct IOSRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var navigation = AppNavigation()
    @State private var shell = ShellState()
    @State private var importError: String?

    var body: some View {
        IOSExploreHost {
            Group {
                if sizeClass == .regular {
                    PadShell()
                } else {
                    PhoneShell()
                }
            }
        }
        .environment(navigation)
        .environment(shell)
        .environment(\.openIterSettings, OpenIterSettingsAction { shell.showSettings() })
        .onAppear {
            model.store.undoManager = undoManager
            applyLaunchSelection()
        }
        .onChange(of: undoManager) { _, new in model.store.undoManager = new }
        .onChange(of: navigation.selection) { _, new in shell.follow(new) }
        .onChange(of: model.store.revision) { fixStaleSelection() }
        .onOpenURL { url in importTrip(from: url) }
        .alert(String(localized: "Couldn't open this trip", comment: "Alert title"),
               isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button(String(localized: "OK", comment: "Alert button")) {}
        } message: {
            Text(importError ?? "")
        }
    }

    /// The same launch switches as the Mac (`-IterSection`, `-IterSpot`, `-IterLocationFolder`), plus `settings` and `search`.
    private func applyLaunchSelection() {
        if let forced = AppLaunch.section {
            navigation.selection = forced
        } else if AppLaunch.sectionName == "trip", let first = model.store.pinnedTrips().first ?? model.store.trips().first {
            navigation.selection = .trip(first.id)
        } else {
            navigation.selection = .explore
        }
        if let name = AppLaunch.locationFolderName,
           let folder = model.store.folders(kind: .locations).flatMap({ [$0] + model.store.subfolders(of: $0) })
               .first(where: { $0.name == name }) {
            navigation.selection = .locationFolder(folder.id)
        }
        if let spot = AppLaunch.spot {
            navigation.selection = .explore
            navigation.explorePath = [SpotRoute(spot: spot)]
        }
        shell.follow(navigation.selection)
        switch AppLaunch.sectionName {
        case "settings": shell.showSettings()
        case "search": shell.phoneTab = .search
        default: break
        }
    }

    private func fixStaleSelection() {
        switch navigation.selection {
        case .trip(let id) where model.store.trip(id: id) == nil: navigation.selection = .trips
        case .locationFolder(let id) where model.store.folder(id: id) == nil: navigation.selection = .locations
        default: break
        }
    }

    /// A `.iter` file opened from Files, Mail or the share sheet lands here as a new trip and opens it.
    private func importTrip(from url: URL) {
        guard url.isFileURL else { return }
        switch TripImport.read(url, into: model.store) {
        case .success(let id): navigation.show(.trip(id))
        case .failure(let message): importError = message
        }
    }
}

/// Reads a `.iter` trip file into the store. Shared by `onOpenURL` and the Trips list's Import.
enum TripImport {
    enum Outcome { case success(UUID), failure(String) }

    @MainActor static func read(_ url: URL, into store: IterStore) -> Outcome {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let document = try TripDocument.decode(Data(contentsOf: url))
            return .success(store.importTrip(document).id)
        } catch TripDocument.DocumentError.unsupportedVersion {
            return .failure(String(localized: "It was made by a newer version of Iter.", comment: "Import error"))
        } catch {
            return .failure(String(localized: "The file isn't a readable Iter trip.", comment: "Import error"))
        }
    }
}

/// iOS-only shell state beside `AppNavigation`: the phone's tab, the trip and folder each tab has open, and the iPad Settings sheet.
/// `AppNavigation.selection` stays the single "where am I" that shared views write; the shell follows it.
@MainActor
@Observable
final class ShellState {
    enum PhoneTab: Hashable { case explore, trips, locations, settings, search }

    var phoneTab: PhoneTab = .explore
    /// The trip open on the phone's Trips tab (pushed above the list), kept while you visit other tabs.
    var openTripID: UUID?
    /// The location folder open on the phone's Locations tab.
    var openFolderID: UUID?
    /// iPad: Settings is a sheet over the split view.
    var showsSettingsSheet = false
    var usesTabs = true

    func showSettings() {
        if usesTabs { phoneTab = .settings } else { showsSettingsSheet = true }
    }

    /// Mirrors a selection change made anywhere (a shared view calling `navigation.show`) onto the phone's tabs.
    func follow(_ selection: SidebarItem?) {
        switch selection {
        case .explore: phoneTab = .explore
        case .trips, nil: phoneTab = .trips; openTripID = nil
        case .trip(let id): phoneTab = .trips; openTripID = id
        case .locations: phoneTab = .locations; openFolderID = nil
        case .locationFolder(let id): phoneTab = .locations; openFolderID = id
        }
    }
}

/// A screen pushed on a phone tab's stack. Trips push a trip and then spots; Locations push a folder and then spots.
enum PhoneRoute: Hashable {
    case trip(UUID)
    case folder(UUID)
    case spot(SpotRoute)
}

extension View {
    /// Every stack can push the spot page.
    func iosSpotDestination() -> some View {
        navigationDestination(for: SpotRoute.self) { route in SpotPageScreen(route: route) }
    }
}
