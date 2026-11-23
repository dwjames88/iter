import Foundation
import SwiftUI
import Testing
import IterModel
import IterGoActivity
import IterUI
@testable import IterScreens

enum GoSectionCases {
    static let hero: [GoSample] = GoSample.allCases.filter { $0 != .idle && $0 != .finished }
    static let conditions: [GoSample] = [.armedEarly, .leaveSoon, .drivingOnTime, .atStopShooting, .nextWindowForecast, .offline, .stale]
    static let alerts: [GoSample] = [.alert]
    static let freshness: [GoSample] = [.offline, .stale, .powerSaving]
}

/// Offscreen renders of the Go sections at iPhone width. PNGs are written only with `ITER_SNAPSHOT_RECORD=1`.
@MainActor
@Suite("Go section snapshots")
struct GoSectionSnapshotTests {
    static let now = ISO8601DateFormatter().date(from: "2026-10-24T22:30:00Z")!
    static let width: CGFloat = 393


    static func framed(_ content: some View) -> some View {
        content
            .padding(IterSpace.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .environment(\.goClockMode, .frozen)
            .environment(\.goFlatButtons, true)
            .environment(\.locale, Locale(identifier: "en_US"))
    }

    @Test("hero card", arguments: GoSectionCases.hero)
    func hero(_ sample: GoSample) async throws {
        let now = sample.renderNow
        let s = sample.snapshot(now: now)
        try await GoSnapshotHarness.render(Self.framed(GoHeroCard(snapshot: s, now: now, actions: .inert)),
                                           name: "go-section-hero-\(sample.rawValue)", size: CGSize(width: Self.width, height: 640))
    }

    @Test("conditions", arguments: GoSectionCases.conditions)
    func conditions(_ sample: GoSample) async throws {
        let now = sample.renderNow
        let s = sample.snapshot(now: now)
        try await GoSnapshotHarness.render(Self.framed(GoConditionsSection(snapshot: s, now: now)),
                                           name: "go-section-conditions-\(sample.rawValue)", size: CGSize(width: Self.width, height: 1180))
    }

    @Test("alerts", arguments: GoSectionCases.alerts)
    func alerts(_ sample: GoSample) async throws {
        let now = sample.renderNow
        let s = sample.snapshot(now: now)
        try await GoSnapshotHarness.render(Self.framed(GoAlertsSection(snapshot: s, now: now)),
                                           name: "go-section-alerts-\(sample.rawValue)", size: CGSize(width: Self.width, height: 260))
    }

    @Test("freshness note", arguments: GoSectionCases.freshness)
    func freshness(_ sample: GoSample) async throws {
        let now = sample.renderNow
        let s = sample.snapshot(now: now)
        try await GoSnapshotHarness.render(Self.framed(GoFreshnessNote(snapshot: s, now: now)),
                                           name: "go-section-freshness-\(sample.rawValue)", size: CGSize(width: Self.width, height: 140))
    }

    @Test("sections draw nothing for an idle snapshot")
    func idleIsEmpty() {
        let s = GoSnapshot.idle(at: Self.now)
        #expect(GoText.heroKind(s) == nil)
        #expect(GoText.freshnessLines(s, now: Self.now).isEmpty)
        #expect(s.alerts.isEmpty)
    }
}
