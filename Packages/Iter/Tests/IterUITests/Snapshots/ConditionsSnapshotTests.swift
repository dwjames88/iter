import SwiftUI
import Testing
import IterModel
@testable import IterUI

@MainActor
@Suite("Conditions snapshots")
struct ConditionsSnapshotTests {
    typealias F = ConditionsFixture
    static let width: CGFloat = 390

    @Test func sourceLine() async throws {
        func line(_ name: String, _ tier: SourceTier, model: String? = nil, km: Double? = nil, ageMin: Double, url: URL? = nil) -> some View {
            SourceLine(sourceName: name, tier: tier, fetchedAt: F.ago(ageMin), now: F.now, model: model, distanceKm: km, url: url,
                       zone: F.zone, locale: F.locale)
        }
        let view = VStack(alignment: .leading, spacing: 14) {
            line("GPS", .military, model: "GFS", ageMin: 12)
            line("NOAA", .government, model: "HRRR", km: 12, ageMin: 5, url: URL(string: "https://weather.gov"))
            line("Open-Meteo", .openData, ageMin: 0.2)
            line("Your OpenWeather Key", .userKey, ageMin: 95)
            line("Barometer", .device, ageMin: 2)
            line("NOAA", .government, model: "GFS", ageMin: 9 * 60)
            line("GPS", .military, ageMin: 30 * 60)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        try await Snapshot.assertMatches(view, name: "conditions-source-line", size: CGSize(width: Self.width, height: 330),
                                         background: IterColor.backgroundWindow)
    }

    @Test func dataState() async throws {
        let states: [DataStateKind] = [.noData, .stale(age: 7 * 3600), .offline(lastUpdated: F.ago(60)), .loading,
                                       .unavailable(reason: "Outside coverage.")]
        let inline = VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(states.enumerated()), id: \.offset) { _, s in DataStateView(s, style: .inline, now: F.now, zone: F.zone, locale: F.locale) }
        }
        .padding(16)
        try await Snapshot.assertMatches(inline, name: "conditions-data-state", size: CGSize(width: Self.width, height: 160),
                                         background: IterColor.backgroundWindow)
        for (i, s) in states.enumerated() {
            let large = DataStateView(s, style: .large, now: F.now, zone: F.zone, locale: F.locale).padding(16)
            try await Snapshot.assertMatches(large, name: "conditions-data-state-large-\(i)", size: CGSize(width: Self.width, height: 240),
                                             background: IterColor.backgroundWindow)
        }
    }

    @Test func factorRow() async throws {
        let view = VStack(spacing: 0) {
            FactorRow(name: "High Cloud", symbol: "cloud.sun", valueText: "40% at 9 km", contribution: .points(21), locale: F.locale)
            Divider()
            FactorRow(name: "Smoke", symbol: "smoke", valueText: "Moderate, 35 µg/m³", contribution: .points(-12), locale: F.locale)
            Divider()
            FactorRow(name: "Moon", symbol: "moon", valueText: "Below horizon", contribution: .points(0), locale: F.locale)
            Divider()
            FactorRow(name: "Humidity", symbol: "humidity", valueText: "62%", contribution: .fraction(-0.4), locale: F.locale)
            Divider()
            FactorRow(name: "Aerosol", symbol: "aqi.medium", valueText: nil, contribution: nil, locale: F.locale)
        }
        .padding(.horizontal, 16)
        try await Snapshot.assertMatches(view, name: "conditions-factor-row", size: CGSize(width: Self.width, height: 330),
                                         background: IterColor.backgroundWindow)
    }

    @Test func confidence() async throws {
        let view = VStack(alignment: .leading, spacing: 14) {
            ForEach(ConfidenceLevel.allCases, id: \.self) { l in
                HStack(spacing: 24) { ConfidenceIndicator(l, locale: F.locale); ConfidenceIndicator(l, showsLabel: false, locale: F.locale) }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        try await Snapshot.assertMatches(view, name: "conditions-confidence", size: CGSize(width: Self.width, height: 110),
                                         background: IterColor.backgroundWindow)
    }
}
