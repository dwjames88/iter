import SwiftUI
import IterCore
import IterDesign
import IterFeatures

// Pieces of the Trip Builder's plan that the Mac list and the iPhone/iPad list both draw.

/// Feeds `DriveSegmentRow` from a drive of the plan.
struct DriveRowAdapter: View {
    enum Style { case inline, transfer(OvernightBoundary?) }

    let drive: TripDriveItem
    let style: Style
    let builder: TripBuilderModel
    /// The day of the stop the drive arrives at.
    let day: Int

    var body: some View {
        let leaveBy = drive.leaveBy.map { TimeText.time($0, in: drive.leaveZone) }
        let summary = drive.leg.map(ConnectorText.driveLine)
        let warning = drive.shortBySeconds.map { ScheduleText.driveDoesNotFit(shortBy: $0) }
        let onNote: (String) -> Void = { [builder, id = drive.toStopID] in builder.setDriveNote(id, to: $0) }
        switch style {
        case .inline:
            DriveSegmentRow(style: .inline, leaveBy: leaveBy, summary: summary, isEstimate: drive.isEstimate, warning: warning,
                            note: drive.note, onNote: onNote)
        case .transfer(let overnight):
            DriveSegmentRow(style: .transfer(timing: drive.transferTiming ?? .morning, from: drive.fromName,
                                             overnight: overnight.map { ConnectorText.overnightNear($0.place) },
                                             hotels: overnight?.coordinate),
                            leaveBy: leaveBy, summary: summary, isEstimate: drive.isEstimate, warning: warning,
                            note: drive.note, onNote: onNote,
                            onTiming: { [builder, day] in builder.setTransferTiming(intoDay: day, to: $0) })
        }
    }
}


extension TripMetaItem {
    /// The header card's facts for a trip: its dates (a button that changes them), its size and its driving total.
    @MainActor
    static func items(plan: TripPlan, builder: TripBuilderModel, changeDates: @escaping () -> Void) -> [TripMetaItem] {
        var items = [
            TripMetaItem(symbol: "calendar", text: TimeText.tripDates(from: plan.startDay, to: plan.day(plan.dayCount - 1)),
                         help: Text("Change Dates…", comment: "Tooltip"), action: changeDates),
            TripMetaItem(symbol: "point.topleft.filled.down.to.point.bottomright.curvepath",
                         text: TimeText.tripSize(days: plan.dayCount, stops: plan.stops.count)),
        ]
        if builder.totalDriveSeconds >= 60 {
            let base = String(localized: "\(TimeText.distance(builder.totalDriveMeters)) • \(TimeText.duration(builder.totalDriveSeconds))",
                              comment: "Trip total driving distance and time, e.g. 490 mi • 9 h 34 min")
            let text = builder.hasEstimatedDrive
                ? String(localized: "\(base) (estimated)", comment: "Trip driving total that includes estimated drives") : base
            items.append(TripMetaItem(symbol: "car.fill", text: text))
        }
        return items
    }
}
