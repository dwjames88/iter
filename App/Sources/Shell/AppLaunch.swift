import Foundation
import OSLog
import IterCore
import IterData
import IterServices
import IterFeatures

/// Launch-time switches. `-IterInMemoryStore YES` runs on a throwaway store; `-IterSmokeTest YES` walks the main
/// view models once and logs what it found (used by the background smoke test; no UI interaction needed).
enum AppLaunch {
    static let log = Logger(subsystem: "com.dwjames.iter", category: "app")

    static var inMemoryStore: Bool { UserDefaults.standard.bool(forKey: "IterInMemoryStore") }
    static var isRunningTests: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil }
    static var smokeTest: Bool { UserDefaults.standard.bool(forKey: "IterSmokeTest") }

    /// The Apple Intelligence scout over MapKit and the curated set. It reports its own availability at run time.
    static func makeScout() -> (any Scouting)? {
        AppleIntelligenceScout(search: MapKitPlaceSearch(), geocoder: MapKitGeocoder(), drives: MapKitDriveTimes(),
                               curated: CuratedSpots.all)
    }
}
