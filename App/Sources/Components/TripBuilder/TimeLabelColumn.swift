import SwiftUI
import IterDesign

/// A time with its one-word label under it ("17:07 / Set up", "14:35 / Leave by"). The time is tertiary, the label
/// secondary semibold, as the design sets them. Draws nothing for a time that is not known.
struct TimeLabelColumn: View {
    let time: String?
    let label: String
    /// The column's least width, so the badge beside it lines up from row to row.
    var minWidth: CGFloat = 0

    var body: some View {
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

#Preview("Time label, light") { TimeLabelPreview().preferredColorScheme(.light) }
#Preview("Time label, dark") { TimeLabelPreview().preferredColorScheme(.dark) }

private struct TimeLabelPreview: View {
    var body: some View {
        HStack(spacing: IterSpace.xl) {
            TimeLabelColumn(time: "17:07", label: "Set up")
            TimeLabelColumn(time: "14:35", label: "Leave by")
            TimeLabelColumn(time: nil, label: "Set up")
        }
        .padding(IterSpace.xl)
        .background(IterColor.backgroundWindow)
    }
}
