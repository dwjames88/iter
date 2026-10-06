import SwiftUI
import IterCore
import IterDesign
import IterFeatures

/// The colour of a stretch of the timeline's rail: coral when the drive fits, violet when it does not, neutral otherwise.
enum RailTone {
    case route, warning, neutral

    init(_ drive: TripDriveItem) {
        self = drive.leg == nil ? .neutral : (drive.fits ? .route : .warning)
    }

    var color: Color {
        switch self {
        case .route: IterColor.route
        case .warning: IterColor.warning
        case .neutral: IterColor.separator
        }
    }
}

enum TimelineMetrics {
    /// The time gutter to the left of the rail.
    static let gutterWidth: CGFloat = 68
    static let railWidth: CGFloat = 28
}

/// The left time gutter: a time in monospaced digits with a one-word label under it ("Leave", "Set up").
struct TimeGutter: View {
    let time: Date?
    let zone: TimeZone
    let label: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if let time {
                Text(TimeText.time(time, in: zone))
                    .font(IterFont.timeSmall)
                    .foregroundStyle(IterColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(label)
                    .font(IterFont.caption)
                    .foregroundStyle(IterColor.textSecondary)
            }
        }
        .frame(width: TimelineMetrics.gutterWidth, alignment: .trailing)
        .padding(.trailing, IterSpace.sm)
        .accessibilityHidden(true)
    }
}

/// The vertical line of the timeline for one row: a segment above the node, the node, a segment below it.
/// The row's content decides where the node sits (`nodeTop`), so the rail lines up with the row's first line.
struct TimelineRail<Node: View>: View {
    var above: RailTone?
    var below: RailTone?
    let nodeTop: CGFloat
    let nodeSize: CGFloat
    @ViewBuilder let node: Node

    var body: some View {
        VStack(spacing: 0) {
            segment(above).frame(height: nodeTop + nodeSize / 2)
            segment(below).frame(maxHeight: .infinity)
        }
        .frame(width: TimelineMetrics.railWidth)
        .overlay(alignment: .top) { node.padding(.top, nodeTop) }
        .accessibilityHidden(true)
    }

    private func segment(_ tone: RailTone?) -> some View {
        Rectangle().fill(tone?.color ?? .clear).frame(width: IterStroke.thick)
    }
}

/// A drive on the timeline: the car on the rail, the time and distance, and whether it fits. The gutter shows when to
/// leave. A drive into a day's first stop (`isDriveIn`) names where it starts, since that stop is on the day before.
struct DriveRowView: View {
    let drive: TripDriveItem
    var isDriveIn = false
    var above: RailTone?
    var below: RailTone?

    private var tone: RailTone { RailTone(drive) }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            TimeGutter(time: drive.leaveBy, zone: drive.leaveZone, label: String(localized: "Leave", comment: "Label under a drive's leave-by time"))
            TimelineRail(above: above, below: below, nodeTop: IterSpace.xs, nodeSize: IterSize.iconMedium) {
                Image(systemName: "car.fill")
                    .font(.system(size: IterSize.iconSmall - 4))
                    .foregroundStyle(tone.color)
                    .frame(width: IterSize.iconMedium, height: IterSize.iconMedium)
                    .background(IterColor.backgroundContent, in: Circle())
            }
            VStack(alignment: .leading, spacing: IterSpace.xxs) {
                if let leg = drive.leg {
                    HStack(spacing: IterSpace.xs) {
                        Text(ConnectorText.drive(leg)).monospacedDigit()
                        if leg.isEstimate {
                            Text(verbatim: "·").accessibilityHidden(true)
                            Text(ConnectorText.estimated).help(Text(ConnectorText.driveEstimatedHelp))
                        }
                    }
                    .font(IterFont.caption)
                    .foregroundStyle(IterColor.textSecondary)
                    if let short = drive.shortBySeconds {
                        Label {
                            Text(ScheduleText.driveDoesNotFit(shortBy: short)).fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .font(IterFont.caption)
                        .foregroundStyle(IterColor.warning)
                    }
                }
                if isDriveIn {
                    Text("From \(drive.fromName)", comment: "Under the drive into a day's first stop: where the drive starts")
                        .font(IterFont.caption)
                        .foregroundStyle(IterColor.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(.leading, IterSpace.sm)
            .padding(.vertical, IterSpace.xs)
            .frame(maxWidth: .infinity, minHeight: IterSize.iconMedium + IterSpace.xs * 2, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
