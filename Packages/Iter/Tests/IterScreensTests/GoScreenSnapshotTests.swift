import Foundation
import SwiftUI
import Testing
import IterModel
import IterGo
import IterGoActivity
import IterFeatures
@testable import IterScreens

/// Offscreen renders of the Go screens. Rendering always runs; PNGs are written only with `ITER_SNAPSHOT_RECORD=1`.
@MainActor
@Suite("Go screen snapshots")
struct GoScreenSnapshotTests {
    static let now = Date(timeIntervalSince1970: 1_792_000_000)
    static let full = CGSize(width: 393, height: 852)
    static let half = CGSize(width: 393, height: 430)

    static func permissions(for snapshot: GoSnapshot) -> GoPermissions {
        GoPermissions(location: .always, notifications: .authorized, liveActivitiesEnabled: true, runPhase: snapshot.phase)
    }

    static func screen(_ snapshot: GoSnapshot, permissions: GoPermissions? = nil, trips: [GoTripChoice] = sampleTrips) -> some View {
        NavigationStack {
            GoSheetContent(snapshot: snapshot, permissions: permissions ?? Self.permissions(for: snapshot), now: now, trips: trips,
                           actions: .inert)
        }
        .environment(\.goClockMode, .frozen)
        .environment(\.goFlatButtons, true)
    }

    // MARK: Sample trips

    static let sampleTrips: [GoTripChoice] = [
        trip("Moab and Canyonlands", days: 3, stopsPerDay: 3, start: LocalDay(year: 2026, month: 10, day: 14)),
        trip("Coastal Weekend", days: 2, stopsPerDay: 2, start: LocalDay(year: 2026, month: 11, day: 6)),
        trip("Alabama Hills Sunrise", days: 1, stopsPerDay: 1, start: LocalDay(year: 2026, month: 12, day: 2)),
    ]

    static func trip(_ name: String, days: Int, stopsPerDay: Int, start: LocalDay) -> GoTripChoice {
        let names = ["Mesa Arch", "Dead Horse Point", "Delicate Arch", "Fisher Towers", "Horsethief Point", "Island in the Sky",
                     "Needles Overlook", "Corona Arch", "Park Avenue"]
        let kinds: [LightWindowKind] = [.goldenMorning, .goldenEvening, .blueEvening, .night]
        var stops: [GoTripChoice.StopChoice] = []
        var n = 0
        for d in 0..<days {
            for _ in 0..<stopsPerDay {
                stops.append(.init(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n + 1 + name.count * 100))!,
                                   number: n + 1, name: names[n % names.count], dayIndex: d, windowKind: kinds[n % kinds.count]))
                n += 1
            }
        }
        return GoTripChoice(id: UUID(uuidString: String(format: "10000000-0000-0000-0000-%012d", name.count))!, name: name,
                            startDay: start, dayCount: days, stops: stops)
    }

    // MARK: Every sample

    @Test("every sample renders at full and half height", arguments: GoSample.allCases)
    func sample(_ sample: GoSample) async throws {
        let snapshot = sample.snapshot(now: Self.now)
        try await GoSnapshotHarness.render(Self.screen(snapshot), name: "go-screen-\(sample.rawValue)-full", size: Self.full)
        try await GoSnapshotHarness.render(Self.screen(snapshot), name: "go-screen-\(sample.rawValue)-half", size: Self.half)
    }

    /// The schedule sits below the fold in the full-screen renders, so it is drawn on its own as well.
    @Test("schedule section on its own", arguments: [GoSample.betweenOvernight, .drivingLate, .atStopShooting])
    func schedule(_ sample: GoSample) async throws {
        let snapshot = sample.snapshot(now: Self.now)
        let view = ScrollView { GoScheduleSection(snapshot: snapshot, now: Self.now).padding(16) }
            .environment(\.goClockMode, .frozen)
        try await GoSnapshotHarness.render(view, name: "go-screen-schedule-\(sample.rawValue)", size: CGSize(width: 393, height: 700))
    }

    // MARK: Start flow

    @Test func startWithTrips() async throws {
        try await GoSnapshotHarness.render(Self.screen(.idle(at: Self.now)), name: "go-screen-start-trips", size: Self.full)
    }

    @Test func startWithoutTrips() async throws {
        try await GoSnapshotHarness.render(Self.screen(.idle(at: Self.now), trips: []), name: "go-screen-start-empty", size: Self.full)
    }

    @Test func startFromStopStep() async throws {
        let trip = Self.sampleTrips[0]
        let view = NavigationStack {
            GoStartView(trips: Self.sampleTrips, actions: .inert, initialSelection: trip.id)
        }
        .environment(\.goFlatButtons, true)
        try await GoSnapshotHarness.render(view, name: "go-screen-start-from-stop", size: Self.full)
    }

    // MARK: Finished

    @Test func finished() async throws {
        let snapshot = GoSample.finished.snapshot(now: Self.now)
        let view = NavigationStack { GoFinishedView(snapshot: snapshot, done: {}).navigationTitle("Go") }
            .environment(\.goFlatButtons, true)
        try await GoSnapshotHarness.render(view, name: "go-screen-finished-view", size: Self.full)
    }

    // MARK: Permission variants

    @Test func permissionVariants() async throws {
        let idle = GoSnapshot.idle(at: Self.now)
        try await GoSnapshotHarness.render(
            Self.screen(idle, permissions: GoPermissions(location: .denied, notifications: .authorized, liveActivitiesEnabled: true, runPhase: .idle)),
            name: "go-screen-permission-location-denied-idle", size: Self.full)
        let driving = GoSample.drivingOnTime.snapshot(now: Self.now)
        try await GoSnapshotHarness.render(
            Self.screen(driving, permissions: GoPermissions(location: .whenInUse, notifications: .authorized, liveActivitiesEnabled: true, runPhase: .driving)),
            name: "go-screen-permission-always-driving", size: Self.full)
        let atStop = GoSample.atStopShooting.snapshot(now: Self.now)
        try await GoSnapshotHarness.render(
            Self.screen(atStop, permissions: GoPermissions(location: .always, notifications: .denied, liveActivitiesEnabled: true, runPhase: .atStop)),
            name: "go-screen-permission-notifications-denied-stop", size: Self.full)
        try await GoSnapshotHarness.render(
            Self.screen(driving, permissions: GoPermissions(location: .always, notifications: .authorized, liveActivitiesEnabled: false, runPhase: .driving)),
            name: "go-screen-permission-live-activities-off", size: Self.full)
        try await GoSnapshotHarness.render(
            Self.screen(driving, permissions: GoPermissions(location: .notDetermined, notifications: .notDetermined, liveActivitiesEnabled: true, runPhase: .driving)),
            name: "go-screen-permission-location-ask", size: Self.full)
    }

    // MARK: Map layer

    /// The map cannot render offscreen: this only proves the layer builds for every sample and fits a sensible rect.
    @Test func mapLayerInstantiates() throws {
        for sample in GoSample.allCases {
            let snapshot = sample.snapshot(now: Self.now)
            _ = GoMapLayer(snapshot: snapshot, routePath: [Coordinate(latitude: 38.57, longitude: -109.55), Coordinate(latitude: 38.40, longitude: -109.82)]).body
            _ = GoMapLayer(snapshot: snapshot, routePath: []).body
        }
    }
}
