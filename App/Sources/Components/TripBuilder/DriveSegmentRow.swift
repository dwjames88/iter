import SwiftUI
import IterCore
import IterDesign

/// A drive in the plan. `.inline` sits between two stops of a day, no card: the leave-by time, the blue car and the drive
/// time and distance. `.transfer` is the card between two days: the same, with a sentence about the move, where it starts
/// and, when there is one, the night's stay with a Find Hotels link.
struct DriveSegmentRow: View {
    enum Style {
        case inline
        /// `timing`: the picker's value ("Drive to the next area the [Morning] before the shoot."); `from`: the stop the drive
        /// leaves; `overnight`: "Overnight near Page, AZ" and where, for the hotels search.
        case transfer(timing: TransferTiming, from: String?, overnight: String?, hotels: Coordinate?)
    }

    var style: Style
    /// "14:35"; nil until the drive has a leave-by time.
    var leaveBy: String?
    /// "3hr, 21min • 183mi"; nil until the drive has been fetched or estimated.
    var summary: String?
    var isEstimate = false
    /// "Drive doesn't fit: 25 min short"
    var warning: String?
    /// The drive's note, edited in place when `onNote` is given.
    var note = ""
    var onNote: ((String) -> Void)?
    /// A change of the transfer card's timing picker.
    var onTiming: (TransferTiming) -> Void = { _ in }

