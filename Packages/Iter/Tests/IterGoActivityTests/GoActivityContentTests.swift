import Foundation
import Testing
import IterGoActivity
import IterModel

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func stop(_ name: String) -> GoStopInfo {
    GoStopInfo(id: UUID(), number: 3, name: name, locality: "Moab", kind: .light, dayIndex: 1, coordinate: Coordinate(latitude: 38.6, longitude: -109.6),
               timeZoneIdentifier: "America/Denver", windowKind: .goldenEvening, windowStart: t0.addingTimeInterval(7200))
}

private func fullSnapshot(name: String = "Mesa Arch") -> GoSnapshot {
    GoSnapshot(generatedAt: t0, tripID: UUID(), tripName: "Utah", runID: UUID(), phase: .driving, next: stop(name), remainingCount: 2,
               leave: GoLeaveInfo(leaveBy: t0.addingTimeInterval(600), status: .late, lateBySeconds: 8 * 60 + 20),
               drive: GoDriveInfo(arrival: t0.addingTimeInterval(3000), driveSeconds: 2880, driveMeters: 50_000, source: .live, asOf: t0),
               sky: GoSkyInfo(stopID: nil, windowKind: .blueEvening, windowStart: t0.addingTimeInterval(7000), windowEnd: nil, liveScore: 72,
                              forecastScore: 45, band: .great, confidence: .medium, trend: .rising, basis: .blended, asOf: t0, notice: nil, isStale: false),
               freshness: GoFreshness(etaAsOf: t0.addingTimeInterval(-300), conditionsAsOf: t0.addingTimeInterval(-700), isOffline: true, isPowerSaving: true),
               undo: GoUndoInfo(toPhase: .driving, stopID: nil, stopName: nil, expiresAt: t0.addingTimeInterval(120)))
}

@Test func contentMapsSnapshot() {
    let c = GoActivityContent(snapshot: fullSnapshot())
    #expect(c.phase == .driving && c.nextStopName == "Mesa Arch" && c.status == .late)
    #expect(c.leaveBy == t0.addingTimeInterval(600) && c.eta == t0.addingTimeInterval(3000))
    #expect(c.windowKind == .blueEvening && c.windowStart == t0.addingTimeInterval(7000))
    #expect(c.liveScore == 72 && c.forecastScore == 45 && c.band == .great && c.confidence == .medium && c.trend == .rising)
    #expect(c.dataAsOf == t0.addingTimeInterval(-300))
    #expect(c.lateMinutes == 8)
    #expect(c.isOffline && c.isPowerSaving)
    #expect(c.undoExpiresAt == t0.addingTimeInterval(120))
}

@Test func contentFallsBackWhenThereIsNoSky() {
    var s = fullSnapshot()
    s.sky = nil
    s.freshness = GoFreshness()
    s.leave = nil
    let c = GoActivityContent(snapshot: s)
    #expect(c.windowKind == .goldenEvening)
    #expect(c.liveScore == nil && c.confidence == nil && c.lateMinutes == nil)
    #expect(c.dataAsOf == t0)
}

@Test func idleSnapshotMakesEmptyContent() {
    let c = GoActivityContent(snapshot: .idle(at: t0))
    #expect(c.phase == .idle && c.nextStopName == nil)
}

@Test func namesTruncateToFortyCharacters() {
    let c = GoActivityContent(snapshot: fullSnapshot(name: String(repeating: "Wide-Open Mountain ", count: 6)))
    #expect(c.nextStopName?.count == 40)
    #expect(c.nextStopName?.hasSuffix("\u{2026}") == true)
}

@Test func worstCaseContentStaysUnderTwoKilobytes() throws {
    let c = GoActivityContent(phase: .betweenStops, nextStopName: String(repeating: "W", count: 200), status: .leaveSoon,
                              leaveBy: Date(timeIntervalSince1970: 1_800_000_000.123456), eta: Date(timeIntervalSince1970: 1_800_003_000.654321),
                              windowKind: .goldenMorning, windowStart: Date(timeIntervalSince1970: 1_800_001_000.111111), liveScore: 100,
                              forecastScore: 100, band: .great, confidence: .medium, trend: .unknown,
                              dataAsOf: Date(timeIntervalSince1970: 1_800_000_000.987654), lateMinutes: 1439, isOffline: true, isPowerSaving: true,
                              undoExpiresAt: Date(timeIntervalSince1970: 1_800_000_120.333333))
    let data = try JSONEncoder().encode(c)
    #expect(data.count < 2048)
    #expect(try JSONDecoder().decode(GoActivityContent.self, from: data) == c)
}
