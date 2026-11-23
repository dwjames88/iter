import SwiftUI
import IterFeatures
import IterModel
import IterUI

/// A drive row: the system `DriveSegmentRow` (inline between two stops, or the transfer card between two days) with the
/// drive's state under it: what the time rests on, or that it is loading, failed and retrying, or has no road route.
struct DriveRowView: View {
    enum Style {
        case inline
        case transfer(BuildTransfer)
    }

    let drive: BuildDrive
    let style: Style
    let model: BuildModel

    var body: some View {
        DebouncedText(value: drive.note, save: { model.setDriveNote(drive.toStopID, to: $0) }) { note, commit in
            VStack(alignment: .leading, spacing: 0) {
                row(note: note, commit: commit)
                if let status = DriveStatus(drive), showsStatus(status) { statusLine(status) }
            }
        }
        .id(rowID)
    }

    private var rowID: String {
        if case .transfer(let transfer) = style { return "transfer-\(transfer.day)" }
        return "drive-\(drive.toStopID)"
    }

    @ViewBuilder private func row(note: Binding<String>, commit: @escaping () -> Void) -> some View {
        let value = drive.seconds.map { DriveSegmentRow.Drive(seconds: $0, meters: drive.meters ?? 0, isEstimate: drive.isEstimate) }
        let shortBy: TimeInterval? = {
            if case .driveDoesNotFit(let seconds) = drive.issue { return seconds }
            return nil
        }()
        switch style {
        case .inline:
            DriveSegmentRow(style: .inline, leaveBy: drive.leaveBy, drive: value, shortBy: shortBy, note: note, onNoteCommit: commit,
                            zone: drive.leaveZone)
        case .transfer(let transfer):
            DriveSegmentRow(style: .transfer(timing: Binding(get: { transfer.timing },
                                                             set: { model.setTransferTiming(intoDay: transfer.day, to: $0) }),
                                             from: drive.fromName,
                                             overnight: transfer.overnight.map {
                                                 DriveSegmentRow.Overnight(place: $0.place, coordinate: $0.coordinate)
                                             }),
                            leaveBy: drive.leaveBy, drive: value, shortBy: shortBy, note: note, onNoteCommit: commit,
                            zone: drive.leaveZone)
        }
    }

    private func statusLine(_ status: DriveStatus) -> some View {
        HStack(spacing: 6) {
            switch status.symbol {
            case .spinner: ProgressView().controlSize(.mini)
            case .symbol(let name): Image(systemName: name).accessibilityHidden(true)
            case .none: EmptyView()
            }
            Text(status.text)
        }
        .font(BuilderType.caption)
        .foregroundStyle(status.isWarning ? AnyShapeStyle(IterColor.warning) : AnyShapeStyle(IterColor.textTertiary))
        .padding(.leading, leading)
        .padding(.top, isTransfer ? 4 : -6)
        .padding(.bottom, 6)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var isTransfer: Bool { if case .transfer = style { true } else { false } }

    /// A transfer card says only what is wrong; the basis label belongs to the inline rows.
    private func showsStatus(_ status: DriveStatus) -> Bool { !isTransfer || status.isWarning || status.symbol == .spinner }

    /// Under the drive's summary: the row's side padding, the time column, the badge and the gaps.
    private var leading: CGFloat {
        if case .transfer = style { return 24 + 12 + 45 + 8 + 20 + 8 }
        return 24 + 12 + 45 + 8 + 20 + 8
    }
}

/// The words under a drive. Pure, so the states are testable without drawing.
struct DriveStatus: Equatable {
    enum Symbol: Equatable { case none, spinner, symbol(String) }

    var text: String
    var symbol: Symbol
    var isWarning: Bool

    /// nil when there is nothing to add (an estimate already says so on the row).
    init?(_ drive: BuildDrive, locale: Locale = .current) {
        switch drive.state {
        case .loading:
            text = String(localized: "Looking up the drive…", comment: "A drive time is being fetched; the row shows an estimate meanwhile")
            symbol = .spinner
            isWarning = false
        case .failed(let retryAt):
            let time = TimeText.time(retryAt, in: drive.leaveZone, locale: locale)
            text = String(localized: "Couldn't get the drive time. Trying again at \(time)", comment: "A drive lookup failed and will be retried at a time")
            symbol = .symbol("exclamationmark.arrow.circlepath")
            isWarning = true
        case .noRoute:
            text = String(localized: "No road route found. Showing a straight-line estimate", comment: "Maps has no road route between two stops")
            symbol = .symbol("exclamationmark.triangle.fill")
            isWarning = true
        case .ready:
            switch drive.basis {
            case .trafficAware:
                text = String(localized: "With traffic", comment: "A drive time that includes expected traffic")
                symbol = .none
            case .typical:
                text = String(localized: "Typical", comment: "A drive time without traffic for a set departure")
                symbol = .none
            case .estimate, nil:
                return nil
            }
            isWarning = false
        }
    }
}
