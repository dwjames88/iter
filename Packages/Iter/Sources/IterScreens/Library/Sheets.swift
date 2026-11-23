import SwiftUI
import IterFeatures
import IterModel
import IterStore
import IterUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

private let utc = TimeZone(identifier: "UTC") ?? .gmt
let maximumTripDays = 14

private func daysLabel(_ days: Int) -> String { InflectedCount.days(days) }

private func utcDate(_ day: LocalDay) -> Date { day.noon(in: utc) }

// MARK: - New Trip

/// New Trip: a name, an optional template, a start date and a number of days. Sized to its content; `.tint(nil)` keeps the
/// accent off the neutral controls.
struct NewTripForm: View {
    let library: LibraryModel
    let firstPlace: UUID?
    let onCreated: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.libraryClock) private var clock
    @State private var name = ""
    @State private var templateID: String?
    @State private var startDay: LocalDay
    @State private var dayCount: Int

    init(library: LibraryModel, templateID: String?, firstPlace: UUID?, onCreated: @escaping (UUID) -> Void,
         tomorrow: LocalDay? = nil) {
        self.library = library
        self.firstPlace = firstPlace
        self.onCreated = onCreated
        _templateID = State(initialValue: templateID)
        _startDay = State(initialValue: tomorrow ?? LocalDay(Date().addingTimeInterval(86_400), in: utc))
        _dayCount = State(initialValue: templateID.flatMap(TripTemplates.template(id:))?.dayCount ?? 3)
    }

    private var template: TripTemplate? { templateID.flatMap(TripTemplates.template(id:)) }
    private var effectiveDays: Int { template?.dayCount ?? dayCount }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("New Trip", comment: "Sheet title").font(IterFont.titleSection)
                .padding([.horizontal, .top], IterSpace.sheet)
            Form {
                Section {
                    TextField(text: $name, prompt: Text(template?.defaultName ?? String(localized: "New Trip", comment: "Default trip name"))) {
                        Text("Name", comment: "New trip field")
                    }
                    Picker(selection: $templateID) {
                        Text("Empty trip", comment: "No template").tag(String?.none)
                        Divider()
                        ForEach(TripTemplates.all) { template in
                            Text("\(template.defaultName) · \(daysLabel(template.dayCount)), \(InflectedCount.stops(template.stops.count))")
                                .tag(String?.some(template.id))
                        }
                    } label: { Text("Start from", comment: "New trip field") }
                }
                Section {
                    DatePicker(selection: Binding(get: { utcDate(startDay) }, set: { startDay = LocalDay($0, in: utc) }),
                               displayedComponents: .date) { Text("Starts", comment: "New trip field") }
                        .datePickerStyle(.compact)
                        .environment(\.timeZone, utc)
                    Picker(selection: Binding(get: { effectiveDays }, set: { dayCount = $0 })) {
                        ForEach(1...maximumTripDays, id: \.self) { Text(daysLabel($0)).tag($0) }
                    } label: { Text("Days", comment: "New trip field") }
                    .disabled(template != nil)
                } footer: {
                    if template != nil {
                        Text("The template sets the number of days. You can add, move and remove stops afterwards.",
                             comment: "Explains the days picker is fixed by a template")
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(role: .cancel) { dismiss() } label: { Text("Cancel", comment: "Button") }
                    .keyboardShortcut(.cancelAction)
                Button { create() } label: { Text("Create", comment: "Button: create the trip") }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, IterSpace.sm)
            .padding([.horizontal, .bottom], IterSpace.sheet)
        }
        .frame(width: 480)
        .tint(nil)
    }

    private func create() {
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let id: UUID
        if let template, let made = library.createTrip(templateID: template.id, startDay: startDay) {
            id = made
            if !typed.isEmpty, typed != template.defaultName { library.renameTrip(id, to: typed) }
        } else {
            id = library.createTrip(name: typed.isEmpty ? String(localized: "New Trip", comment: "Default trip name") : typed,
                                    startDay: startDay, dayCount: effectiveDays)
        }
        if let firstPlace { library.addStop(placeID: firstPlace, toTrip: id, day: 0) }
        dismiss()
        onCreated(id)
    }
}

