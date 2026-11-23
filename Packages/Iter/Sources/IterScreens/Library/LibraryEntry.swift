import SwiftUI
import IterFeatures

// CONTRACT STUB (Phase 6 lead). The Build/Library screens worker replaces the bodies; the type names and inits stay.

/// All Trips (or one trip folder when `folderID` is set): hero, pinned, folders, the rest; empty state with templates.
public struct AllTripsScreen: View {
    let library: LibraryModel
    let folderID: UUID?
    public init(library: LibraryModel, folderID: UUID? = nil) { self.library = library; self.folderID = folderID }
    public var body: some View { Text("All Trips").frame(maxWidth: .infinity, maxHeight: .infinity) }
}

/// Saved Places (or one place folder): folders at the top, places, map. Drag and drop, pins, edit (⌘E), undo.
public struct SavedPlacesScreen: View {
    let library: LibraryModel
    let folderID: UUID?
    public init(library: LibraryModel, folderID: UUID? = nil) { self.library = library; self.folderID = folderID }
    public var body: some View { Text("Saved Places").frame(maxWidth: .infinity, maxHeight: .infinity) }
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
    public var body: some View { Text("New Trip") }
}

/// Change Dates sheet.
public struct ChangeDatesSheet: View {
    let model: BuildModel
    public init(model: BuildModel) { self.model = model }
    public var body: some View { Text("Change Dates") }
}

/// The place editor (⌘E).
public struct PlaceEditorSheet: View {
    let library: LibraryModel
    let placeID: UUID
    public init(library: LibraryModel, placeID: UUID) { self.library = library; self.placeID = placeID }
    public var body: some View { Text("Edit Place") }
}
