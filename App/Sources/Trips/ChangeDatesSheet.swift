import SwiftUI
import IterCore
import IterDesign
import IterFeatures

/// Change Dates: a new start and length. Shrinking moves the stops that would fall off the end onto the last day,
/// and the sheet says how many before anything changes.
struct ChangeDatesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let builder: TripBuilderModel
    @State private var startDay: LocalDay
    @State private var dayCount: Int

    init(builder: TripBuilderModel) {
        self.builder = builder
        _startDay = State(initialValue: builder.plan?.startDay ?? LocalDay(year: 1970, month: 1, day: 1))
        _dayCount = State(initialValue: builder.plan?.dayCount ?? 1)
    }

    private static let utc = TimeZone(identifier: "UTC")!

    private var displaced: Int { builder.stopsDisplaced(byDayCount: dayCount) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Change Dates", comment: "Sheet title")
                .font(IterFont.titleSection)
                .padding([.horizontal, .top], IterSpace.sheet)
            Form {
                DatePicker(String(localized: "Starts", comment: "Change dates field"), selection: Binding(
                    get: { startDay.noon(in: Self.utc) }, set: { startDay = LocalDay($0, in: Self.utc) }),
                           displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .environment(\.timeZone, Self.utc)
                Picker(String(localized: "Days", comment: "Change dates field"), selection: $dayCount) {
                    ForEach(1...TripsHomeModel.maximumDayCount, id: \.self) { days in
                        Text(InflectedCount.string("day", count: days) { AttributedString(localized: "^[\(days) day](inflect: true)", comment: "Number of days in a trip, e.g. 3 days") }).tag(days)
                    }
                }
                LabeledContent(String(localized: "Ends", comment: "Change dates field")) {
                    Text(TimeText.day(startDay.adding(days: dayCount - 1)))
                }
                if displaced > 0 {
                    Label {
                        Text("^[\(displaced) stop](inflect: true) will move to Day \(dayCount), the new last day. You can undo this.",
                             comment: "Warning when shortening a trip moves stops; the number is how many")
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .foregroundStyle(IterColor.warning)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(String(localized: "Cancel", comment: "Button"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Change Dates", comment: "Button: apply the new dates")) {
                    builder.setDates(start: startDay, dayCount: dayCount)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], IterSpace.sheet)
        }
        .frame(width: NewTripSheet.width)
        .tint(nil)
    }
}
