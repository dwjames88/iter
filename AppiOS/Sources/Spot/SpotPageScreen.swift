import SwiftUI
import IterCore

/// The spot page, pushed from any section (SpotRoute).
struct SpotPageScreen: View {
    let route: SpotRoute
    var body: some View { SpotDetailView(spot: route.spot, initialDay: route.day) }
}
