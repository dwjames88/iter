import SwiftUI
import IterCore

struct SpotDetailView: View {
    let spot: Spot
    var initialDay: LocalDay?
    var body: some View {
        Text(spot.name)
    }
}
