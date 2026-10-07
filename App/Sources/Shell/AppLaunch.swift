import AppKit
import Foundation
import SwiftUI
import OSLog
import IterCore
import IterDesign
import IterData
import IterServices
import IterFeatures

/// Launch-time switches. `-IterInMemoryStore YES` runs on a throwaway store; `-IterSmokeTest YES` walks the main
/// view models once and logs what it found (used by the background smoke test; no UI interaction needed).
/// `-IterSection explore|saved|scout|trips|trip` (`trip` = the first trip in the store) opens the main window on that sidebar section, overriding the restored
/// selection; `-IterAppearance light|dark` forces the app's appearance. Both exist for screenshot testing.
/// `-IterSettingsTab general|weather|intelligence|about` opens the Settings window on that tab at launch, and
/// `-IterSpot <curated spot id>` (for example `mesa-arch`) opens Explore with that spot's page pushed. Also for screenshots.
/// `-IterShowLayoutGrid YES` draws the 8 pt layout grid and lane guides over lists and cards (Debug ▸ Show Layout Grid).
/// `-IterWindowSize WxH` (for example `1280x820`, `960x652`, or `min` for the window minimum) sets the main window's
/// content size once at launch; absent, the window opens as usual. Sizes below the minimum are raised to it.
enum AppLaunch {
    static let log = Logger(subsystem: "com.dwjames.iter", category: "app")

    static var inMemoryStore: Bool { UserDefaults.standard.bool(forKey: "IterInMemoryStore") }
    static var isRunningTests: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil }
    static var smokeTest: Bool { UserDefaults.standard.bool(forKey: "IterSmokeTest") }

    static var sectionName: String? { UserDefaults.standard.string(forKey: "IterSection") }
    static var section: SidebarItem? {
        switch sectionName {
        case "explore": .explore
        case "saved": .saved
        case "scout": .scout
        case "trips": .trips
        default: nil
        }
    }
    static var settingsTab: SettingsTab? {
        switch UserDefaults.standard.string(forKey: "IterSettingsTab") {
        case "general": .general
        case "weather": .weather
        case "intelligence": .intelligence
        case "about": .about
        default: nil
        }
    }
    static var spot: Spot? { UserDefaults.standard.string(forKey: "IterSpot").flatMap { CuratedSpots.spot(id: $0) } }
    /// `-IterSelectRow <spot id>` (for example `mesa-arch`): Explore selects that row, scrolls it into view once when it
    /// is first built, and so shows its place card. For screenshots.
    static var selectRowID: String? { UserDefaults.standard.string(forKey: "IterSelectRow") }
    /// `-IterSearch <text>`: Explore runs that Apple Maps search at launch (screenshots of search results).
    static var searchText: String? { UserDefaults.standard.string(forKey: "IterSearch") }
    /// `-IterAddSpot "lat,lon,Name"`: Explore adds your own spot there at launch, through the same path as the spot
    /// editor's Save, and selects it. Honoured only with `-IterInMemoryStore YES`, so it never touches real data.
    static var addSpot: (coordinate: Coordinate, name: String)? {
        guard inMemoryStore, let raw = UserDefaults.standard.string(forKey: "IterAddSpot") else { return nil }
        let parts = raw.split(separator: ",", maxSplits: 2).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 3, let lat = Double(parts[0]), let lon = Double(parts[1]) else { return nil }
        return (Coordinate(latitude: lat, longitude: lon), parts[2])
    }
    /// `-IterCardScrolled YES`: the map's place card opens already scrolled to its lower sections. For screenshots.
    static var cardScrolled: Bool { UserDefaults.standard.bool(forKey: "IterCardScrolled") }
    /// `-IterShowLayoutGrid YES`: the layout grid overlay is on (same key as Debug ▸ Show Layout Grid). For screenshots.
    static var showLayoutGrid: Bool { UserDefaults.standard.bool(forKey: "IterShowLayoutGrid") }
    static var appearanceName: String? { UserDefaults.standard.string(forKey: "IterAppearance") }

    /// The `-IterWindowSize` request in points, or nil. `min` is the window minimum.
    static var windowSize: CGSize? {
        guard let raw = UserDefaults.standard.string(forKey: "IterWindowSize") else { return nil }
        if raw == "min" { return CGSize(width: IterSize.mainWindowMinWidth, height: IterSize.windowMinHeight) }
        let parts = raw.lowercased().split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return nil }
        return CGSize(width: parts[0], height: parts[1])
    }

    /// The Apple Intelligence scout over MapKit and the curated set. It reports its own availability at run time.
    static func makeScout() -> (any Scouting)? {
        AppleIntelligenceScout(search: MapKitPlaceSearch(), geocoder: MapKitGeocoder(), drives: MapKitDriveTimes(),
                               curated: CuratedSpots.all)
    }
}

/// Reaches the hosting window to enforce the content minimum (so no resize can clip a column) and to apply
/// `-IterWindowSize` once.
struct MainWindowConfigurator: NSViewRepresentable {
    let minSize: CGSize
    /// The window's content width, kept current as the window resizes.
    @Binding var contentWidth: CGFloat

    final class Coordinator {
        var appliedLaunchSize = false
        var observer: NSObjectProtocol?
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let minSize = minSize
        let contentWidth = $contentWidth
        let coordinator = context.coordinator
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.contentMinSize = minSize
            if coordinator.observer == nil {
                let publish: @MainActor () -> Void = { [weak window] in
                    guard let window else { return }
                    let width = window.contentLayoutRect.width
                    if abs(width - contentWidth.wrappedValue) > 0.5 { contentWidth.wrappedValue = width }
                }
                coordinator.observer = NotificationCenter.default.addObserver(
                    forName: NSWindow.didResizeNotification, object: window, queue: .main) { _ in
                    MainActor.assumeIsolated { publish() }
                }
                publish()
            }
            guard !coordinator.appliedLaunchSize, let size = AppLaunch.windowSize else { return }
            coordinator.appliedLaunchSize = true
            window.setContentSize(CGSize(width: max(size.width, minSize.width), height: max(size.height, minSize.height)))
        }
    }
}
