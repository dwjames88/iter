import Foundation
import Testing
import IterModel
@testable import IterUI

enum ConditionsFixture {
    /// 2026-11-22 22:00 UTC = 15:00 in Denver.
    static let now = Date(timeIntervalSince1970: 1_795_384_800)
    static let zone = TimeZone(identifier: "America/Denver")!
    static let locale = Locale(identifier: "en_US")
    static func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
    static func ahead(_ minutes: Double) -> Date { now.addingTimeInterval(minutes * 60) }
    /// en_US puts U+202F before AM/PM; tests compare with a plain space.
    static func n(_ s: String) -> String { s.replacingOccurrences(of: "\u{202F}", with: " ") }
}

@MainActor @Suite("Conditions text")
struct ConditionsTests {
    typealias F = ConditionsFixture

    @Test func sourceLineFresh() {
        let c = SourceLine.content(sourceName: "NOAA", tier: .government, issuedAt: F.ago(12), fetchedAt: F.ago(2), now: F.now,
                                   model: "GFS", distanceKm: 12, staleAfter: DataText.defaultStaleAfter, zone: F.zone, locale: F.locale)
        #expect(c.primary == "NOAA · GFS · 7 mi away · Updated 12 min ago")
        #expect(c.tier == "Government data")
        #expect(!c.isMilitary && !c.isStale)
    }

    @Test func sourceLineMilitaryIsMarkedInWords() {
        let c = SourceLine.content(sourceName: "GPS", tier: .military, issuedAt: nil, fetchedAt: F.ago(3), now: F.now,
                                   model: nil, distanceKm: nil, staleAfter: DataText.defaultStaleAfter, zone: F.zone, locale: F.locale)
        #expect(c.isMilitary)
        #expect(c.tier == "Military-origin data")
        #expect(c.primary == "GPS · Updated 3 min ago")
    }

    @Test func sourceLineStaleSaysAsOf() {
        let c = SourceLine.content(sourceName: "Open-Meteo", tier: .openData, issuedAt: F.ago(8 * 60), fetchedAt: F.ago(8 * 60), now: F.now,
                                   model: nil, distanceKm: nil, staleAfter: DataText.defaultStaleAfter, zone: F.zone, locale: F.locale)
        #expect(c.isStale)
        #expect(F.n(c.primary) == "Open-Meteo · Stale, as of 7:00 AM")
    }

    @Test func sourceLineUsesIssuedAtOverFetchedAt() {
        let c = SourceLine.content(sourceName: "X", tier: .device, issuedAt: F.ago(30), fetchedAt: F.ago(1), now: F.now, model: nil,
                                   distanceKm: nil, staleAfter: DataText.defaultStaleAfter, zone: F.zone, locale: F.locale)
        #expect(c.primary.hasSuffix("Updated 30 min ago"))
    }

    @Test func sourceLineFromProvenance() {
        let p = Provenance(source: "noaa.gfs", model: "GFS", issuedAt: F.ago(60), fetchedAt: F.ago(5), distanceKm: nil,
                           licence: LicenceTag(key: "pd", mayStore: true))
        let v = SourceLine(p, displayName: "NOAA", tier: .government, now: F.now, zone: F.zone, locale: F.locale)
        #expect(v.content.primary == "NOAA · GFS · 1 hr old")
    }

    @Test func dataStateWords() {
        func w(_ s: DataStateKind) -> DataStateView.Words { DataStateView.words(for: s, zone: F.zone, locale: F.locale) }
        #expect(w(.noData).title == "No Data")
        #expect(w(.stale(age: 7 * 3600)).detail == "7 hr old. Check again before you rely on it.")
        #expect(F.n(w(.offline(lastUpdated: F.ago(60))).detail) == "Last updated at 2:00 PM.")
        #expect(w(.offline(lastUpdated: nil)).detail == "This appears when you're back online.")
        #expect(w(.loading).title == "Loading")
        #expect(w(.unavailable(reason: "Outside coverage.")).detail == "Outside coverage.")
        #expect(w(.noData).symbol == "circle.dashed")
    }

