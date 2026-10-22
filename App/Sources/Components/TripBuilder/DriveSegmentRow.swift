import SwiftUI
import IterCore
import IterDesign

/// A drive in the plan. `.inline` sits between two stops of a day, no card: the leave-by time, the blue car and the drive
/// time and distance. `.transfer` is the card between two days: the same, with a sentence about the move, where it starts
/// and, when there is one, the night's stay with a Find Hotels link.
struct DriveSegmentRow: View {
    enum Style {
        case inline
        /// `headline`: "Drive to the next area in the morning, before the shoot."; `from`: the stop the drive leaves;
        /// `overnight`: "Overnight near Page, AZ" and where, for the hotels search.
        case transfer(headline: String, from: String?, overnight: String?, hotels: Coordinate?)
    }

    var style: Style
    /// "14:35"; nil until the drive has a leave-by time.
    var leaveBy: String?
    /// "3hr, 21min • 183mi"; nil until the drive has been fetched or estimated.
    var summary: String?
    var isEstimate = false
    /// "Drive doesn't fit: 25 min short"
    var warning: String?

    var body: some View {
        switch style {
        case .inline: inline
        case .transfer(let headline, let from, let overnight, let hotels): transfer(headline, from, overnight, hotels)
        }
    }

    // MARK: Inline

    private var inline: some View {
        HStack(alignment: .top, spacing: 8) {
            HStack(spacing: 8) {
                TimeLabelColumn(time: leaveBy, label: leaveLabel, minWidth: 45)
                DriveBadge()
            }
            .padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 2) { summaryLines }
                .padding(.top, 4)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 24 + 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Transfer

    private func transfer(_ headline: String, _ from: String?, _ overnight: String?, _ hotels: Coordinate?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            HStack(spacing: 8) {
                TimeLabelColumn(time: leaveBy, label: leaveLabel, minWidth: 45)
                DriveBadge()
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(headline)
                    .font(BuilderType.bodyStrong)
                    .foregroundStyle(IterColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let summary {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "info.circle").font(BuilderType.body).foregroundStyle(IterColor.accentText).accessibilityHidden(true)
                        HStack(spacing: 4) {
                            Text(summary).foregroundStyle(IterColor.textPrimary).monospacedDigit()
                            if let from {
                                Text("from \(from)", comment: "Transfer card: where the drive starts, after its time and distance")
                                    .foregroundStyle(IterColor.textTertiary)
                                    .lineLimit(1)
                            }
                        }
                        .font(BuilderType.body)
                    }
                }
                if let warning { warningLine(warning) }
                if let overnight {
                    HStack(spacing: 8) {
                        Image(systemName: "moon.zzz").font(BuilderType.bodyStrong).accessibilityHidden(true)
                        Text(overnight).font(BuilderType.bodyStrong).lineLimit(1)
                        if let hotels { FindHotelsButton(coordinate: hotels) }
                    }
                    .foregroundStyle(IterColor.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(IterColor.backgroundContent, in: RoundedRectangle(cornerRadius: BuilderMetrics.innerCorner, style: .continuous))
        .padding(.horizontal, 24)
        .accessibilityElement(children: .contain)
    }

    // MARK: Shared

    private var leaveLabel: String { String(localized: "Leave by", comment: "Label under a drive's leave-by time") }

    @ViewBuilder private var summaryLines: some View {
        if let summary {
            HStack(spacing: 4) {
                Text(summary).monospacedDigit()
                if isEstimate {
                    Text(verbatim: "•").accessibilityHidden(true)
                    Text(ConnectorText.estimated).foregroundStyle(IterColor.textTertiary).help(Text(ConnectorText.driveEstimatedHelp))
                }
            }
            .font(BuilderType.body)
            .foregroundStyle(IterColor.textPrimary)
        }
        if let warning { warningLine(warning) }
    }

    private func warningLine(_ text: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(BuilderType.caption)
        .foregroundStyle(IterColor.warning)
    }
}

#Preview("Drive segments, light") { DriveSegmentsPreview().preferredColorScheme(.light) }
#Preview("Drive segments, dark") { DriveSegmentsPreview().preferredColorScheme(.dark) }

struct DriveSegmentsPreview: View {
    var body: some View {
        VStack(spacing: 24) {
            DriveSegmentRow(style: .inline, leaveBy: "14:35", summary: "3hr, 21min • 183mi")
                .background(IterColor.backgroundContent)
            DriveSegmentRow(style: .inline, leaveBy: "14:35", summary: "3hr, 21min • 183mi", isEstimate: true, warning: "Drive doesn't fit: 25 min short")
                .background(IterColor.backgroundContent)
            DriveSegmentRow(style: .transfer(headline: "Drive to the next area in the morning, before the shoot.", from: "Horseshoe Bend",
                                             overnight: "Overnight near Page, AZ", hotels: Coordinate(latitude: 36.9, longitude: -111.45)),
                            leaveBy: "03:56", summary: "2hr, 5min • 128mi")
        }
        .frame(width: 608)
        .padding(16)
        .background(IterColor.backgroundWindow)
    }
}
