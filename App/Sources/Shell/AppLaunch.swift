import Foundation
import OSLog
import IterCore
import IterData
import IterServices
import IterFeatures

/// Launch-time switches. `-IterInMemoryStore YES` runs on a throwaway store; `-IterSmokeTest YES` walks the main
/// view models once and logs what it found (used by the background smoke test; no UI interaction needed).
/// `-IterSection explore|saved|scout|trips|trip` (`trip` = the first trip in the store) opens the main window on that sidebar section, overriding the restored
/// selection; `-IterAppearance light|dark` forces the app's appearance. Both exist for screenshot testing.
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
    static var appearanceName: String? { UserDefaults.standard.string(forKey: "IterAppearance") }

    /// The Apple Intelligence scout over MapKit and the curated set. It reports its own availability at run time.
    static func makeScout() -> (any Scouting)? {
        AppleIntelligenceScout(search: MapKitPlaceSearch(), geocoder: MapKitGeocoder(), drives: MapKitDriveTimes(),
                               curated: CuratedSpots.all)
    }
}
