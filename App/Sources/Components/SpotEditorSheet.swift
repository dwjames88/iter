import SwiftUI
import IterCore
import IterData
import IterFeatures

/// Create a spot from a dropped pin, or edit one of your own. (Contract stub: the Saved/Scout agent implements it.)
struct SpotEditorSheet: View {
    enum Mode {
        case create(Coordinate)
        case edit(PlaceRecord)
    }

    let mode: Mode
    /// Called with the saved record (new or edited).
    var onSave: (PlaceRecord) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Text(verbatim: "Spot editor")
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Cancel", comment: "Button")) { dismiss() } }
            }
    }
}
