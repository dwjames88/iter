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
                .padding([.horizontal, .top], IterSpace.lg)
            Form {
                TextField(String(localized: "Name", comment: "New trip field"), text: $draft.name,
                          prompt: Text(draft.template?.defaultName ?? String(localized: "New Trip", comment: "Default trip name")))
                DatePicker(String(localized: "Starts", comment: "New trip field"), selection: startDate, displayedComponents: .date)
                    .environment(\.timeZone, Self.utc)
                Stepper(value: $draft.dayCount, in: 1...TripsHomeModel.maximumDayCount) {
                    LabeledContent(String(localized: "Days", comment: "New trip field")) {
                        Text(draft.effectiveDayCount, format: .number).monospacedDigit()
                    }
                }
                .disabled(draft.template != nil)
                Picker(String(localized: "Start from", comment: "New trip field"), selection: $draft.templateID) {
                    Text("Empty trip", comment: "No template").tag(String?.none)
                    Divider()
                    ForEach(TripTemplates.all) { template in
                        Text(templateLabel(template)).tag(String?.some(template.id))
                    }
                }
                if draft.template != nil {
                    Text("The template sets the number of days. You can add, move and remove stops afterwards.", comment: "Explains the days stepper is fixed by a template")
                        .font(IterFont.caption)
                        .foregroundStyle(IterColor.textSecondary)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            HStack {
                Spacer()
                Button(String(localized: "Cancel", comment: "Button"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Create", comment: "Button: create the trip")) { create() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding([.horizontal, .bottom], IterSpace.lg)
        }
        .frame(width: NewTripSheet.width)
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
