import CoreGraphics
import Foundation
import IterModel
import SwiftUI
import Testing

@testable import IterUI

/// Score chip galleries and the ramp-endpoint pixel check.
@MainActor
@Suite(.serialized) struct ScoreSnapshotTests {
    private static let zone = TimeZone(identifier: "UTC")!
    private static let locale = Locale(identifier: "en_GB")
    private static let base = Date(timeIntervalSince1970: 1_791_269_700) // 2026-10-06 06:55 UTC

    private static func chip(_ kind: LightWindowKind = .goldenMorning, score: Int?, size: ScoreChip.Size,
                             style: ScoreChip.TimeStyle = .start, low: Bool = false, loading: Bool = false,
                             tomorrow: Bool = false, selected: Bool = false, offsetMinutes: Double = 0) -> ScoreChip {
        let start = base.addingTimeInterval(offsetMinutes * 60)
        return ScoreChip(kind: kind, start: start, end: start.addingTimeInterval(35 * 60), score: score, zone: zone,
                         locale: locale, size: size, timeStyle: style, isLowConfidence: low, isTomorrow: tomorrow,
                         isLoading: loading, isSelected: selected)
    }

    private static func gallery<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: IterSpace.xl, content: content)
            .padding(IterSpace.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(IterColor.backgroundWindow)
    }

    @Test func sizes() async throws {
        let kinds: [(LightWindowKind, Double)] = [(.blueMorning, -70), (.goldenMorning, 0), (.goldenEvening, 680),
                                                  (.blueEvening, 720), (.night, 900)]
        let view = Self.gallery {
            ForEach([ScoreChip.Size.large, .small, .compact], id: \.self) { size in
                VStack(alignment: .leading, spacing: IterSpace.md) {
                    HStack(spacing: IterSpace.lg) {
                        ForEach([0, 7, 25, 50, 75, 100] as [Int?] + [nil], id: \.self) { Self.chip(score: $0, size: size) }
                    }
                    HStack(spacing: IterSpace.lg) {
                        ForEach(kinds, id: \.0) { Self.chip($0.0, score: 64, size: size, offsetMinutes: $0.1) }
                    }
                }
            }
        }
        try await Snapshot.assertMatches(view, name: "score-chip-sizes", size: CGSize(width: 1000, height: 350))
    }

    @Test func states() async throws {
        let view = Self.gallery {
            HStack(alignment: .bottom, spacing: IterSpace.lg) {
                Self.chip(score: nil, size: .small)
                Self.chip(score: nil, size: .small, loading: true)
                Self.chip(.blueEvening, score: nil, size: .small, loading: true)
                Self.chip(score: 77, size: .small, low: true)
                Self.chip(.goldenEvening, score: 88, size: .small, tomorrow: true)
                Self.chip(score: 88, size: .small, style: .range)
                Self.chip(.blueEvening, score: nil, size: .small, style: .range, offsetMinutes: 700)
                Self.chip(score: 100, size: .large, style: .range)
            }
        }
        try await Snapshot.assertMatches(view, name: "score-chip-states", size: CGSize(width: 1100, height: 120))
    }

    @Test func pin() async throws {
        let view = Self.gallery {
            HStack(alignment: .bottom, spacing: IterSpace.xl) {
                Self.chip(score: 88, size: .pin)
                Self.chip(score: 88, size: .pin, selected: true)
                Self.chip(score: 20, size: .pin)
                Self.chip(.blueMorning, score: nil, size: .pin)
            }
        }
        try await Snapshot.assertMatches(view, name: "score-chip-pin", size: CGSize(width: 420, height: 110))
    }

    @Test func fixedWidth() async throws {
        let view = Self.gallery {
            ForEach([ScoreChip.Size.large, .small, .compact], id: \.self) { size in
                HStack(alignment: .bottom, spacing: IterSpace.lg) {
                    ForEach([0, 7, 50, 100] as [Int?] + [nil], id: \.self) { Self.chip(score: $0, size: size) }
                }
            }
        }
        try await Snapshot.assertMatches(view, name: "score-chip-fixedwidth", size: CGSize(width: 720, height: 260))
    }

    // MARK: Ramp endpoints

    /// Renders a .small chip at the top-left of a padded canvas and reads a pixel inside the fill, left of the symbol.
    private func fillPixel(score: Int, appearance: SnapshotAppearance) async throws -> (r: Int, g: Int, b: Int, a: Int) {
        let view = Self.chip(score: score, size: .small)
            .padding(20)
            .frame(width: 200, height: 80, alignment: .topLeading)
        let image = try await Snapshot.image(view, appearance: appearance, size: CGSize(width: 200, height: 80),
                                             background: IterColor.backgroundWindow)
        let px = try #require(Pixels(image))
        let scale = CGFloat(image.width) / 200
        return px.rgba(Int(24 * scale), Int(39 * scale))
    }

    @Test func rampEndpointPixels() async throws {
        let expectations: [(Int, SnapshotAppearance, (Int, Int, Int))] = [
            (0, .light, (0xFF, 0xFF, 0xFF)), (100, .light, (0xC9, 0x50, 0x2A)),
            (0, .dark, (0x1E, 0x14, 0x10)), (100, .dark, (0xE6, 0x8A, 0x62)),
        ]
        for (score, appearance, want) in expectations {
            let got = try await fillPixel(score: score, appearance: appearance)
            print("ramp endpoint \(appearance.rawValue) \(score): rgb(\(got.r), \(got.g), \(got.b)) expected \(want)")
            #expect(abs(got.r - want.0) <= 2 && abs(got.g - want.1) <= 2 && abs(got.b - want.2) <= 2,
                    "\(appearance.rawValue) score \(score): got \(got), want \(want)")
        }
    }
}
