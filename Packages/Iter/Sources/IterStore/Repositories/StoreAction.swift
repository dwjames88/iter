import Foundation

/// Every mutation the store performs; each registers one undo group named by `LibraryStore.actionName`.
public enum StoreAction: String, Sendable, CaseIterable {
    case createTrip, createTripFromTemplate, renameTrip, setTripNotes, setDates, duplicateTrip, deleteTrip, importTrip
    case addStop, removeStop, moveStop, reorderStops, setSession, setNote, setBuffer, setDriveNote, setTransferTiming
    case setDwell, setStopKind, setFixedArrival, setStartPlace
    case setSaved, createUserSpot, updatePlace, moveSpot, deletePlace, setPlaceProvenance
    case createFolder, newFolderWithSelection, renameFolder, deleteFolder, moveFolder, moveTrips, movePlaces
    case pinTrip, unpinTrip, pinFolder, unpinFolder, pinPlace, unpinPlace
}
