import SwiftUI
import Testing
import IterCore
import IterDesign
@testable import Iter

/// The event unit alone: every size, window kind and band, scored and unscored, light and dark.
@MainActor
@Suite(.serialized) struct EventUnitSnapshotTests {
    private static let zone = TimeZone(identifier: "UTC")!
    private static let day = LocalDay(year: 2026, month: 10, day: 6)

    private static let kinds: [(LightWindowKind, Int, Int)] = [
        (.goldenMorning, 6, 12), (.blueMorning, 5, 45), (.goldenEvening, 18, 9), (.blueEvening, 18, 43), (.night, 21, 30),
    ]
    private static let bands: [(LightBand, Int)] = [(.poor, 22), (.fair, 41), (.good, 63), (.great, 82), (.epic, 94)]

    private static func window(_ kind: LightWindowKind, _ hour: Int, _ minute: Int, score: (LightBand, Int)?,
                               confidence: Confidence = .high, lengthMinutes: Int = 35) -> LightWindow {
        let start = day.at(hour: hour, minute: minute, in: zone)
        let span = TimeSpan(start: start, end: start.addingTimeInterval(Double(lengthMinutes) * 60))
        guard let (band, value) = score else {
            return LightWindow(kind: kind, span: span, assessment: .noForecast(.beyondHorizon))
        }
        let s = LightScore(value: value, band: band, confidence: confidence, range: value...value, contributors: [],
                           source: .sample, forecastFetchedAt: start, leadHours: 12)
        return LightWindow(kind: kind, span: span, assessment: .scored(s))
    }

    private static func unit(_ w: LightWindow, _ variant: EventScore.Variant, style: TimeStyle = .start,
                             loading: Bool = false, selected: Bool = false) -> some View {
        EventScore(window: w, zone: zone, timeStyle: style, variant: variant, isLoading: loading, isSelected: selected)
    }

    private static func row(_ variant: EventScore.Variant, kind: (LightWindowKind, Int, Int)) -> some View {
        HStack(alignment: .bottom, spacing: IterSpace.lg) {
            ForEach(bands, id: \.0) { band in
                unit(window(kind.0, kind.1, kind.2, score: band), variant)
            }
            unit(window(kind.0, kind.1, kind.2, score: nil), variant)
        }
    }

    @Test(.enabled(if: Snapshot.enabled)) func sizesAndBands() async throws {
        let view = VStack(alignment: .leading, spacing: IterSpace.xl) {
            ForEach(Self.kinds, id: \.0) { kind in
                VStack(alignment: .leading, spacing: IterSpace.md) {
                    Self.row(.large, kind: kind)
                    Self.row(.regular, kind: kind)
                    Self.row(.compact, kind: kind)
                    Self.row(.pin, kind: kind)
                }
            }
        }
        .padding(IterSpace.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(IterColor.backgroundWindow)
        try await Snapshot.render(view, screen: "eventunit", state: "sizes",
                                  sizes: [Snapshot.Size(name: "1060x1160", width: 1060, height: 1160)],
                                  settle: .milliseconds(300), chrome: .bare)
    }

    /// The same unit at a larger scale in the owner's mock proportions, plus the states: range time, low confidence,
    /// loading, a 100, a selected pin.
    @Test(.enabled(if: Snapshot.enabled)) func states() async throws {
        let gold = Self.window(.goldenMorning, 5, 45, score: (.good, 88))
        let view = VStack(alignment: .leading, spacing: IterSpace.xl) {
            HStack(alignment: .bottom, spacing: IterSpace.lg) {
                Self.unit(gold, .large)
                Self.unit(gold, .regular)
                Self.unit(gold, .compact)
            }
            HStack(alignment: .bottom, spacing: IterSpace.lg) {
                Self.unit(gold, .large, style: .range)
                Self.unit(gold, .regular, style: .range)
                Self.unit(Self.window(.goldenEvening, 18, 9, score: (.epic, 100)), .large)
                Self.unit(Self.window(.goldenEvening, 18, 9, score: (.epic, 100)), .regular)
                Self.unit(Self.window(.goldenEvening, 18, 9, score: (.epic, 100)), .compact)
            }
            HStack(alignment: .bottom, spacing: IterSpace.lg) {
                Self.unit(Self.window(.goldenMorning, 6, 12, score: (.great, 77), confidence: .low), .large)
                Self.unit(Self.window(.goldenMorning, 6, 12, score: (.great, 77), confidence: .low), .regular)
                Self.unit(Self.window(.blueEvening, 18, 43, score: nil), .large, loading: true)
                Self.unit(Self.window(.blueEvening, 18, 43, score: nil), .regular, loading: true)
                Self.unit(Self.window(.blueEvening, 18, 43, score: nil), .large, style: .range)
            }
            HStack(alignment: .bottom, spacing: IterSpace.lg) {
                Self.unit(gold, .pin)
                Self.unit(gold, .pin, selected: true)
                Self.unit(Self.window(.blueMorning, 5, 45, score: nil), .pin)
            }
        }
        .padding(IterSpace.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(IterColor.backgroundWindow)
        try await Snapshot.render(view, screen: "eventunit", state: "states",
                                  sizes: [Snapshot.Size(name: "900x520", width: 900, height: 520)],
                                  settle: .milliseconds(300), chrome: .bare)
    }

    /// The "What the scores mean" popover content (Mac), as it sits in the sidebar popover.
    @Test(.enabled(if: Snapshot.enabled)) func legend() async throws {
        let view = ScoreLegendPopover(source: .appleWeather)
            .background(IterColor.backgroundWindow)
        try await Snapshot.render(view, screen: "scorelegend", state: "popover",
                                  sizes: [Snapshot.Size(name: "340x700", width: 340, height: 700)],
                                  settle: .milliseconds(300), chrome: .bare)
    }
}
