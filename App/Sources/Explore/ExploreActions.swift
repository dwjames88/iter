import SwiftUI
import AppKit
import MapKit
import CoreLocation
import IterCore
import IterData
import IterFeatures

/// The actions every row, pin and the place card share: Open, Save, Add to Trip, Open in Maps, Copy Coordinates.
enum ExploreActions {
    @MainActor static func open(_ spot: Spot, day: LocalDay, navigation: AppNavigation) {
        navigation.open(SpotRoute(spot: spot, day: day))
    }

    @MainActor static func openInMaps(_ spot: Spot) {
        let location = CLLocation(latitude: spot.coordinate.latitude, longitude: spot.coordinate.longitude)
        let item = MKMapItem(location: location, address: nil)
        item.name = spot.name
        item.openInMaps(launchOptions: nil)
    }

    @MainActor static func copyCoordinates(_ spot: Spot) {
        let text = String(format: "%.5f, %.5f", spot.coordinate.latitude, spot.coordinate.longitude)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Context-menu content for one spot.
struct ExploreSpotMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    let spot: Spot
    let day: LocalDay

    var body: some View {
        Button {
            ExploreActions.open(spot, day: day, navigation: navigation)
        } label: {
            Label(String(localized: "Open", comment: "Context menu: open the spot page"), systemImage: "arrow.right.circle")
        }
        if spot.origin != .user {
            let saved = isSaved
            Button {
                model.store.setSaved(spot, !saved)
            } label: {
                if saved {
                    Label(String(localized: "Unsave", comment: "Context menu"), systemImage: "star.slash")
                } else {
                    Label(String(localized: "Save", comment: "Context menu"), systemImage: "star")
                }
            }
        }
        AddToTripMenu(spot: spot)
        Divider()
        Button {
            ExploreActions.openInMaps(spot)
        } label: {
            Label(String(localized: "Open in Maps", comment: "Context menu"), systemImage: "map")
        }
        Button {
            ExploreActions.copyCoordinates(spot)
        } label: {
            Label(String(localized: "Copy Coordinates", comment: "Context menu"), systemImage: "doc.on.doc")
        }
    }

    private var isSaved: Bool {
        _ = model.store.revision
        return model.store.isSaved(spotID: spot.id)
    }
}
