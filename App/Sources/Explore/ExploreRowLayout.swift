import AppKit
import SwiftUI
import IterCore
import IterDesign

/// The fixed lanes of the light column in an Explore list row, so every row's window symbol, score chip and start
/// time sit on the same x. Nothing here is typed in except the symbol lane: the chip and time widths are measured
/// once from the strings and fonts the lane actually uses.
///
/// - `symbolLane`: the window symbol plus a little air.
/// - `chipLane`: the widest score chip (the larger of `IterSize.badgeMinWidth` and three digits at the score font,
///   plus the chip's own horizontal padding).
/// - `timeLane`: the widest start time the current locale and clock format can produce, sampled at :58 past every
///   hour with the formatter `LightText.startTime` uses, at the footnote size with monospaced digits.
///
/// Measured with `NSFont.preferredFont(forTextStyle:)`, which is what SwiftUI's text styles resolve to on macOS.
@MainActor
enum ExploreRowLayout {
    /// Gap between the lanes.
    nonisolated static let laneGap = IterSpace.sm

    struct Metrics {
        var symbolLane: CGFloat
        var chipLane: CGFloat
        var timeLane: CGFloat
        /// symbol + chip + time + the two gaps.
        var total: CGFloat { symbolLane + chipLane + timeLane + laneGap * 2 }
    }

    static let metrics: Metrics = measure()

    private static func measure() -> Metrics {
        let timeBase = NSFont.preferredFont(forTextStyle: .footnote)
        let timeFont = NSFont.monospacedDigitSystemFont(ofSize: timeBase.pointSize, weight: .regular)
        let scoreBase = NSFont.preferredFont(forTextStyle: .title3)
        let scoreFont = NSFont.monospacedDigitSystemFont(ofSize: scoreBase.pointSize, weight: .semibold)

        // Chip: three digits is the widest score (100).
        let chipText = ceil(width("100", scoreFont)) + IterSpace.xs * 2
        let chipLane = max(IterSize.badgeMinWidth + IterSpace.xs * 2, chipText, IterSize.badgeHeight)

        // Time: the widest of 00:58 ... 23:58 in the current format.
        let utc = TimeZone(identifier: "UTC")!
        let midnight = LocalDay(year: 2026, month: 1, day: 1).at(hour: 0, in: utc)
        let times = (0..<24).map { hour -> String in
            TimeText.time(midnight.addingTimeInterval(Double(hour) * 3600 + 58 * 60), in: utc)
        }
        let timeLane = ceil(times.map { width($0, timeFont) }.max() ?? 0)

        return Metrics(symbolLane: IterSize.windowSymbol + IterSpace.xs, chipLane: ceil(chipLane), timeLane: timeLane)
    }

    private static func width(_ string: String, _ font: NSFont) -> CGFloat {
        NSAttributedString(string: string, attributes: [.font: font]).size().width
    }
}
