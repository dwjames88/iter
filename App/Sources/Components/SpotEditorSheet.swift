import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// Create a spot from a dropped pin, or edit one of your own (flows/04, critique C44 to C46).
/// The pin stays fixed at the centre of a small map; drag the map to move it. Name, locality and time zone are
/// looked up for the pin, but anything you type is yours: a lookup never overwrites it.
struct SpotEditorSheet: View {
    enum Mode {
        case create(Coordinate)
        case edit(PlaceRecord)
    }

    let mode: Mode
    /// Called with the saved record (new or edited).
    var onSave: (PlaceRecord) -> Void = { _ in }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var draft: SpotDraft
    @State private var lookup: LookupState
    @State private var nameTouched = false
    @State private var localityTouched = false
    @State private var showProblems = false
    private let original: Coordinate

    enum LookupState: Equatable { case idle, looking, found, failed }

    init(mode: Mode, onSave: @escaping (PlaceRecord) -> Void = { _ in }, lookupState: LookupState? = nil) {
        self.mode = mode
        self.onSave = onSave
        let start: SpotDraft
        switch mode {
        case .create(let coordinate):
            start = SpotDraft(coordinate: coordinate)
        case .edit(let record):
            var d = SpotDraft(coordinate: record.coordinate, timeZone: TimeZone(identifier: record.timeZoneIdentifier) ?? .current,
                              timeZoneIsFallback: false)
            d.name = record.name
            d.locality = record.locality
            d.notes = record.notes
            d.category = record.category
            d.bestLight = Set(record.bestLight)
            d.walkInText = record.walkInMinutes.map(String.init) ?? ""
            start = d
        }
        _draft = State(initialValue: start)
        original = start.coordinate
        if let lookupState { _lookup = State(initialValue: lookupState) }
        else if case .create = mode { _lookup = State(initialValue: .looking) }
        else { _lookup = State(initialValue: .idle) }
    }

    private var isCreate: Bool { if case .create = mode { true } else { false } }

