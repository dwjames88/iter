import SwiftUI
import Testing
import IterModel
@testable import IterUI

@MainActor
@Suite("Go snapshots")
struct GoSnapshotTests {
    typealias F = ConditionsFixture
    static let width: CGFloat = 390

    @Test func leaveByCard() async throws {
        func card(_ name: String, departMin: Double, deadlineMin: Double) -> some View {
            LeaveByCard(stopName: name, departure: F.ahead(departMin), arrival: F.ahead(departMin + 48), deadline: F.ahead(deadlineMin),
                        driveSeconds: 48 * 60, driveMeters: 60_000, now: F.now, zone: F.zone, locale: F.locale)
        }
        let view = VStack(spacing: 12) {
            card("Mesa Arch", departMin: 25, deadlineMin: 120)
            card("Delicate Arch", departMin: 0, deadlineMin: 70)
            card("Dead Horse Point", departMin: -6, deadlineMin: 30)
        }
        .padding(16)
        try await Snapshot.assertMatches(view, name: "go-leave-by-card", size: CGSize(width: Self.width, height: 560),
                                         background: IterColor.backgroundWindow)
    }

    @Test func liveSkyCard() async throws {
        func card(_ score: Int?, _ kind: LightWindowKind, _ c: ConfidenceLevel, age: Double) -> some View {
            LiveSkyCard(score: score, kind: kind, windowStart: F.ahead(90), confidence: c, updatedAt: F.ago(age), now: F.now,
                        zone: F.zone, locale: F.locale)
        }
        let view = VStack(spacing: 12) {
            card(0, .night, .high, age: 4)
            card(50, .blueMorning, .medium, age: 12)
            card(100, .goldenEvening, .high, age: 1)
            card(62, .goldenMorning, .low, age: 45)
            card(nil, .blueEvening, .low, age: 200)
        }
        .padding(16)
        try await Snapshot.assertMatches(view, name: "go-live-sky-card", size: CGSize(width: Self.width, height: 620),
                                         background: IterColor.backgroundWindow)
    }

    @Test func nextStopCard() async throws {
        let view = VStack(spacing: 12) {
            NextStopCard(number: 2, name: "Mesa Arch", locality: "Moab, Utah", kind: .goldenMorning, windowStart: F.ahead(90),
                         arrival: F.ahead(60), zone: F.zone, locale: F.locale)
            NextStopCard(number: 11, name: "A Very Long Overlook Name That Wraps To Two Lines", locality: nil, kind: .night,
                         windowStart: F.ahead(300), arrival: F.ahead(240), zone: F.zone, locale: F.locale)
        }
        .padding(16)
        try await Snapshot.assertMatches(view, name: "go-next-stop-card", size: CGSize(width: Self.width, height: 270),
                                         background: IterColor.backgroundWindow)
    }
}
