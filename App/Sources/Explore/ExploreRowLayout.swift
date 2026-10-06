import AppKit
import SwiftUI
import IterCore
import IterDesign

/// The fixed lanes of the light column in an Explore list row, so every row's chip, window name, band and start
/// time sit on the same x. Nothing here is typed in: each width is measured once from the strings and fonts the
/// lane actually uses.
///
/// - `chipLane`: the widest score chip (the larger of `IterSize.badgeMinWidth` and three digits at the score font,
///   plus the chip's own horizontal padding). The dashed ring is centred in the same lane.
/// - `textLane`: the larger of (a) the widest localized window name over every `LightWindowKind` at the
///   subheadline size, and (b) the widest "band word + confidence mark" (or "No forecast") at the caption size.
///   If the one-line lanes would leave the spot name less than `minSpotColumn` at the ideal list width, the window
///   name is set on two lines (broken at a space, never abbreviated) and the lane is the widest of the best two-line
///   breaks instead.
/// - `timeLane`: the widest start time the current locale and clock format can produce, sampled at :58 past every
///   hour with the formatter `LightText.startTime` uses, at the footnote size with monospaced digits.
///
/// Measured with `NSFont.preferredFont(forTextStyle:)`, which is what SwiftUI's text styles resolve to on macOS.
@MainActor
enum ExploreRowLayout {
    /// Gap between the lanes.
    nonisolated static let laneGap = IterSpace.sm
    /// Space the list leaves at each side of a row's content (row inset plus the row's own padding).
    private static let rowInset = IterSpace.lg
    /// The least width the spot name column keeps before the window name goes to two lines.
    private static let minSpotColumn = IterSize.listMin / 2

    struct Metrics {
        var chipLane: CGFloat
        var textLane: CGFloat
        var timeLane: CGFloat
        var nameLines: Int
        var oneLineNameWidth: CGFloat
        /// chip + text + time + the two gaps.
        var total: CGFloat { chipLane + textLane + timeLane + laneGap * 2 }
    }

    static let metrics: Metrics = measure()

    private static func measure() -> Metrics {
        let nameFont = NSFont.preferredFont(forTextStyle: .subheadline)
        let captionFont = NSFont.preferredFont(forTextStyle: .caption1)
        let timeBase = NSFont.preferredFont(forTextStyle: .footnote)
        let timeFont = NSFont.monospacedDigitSystemFont(ofSize: timeBase.pointSize, weight: .regular)
        let scoreBase = NSFont.preferredFont(forTextStyle: .title3)
        let scoreFont = NSFont.monospacedDigitSystemFont(ofSize: scoreBase.pointSize, weight: .semibold)

        // Chip: three digits is the widest score (100).
        let chipText = ceil(width("100", scoreFont)) + IterSpace.xs * 2
        let chipLane = max(IterSize.badgeMinWidth + IterSpace.xs * 2, chipText, IterSize.badgeHeight)

        // Window name: one line, or two.
        let names = LightWindowKind.allCases.map { LightText.name($0) }
        let oneLine = ceil(names.map { width($0, nameFont) }.max() ?? 0)
        let twoLine = ceil(names.map { balancedWidth($0, nameFont) }.max() ?? 0)

        // Band word and confidence mark, or "No forecast".
        let markWidth = IterStroke.thick * 3 + IterStroke.thin * 2
        let bands = LightBand.allCases.map { width(LightText.name($0), captionFont) + IterSpace.xs + markWidth }
        let bandRow = ceil(max(bands.max() ?? 0, width(LightText.noForecast, captionFont)))

        // Time: the widest of 00:58 ... 23:58 in the current format.
        let utc = TimeZone(identifier: "UTC")!
        let midnight = LocalDay(year: 2026, month: 1, day: 1).at(hour: 0, in: utc)
        let times = (0..<24).map { hour -> String in
            TimeText.time(midnight.addingTimeInterval(Double(hour) * 3600 + 58 * 60), in: utc)
        }
        let timeLane = ceil(times.map { width($0, timeFont) }.max() ?? 0)

        let budget = IterSize.listIdeal - rowInset * 2
        let oneLineTotal = chipLane + max(oneLine, bandRow) + timeLane + laneGap * 2
        let fits = budget - oneLineTotal >= minSpotColumn
        let textLane = fits ? max(oneLine, bandRow) : max(twoLine, bandRow)
        return Metrics(chipLane: ceil(chipLane), textLane: textLane, timeLane: timeLane,
                       nameLines: fits ? 1 : 2, oneLineNameWidth: oneLine)
    }

    private static func width(_ string: String, _ font: NSFont) -> CGFloat {
        NSAttributedString(string: string, attributes: [.font: font]).size().width
    }

    /// The narrowest width at which `string` fits on two lines, breaking at a space.
    private static func balancedWidth(_ string: String, _ font: NSFont) -> CGFloat {
        let words = string.split(separator: " ").map(String.init)
        guard words.count > 1 else { return width(string, font) }
        return (1..<words.count).map { split in
            max(width(words[..<split].joined(separator: " "), font), width(words[split...].joined(separator: " "), font))
        }.min() ?? width(string, font)
    }
}
