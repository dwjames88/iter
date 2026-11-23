import AppKit
import SwiftUI
import Testing
import IterFeatures
import IterModel
@testable import Iter

/// Whole-window and pane renders for the Mac shell, light and dark, into Design/snapshots/rebuild/mac/. One line per
/// screen or state in `Windows` and `Panes`; everything else is the two helpers below.
///
/// Offscreen, glass does not draw (the search field and the sidebar footer show flat) and MapKit is blank, so these check
/// layout, copy, colour and state. The screens inside the detail are the other workers' (stubs until they land): re-run
/// `scripts/test-mac.sh --only WindowSnapshotTests` after they merge and open the PNGs again.
@MainActor @Suite struct WindowSnapshotTests {
    static let window = CGSize(width: 1280, height: 820)
    static let pane = CGSize(width: 600, height: 520)

    /// Renders the whole main window on a route, over an empty or seeded library.
    @discardableResult
    func window(_ name: String, _ route: Route, seeded: Bool) async throws -> [URL] {
        let shell = try makeShell(seed: seeded)
        let resolved = route.resolve(shell.library)
        let urls = try await Snapshot.render(MainWindow(shell: shell, route: resolved), name: "mac-\(name)", size: Self.window, chrome: .titled)
        try Self.expectContent(urls)
        return urls
    }

    /// Renders one Settings pane (the tab bar renders badly offscreen, so panes are drawn on their own).
    @discardableResult
    func pane<V: View>(_ name: String, _ view: V, size: CGSize = pane) async throws -> [URL] {
        let urls = try await Snapshot.render(view.frame(width: size.width, height: size.height).background(Color(nsColor: .windowBackgroundColor)),
                                             name: "mac-\(name)", size: size)
        try Self.expectContent(urls)
        return urls
    }

    enum Route {
        case find, allTrips, firstTrip, savedPlaces
        @MainActor func resolve(_ library: LibraryModel) -> AppRoute {
            switch self {
            case .find: .find
            case .allTrips: .allTrips
            case .savedPlaces: .savedPlaces
            case .firstTrip: library.trips.first.map { .trip($0.id) } ?? .allTrips
            }
        }
    }

    static func expectContent(_ urls: [URL]) throws {
        #expect(urls.count == 2)
        for url in urls {
            let image = try #require(NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
            let pixels = try #require(Pixels(image))
            #expect(pixels.stats(x: 0, y: 0, w: image.width / 2, h: image.height / 2).hasContent, "\(url.lastPathComponent) looks blank")
        }
    }

    // MARK: Windows

    @Test func allTripsEmpty() async throws { try await window("allTrips-empty", .allTrips, seeded: false) }
    @Test func allTripsPopulated() async throws { try await window("allTrips-populated", .allTrips, seeded: true) }
    @Test func findEmpty() async throws { try await window("find-empty", .find, seeded: false) }
    @Test func tripThreeColumns() async throws { try await window("trip", .firstTrip, seeded: true) }
    @Test func savedPlaces() async throws { try await window("savedPlaces", .savedPlaces, seeded: true) }

    // MARK: Panes

    @Test func settingsPanes() async throws {
        let shell = try makeShell(seed: false)
        try await pane("settings-general", GeneralSettingsPane(model: shell.settings))
        try await pane("settings-search", SearchSettingsPane(model: shell.settings), size: CGSize(width: 600, height: 760))
        try await pane("settings-sources", SourcesSettingsPane(model: shell.settings), size: CGSize(width: 600, height: 1500))
        try await pane("settings-keys", KeysSettingsPane(model: shell.settings))
        try await pane("settings-updates", UpdatesSettingsPane(controller: shell.updates))
    }

    // MARK: Notices

    @Test func recoveryNotice() async throws {
        try await pane("recovery-notice", RecoveryNoticeView(backupFolder: URL(fileURLWithPath: "/Users/example/Library/Application Support/Iter/Backups/2027-03-10"),
                                                             skippedFiles: ["Moab Recon.iter"], showInFinder: {}, dismiss: {}),
                       size: CGSize(width: 560, height: 260))
    }

    @Test func storeFailure() async throws {
        let failure = StoreFailure(message: StoreFailureText.message(for: NSError(domain: "Test", code: 1)),
                                   backupFolder: URL(fileURLWithPath: "/Users/example/Library/Application Support/Iter/Backups"))
        try await pane("store-failure", StoreFailureView(failure: failure), size: CGSize(width: 600, height: 320))
    }

    @Test func sidebarFooterPieces() async throws {
        try await pane("sidebar-legend", ScoreLegendView().padding(16), size: CGSize(width: 340, height: 560))
        try await pane("sidebar-sample-banner", SampleDataBanner().padding(12), size: CGSize(width: 280, height: 90))
    }
}
