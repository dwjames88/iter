import SwiftUI
import Testing
import IterCore
import IterDesign
@testable import Iter

/// The score chip alone: every size at the ramp stops 0/25/50/75/100, unscored and loading, plus the states.
@MainActor
@Suite(.serialized) struct ScoreChipSnapshotTests {
    private static let zone = TimeZone(identifier: "UTC")!
    private static let day = LocalDay(year: 2026, month: 10, day: 6)
    private static let stops = [0, 25, 50, 75, 100]

    private static func window(_ kind: LightWindowKind = .goldenMorning, _ hour: Int = 6, _ minute: Int = 55, score: Int?,
                               confidence: Confidence = .high, lengthMinutes: Int = 35) -> LightWindow {
        let start = day.at(hour: hour, minute: minute, in: zone)
        let span = TimeSpan(start: start, end: start.addingTimeInterval(Double(lengthMinutes) * 60))
        guard let value = score else {
            return LightWindow(kind: kind, span: span, assessment: .noForecast(.beyondHorizon))
        }
        let s = LightScore(value: value, band: LightBand(score: value), confidence: confidence, range: value...value, contributors: [],
                           source: .sample, forecastFetchedAt: start, leadHours: 12)
        return LightWindow(kind: kind, span: span, assessment: .scored(s))
    }

    private static func chip(_ w: LightWindow, _ size: ScoreChip.Size, style: TimeStyle = .start,
                             loading: Bool = false, selected: Bool = false) -> some View {
        ScoreChip(window: w, zone: zone, timeStyle: style, size: size, isLoading: loading, isSelected: selected)
    }

    @Test(.enabled(if: Snapshot.enabled)) func sizes() async throws {
        let view = VStack(alignment: .leading, spacing: IterSpace.xl) {
            ForEach([ScoreChip.Size.large, .small, .compact, .pin], id: \.self) { size in
                HStack(alignment: .bottom, spacing: IterSpace.lg) {
                    ForEach(Self.stops, id: \.self) { Self.chip(Self.window(score: $0), size) }
                    Self.chip(Self.window(score: nil), size)
                    Self.chip(Self.window(score: nil), size, loading: true)
                }
            }
        }
        .padding(IterSpace.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(IterColor.backgroundWindow)
        try await Snapshot.render(view, screen: "scorechip", state: "sizes",
                                  sizes: [Snapshot.Size(name: "1000x560", width: 1000, height: 560)],
                                  settle: .milliseconds(300), chrome: .bare)
    }

    /// Scores 7 and 100 side by side per size: the chips are the same width.
    @Test(.enabled(if: Snapshot.enabled)) func fixedwidth() async throws {
        for size in ScoreChip.Size.allCases {
            print("scorechip width \(size): \(ScoreChip.maxWidth(size: size, timeStyle: .start)) x \(ScoreChip.height(size)), score field \(ScoreChip.scoreFieldWidth(size))")
        }
        let view = VStack(alignment: .leading, spacing: IterSpace.xl) {
            ForEach([ScoreChip.Size.large, .small, .compact, .pin], id: \.self) { size in
                HStack(alignment: .bottom, spacing: IterSpace.lg) {
                    Self.chip(Self.window(score: 7), size)
                    Self.chip(Self.window(score: 100), size)
                    Self.chip(Self.window(score: nil), size)
                }
            }
        }
        .padding(IterSpace.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(IterColor.backgroundWindow)
        try await Snapshot.render(view, screen: "scorechip", state: "fixedwidth",
                                  sizes: [Snapshot.Size(name: "420x300", width: 420, height: 300)],
                                  settle: .milliseconds(300), chrome: .bare)
    }

    /// Window kinds, the range time, low confidence, a 100, the selected pin.
    @Test(.enabled(if: Snapshot.enabled)) func states() async throws {
        let view = VStack(alignment: .leading, spacing: IterSpace.xl) {
            HStack(alignment: .bottom, spacing: IterSpace.lg) {
                Self.chip(Self.window(.goldenMorning, 6, 12, score: 88), .small)
                Self.chip(Self.window(.blueMorning, 5, 45, score: 63), .small)
                Self.chip(Self.window(.goldenEvening, 18, 9, score: 100), .small)
                Self.chip(Self.window(.blueEvening, 18, 43, score: 41), .small)
                Self.chip(Self.window(.night, 21, 30, score: 22), .small)
            }
            HStack(alignment: .bottom, spacing: IterSpace.lg) {
                Self.chip(Self.window(score: 88), .small, style: .range)
                Self.chip(Self.window(score: 77, confidence: .low), .small)
                Self.chip(Self.window(.blueEvening, 18, 43, score: nil), .small, style: .range)
            }
            HStack(alignment: .bottom, spacing: IterSpace.lg) {
                Self.chip(Self.window(score: 88), .pin)
                Self.chip(Self.window(score: 88), .pin, selected: true)
                Self.chip(Self.window(.blueMorning, 5, 45, score: nil), .pin)
            }
        }
        .padding(IterSpace.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(IterColor.backgroundWindow)
        try await Snapshot.render(view, screen: "scorechip", state: "states",
                                  sizes: [Snapshot.Size(name: "700x360", width: 700, height: 360)],
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
