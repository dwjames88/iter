import SwiftUI

/// A time with its one-word label under it ("17:07 / Set up", "14:35 / Leave by"). The time is tertiary, the label
/// secondary semibold, as the design sets them. Draws nothing for a time that is not known.
/// Figma part: time label column.
public struct TimeLabelColumn: View {
    public let time: String?
    public let label: String
    /// The column's least width, so the badge beside it lines up from row to row.
    public var minWidth: CGFloat

    public init(time: String?, label: String, minWidth: CGFloat = 0) {
        self.time = time
        self.label = label
        self.minWidth = minWidth
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let time {
                Text(time)
                    .font(BuilderType.body)
                    .monospacedDigit()
                    .foregroundStyle(IterColor.textTertiary)
                    .lineLimit(1)
                Text(label)
                    .font(BuilderType.captionStrong)
                    .foregroundStyle(IterColor.textSecondary)
                    .lineLimit(1)
            }
        }
        .fixedSize()
        .frame(minWidth: minWidth, alignment: .leading)
        .accessibilityHidden(true)
    }
}
