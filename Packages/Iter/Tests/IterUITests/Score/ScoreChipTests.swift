import Foundation
import IterModel
import SwiftUI
import Testing

@testable import IterUI

private let utc = TimeZone(identifier: "UTC")!
private let gb = Locale(identifier: "en_GB")
/// 2026-10-06 18:14 UTC.
private let sunset = Date(timeIntervalSince1970: 1_791_310_440)

@MainActor
@Suite("ScoreChip")
struct ScoreChipTests {
    @Test func scoreFieldIsOneWidthPerSize() {
        for size in ScoreChip.Size.allCases {
            let w = ScoreChip.scoreFieldWidth(size)
            #expect(w > 0)
            // The field fits "100" at the size's numeral font and is never re-measured per score.
            #expect(ScoreChip.scoreFieldWidth(size) == w)
        }
        #expect(ScoreChip.scoreFieldWidth(.large) > ScoreChip.scoreFieldWidth(.small))
        #expect(ScoreChip.scoreFieldWidth(.small) > ScoreChip.scoreFieldWidth(.compact))
        #expect(ScoreChip.scoreFieldWidth(.pin) == ScoreChip.scoreFieldWidth(.compact))
    }

    @Test func renderedWidthIsTheSameAtEveryScore() {
        for size in ScoreChip.Size.allCases where size != .pin {
            var widths = Set<CGFloat>()
            for score in [0, 7, 100, nil] as [Int?] {
                let chip = ScoreChip(kind: .goldenEvening, start: sunset, score: score, zone: utc, locale: gb, size: size)
                let r = ImageRenderer(content: chip)
                widths.insert(r.cgImage.map { CGFloat($0.width) } ?? 0)
            }
            #expect(widths.count == 1, "size \(size): \(widths)")
        }
    }

    @Test func heightsFollowTheTokens() {
        #expect(ScoreChip.height(.large) == 48)
        #expect(ScoreChip.height(.small) == 38)
        #expect(ScoreChip.height(.compact) == 26)
        #expect(ScoreChip.height(.pin) == 26)
    }

    @Test func maxWidthIsCachedAndOrdered() {
        let l = ScoreChip.maxWidth(size: .large, timeStyle: .start, locale: gb)
        let s = ScoreChip.maxWidth(size: .small, timeStyle: .start, locale: gb)
        let c = ScoreChip.maxWidth(size: .compact, timeStyle: .start, locale: gb)
        #expect(l > s && s > c)
        #expect(ScoreChip.maxWidth(size: .small, timeStyle: .range, locale: gb) > s)
        #expect(ScoreChip.maxWidth(size: .small, timeStyle: .start, locale: gb) == s)
    }

    @Test func symbolPerKind() {
        #expect(LightText.symbol(LightWindowKind.goldenMorning) == "sunrise.fill")
        #expect(LightText.symbol(LightWindowKind.goldenEvening) == "sunset.fill")
        #expect(LightText.symbol(LightWindowKind.blueMorning) == "sun.haze.fill")
        #expect(LightText.symbol(LightWindowKind.blueEvening) == "moon.haze.fill")
        #expect(LightText.symbol(LightWindowKind.night) == "moon.stars.fill")
    }

    @Test func accessibilityLabels() {
        #expect(ScoreChip(kind: .goldenEvening, start: sunset, score: 64, zone: utc, locale: gb).accessibilityText
                == "Sunset, 18:14, score 64")
        #expect(ScoreChip(kind: .goldenEvening, start: sunset, score: nil, zone: utc, locale: gb).accessibilityText
                == "Sunset, 18:14")
        #expect(ScoreChip(kind: .goldenEvening, start: sunset, score: 64, zone: utc, locale: gb, isTomorrow: true).accessibilityText
                == "Sunset, tomorrow at 18:14, score 64")
        #expect(ScoreChip(kind: .blueEvening, start: sunset, score: 64, zone: utc, locale: gb, isLowConfidence: true).accessibilityText
                == "Evening Blue Hour, 18:14, score 64, low confidence")
    }

    @Test func scoreClampsToRange() {
        #expect(ScoreChip(kind: .night, start: sunset, score: 140, zone: utc).score == 100)
        #expect(ScoreChip(kind: .night, start: sunset, score: -3, zone: utc).score == 0)
    }
}