// MARK: - Change Dates

/// Change Dates: a new start and length. Shortening moves the stops that would fall off the end onto the last day, and the sheet
/// says how many before anything changes.
struct ChangeDatesForm: View {
    let model: BuildModel
    @Environment(\.dismiss) private var dismiss
    @State private var startDay: LocalDay
    @State private var dayCount: Int

    init(model: BuildModel, dayCount: Int? = nil) {
        self.model = model
        _startDay = State(initialValue: model.header?.startDay ?? LocalDay(year: 1970, month: 1, day: 1))
        _dayCount = State(initialValue: dayCount ?? model.header?.dayCount ?? 1)
    }

    private var moved: Int { model.stopsAffected(byDayCount: dayCount) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Change Dates", comment: "Sheet title").font(IterFont.titleSection)
                .padding([.horizontal, .top], IterSpace.sheet)
            Form {
                DatePicker(selection: Binding(get: { utcDate(startDay) }, set: { startDay = LocalDay($0, in: utc) }),
                           displayedComponents: .date) { Text("Starts", comment: "Change dates field") }
                    .datePickerStyle(.compact)
                    .environment(\.timeZone, utc)
                Picker(selection: $dayCount) {
                    ForEach(1...maximumTripDays, id: \.self) { Text(daysLabel($0)).tag($0) }
                } label: { Text("Days", comment: "Change dates field") }
                LabeledContent {
                    Text(LibraryText.fullDay(startDay.adding(days: dayCount - 1)))
                } label: { Text("Ends", comment: "Change dates field") }
                if moved > 0 {
                    Label {
                        Text("^[\(moved) stop](inflect: true) will move to Day \(dayCount), the new last day. You can undo this.",
                             comment: "Warning when shortening a trip moves stops; the number is how many")
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                    .foregroundStyle(IterColor.warning)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(role: .cancel) { dismiss() } label: { Text("Cancel", comment: "Button") }
                    .keyboardShortcut(.cancelAction)
                Button {
                    model.changeDates(startDay: startDay, dayCount: dayCount)
                    dismiss()
                } label: { Text("Change Dates", comment: "Button: apply the new dates") }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, IterSpace.sm)
            .padding([.horizontal, .bottom], IterSpace.sheet)
        }
        .frame(width: 480)
        .tint(nil)
    }
}

// MARK: - Place editor

/// Edit Location: name, place, notes, folder and pin; for your own spots also position and light facts. A catalogue spot shows its
/// fixed facts read-only with the reason. Done saves in one undo step ("Edit Location").
struct PlaceEditorForm: View {
    let library: LibraryModel
    let placeID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PlaceEdit?
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var walkIn = ""
    @State private var tags = ""
    @State private var nameTouched = false

    private var editsFacts: Bool { library.editsFacts(id: placeID) }

