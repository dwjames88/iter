import Foundation
import Testing
import IterCore
import IterLight
@testable import IterServices
@testable import IterFeatures

private let moab = Coordinate(latitude: 38.5733, longitude: -109.5498)
private let mesa = Coordinate(latitude: 38.3896, longitude: -109.8681)

private func routed(_ a: Coordinate, _ b: Coordinate) -> DriveLeg {
    DriveLeg(from: a, to: b, seconds: 2400, meters: 50_000, isEstimate: false, path: [a, b])
}

@Suite struct CachedLegTests {
    @Test func aProviderWithoutACacheKnowsNothing() {
        let provider: any DriveTimeProviding = FakeDrives()
        #expect(provider.cachedLeg(from: moab, to: mesa) == nil)
    }

    @Test func mapKitAnswersFromItsCacheThroughTheProtocol() async throws {
        let service = MapKitDriveTimes(minimumSpacing: .zero, backoffs: [], sleep: { _ in }, fetch: { a, b in routed(a, b) })
        let provider: any DriveTimeProviding = service
        #expect(provider.cachedLeg(from: moab, to: mesa) == nil)
        _ = try await provider.drive(from: moab, to: mesa)
        #expect(provider.cachedLeg(from: moab, to: mesa)?.seconds == 2400, "the actor's cache is reached, not the nil default")
        #expect(provider.cachedLeg(from: mesa, to: moab) == nil)
    }

    @Test func offlineDriveTimesAnswerSeededLegsThenTheWrappedCache() async throws {
        let service = MapKitDriveTimes(minimumSpacing: .zero, backoffs: [], sleep: { _ in }, fetch: { a, b in routed(a, b) })
        let offline = OfflineDriveTimes(wrapping: service)
        #expect(offline.cachedLeg(from: moab, to: mesa) == nil)

        offline.seed([routed(moab, mesa)])
        #expect(offline.cachedLeg(from: moab, to: mesa) != nil)

        _ = try await service.drive(from: mesa, to: moab)
        #expect(offline.cachedLeg(from: mesa, to: moab) != nil, "a leg the wrapped provider fetched is known too")

        offline.seed([DriveLeg.estimate(from: moab, to: Coordinate(latitude: 40, longitude: -110))])
        #expect(offline.cachedLeg(from: moab, to: Coordinate(latitude: 40, longitude: -110)) == nil, "estimates are never cached")
    }
}
