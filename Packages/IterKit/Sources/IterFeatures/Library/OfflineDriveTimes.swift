import Foundation
import Synchronization
import IterCore

/// Drive times that answer from offline packs first, then from the wrapped provider. Seeded legs are real routes
/// (never estimates), so a pinned trip shows its drives and route lines with no network.
public final class OfflineDriveTimes: DriveTimeProviding {
    private struct Key: Hashable, Sendable { var from: String; var to: String }

    /// The real provider. The downloader fetches through this one so a re-download gets fresh routes.
    public let wrapped: any DriveTimeProviding
    private let seeded = Mutex<[Key: DriveLeg]>([:])

    public init(wrapping wrapped: any DriveTimeProviding) {
        self.wrapped = wrapped
    }

    /// Adds legs (replacing the same pair). Estimates are ignored.
    public func seed(_ legs: [DriveLeg]) {
        seeded.withLock { cache in
            for leg in legs where !leg.isEstimate { cache[Key(from: leg.from.cacheKey, to: leg.to.cacheKey)] = leg }
        }
    }

    public func seededLeg(from a: Coordinate, to b: Coordinate) -> DriveLeg? {
        seeded.withLock { $0[Key(from: a.cacheKey, to: b.cacheKey)] }
    }

    public func drive(from a: Coordinate, to b: Coordinate) async throws -> DriveLeg {
        if let leg = seededLeg(from: a, to: b) { return leg }
        return try await wrapped.drive(from: a, to: b)
    }
}
