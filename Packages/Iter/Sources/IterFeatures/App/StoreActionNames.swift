import Foundation
import IterStore

/// The undo and redo menu names, in English ("Undo Rename Trip"). The shell may replace `LibraryStore.actionName` with
/// localized ones; every composition starts with these so no undo step is unnamed.
public enum StoreActionNames {
    public static func english(_ action: StoreAction) -> String {
        switch action {
        case .createTrip: "New Trip"
        case .createTripFromTemplate: "New Trip from Template"
        case .renameTrip: "Rename Trip"
        case .setTripNotes: "Edit Trip Notes"
        case .setDates: "Change Dates"
        case .duplicateTrip: "Duplicate Trip"
        case .deleteTrip: "Delete Trip"
        case .importTrip: "Import"
        case .addStop: "Add Stop"
        case .removeStop: "Remove Stop"
        case .moveStop: "Move Stop"
        case .reorderStops: "Reorder Stops"
        case .setSession: "Change Light Window"
        case .setNote: "Edit Stop Note"
        case .setBuffer: "Change Set-Up Time"
        case .setDriveNote: "Edit Drive Note"
        case .setTransferTiming: "Change Transfer Timing"
        case .setDwell: "Change Time at Stop"
        case .setStopKind: "Change Stop Type"
        case .setFixedArrival: "Change Arrival Time"
        case .setStartPlace: "Set Starting Point"
        case .setSaved: "Save Place"
        case .createUserSpot: "Add Place"
        case .updatePlace: "Edit Place"
        case .moveSpot: "Move Place"
        case .deletePlace: "Delete Place"
        case .setPlaceProvenance: "Update Place Sources"
        case .createFolder: "New Folder"
        case .newFolderWithSelection: "New Folder with Selection"
        case .renameFolder: "Rename Folder"
        case .deleteFolder: "Delete Folder"
        case .moveFolder: "Move Folder"
        case .moveTrips: "Move Trips"
        case .movePlaces: "Move Places"
        case .pinTrip: "Pin Trip"
        case .unpinTrip: "Unpin Trip"
        case .pinFolder: "Pin Folder"
        case .unpinFolder: "Unpin Folder"
        case .pinPlace: "Pin Place"
        case .unpinPlace: "Unpin Place"
        }
    }
}