    @Test func factorContributionText() {
        let l = F.locale
        #expect(FactorContribution.points(12).text(locale: l) == "+12")
        #expect(FactorContribution.points(-4).text(locale: l) == "\u{2212}4")
        #expect(FactorContribution.points(0).text(locale: l) == "0")
        #expect(FactorContribution.fraction(0.4).text(locale: l) == "+40%")
        #expect(FactorContribution.fraction(-0.25).text(locale: l) == "\u{2212}25%")
        #expect(FactorContribution.fraction(3).text(locale: l) == "+100%")
        #expect(FactorContribution.points(-4).direction == .hurts)
        #expect(FactorContribution.fraction(0).direction == .neutral)
    }

    @Test func factorRowAccessibility() {
        let r = FactorRow(name: "Cloud Cover", symbol: "cloud", valueText: "30%", contribution: .points(12), locale: F.locale)
        #expect(r.accessibilityText == "Cloud Cover, 30%, helps, +12")
        let m = FactorRow(name: "Wind", symbol: "wind", valueText: nil, contribution: nil, locale: F.locale)
        #expect(m.accessibilityText == "Wind, No data")
    }

    @Test func confidenceNames() {
        #expect(ConfidenceLevel.allCases.map { $0.name(locale: F.locale) } == ["Low", "Medium", "High"])
        #expect(ConfidenceLevel.high.phrase(locale: F.locale) == "High Confidence")
        #expect(ConfidenceLevel.low < .high)
    }

    // MARK: Go

    @Test func leaveByStatus() {
        #expect(LeaveByStatus(departure: F.ahead(20), now: F.now) == .onTime)
        #expect(LeaveByStatus(departure: F.ahead(0.5), now: F.now) == .leaveNow)
        #expect(LeaveByStatus(departure: F.ago(0.5), now: F.now) == .leaveNow)
        #expect(LeaveByStatus(departure: F.ago(6), now: F.now) == .late(minutes: 6))
    }

    @Test func leaveByCardWords() {
        let c = LeaveByCard(stopName: "Mesa Arch", departure: F.ahead(25), arrival: F.ahead(25 + 48), deadline: F.ahead(90),
                            driveSeconds: 48 * 60, driveMeters: 60_000, now: F.now, zone: F.zone, locale: F.locale)
        #expect(F.n(c.leaveByText) == "Leave by 3:25 PM")
        #expect(F.n(c.etaText) == "Arrive 4:13 PM")
        #expect(c.driveText == "48 min · 37 mi")
        let late = LeaveByCard(stopName: "Mesa Arch", departure: F.ago(6), arrival: F.ahead(60), deadline: F.ahead(50),
                               driveSeconds: 3600, driveMeters: 90_000, now: F.now, zone: F.zone, locale: F.locale)
        #expect(late.leaveByText == "Late by 6 min")
        #expect(late.etaText == "Late by 10 min")
    }

    @Test func nextStopWords() {
        let c = NextStopCard(number: 2, name: "Mesa Arch", locality: "Moab, UT", kind: .goldenEvening, windowStart: F.ahead(90),
                             arrival: F.ahead(60), zone: F.zone, locale: F.locale)
        #expect(F.n(c.windowText) == "Sunset starts 4:30 PM")
        #expect(F.n(c.arriveText) == "Arrive 4:00 PM")
        #expect(F.n(c.accessibilityText) == "Stop 2, Mesa Arch, Moab, UT, Sunset starts 4:30 PM, Arrive 4:00 PM")
    }

    @Test func liveSkyAccessibility() {
        let c = LiveSkyCard(score: 74, kind: .goldenEvening, windowStart: F.ahead(90), confidence: .medium, updatedAt: F.ago(12),
                            now: F.now, zone: F.zone, locale: F.locale)
        #expect(F.n(c.accessibilityText) == "Live Sky Index, Sunset, 74 out of 100, Medium Confidence, Updated 12 min ago")
    }
}
