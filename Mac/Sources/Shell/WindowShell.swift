import AppKit
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers
import IterFeatures
import IterModel
import IterStore

/// Everything one main window owns: its navigator, the Find model (kept for the window's life), the sheets and the import
/// and export flows. The models that belong to one route (Build, Conditions) live in the detail views; this class only
/// borrows the current ones for the menu commands.
@MainActor @Observable
final class WindowShell {
    @ObservationIgnored let shell: AppShell
    @ObservationIgnored let navigator: AppNavigator
    @ObservationIgnored let find: FindModel

    /// The Trip Builder inspector is shown (remembered per window by the scene).
    var inspectorShown = true
    /// A trip or place is open; used by commands.
    @ObservationIgnored weak var currentBuild: BuildModel?
    @ObservationIgnored weak var currentConditions: ConditionsModel?

    // Import and export
    var showsImporter = false
    var pendingImport: PendingImport?
    var showsExporter = false
    var exportDocument: IterFileDocument?
    var exportName = "Iter Library"
    /// One alert for every outcome ("Couldn't Import Trip", the import summary, ...).
    var notice: ShellNotice?

    // Recovery and debug
    var recovery: RecoveryInfo?
    var showsResetConfirmation = false

    /// Set when the window's content first appears (the smoke run waits for it).
    var hasAppeared = false

    var container: AppContainer { shell.container }
    var library: LibraryModel { shell.library }

    init(shell: AppShell, initialRoute: AppRoute? = nil) {
        self.shell = shell
        navigator = AppNavigator(route: initialRoute ?? .find)
        find = shell.container.makeFindModel()
        recovery = shell.takeRecoveryNotice()
    }

    // MARK: Route

    var route: AppRoute { navigator.route ?? .find }

    /// The window's own route restoration: used when no launch switch picked a section.
    func restore(stored: String) {
        guard let route = AppRoute(stored: stored) else { return }
        navigator.open(route)
        validateRoute()
    }

    /// Falls back to All Trips when the trip, folder or place the route names is gone.
    func validateRoute() {
        switch route {
        case .trip(let id) where library.tripRow(id: id) == nil: navigator.open(.allTrips)
        case .tripFolder(let id) where !library.tripFolders.contains(where: { $0.id == id }): navigator.open(.allTrips)
        case .placeFolder(let id) where !library.placeFolders.contains(where: { $0.id == id }): navigator.open(.savedPlaces)
        case .place(let id) where library.place(id: id) == nil: navigator.open(.savedPlaces)
        default: break
        }
    }

    /// The window title for the current route.
    var title: String {
        switch route {
        case .find: "Find"
        case .allTrips: "All Trips"
        case .trip(let id): library.tripRow(id: id)?.name ?? "Trip"
        case .tripFolder(let id): library.tripFolders.first { $0.id == id }?.name ?? "All Trips"
        case .savedPlaces: "Saved Places"
        case .placeFolder(let id): library.placeFolders.first { $0.id == id }?.name ?? "Saved Places"
        case .place(let id): library.placeRow(id: id)?.name ?? "Place"
        }
    }

    var availability: CommandAvailability { CommandAvailability(route: navigator.route) }

    // MARK: File

    func newTrip() { navigator.present(.newTrip(templateID: nil, firstPlace: nil)) }

    func addSpot() { navigator.addSpot() }

    func newFolder() {
        switch route {
        case .savedPlaces, .placeFolder, .place:
            navigator.open(.placeFolder(library.createFolder(name: "New Folder", kind: .locations)))
        default:
            navigator.open(.tripFolder(library.createFolder(name: "New Folder", kind: .trips)))
        }
    }

    func beginImport() { showsImporter = true }

    /// Reads the chosen file and asks whether to merge or add as a copy.
    func chooseImport(_ result: Result<URL, any Error>) {
        switch result {
        case .failure(let error):
            notice = .importFailed(error.localizedDescription)
        case .success(let url):
            readImport(at: url)
        }
    }