    var body: some View {
        switch style {
        case .inline: inline
        case .transfer(let timing, let from, let overnight, let hotels): transfer(timing, from, overnight, hotels)
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
            .accessibilityElement(children: .combine)
            VStack(alignment: .leading, spacing: 2) {
                SummaryAndNote {
                    inlineSummary
                } note: {
                    noteField
                }
                if let warning { warningLine(warning) }
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 24 + 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    // MARK: Transfer

    private func transfer(_ timing: TransferTiming, _ from: String?, _ overnight: String?, _ hotels: Coordinate?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            HStack(spacing: 8) {
                TimeLabelColumn(time: leaveBy, label: leaveLabel, minWidth: 45)
                DriveBadge()
            }
            VStack(alignment: .leading, spacing: 8) {
                headline(timing)
                if let summary {
                    SummaryAndNote {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "info.circle").font(BuilderType.body).foregroundStyle(IterColor.accentText).accessibilityHidden(true)
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 4) { summaryParts(summary, from) }
                                VStack(alignment: .leading, spacing: 2) { summaryParts(summary, from) }
                            }
                            .font(BuilderType.body)
                        }
                        .accessibilityElement(children: .combine)
                    } note: {
                        noteField
                    }
                } else {
                    noteField
                }
                if let warning { warningLine(warning) }
                if let overnight {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { overnightParts(overnight, hotels) }
                        VStack(alignment: .leading, spacing: 4) { overnightParts(overnight, hotels) }
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

    /// "Drive to the next area the [Morning] before the shoot." The picker is the system menu; the sentence wraps with it.
    private func headline(_ timing: TransferTiming) -> some View {
        let prefix = Text("Drive to the next area the", comment: "Transfer card sentence, before the timing picker")
        let suffix: Text? = timing == .morning ? Text("before the shoot.", comment: "Transfer card sentence, after the Morning timing picker") : nil
        let picker = timingPicker(timing)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                prefix
                picker
                if let suffix { suffix }
            }
            VStack(alignment: .leading, spacing: 4) {
                prefix
                HStack(spacing: 4) {
                    picker
                    if let suffix { suffix }
                }
                #if os(iOS)
                // The iOS menu picker draws its own leading inset; pull it back so the second line aligns with the first.
                .padding(.leading, -12)
                #endif
            }
        }
        .font(BuilderType.bodyStrong)
        .foregroundStyle(IterColor.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func timingPicker(_ timing: TransferTiming) -> some View {
        Picker(selection: Binding(get: { timing }, set: { onTiming($0) })) {
            ForEach(TransferTiming.allCases, id: \.self) { Text(ConnectorText.transferTimingName($0)).tag($0) }
        } label: {
            Text("Drive timing", comment: "Accessibility label of the transfer card's timing picker")
        }
        .pickerStyle(.menu)
        .labelsHidden()
        #if os(macOS)
        .controlSize(.small)
        #endif
        .fixedSize()
        .help(Text("Drive on the morning of the shoot, or the evening before after the last session", comment: "Tooltip of the transfer card's timing picker"))
    }

    @ViewBuilder private var noteField: some View {
        if let onNote {
            NotePlaceholder(note: note,
                            prompt: LocalizedStringResource("Add a note…", comment: "Placeholder for a drive's note"),
                            accessibilityName: LocalizedStringResource("Drive note", comment: "Accessibility label of a drive's note field"),
                            onCommit: onNote)
        }
    }

    @ViewBuilder private func summaryParts(_ summary: String, _ from: String?) -> some View {
        Text(summary).foregroundStyle(IterColor.textPrimary).monospacedDigit()
        if let from {
            Text("from \(from)", comment: "Transfer card: where the drive starts, after its time and distance")
                .foregroundStyle(IterColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func overnightParts(_ overnight: String, _ hotels: Coordinate?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "moon.zzz").font(BuilderType.bodyStrong).accessibilityHidden(true)
            Text(overnight).font(BuilderType.bodyStrong).fixedSize(horizontal: false, vertical: true)
        }
        if let hotels { FindHotelsButton(coordinate: hotels) }
    }

    // MARK: Shared

    private var leaveLabel: String {
        if case .transfer(.eveningBefore, _, _, _) = style {
            return String(localized: "Leave at", comment: "Label under a transfer's time when you drive the evening before: when the last session ends")
        }
        return String(localized: "Leave by", comment: "Label under a drive's leave-by time")
    }

    @ViewBuilder private var inlineSummary: some View {
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
            .accessibilityElement(children: .combine)
        }
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

/// A drive's summary and its note: on one line when both fit (the note takes at least `minNote`), else the note under the
/// summary. `ViewThatFits` measures with the real width; the note field is rebuilt when the arrangement changes.
private struct SummaryAndNote<Summary: View, Note: View>: View {
    var minNote: CGFloat = 120
    @ViewBuilder var summary: Summary
    @ViewBuilder var note: Note

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                summary.fixedSize(horizontal: true, vertical: false)
                note.frame(minWidth: minNote, maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 2) {
                summary.fixedSize(horizontal: false, vertical: true)
                note
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Drive segments, light") { DriveSegmentsPreview().preferredColorScheme(.light) }
#Preview("Drive segments, dark") { DriveSegmentsPreview().preferredColorScheme(.dark) }

struct DriveSegmentsPreview: View {
    @State private var timing = TransferTiming.morning

    var body: some View {
        VStack(spacing: 24) {
            DriveSegmentRow(style: .inline, leaveBy: "14:35", summary: "3hr, 21min • 183mi", note: "Fuel in Kanab", onNote: { _ in })
                .background(IterColor.backgroundContent)
            DriveSegmentRow(style: .inline, leaveBy: "14:35", summary: "3hr, 21min • 183mi", isEstimate: true,
                            warning: "Drive doesn't fit: 25 min short", onNote: { _ in })
                .background(IterColor.backgroundContent)
            DriveSegmentRow(style: .transfer(timing: timing, from: "Horseshoe Bend",
                                             overnight: "Overnight near Page, AZ", hotels: Coordinate(latitude: 36.9, longitude: -111.45)),
                            leaveBy: "03:56", summary: "2hr, 5min • 128mi", onNote: { _ in }, onTiming: { timing = $0 })
            DriveSegmentRow(style: .transfer(timing: .eveningBefore, from: "Horseshoe Bend",
                                             overnight: "Overnight near Page, AZ", hotels: Coordinate(latitude: 36.9, longitude: -111.45)),
                            leaveBy: "19:40", summary: "2hr, 5min • 128mi", note: "Dinner in Kanab on the way", onNote: { _ in })
        }
        .frame(width: 608)
        .padding(16)
        .background(IterColor.backgroundWindow)
    }
}
