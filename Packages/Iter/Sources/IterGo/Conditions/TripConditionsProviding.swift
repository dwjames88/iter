import Foundation
import IterModel
import IterSources
import IterSky
import IterConditions

/// What the conditions loop needs from the data layer. `ConditionsService` conforms; tests use fakes.
public protocol TripConditionsProviding: Sendable {
    func live(for place: Place, target: LightWindowKind?, priority: ConditionsPriority) async -> LiveConditions
    func report(for place: Place, day: LocalDay, priority: ConditionsPriority) async -> SkyReport
    /// Builds (or rebuilds) the trip's offline pack and returns when it was built.
    /// Named `buildTripPack` because `ConditionsService.buildPack(for:)` already exists and returns the pack itself.
    func buildTripPack(for trip: Trip) async throws -> Date
    func packBuiltAt(tripID: UUID) async -> Date?
}

extension ConditionsService: TripConditionsProviding {
    public func report(for place: Place, day: LocalDay, priority: ConditionsPriority) async -> SkyReport {
        await report(for: place, day: day, priority: priority, waitFor: .quick)
    }

    public func buildTripPack(for trip: Trip) async throws -> Date {
        try await buildPack(for: trip, priority: .activeTrip).builtAt
    }

    public func packBuiltAt(tripID: UUID) async -> Date? { pack(for: tripID)?.builtAt }
}