    func readImport(at url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            pendingImport = PendingImport(name: url.deletingPathExtension().lastPathComponent, data: try Data(contentsOf: url))
        } catch {
            notice = .importFailed(error.localizedDescription)
        }
    }

    func performImport(_ pending: PendingImport, asCopy: Bool) {
        pendingImport = nil
        do {
            notice = .imported(ImportText.summary(try library.importLibrary(pending.data, asCopy: asCopy), fileName: pending.name))
        } catch {
            notice = .importFailed(ImportText.reason(for: error))
        }
    }

    func exportLibrary() {
        do {
            let file = try library.exportLibrary()
            beginExport(file)
        } catch {
            notice = .exportFailed(error.localizedDescription)
        }
    }

    func exportCurrentTrip() {
        guard case .trip(let id) = route else { return }
        do {
            guard let file = try library.exportTrip(id) else { notice = .exportFailed("That trip is no longer in your library."); return }
            beginExport(file)
        } catch {
            notice = .exportFailed(error.localizedDescription)
        }
    }

    private func beginExport(_ file: ExportedLibrary) {
        exportDocument = IterFileDocument(data: file.data)
        exportName = (file.suggestedFileName as NSString).deletingPathExtension
        showsExporter = true
    }

    func finishExport(_ result: Result<URL, any Error>) {
        exportDocument = nil
        if case .failure(let error) = result { notice = .exportFailed(error.localizedDescription) }
    }

    // MARK: Edit, trip and conditions

    func findSpots() { navigator.focusSearch() }
    func searchHere() { navigator.searchHere() }

    func editPlace() {
        if case .place(let id) = route { navigator.present(.editPlace(id)) }
    }

    func changeDates() {
        if case .trip(let id) = route { navigator.present(.changeDates(tripID: id)) }
    }

    /// Conditions ▸ Refresh: the place on screen, or every stop of the open trip.
    func refreshConditions() {
        switch route {
        case .place:
            currentConditions?.refresh()
        case .trip(let id):
            guard let trip = library.trip(id: id) else { return }
            for stop in trip.stops { container.conditions.refresh(stop.place, day: trip.day(stop.dayIndex)) }
        default:
            break
        }
    }

    // MARK: Debug

    func seedSampleTrip() {
        do {
            let seeded = try container.seedSampleTrip()
            library.refresh()
            navigator.open(.trip(seeded.canyonCountryID))
        } catch {
            notice = .debugFailed("Seed Sample Trip", Self.debugReason(error))
        }
    }

    func resetAllData() {
        do {
            try container.resetLibrary()
            library.refresh()
            navigator.open(.allTrips)
        } catch {
            notice = .debugFailed("Reset All Data", Self.debugReason(error))
        }
    }

    static func debugReason(_ error: any Error) -> String {
        if let e = error as? DebugActionError, e == .refusedOnRealStore {
            return "This is your real library, so Iter won't change it from the Debug menu. Quit and open the render copy to try this."
        }
        return error.localizedDescription
    }
}

/// A file the user picked, read and waiting for "Import" or "Import as Copy".
struct PendingImport: Equatable, Identifiable {
    var id = UUID()
    var name: String
    var data: Data
}

/// What the window's alert says.
enum ShellNotice: Equatable, Identifiable {
    case imported(String)
    case importFailed(String)
    case exportFailed(String)
    case debugFailed(String, String)

    var id: String { title + message }

    var title: String {
        switch self {
        case .imported: "Import Finished"
        case .importFailed: "Couldn't Import Trip"
        case .exportFailed: "Couldn't Export"
        case .debugFailed(let what, _): "Couldn't \(what)"
        }
    }

    var message: String {
        switch self {
        case .imported(let text), .importFailed(let text), .exportFailed(let text): text
        case .debugFailed(_, let text): text
        }
    }
}

/// Which menu commands are available for a route. Pure.
struct CommandAvailability: Equatable {
    var editPlace: Bool
    var tripCommands: Bool
    var refreshConditions: Bool
    var trips: Bool

    init(route: AppRoute?) {
        if case .trip = route { tripCommands = true } else { tripCommands = false }
        if case .place = route { editPlace = true } else { editPlace = false }
        refreshConditions = tripCommands || editPlace
        trips = true
    }
}

/// The `.iter` file as a document, for the save panel.
struct IterFileDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.iterTrip, .json]
    static let writableContentTypes: [UTType] = [.iterTrip]
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

extension UTType {
    /// `com.dwjames.iter.trip`, exported in Info.plist (conforms to public.json).
    static let iterTrip = UTType("com.dwjames.iter.trip") ?? .json
}

/// The sentences of the import flow.
enum ImportText {
    static func summary(_ s: ImportSummary, fileName: String) -> String {
        if s.isEmpty { return "\"\(fileName)\" is already in your library. Nothing changed." }
        var parts: [String] = []
        if s.tripsAdded > 0 { parts.append("added \(count(s.tripsAdded, "trip"))") }
        if s.tripsUpdated > 0 { parts.append("updated \(count(s.tripsUpdated, "trip"))") }
        if s.tripsRemoved > 0 { parts.append("removed \(count(s.tripsRemoved, "trip")) that were deleted elsewhere") }
        if s.placesAdded > 0 { parts.append("added \(count(s.placesAdded, "place"))") }
        if s.foldersAdded > 0 { parts.append("added \(count(s.foldersAdded, "folder"))") }
        var text = parts.joined(separator: ", ")
        text = text.prefix(1).uppercased() + text.dropFirst() + "."
        if s.asCopy { text += " Everything came in as new copies." }
        return text
    }

    static func reason(for error: any Error) -> String {
        "That file isn't an Iter trip Iter can read. (\(error.localizedDescription))"
    }

    private static func count(_ n: Int, _ noun: String) -> String { n == 1 ? "1 \(noun)" : "\(n) \(noun)s" }
}
