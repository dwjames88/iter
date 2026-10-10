import SwiftUI
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import IterCore
import IterDesign
import IterFeatures

/// Latitude and Longitude fields (decimal degrees) with inline errors and a Paste Coordinates button, as a `Form` section for
/// Mac and iOS. Edits `coordinate` only while both fields are valid; a coordinate set from outside (a drag, the map)
/// rewrites the text. Reused by the spot editor and the place card's details.
struct CoordinateFieldsSection: View {
    @Binding var coordinate: Coordinate
    /// False: every valid edit goes to `coordinate` at once (the spot editor). True: typing waits for Return, leaving the
    /// field or Paste Coordinates, so a saved place is not moved, re-scored and put on the undo stack on every keystroke.
    var commitsOnSubmit = false
    @State private var fields: CoordinateFields
    private enum Field { case latitude, longitude }
    @FocusState private var focused: Field?

    init(coordinate: Binding<Coordinate>, commitsOnSubmit: Bool = false) {
        _coordinate = coordinate
        self.commitsOnSubmit = commitsOnSubmit
        _fields = State(initialValue: CoordinateFields(coordinate.wrappedValue))
    }

    var body: some View {
        Section {
            field(String(localized: "Latitude", comment: "Spot editor field: decimal degrees"), text: $fields.latitudeText,
                  problem: fields.latitudeProblem, focus: .latitude)
            field(String(localized: "Longitude", comment: "Spot editor field: decimal degrees"), text: $fields.longitudeText,
                  problem: fields.longitudeProblem, focus: .longitude)
            HStack {
                Button { pasteCoordinates() } label: {
                    Label(String(localized: "Paste Coordinates", comment: "Button: read a latitude and longitude from the clipboard"),
                          systemImage: "doc.on.clipboard")
                }
                .help(String(localized: "Paste a latitude and longitude, or an Apple Maps link", comment: "Tooltip"))
                if fields.pasteFailed {
                    Text("No coordinates found on the clipboard.", comment: "Spot editor: Paste Coordinates found nothing")
                        .font(IterFont.caption).foregroundStyle(IterColor.danger)
                }
            }
        }
        .onChange(of: fields) { _, _ in if !commitsOnSubmit { commit() } }
        .onChange(of: focused) { old, new in if commitsOnSubmit, old != nil, new != old { commit() } }
        .onChange(of: coordinate) { _, new in
            if fields.coordinate != new { fields.set(new) }
        }
    }

    private func commit() {
        if let c = fields.coordinate, c != coordinate { coordinate = c }
    }

    private func field(_ title: String, text: Binding<String>, problem: String?, focus: Field) -> some View {
        VStack(alignment: .leading, spacing: IterSpace.xs) {
            LabeledContent {
                TextField(text: text, prompt: Text(verbatim: "0.0")) { Text(title) }
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .focused($focused, equals: focus)
                    .onSubmit { commit() }
                    #if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    #endif
                    .monospacedDigit()
            } label: { Text(title) }
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(IterFont.caption)
                    .foregroundStyle(IterColor.danger)
            }
        }
    }

    private func pasteCoordinates() {
        #if canImport(AppKit)
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        #else
        let text = UIPasteboard.general.string ?? ""
        #endif
        fields.paste(text)
        commit()
    }
}
