import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// New Trip: a name, a start date, a number of days, and optionally a template to start from.
struct NewTripSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss
    @State private var draft: NewTripDraft

    init(initialStart: LocalDay, initialTemplate: String? = nil) {
        _draft = State(initialValue: NewTripDraft(startDay: initialStart, dayCount: initialTemplate.flatMap(TripTemplates.template(id:))?.dayCount ?? 3,
                                                  templateID: initialTemplate))
    }

    private static let utc = TimeZone(identifier: "UTC")!

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("New Trip", comment: "Sheet title")
                .font(IterFont.titleSection)
                .padding([.horizontal, .top], IterSpace.sheet)
            Form {
                Section {
                    TextField(String(localized: "Name", comment: "New trip field"), text: $draft.name,
                              prompt: Text(draft.template?.defaultName ?? String(localized: "New Trip", comment: "Default trip name")))
                    Picker(String(localized: "Start from", comment: "New trip field"), selection: $draft.templateID) {
                        Text("Empty trip", comment: "No template").tag(String?.none)
                        Divider()
                        ForEach(TripTemplates.all) { template in
                            Text(templateLabel(template)).tag(String?.some(template.id))
                        }
                    }
                }
                Section {
                    DatePicker(String(localized: "Starts", comment: "New trip field"), selection: startDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .environment(\.timeZone, Self.utc)
                    Picker(String(localized: "Days", comment: "New trip field"), selection: dayCount) {
                        ForEach(1...TripsHomeModel.maximumDayCount, id: \.self) { days in
                            Text(InflectedCount.string("day", count: days) { AttributedString(localized: "^[\(days) day](inflect: true)", comment: "Number of days in a trip, e.g. 3 days") }).tag(days)
                        }
                    }
                    .disabled(draft.template != nil)
                } footer: {
                    if draft.template != nil {
                        Text("The template sets the number of days. You can add, move and remove stops afterwards.", comment: "Explains the days picker is fixed by a template")
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(String(localized: "Cancel", comment: "Button"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Create", comment: "Button: create the trip")) { create() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], IterSpace.sheet)
        }
        .frame(width: NewTripSheet.width)
        .tint(nil)
    }

    private var dayCount: Binding<Int> {
        Binding(get: { draft.effectiveDayCount }, set: { draft.dayCount = $0 })
    }

    /// Wide enough for the template names; the sheet is fixed-size like a system form sheet.
    static let width = IterSize.listIdeal + IterSize.inspectorIdeal

    private var startDate: Binding<Date> {
        Binding(get: { draft.startDay.noon(in: Self.utc) }, set: { draft.startDay = LocalDay($0, in: Self.utc) })
    }

    private func templateLabel(_ template: TripTemplate) -> String {
        String(localized: "\(template.defaultName) · \(template.dayCount) days, \(template.stops.count) stops",
               comment: "Template menu item: name, days, stops")
    }

    private func create() {
        let home = TripsHomeModel(store: model.store, engine: model.engine, now: { model.now() })
        let trip = home.create(draft, fallbackName: String(localized: "New Trip", comment: "Default trip name"))
        navigation.show(.trip(trip.id))
        dismiss()
    }
}
