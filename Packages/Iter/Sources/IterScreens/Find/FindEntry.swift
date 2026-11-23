import SwiftUI
import IterFeatures

// CONTRACT STUB (Phase 6 lead). The Find screens worker replaces the body; the type names and inits stay.

/// The Find detail: the map with the floating card (search results, source statuses, place card). Mac layout.
public struct FindScreen: View {
    let model: FindModel
    public init(model: FindModel) { self.model = model }
    public var body: some View { Text("Find").frame(maxWidth: .infinity, maxHeight: .infinity) }
}
