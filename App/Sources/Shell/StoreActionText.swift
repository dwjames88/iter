import Foundation
import IterData

/// Names shown in Edit > Undo …
enum StoreActionText {
    static func name(_ action: StoreAction) -> String {
        switch action {
        case .createTrip: String(localized: "New Trip", comment: "Undo action name")
        case .createTripFromTemplate: String(localized: "New Trip from Template", comment: "Undo action name")
        case .renameTrip: String(localized: "Rename Trip", comment: "Undo action name")
        case .setTripNotes: String(localized: "Trip Notes", comment: "Undo action name")
        case .setDates: String(localized: "Change Dates", comment: "Undo action name")
        case .duplicateTrip: String(localized: "Duplicate Trip", comment: "Undo action name")
        case .deleteTrip: String(localized: "Delete Trip", comment: "Undo action name")
        case .importTrip: String(localized: "Import Trip", comment: "Undo action name")
        case .addStop: String(localized: "Add Stop", comment: "Undo action name")
        case .removeStop: String(localized: "Remove Stop", comment: "Undo action name")
        case .moveStop: String(localized: "Move Stop", comment: "Undo action name")
        case .reorderStops: String(localized: "Reorder Stops", comment: "Undo action name")
        case .setSession: String(localized: "Change Session", comment: "Undo action name")
        case .setNote: String(localized: "Edit Note", comment: "Undo action name")
        case .setBuffer: String(localized: "Change Set-up Time", comment: "Undo action name")
        case .setSaved: String(localized: "Save Spot", comment: "Undo action name")
        case .createUserSpot: String(localized: "Add Spot", comment: "Undo action name")
        case .updatePlace: String(localized: "Edit Spot", comment: "Undo action name")
        case .deletePlace: String(localized: "Delete Spot", comment: "Undo action name")
        case .createFolder: String(localized: "New Folder", comment: "Undo action name")
        case .newFolderWithSelection: String(localized: "New Folder with Selection", comment: "Undo action name")
        case .renameFolder: String(localized: "Rename Folder", comment: "Undo action name")
        case .deleteFolder: String(localized: "Delete Folder", comment: "Undo action name")
        case .moveFolder: String(localized: "Move Folder", comment: "Undo action name")
        case .moveTrips: String(localized: "Move to Folder", comment: "Undo action name")
        case .movePlaces: String(localized: "Move to Folder", comment: "Undo action name")
        case .pinTrip: String(localized: "Pin Trip", comment: "Undo action name")
        case .unpinTrip: String(localized: "Unpin Trip", comment: "Undo action name")
        case .pinFolder: String(localized: "Pin Folder", comment: "Undo action name")
        case .unpinFolder: String(localized: "Unpin Folder", comment: "Undo action name")
        case .pinPlace: String(localized: "Pin Location", comment: "Undo action name")
        case .unpinPlace: String(localized: "Unpin Location", comment: "Undo action name")
        }
    }
}
