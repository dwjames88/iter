import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// What Edit > Edit Location (Command-E) runs: the screen showing a saved or own place publishes it while that place is
/// the subject (the place card, the spot page, a selected row in Locations).
struct EditLocationAction {
    let run: () -> Void
}

extension FocusedValues {
    @Entry var editLocation: EditLocationAction?
}

/// Edits a saved or own place: a system Form in a system sheet with Cancel and Done in the toolbar. Done saves in one
/// undoable step ("Undo Edit Location"); Cancel throws the draft away. Fields that are a catalogue spot's facts are shown
/// read-only with the reason beside them; nothing is silently ignored.
struct PlaceEditorSheet: View {
    let record: PlaceRecord

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.renderMode) private var renderMode
    @State private var draft: PlaceEditDraft
    @State private var nameTouched = false

    init(record: PlaceRecord) {
        self.record = record
        _draft = State(initialValue: PlaceEditDraft(record))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledField(text: nameBinding, prompt: Text("Name this location", comment: "Name placeholder")) { Text("Name", comment: "Place editor field") }
                    if nameTouched, draft.problems.contains(.nameRequired) {
                        problem(String(localized: "Name this location to save it.", comment: "Validation: name required"))
                    }
                    LabeledField(text: $draft.locality, prompt: Text("Park, town or region", comment: "Locality placeholder")) { Text("Place", comment: "Place editor field") }
                }
                if draft.editsFacts {
                    CoordinateFieldsSection(coordinate: $draft.coordinate)
                    factsSections
                } else {
                    catalogueSection
                }
                Section {
                    TextField(text: $draft.notes, prompt: Text("Access, gear, crowds, permits", comment: "Notes placeholder"), axis: .vertical) {
                        Text("Notes", comment: "Place editor field")
                    }
                    .lineLimit(3...8)
                } header: {
                    Text("Notes", comment: "Place editor section")
                }
                Section {
                    Picker(selection: $draft.folderID) {
                        Text("None", comment: "Place editor: not in a folder").tag(UUID?.none)
                        ForEach(model.store.folders(kind: .locations), id: \.id) { folder in
                            Text(folder.name).tag(UUID?.some(folder.id))
                        }
                    } label: { Text("Folder", comment: "Place editor field") }
                    Toggle(isOn: $draft.isPinned) { Text("Pin to Sidebar", comment: "Place editor field") }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text("Edit Location", comment: "Place editor title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Text("Cancel", comment: "Button") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Text("Done", comment: "Button: save the place editor") }
                        .disabled(!draft.isValid)
                }
            }
        }
        #if os(macOS)
        .frame(width: IterSize.listMax, height: IterSize.windowMinHeight + IterSize.listMin / 2)
        #endif
        .task(id: draft.coordinate) { await refreshTimeZone() }
    }

    // MARK: Sections

    @ViewBuilder private var factsSections: some View {
        Section {
            Picker(selection: $draft.category) {
                ForEach(SpotCategory.allCases) { (category: SpotCategory) in
                    Label(LightText.name(category), systemImage: LightText.symbol(category)).tag(category)
                }
            } label: { Text("Category", comment: "Place editor field: single choice") }
            LabeledField(text: $draft.walkInText, prompt: Text("Optional", comment: "Walk-in placeholder")) { Text("Walk-in (minutes)", comment: "Place editor field: minutes from parking") }
            #if os(iOS)
            .keyboardType(.numberPad)
            #endif
            if draft.problems.contains(.walkInInvalid) {
                problem(String(localized: "Enter whole minutes from 0 to \(SpotDraft.maximumWalkInMinutes), or leave it empty if you don't know.",
                               comment: "Validation: walk-in minutes"))
            }
            LabeledField(text: $draft.tagsText, prompt: Text("Separate with commas", comment: "Tags placeholder")) { Text("Tags", comment: "Place editor field") }
        }
        Section {
            ForEach(BestLight.allCases) { (light: BestLight) in
                Toggle(LightText.name(light), isOn: bestLightBinding(light))
            }
        } header: {
            Text("Best light (choose any)", comment: "Place editor section: multiple choice")
        } footer: {
            Text("With none chosen, light is shown for sunset.", comment: "Place editor best light footer")
        }
    }

    /// A curated spot's facts: shown, not editable, with the reason.
    private var catalogueSection: some View {
        Section {
            LabeledContent { Text(coordinateText).monospacedDigit() } label: { Text("Coordinates", comment: "Place editor field") }
            LabeledContent {
                Text(LightText.name(record.category))
            } label: { Text("Category", comment: "Place editor field") }
            LabeledContent {
                Text(record.bestLight.isEmpty ? LightText.name(BestLight.sunset) : record.bestLight.map { LightText.name($0) }.formatted(.list(type: .and)))
            } label: { Text("Best light", comment: "Place editor field") }
            if let minutes = record.walkInMinutes {
                LabeledContent {
                    Text("\(minutes) min", comment: "Place editor: walk-in minutes value")
                } label: { Text("Walk-in", comment: "Place editor field") }
            }
        } header: {
            Text("From the Catalogue", comment: "Place editor section: facts a curated spot keeps")
        } footer: {
            Text("This spot comes from Iter's catalogue, so its position, category and light are fixed. Your name, place, notes, folder and pin are saved with your copy.",
                 comment: "Place editor footer: why a curated spot's facts are read-only")
        }
    }

    // MARK: Helpers

    private var coordinateText: String {
        let c = record.coordinate
        return "\(c.latitude.formatted(.number.precision(.fractionLength(4)))), \(c.longitude.formatted(.number.precision(.fractionLength(4))))"
    }

    private var nameBinding: Binding<String> {
        Binding(get: { draft.name }, set: { draft.name = $0; nameTouched = true })
    }

    private func bestLightBinding(_ light: BestLight) -> Binding<Bool> {
        Binding(get: { draft.bestLight.contains(light) },
                set: { if $0 { draft.bestLight.insert(light) } else { draft.bestLight.remove(light) } })
    }

    private func problem(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(IterFont.caption)
            .foregroundStyle(IterColor.danger)
            .accessibilityLabel(text)
    }

    /// After the coordinate moves, the place's time zone follows it (the lookup is the truth; the estimate stands in).
    private func refreshTimeZone() async {
        guard draft.movesPlace, renderMode != .snapshot else { return }
        do {
            try await Task.sleep(for: .milliseconds(400))
            let result = try await model.geocoder.reverseGeocode(draft.coordinate)
            guard !Task.isCancelled else { return }
            draft.applyTimeZone(from: result)
        } catch {
            return
        }
    }

    private func save() {
        guard draft.isValid else { nameTouched = true; return }
        model.applyEdit(draft, to: record)
        dismiss()
    }
}

/// A text field with its label beside it (a bare TextField shows only its prompt on iOS).
struct LabeledField<Label: View>: View {
    @Binding var text: String
    let prompt: Text
    @ViewBuilder let label: Label

    var body: some View {
        LabeledContent {
            TextField(text: $text, prompt: prompt) { label }
                .labelsHidden()
                .multilineTextAlignment(.trailing)
        } label: { label }
    }
}
