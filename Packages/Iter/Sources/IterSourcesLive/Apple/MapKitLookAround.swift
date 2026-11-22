import Foundation
import MapKit
import IterModel
import IterSources

/// Whether Look Around imagery exists at a point (`MKLookAroundSceneRequest`). No permission is needed.
public struct MapKitLookAround: StreetLevelImageryProvider {
    typealias Check = @Sendable (Coordinate) async throws -> Bool

    public let descriptor: SourceDescriptor
    private let throttle: MapKitThrottle
    private let check: Check

    public init(clock: any SourceClock = SystemSourceClock(), descriptor: SourceDescriptor = SourceCatalogue.appleLookAround) {
        self.init(clock: clock, descriptor: descriptor, check: Self.runMapKit)
    }

    init(clock: any SourceClock, descriptor: SourceDescriptor = SourceCatalogue.appleLookAround, check: @escaping Check) {
        self.descriptor = descriptor
        self.throttle = MapKitThrottle(policy: descriptor.policy, clock: clock)
        self.check = check
    }

    public func isAvailable(at coordinate: Coordinate) async throws -> Bool {
        guard MapKitConversion.isValid(coordinate) else { throw SourceError.invalidRequest("coordinate out of range") }
        guard descriptor.coverage.contains(coordinate) else { throw SourceError.outsideCoverage }
        try await throttle.acquire()
        do { return try await check(coordinate) } catch { throw MapKitLookAround.map(error) }
    }

    /// Look Around has no imagery for most places and MapKit reports that as a not-found error: that is "false", not a failure.
    static func map(_ error: any Error) -> SourceError { MapKitErrors.map(error) }

    private static let runMapKit: Check = { coordinate in
        let request = MKLookAroundSceneRequest(coordinate: MapKitConversion.clCoordinate(coordinate))
        do { return try await request.scene != nil } catch {
            if case .http(404, _) = MapKitErrors.map(error) { return false }
            throw error
        }
    }
}