    var body: some View {
        NavigationStack {
            Group {
                if draft != nil { form } else {
                    ContentUnavailableView(String(localized: "Place Not Found", comment: "Editor empty state"), systemImage: "mappin.slash")
                }
            }
            .navigationTitle(Text("Edit Location", comment: "Place editor title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(role: .cancel) { dismiss() } label: { Text("Cancel", comment: "Button") } }
                ToolbarItem(placement: .confirmationAction) { Button { save() } label: { Text("Done", comment: "Button") }.disabled(!isValid) }
            }
        }
        #if os(macOS)
        .frame(width: IterSize.listMax)
        .frame(minHeight: 520)
        #endif
        .tint(nil)
        .onAppear(perform: load)
    }

    private var form: some View {
        Form {
            Section {
                LabeledContent {
                    TextField(text: binding(\.name), prompt: Text("Name this location", comment: "Name placeholder")) { Text("Name", comment: "Field") }
                        .labelsHidden().multilineTextAlignment(.trailing)
                } label: { Text("Name", comment: "Place editor field") }
                if nameTouched, !nameValid {
                    Label(String(localized: "Name this location to save it.", comment: "Validation: name required"), systemImage: "exclamationmark.triangle.fill")
                        .font(IterFont.caption).foregroundStyle(IterColor.danger)
                }
                LabeledContent {
                    TextField(text: binding(\.locality), prompt: Text("Park, town or region", comment: "Locality placeholder")) { Text("Place", comment: "Field") }
                        .labelsHidden().multilineTextAlignment(.trailing)
                } label: { Text("Place", comment: "Place editor field") }
            }
            if editsFacts { factsSections } else { catalogueSection }
            Section {
                TextField(text: binding(\.notes), prompt: Text("Access, gear, crowds, permits", comment: "Notes placeholder"), axis: .vertical) {
                    Text("Notes", comment: "Field")
                }
                .lineLimit(3...8)
            } header: { Text("Notes", comment: "Section title") }
            Section {
                Picker(selection: binding(\.folderID)) {
                    Text("None", comment: "Not in a folder").tag(UUID?.none)
                    ForEach(library.placeFolders) { Text($0.name).tag(UUID?.some($0.id)) }
                } label: { Text("Folder", comment: "Place editor field") }
                Toggle(isOn: binding(\.isPinned)) { Text("Pin to Sidebar", comment: "Place editor field") }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var factsSections: some View {
        Section {
            LabeledContent {
                TextField(text: $latitude, prompt: Text("Latitude", comment: "Placeholder")) { Text("Latitude", comment: "Field") }
                    .labelsHidden().multilineTextAlignment(.trailing).monospacedDigit()
            } label: { Text("Latitude", comment: "Place editor field") }
            LabeledContent {
                TextField(text: $longitude, prompt: Text("Longitude", comment: "Placeholder")) { Text("Longitude", comment: "Field") }
                    .labelsHidden().multilineTextAlignment(.trailing).monospacedDigit()
            } label: { Text("Longitude", comment: "Place editor field") }
            Button { pasteCoordinates() } label: { Text("Paste Coordinates", comment: "Button: fill latitude and longitude from the clipboard") }
            if coordinate == nil {
                Label(String(localized: "Enter a latitude from -90 to 90 and a longitude from -180 to 180.", comment: "Validation: coordinates"),
                      systemImage: "exclamationmark.triangle.fill").font(IterFont.caption).foregroundStyle(IterColor.danger)
            }
        } header: { Text("Position", comment: "Section title") }
        Section {
            Picker(selection: binding(\.category)) {
                ForEach(PlaceCategory.allCases) { Label(LightText.name($0), systemImage: LightText.symbol($0)).tag($0) }
            } label: { Text("Category", comment: "Place editor field") }
            LabeledContent {
                TextField(text: $walkIn, prompt: Text("Optional", comment: "Placeholder")) { Text("Walk-in", comment: "Field") }
                    .labelsHidden().multilineTextAlignment(.trailing)
            } label: { Text("Walk-in (minutes)", comment: "Place editor field") }
            if !walkInValid {
                Label(String(localized: "Enter whole minutes from 0 to 240, or leave it empty if you don't know.", comment: "Validation: walk-in"),
                      systemImage: "exclamationmark.triangle.fill").font(IterFont.caption).foregroundStyle(IterColor.danger)
            }
            LabeledContent {
                TextField(text: $tags, prompt: Text("Separate with commas", comment: "Placeholder")) { Text("Tags", comment: "Field") }
                    .labelsHidden().multilineTextAlignment(.trailing)
            } label: { Text("Tags", comment: "Place editor field") }
        }
        Section {
            ForEach(BestLight.allCases) { light in
                Toggle(LightText.name(light), isOn: Binding(
                    get: { draft?.bestLight.contains(light) ?? false },
                    set: { on in
                        if on { if draft?.bestLight.contains(light) == false { draft?.bestLight.append(light) } }
                        else { draft?.bestLight.removeAll { $0 == light } }
                    }))
            }
        } header: { Text("Best light (choose any)", comment: "Section title") } footer: {
            Text("With none chosen, light is shown for sunset.", comment: "Best light footer")
        }
    }

    private var catalogueSection: some View {
        Section {
            if let draft {
                LabeledContent { Text("\(CoordinateText.format(draft.coordinate.latitude)), \(CoordinateText.format(draft.coordinate.longitude))").monospacedDigit() }
                    label: { Text("Coordinates", comment: "Place editor field") }
                LabeledContent { Text(LightText.name(draft.category)) } label: { Text("Category", comment: "Place editor field") }
                LabeledContent {
                    Text(draft.bestLight.isEmpty ? LightText.name(BestLight.sunset) : draft.bestLight.map { LightText.name($0) }.formatted(.list(type: .and)))
                } label: { Text("Best light", comment: "Place editor field") }
                if let minutes = draft.walkInMinutes {
                    LabeledContent { Text("\(minutes) min") } label: { Text("Walk-in", comment: "Place editor field") }
                }
            }
        } header: { Text("From the Catalogue", comment: "Section title") } footer: {
            Text("This spot comes from Iter's catalogue, so its position, category and light are fixed. Your name, place, notes, folder and pin are saved with your copy.",
                 comment: "Why a catalogue spot's facts are read-only")
        }
    }

    // MARK: State

    private func binding<V>(_ keyPath: WritableKeyPath<PlaceEdit, V>) -> Binding<V> {
        Binding(get: { draft![keyPath: keyPath] }, set: { draft?[keyPath: keyPath] = $0; nameTouched = true })
    }

    private func load() {
        guard draft == nil, let edit = library.placeEdit(id: placeID) else { return }
        draft = edit
        latitude = CoordinateText.format(edit.coordinate.latitude)
        longitude = CoordinateText.format(edit.coordinate.longitude)
        walkIn = edit.walkInMinutes.map(String.init) ?? ""
        tags = edit.tags.joined(separator: ", ")
    }

    private var nameValid: Bool { !(draft?.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }

    private var coordinate: Coordinate? {
        guard let lat = Double(latitude.trimmingCharacters(in: .whitespaces)), let lon = Double(longitude.trimmingCharacters(in: .whitespaces)),
              (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        return Coordinate(latitude: lat, longitude: lon)
    }

    private var walkInValid: Bool {
        let text = walkIn.trimmingCharacters(in: .whitespaces)
        return text.isEmpty || Int(text).map { (0...240).contains($0) } == true
    }

    private var isValid: Bool { draft != nil && nameValid && (!editsFacts || (coordinate != nil && walkInValid)) }

    private func pasteCoordinates() {
        #if canImport(AppKit)
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        #elseif canImport(UIKit)
        let text = UIPasteboard.general.string ?? ""
        #endif
        guard let c = CoordinateText.parse(text) else { return }
        latitude = CoordinateText.format(c.latitude)
        longitude = CoordinateText.format(c.longitude)
    }

    private func save() {
        guard var edit = draft, isValid else { nameTouched = true; return }
        edit.name = edit.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if editsFacts, let coordinate {
            if coordinate != edit.coordinate {
                edit.timeZoneIdentifier = CoordinateText.zone(near: coordinate, keeping: edit.timeZoneIdentifier)
            }
            edit.coordinate = coordinate
            let text = walkIn.trimmingCharacters(in: .whitespaces)
            edit.walkInMinutes = text.isEmpty ? nil : Int(text)
            edit.tags = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        library.editPlace(id: placeID, edit)
        dismiss()
    }
}