    var body: some View {
        VStack(spacing: 0) {
            Text(isCreate ? "New Spot" : "Edit Spot", comment: "Spot editor title")
                .font(IterFont.titleSection)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.horizontal, .top], IterSpace.sheet)
                .padding(.bottom, IterSpace.sm)
            Form {
                SpotPinMapSection(coordinate: $draft.coordinate, original: original, label: draft.trimmedName)
                CoordinateFieldsSection(coordinate: $draft.coordinate)
                Section {
                    nameField
                    TextField(text: localityBinding, prompt: Text("Park, town or region", comment: "Locality placeholder")) {
                        Text("Place", comment: "Spot editor field")
                    }
                    Picker(selection: $draft.category) {
                        ForEach(SpotCategory.allCases) { (category: SpotCategory) in
                            Label(LightText.name(category), systemImage: LightText.symbol(category)).tag(category)
                        }
                    } label: { Text("Category", comment: "Spot editor field: single choice") }
                    timeZoneRow
                }
                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), alignment: .leading, spacing: IterSpace.sm) {
                        ForEach(BestLight.allCases) { (light: BestLight) in
                            Toggle(LightText.name(light), isOn: bestLightBinding(light)).checkboxToggleStyle()
                        }
                    }
                } header: {
                    Text("Best light (choose any)", comment: "Spot editor section: multiple choice")
                } footer: {
                    Text("With none chosen, light is shown for sunset.", comment: "Spot editor best light footer")
                }
                Section {
                    walkInField
                    TextField(text: $draft.notes, prompt: Text("Access, gear, crowds, permits", comment: "Notes placeholder"), axis: .vertical) {
                        Text("Notes", comment: "Spot editor field")
                    }
                    .lineLimit(3...6)
                }
            }
            .formStyle(.grouped)
            Divider()
            buttons
        }
        .frame(width: IterSize.listMax, height: IterSize.windowMinHeight + IterSize.listMin / 2)
        .tint(nil)
        .task(id: draft.coordinate) { await lookUp() }
    }

    // MARK: Fields

    private var nameBinding: Binding<String> {
        Binding(get: { draft.name }, set: { draft.name = $0; nameTouched = true })
    }

    private var localityBinding: Binding<String> {
        Binding(get: { draft.locality }, set: { draft.locality = $0; localityTouched = true })
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: IterSpace.xs) {
            HStack {
                TextField(text: nameBinding, prompt: Text("Name this spot", comment: "Name placeholder")) {
                    Text("Name", comment: "Spot editor field")
                }
                if lookup == .looking, draft.trimmedName.isEmpty {
                    ProgressView().controlSize(.small)
                }
            }
            if lookup == .looking, draft.trimmedName.isEmpty {
                Text("Looking up this place…", comment: "Spot editor lookup progress")
                    .font(IterFont.caption).foregroundStyle(IterColor.textSecondary)
            } else if showProblems || nameTouched, draft.problems.contains(.nameRequired) {
                problem(String(localized: "Name this spot to save it.", comment: "Validation: name required"))
            }
        }
    }

    private var walkInField: some View {
        VStack(alignment: .leading, spacing: IterSpace.xs) {
            TextField(text: $draft.walkInText, prompt: Text("Optional", comment: "Walk-in placeholder")) {
                Text("Walk-in (minutes)", comment: "Spot editor field: minutes from parking")
            }
            if draft.problems.contains(.walkInInvalid) {
                problem(String(localized: "Enter whole minutes from 0 to \(SpotDraft.maximumWalkInMinutes), or leave it empty if you don't know.",
                               comment: "Validation: walk-in minutes"))
            }
        }
    }

    private var timeZoneRow: some View {
        let zone = TimeZone(identifier: draft.timeZoneIdentifier) ?? .current
        return LabeledContent {
            VStack(alignment: .trailing, spacing: 0) {
                Text(zone.localizedName(for: .generic, locale: .current) ?? zone.identifier)
                if draft.timeZoneIsFallback {
                    Label(lookup == .looking
                         ? String(localized: "Estimated from the map position until the lookup finishes.", comment: "Time zone fallback while looking up")
                         : String(localized: "Couldn't look up this place's time zone, so it's estimated from the map position.", comment: "Time zone fallback after a failed lookup"),
                          systemImage: "exclamationmark.triangle")
                        .font(IterFont.caption)
                        .foregroundStyle(IterColor.warning)
                        .multilineTextAlignment(.trailing)
                }
            }
        } label: { Text("Time zone", comment: "Spot editor field") }
    }

    private func problem(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(IterFont.caption)
            .foregroundStyle(IterColor.danger)
            .accessibilityLabel(text)
    }

    private func bestLightBinding(_ light: BestLight) -> Binding<Bool> {
        Binding(get: { draft.bestLight.contains(light) },
                set: { if $0 { draft.bestLight.insert(light) } else { draft.bestLight.remove(light) } })
    }

    // MARK: Buttons

    private var buttons: some View {
        HStack {
            Spacer()
            Button(role: .cancel) { dismiss() } label: { Text("Cancel", comment: "Button") }
                .keyboardShortcut(.cancelAction)
            Button { save() } label: { Text(isCreate ? "Add Spot" : "Save", comment: "Button: save the spot editor") }
                .keyboardShortcut(.defaultAction)
        }
        .padding(IterSpace.sheet)
    }

    // MARK: Lookup

    private func lookUp() async {
        if case .edit = mode, draft.coordinate == original { return }
        lookup = .looking
        do {
            try await Task.sleep(for: .milliseconds(300))
            let result = try await model.geocoder.reverseGeocode(draft.coordinate)
            guard !Task.isCancelled else { return }
            draft.apply(lookup: result, fillName: isCreate && !nameTouched, fillLocality: !localityTouched)
            lookup = .found
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            lookup = .failed
        }
    }

    // MARK: Save

    private func save() {
        guard draft.isValid, let walkIn = draft.walkInMinutes else { showProblems = true; return }
        switch mode {
        case .create(let coordinate):
            let record = model.store.createUserSpot(name: draft.trimmedName, locality: draft.trimmedLocality,
                                                    coordinate: draft.coordinate == original ? coordinate : draft.coordinate,
                                                    timeZoneIdentifier: draft.timeZoneIdentifier, category: draft.category,
                                                    bestLight: draft.orderedBestLight, notes: draft.notes, walkInMinutes: walkIn)
            model.spotSaved(record.spot)
            onSave(record)
        case .edit(let record):
            model.store.updatePlace(record, name: draft.trimmedName, locality: draft.trimmedLocality, coordinate: draft.coordinate,
                                    timeZoneIdentifier: draft.timeZoneIdentifier, category: draft.category,
                                    bestLight: draft.orderedBestLight, notes: draft.notes, walkInMinutes: walkIn)
            model.spotSaved(record.spot)
            onSave(record)
        }
        dismiss()
    }
}
