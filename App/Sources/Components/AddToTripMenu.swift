import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// "Add to Trip" everywhere (pattern #11). Each day in the menu shows the light at this spot that day, so the
/// choice of day is a light decision (critique C24).
struct AddToTripMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    let spot: Spot
    var label: String = String(localized: "Add to Trip", comment: "Button")

    var body: some View {
        Menu {
            let trips = tripsSnapshot
            ForEach(trips, id: \.id) { trip in
                Menu(trip.name) {
                    ForEach(0..<trip.dayCount, id: \.self) { day in
                        Button(dayLabel(trip: trip, day: day)) {
                            _ = model.store.addStop(spot, to: trip, day: day)
                        }
                    }
                }
            }
            if !trips.isEmpty { Divider() }
            Button(String(localized: "New Trip with This Spot", comment: "Menu item")) {
                let start = model.today(in: spot.timeZone).adding(days: 1)
                let trip = model.store.createTrip(name: String(localized: "Trip to \(spot.name)", comment: "Default name of a new trip"),
                                                  startDay: start, dayCount: 1)
                _ = model.store.addStop(spot, to: trip, day: 0)
                navigation.show(.trip(trip.id))
            }
        } label: {
            Label(label, systemImage: "plus.circle")
        }
    }

    private var tripsSnapshot: [TripRecord] {
        _ = model.store.revision
        return model.store.trips()
    }

    /// "Day 2 · Thu, Oct 8, 2026 · Sunset · 64" (or "· Sunset · No forecast").
    private func dayLabel(trip: TripRecord, day: Int) -> String {
        let date = trip.startDay.adding(days: day)
        let base = String(localized: "Day \(day + 1) · \(TimeText.day(date))", comment: "Trip day in Add to Trip menu")
        guard let window = model.dayLight(for: spot, on: date).headline(for: model.intent(for: spot)) else { return base }
        return "\(base) · \(LightText.headline(window))"
    }
}
