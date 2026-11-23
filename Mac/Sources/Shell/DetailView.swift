import SwiftUI
import IterFeatures
import IterModel
import IterScreens

/// The detail column for the route: each route builds its own models and closes them with the view.
struct DetailView: View {
    let window: WindowShell

    var body: some View {
        switch window.route {
        case .find:
            FindScreen(model: window.find)
        case .allTrips:
            AllTripsScreen(library: window.library, folderID: nil)
        case .tripFolder(let id):
            AllTripsScreen(library: window.library, folderID: id).id(id)
        case .trip(let id):
            TripLayout(window: window, tripID: id).id(id)
        case .savedPlaces:
            SavedPlacesScreen(library: window.library, folderID: nil)
        case .placeFolder(let id):
            SavedPlacesScreen(library: window.library, folderID: id).id(id)
        case .place(let id):
            PlaceDetail(window: window, placeID: id).id(id)
        }
    }
}

/// A trip: the route map fills the detail and the Trip Builder is the system inspector on the right.
struct TripLayout: View {
    let window: WindowShell
    let tripID: UUID
    @State private var box: Lazy<BuildModel>

    init(window: WindowShell, tripID: UUID) {
        self.window = window
        self.tripID = tripID
        _box = State(initialValue: Lazy { window.container.makeBuildModel(tripID: tripID) })
    }

    var body: some View {
        let model = box.value
        @Bindable var w = window
        TripRouteMap(model: model)
            .inspector(isPresented: $w.inspectorShown) {
                // No background of its own: the system inspector's material shows.
                TripBuilderPanel(model: model)
                    .inspectorColumnWidth(min: 480, ideal: 560, max: 680)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { window.inspectorShown.toggle() } label: {
                        Label("Trip Builder", systemImage: "sidebar.trailing")
                    }
                    .help("Show or Hide the Trip Builder (⌥⌘0)")
                }
            }
            .onAppear {
                window.currentBuild = model
                model.open()
            }
            .onDisappear {
                model.close()
                if window.currentBuild === model { window.currentBuild = nil }
            }
    }
}

/// A saved place's own page. Its Conditions model starts with the view and stops with it.
struct PlaceDetail: View {
    let window: WindowShell
    let placeID: UUID

    var body: some View {
        // Reading the row registers the view for library changes (an edit rebuilds the page's model below).
        if window.library.placeRow(id: placeID) != nil, let place = window.library.place(id: placeID) {
            PlacePage(window: window, place: place).id(place)
        } else {
            ContentUnavailableView("Place Not Found", systemImage: "mappin.slash",
                                   description: Text("This place is no longer in your library."))
        }
    }
}

private struct PlacePage: View {
    let window: WindowShell
    let place: Place
    @State private var box: Lazy<ConditionsModel>

    init(window: WindowShell, place: Place) {
        self.window = window
        self.place = place
        _box = State(initialValue: Lazy { window.container.makeConditionsModel(place: place) })
    }

    var body: some View {
        let conditions = box.value
        PlacePageScreen(place: place, conditions: conditions, library: window.library)
            .onAppear {
                window.currentConditions = conditions
                conditions.start()
            }
            .onDisappear {
                conditions.stop()
                if window.currentConditions === conditions { window.currentConditions = nil }
            }
    }
}
