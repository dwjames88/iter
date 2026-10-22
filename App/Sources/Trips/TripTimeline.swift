import SwiftUI
import IterCore
import IterDesign
import IterFeatures

// TODO(w6): iOS only (AppiOS/Sources/Trips/TripDayList.swift draws its own timeline with this); delete with it.
/// The colour of a stretch of the timeline's rail: coral when the drive fits, violet when it does not, neutral otherwise.
enum RailTone {
    case route, warning, neutral

    init(_ drive: TripDriveItem) {
        self = drive.leg == nil ? .neutral : (drive.fits ? .route : .warning)
    }

    var color: Color {
        switch self {
        case .route: IterColor.route.opacity(0.55)
        case .warning: IterColor.warning
        case .neutral: IterColor.separator
        }
    }
}
