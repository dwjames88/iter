import Foundation
import Testing
import IterCore
import IterData
@testable import IterServices

/// The scout exactly as the app builds it (real MapKit services, the full curated set), on several requests.
@Suite("Scout app live", .enabled(if: ProcessInfo.processInfo.environment["ITER_LIVE_AI"] == "1"), .serialized)
struct ScoutAppLiveTests {
    static let requests = [
        "Waterfalls near Portland, Oregon",
        "foggy forest spots within two hours of Portland for sunrise",
        "Sunset over red rock near Moab",
    ]

    @Test(.timeLimit(.minutes(6)), arguments: requests)
    func appConfiguration(_ request: String) async throws {
        let scout = AppleIntelligenceScout(search: MapKitPlaceSearch(), geocoder: MapKitGeocoder(), drives: MapKitDriveTimes(),
                                           curated: CuratedSpots.all)
        let start = ContinuousClock.now
        do {
            let s = try await scout.scout(request, progress: { _ in })
            print("APP SCOUT [\(request)]: \(s.count) in \(ContinuousClock.now - start)")
            for x in s { print("   - \(x.spot.name) [\(x.provenance)] \(x.spot.locality) :: \(x.why)") }
            #expect(!s.isEmpty)
        } catch {
            print("APP SCOUT [\(request)] FAILED after \(ContinuousClock.now - start): \(error)")
            Issue.record("\(error)")
        }
    }
}
