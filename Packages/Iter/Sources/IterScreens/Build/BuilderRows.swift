import SwiftUI
import IterFeatures
import IterModel
import IterUI

/// One plan row, drawn from its value alone (`==` compares the row and whether it is the selected stop).
struct BuilderRowView: View, Equatable {
    let row: BuildRow
    let isSelected: Bool
    let loadingScores: Bool
    /// A drive row sits above this stop and draws the drop line for both.
    var hasDriveAbove = false
    let model: BuildModel
    let drops: StopDropCoordinator

    nonisolated static func == (lhs: BuilderRowView, rhs: BuilderRowView) -> Bool {
        lhs.row == rhs.row && lhs.isSelected == rhs.isSelected && lhs.loadingScores == rhs.loadingScores
            && lhs.hasDriveAbove == rhs.hasDriveAbove
    }

    var body: some View {
        switch row.kind {
        case .dayHeader(let header):
            DayCardHeader(dayName: TripBuilderText.dayName(index: header.index),
                          date: TripBuilderText.dayCardDate(header.date),
                          totals: Self.totals(header),
                          sunrise: header.sunrise.map { TripBuilderText.sunTime(.goldenMorning, at: $0, in: header.timeZone) },
                          sunset: header.sunset.map { TripBuilderText.sunTime(.goldenEvening, at: $0, in: header.timeZone) })
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 18)
                .onTapGesture { model.selectDay(header.index) }
                .stopDrop(on: .endOfDay(row.day), coordinator: drops)
        case .suggestion(let suggestion):
            SuggestionBanner(suggestion: suggestion, model: model)
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
        case .conflicts(let count):
            ConflictLine(count: count)
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
        case .stop(let stop):
            StopRowView(stop: stop, day: row.day, isSelected: isSelected, loadingScores: loadingScores, model: model)
                .padding(.horizontal, BuilderMetrics.bodyInset)
                .padding(.vertical, 2)
                .onTapGesture { model.selectStop(stop.id) }
                .draggable(StopDragItem(tripID: model.tripID, stopID: stop.id))
                .stopDrop(on: .before(stop.id), line: !hasDriveAbove, coordinator: drops)
        case .drive(let drive):
            DriveRowView(drive: drive, style: .inline, model: model)
                .padding(.horizontal, BuilderMetrics.bodyInset)
                .padding(.vertical, 2)
                .stopDrop(on: .before(drive.toStopID), coordinator: drops)
        case .footer(let day, let overnight):
            DayFooter(model: model, day: day, overnight: overnight)
                .stopDrop(on: .endOfDay(day), coordinator: drops)
        case .transfer(let transfer):
            TransferRow(transfer: transfer, model: model)
        }
    }

    static func totals(_ header: BuildDayHeader) -> String {
        var text = TripBuilderText.dayTotals(stops: header.stopCount, drivingSeconds: header.drivingSeconds)
        if header.hasEstimatedDrive, header.drivingSeconds >= 60 {
            text += " " + String(localized: "(estimated)", comment: "Day card totals: some drive time is a straight-line estimate")
        }
        return text
    }
}

// MARK: - Banners

/// "Putting this day in light order clears 2 conflicts": calm, never automatic. The plan changes only when you press Apply.
struct SuggestionBanner: View {
    let suggestion: BuildSuggestion
    let model: BuildModel

    var body: some View {
        HStack(spacing: IterSpace.sm) {
            Image(systemName: "arrow.up.arrow.down").foregroundStyle(IterColor.textSecondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(suggestion.message).font(BuilderType.body).foregroundStyle(IterColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Puts the stops in the order their light arrives.", comment: "Light-order suggestion explanation")
                    .font(BuilderType.caption).foregroundStyle(IterColor.textSecondary)
            }
            Spacer(minLength: IterSpace.sm)
            Button { model.dismissSuggestion(day: suggestion.dayIndex) } label: { Text("Dismiss", comment: "Button") }
                .buttonStyle(.borderless)
            Button { model.applySuggestion(day: suggestion.dayIndex) } label: { Text("Apply", comment: "Button: apply the suggested order") }
                .buttonStyle(.bordered)
        }
        .controlSize(.small)
        .padding(IterSpace.sm)
        .background(IterColor.backgroundControl, in: RoundedRectangle(cornerRadius: IterRadius.control, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

/// "2 conflicts on this day", in the warning colour.
struct ConflictLine: View {
    let count: Int

    var body: some View {
        Label {
            Text("^[\(count) conflict](inflect: true) on this day", comment: "Day card: how many schedule conflicts the day has")
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(BuilderType.body)
        .foregroundStyle(IterColor.warning)
    }
}

// MARK: - Day foot

/// The foot of a day card: Add Stop (opens the add-stop popover) and, when this card ends the day you sleep after, the
/// overnight note with Find Hotels. The popover's state lives here, so opening it rebuilds this row and not the list.
struct DayFooter: View {
    let model: BuildModel
    let day: Int
    let overnight: BuildOvernight?
    @State private var isAdding = false

    var body: some View {
        HStack(spacing: 8) {
            AddStopButton { isAdding = true }
                .popover(isPresented: $isAdding, arrowEdge: .bottom) { AddStopPopover(model: model, day: day) }
            Spacer(minLength: 8)
            if let overnight {
                OvernightNote(place: overnight.place)
                FindHotelsButton(latitude: overnight.coordinate.latitude, longitude: overnight.coordinate.longitude)
            }
        }
        .padding(.horizontal, 12 + BuilderMetrics.bodyInset)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Transfer

/// The card between two days (or the first drive from the start place).
struct TransferRow: View {
    let transfer: BuildTransfer
    let model: BuildModel

    var body: some View {
        if let drive = transfer.drive {
            if transfer.canChooseTiming {
                DriveRowView(drive: drive, style: .transfer(transfer), model: model)
            } else {
                // The first drive has no night before it: no timing to choose.
                DriveRowView(drive: drive, style: .inline, model: model)
                    .background(IterColor.backgroundContent, in: RoundedRectangle(cornerRadius: BuilderMetrics.innerCorner, style: .continuous))
                    .padding(.horizontal, 24)
            }
        } else if let overnight = transfer.overnight {
            OvernightNote(place: overnight.place).padding(.horizontal, 24)
        }
    }
}
