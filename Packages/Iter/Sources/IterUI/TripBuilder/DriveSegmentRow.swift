import IterModel
import SwiftUI

/// A drive in the plan. `.inline` sits between two stops of a day, no card: the leave-by time, the blue car and the drive
/// time and distance. `.transfer` is the card between two days: the same, with a sentence about the move, where it starts
/// and, when there is one, the night's stay with a Find Hotels link. Figma part: drive segment row.
public struct DriveSegmentRow: View {
    /// A fetched or estimated drive.
    public struct Drive: Equatable, Sendable {
        public var seconds: TimeInterval
        public var meters: Double
        /// A straight-line estimate, not a road route.
        public var isEstimate: Bool

        public init(seconds: TimeInterval, meters: Double, isEstimate: Bool = false) {
            self.seconds = seconds
            self.meters = meters
            self.isEstimate = isEstimate
        }
    }

    /// The night's stay at the end of a transfer: where, and the coordinate the hotels search starts from.
    public struct Overnight: Equatable, Sendable {
        /// "Page, AZ"
        public var place: String
        public var coordinate: Coordinate?

        public init(place: String, coordinate: Coordinate? = nil) {
            self.place = place
            self.coordinate = coordinate
        }
    }

    public enum Style {
        case inline
        /// `timing`: the picker's value ("Drive to the next area the [Morning] before the shoot."); `from`: the stop the
        /// drive leaves; `overnight`: where you sleep, for "Overnight near Page, AZ" and the hotels search.
        case transfer(timing: Binding<TransferTiming>, from: String?, overnight: Overnight?)
    }

    public var style: Style
    /// When to leave; nil until the drive has a leave-by time.
    public var leaveBy: Date?
    /// nil until the drive has been fetched or estimated.
    public var drive: Drive?
    /// How far past the window's start the drive arrives; the warning "Drive doesn't fit: 25 min short". nil when it fits.
    public var shortBy: TimeInterval?
    /// The drive's note, edited in place when given.
    public var note: Binding<String>?
    public var onNoteCommit: () -> Void
    public var zone: TimeZone
    public var locale: Locale

    public init(style: Style, leaveBy: Date?, drive: Drive?, shortBy: TimeInterval? = nil, note: Binding<String>? = nil,
                onNoteCommit: @escaping () -> Void = {}, zone: TimeZone, locale: Locale = .current) {
        self.style = style
        self.leaveBy = leaveBy
        self.drive = drive
        self.shortBy = shortBy
        self.note = note
        self.onNoteCommit = onNoteCommit
        self.zone = zone
        self.locale = locale
    }

    public var body: some View {
        switch style {
        case .inline: inline
        case .transfer(let timing, let from, let overnight): transfer(timing, from, overnight)
        }
    }

    private var summary: String? {
        drive.map { TripBuilderText.driveLine(seconds: $0.seconds, meters: $0.meters, locale: locale) }
    }

    private var leaveByText: String? { leaveBy.map { TimeText.time($0, in: zone, locale: locale) } }

    private var warning: String? { shortBy.map { TripBuilderText.driveDoesntFit(shortBy: $0, locale: locale) } }

    // MARK: Inline

    private var inline: some View {
        HStack(alignment: .top, spacing: 8) {
            HStack(spacing: 8) {
                TimeLabelColumn(time: leaveByText, label: leaveLabel, minWidth: 45)
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

    private func transfer(_ timing: Binding<TransferTiming>, _ from: String?, _ overnight: Overnight?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            HStack(spacing: 8) {
                TimeLabelColumn(time: leaveByText, label: leaveLabel, minWidth: 45)
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
                        HStack(spacing: 8) { overnightParts(overnight) }
                        VStack(alignment: .leading, spacing: 4) { overnightParts(overnight) }
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
    private func headline(_ timing: Binding<TransferTiming>) -> some View {
        let prefix = Text("Drive to the next area the", bundle: .module, comment: "Transfer card sentence, before the timing picker")
        let suffix: Text? = timing.wrappedValue == .morning
            ? Text("before the shoot.", bundle: .module, comment: "Transfer card sentence, after the Morning timing picker") : nil
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

    private func timingPicker(_ timing: Binding<TransferTiming>) -> some View {
        Picker(selection: timing) {
            ForEach(TransferTiming.allCases, id: \.self) { Text(TripBuilderText.transferTimingName($0, locale: locale)).tag($0) }
        } label: {
            Text("Drive timing", bundle: .module, comment: "Accessibility label of the transfer card's timing picker")
        }
        .pickerStyle(.menu)
        .labelsHidden()
        #if os(macOS)
        .controlSize(.small)
        #endif
        .fixedSize()
        .help(Text("Drive on the morning of the shoot, or the evening before after the last session", bundle: .module,
                   comment: "Tooltip of the transfer card's timing picker"))
    }

    @ViewBuilder private var noteField: some View {
        if let note {
            NotePlaceholder(text: note, prompt: NotePlaceholder.driveNotePrompt, accessibilityName: NotePlaceholder.driveNoteName,
                            onCommit: onNoteCommit)
        }
    }

    @ViewBuilder private func summaryParts(_ summary: String, _ from: String?) -> some View {
        Text(summary).foregroundStyle(IterColor.textPrimary).monospacedDigit()
        if let from {
            Text("from \(from)", bundle: .module, comment: "Transfer card: where the drive starts, after its time and distance")
                .foregroundStyle(IterColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func overnightParts(_ overnight: Overnight) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "moon.zzz").font(BuilderType.bodyStrong).accessibilityHidden(true)
            Text(TripBuilderText.overnightNear(overnight.place, locale: locale)).font(BuilderType.bodyStrong)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let c = overnight.coordinate { FindHotelsButton(latitude: c.latitude, longitude: c.longitude) }
    }

    // MARK: Shared

    /// "Leave at" for a transfer driven the evening before (when the last session ends), else "Leave by".
    public var leaveLabel: String {
        if case .transfer(let timing, _, _) = style, timing.wrappedValue == .eveningBefore {
            return String(localized: "Leave at", bundle: .module, locale: locale, comment: "Label under a transfer's time when you drive the evening before: when the last session ends")
        }
        return String(localized: "Leave by", bundle: .module, locale: locale, comment: "Label under a drive's leave-by time")
    }

    @ViewBuilder private var inlineSummary: some View {
        if let summary {
            HStack(spacing: 4) {
                Text(summary).monospacedDigit()
                if drive?.isEstimate == true {
                    Text(verbatim: "•").accessibilityHidden(true)
                    Text("estimated", bundle: .module, comment: "Marks a drive time that is a straight-line estimate, not a road route")
                        .foregroundStyle(IterColor.textTertiary)
                        .help(Text("Drive time estimated", bundle: .module, comment: "Explains an estimated drive"))
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
