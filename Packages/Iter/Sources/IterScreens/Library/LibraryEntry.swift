import SwiftUI
import IterFeatures
import IterModel

/// All Trips (or one trip folder when `folderID` is set): hero, pinned, folders, the rest; empty state with templates.
/// Reads `AppNavigator` from the environment. Drag a card onto a folder header to file it.
public struct AllTripsScreen: View {
    let library: LibraryModel
    let folderID: UUID?
    public init(library: LibraryModel, folderID: UUID? = nil) { self.library = library; self.folderID = folderID }
    public var body: some View { AllTripsContent(library: library, folderID: folderID) }
}

/// Saved Places (or one place folder): folders at the top, places over a full-bleed map. Drag and drop, pins, edit (⌘E), undo.
public struct SavedPlacesScreen: View {
    let library: LibraryModel
    let folderID: UUID?
    public init(library: LibraryModel, folderID: UUID? = nil) { self.library = library; self.folderID = folderID }
    public var body: some View { SavedPlacesContent(library: library, folderID: folderID) }
}

/// New Trip sheet.
public struct NewTripSheet: View {
    let library: LibraryModel
    let templateID: String?
    let firstPlace: UUID?
    let onCreated: (UUID) -> Void
    public init(library: LibraryModel, templateID: String?, firstPlace: UUID?, onCreated: @escaping (UUID) -> Void) {
        self.library = library; self.templateID = templateID; self.firstPlace = firstPlace; self.onCreated = onCreated
    }
    public var body: some View { NewTripForm(library: library, templateID: templateID, firstPlace: firstPlace, onCreated: onCreated) }
}

/// Change Dates sheet.
public struct ChangeDatesSheet: View {
    let model: BuildModel
    public init(model: BuildModel) { self.model = model }
    public var body: some View { ChangeDatesForm(model: model) }
}

/// The place editor (⌘E).
public struct PlaceEditorSheet: View {
    let library: LibraryModel
    let placeID: UUID
    public init(library: LibraryModel, placeID: UUID) { self.library = library; self.placeID = placeID }
    public var body: some View { PlaceEditorForm(library: library, placeID: placeID) }
}
