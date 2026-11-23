import SwiftUI
import IterFeatures
import IterModel
import IterScreens
import IterUI

// OWNER: W3 (screens). CONTRACT: the shell (W1) mounts these. Keep names and initialisers.
// The tab maps and roots are in FindTab.swift, TripsTab.swift and SavedTab.swift; the iPad detail is in PadDetail.swift.

/// What a phone tab's NavigationStack shows for a pushed route (the shell attaches it with `navigationDestination(for: PhoneRoute.self)`).
struct PhoneRouteDestination: View {
    let shell: IOSShell
    let route: PhoneRoute

    var body: some View {
        Group {
            switch route {
            case .trip(let id): PhoneTripScreen(shell: shell, tripID: id).id(id)
            case .tripFolder(let id): TripsListHost(shell: shell, folderID: id).id(id)
            case .placeFolder(let id): SavedListHost(shell: shell, folderID: id).id(id)
            case .place(let id): PhonePlaceScreen(shell: shell, placeID: id).id(id)
            }
        }
        .iterShellEnvironment(shell)
    }
}

/// A trip in the sheet: the Trip Builder panel with the shared parts, Share and Change Dates in the toolbar and Start Trip as the
/// one accent action. The route map behind the sheet shares the panel's model.
struct PhoneTripScreen: View {
    let shell: IOSShell
    let tripID: UUID

    var body: some View {
        if shell.library.tripRow(id: tripID) != nil {
            let model = shell.buildModel(for: tripID)
            TripBuilderPanel(model: model)
                .environment(\.tripBuilderOpensModel, true)
                .environment(\.tripBuilderAddStopFromFind) { trip, day in
                    FindAddTarget.shared.set(tripID: trip, day: day)
                    shell.tab = .find
                    shell.detent = PhoneSheet.half
                }
                // The builder's header card already carries the trip's name, Share, More and the dates (Change Dates), so the
                // bar holds only Back.
                .navigationTitle(Text(verbatim: ""))
                .navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    StartTripBar(model: model) { start() }
                }
        } else {
            ContentUnavailableView("Trip Not Found", systemImage: "suitcase",
                                   description: Text("This trip is no longer in your library."))
        }
    }

    private func start() {
        Task {
            await shell.go.start(tripID: tripID)
            shell.tab = .go
        }
    }
}

/// Start Trip: the trip's one accent action, a prominent glass button over the foot of the list.
struct StartTripBar: View {
    let model: BuildModel
    let start: () -> Void

    var body: some View {
        Button(action: start) {
            Label { Text("Start Trip", comment: "Button: begin trip mode") } icon: { Image(systemName: "play.fill") }
                .font(IterFont.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glassProminent)
        .tint(IterColor.accent)
        .disabled(model.stops.isEmpty)
        .padding(.horizontal, IterSpace.lg)
        .padding(.vertical, IterSpace.sm)
    }
}

/// A saved place's own page in the sheet. Its Conditions model starts with the view and stops with it.
struct PhonePlaceScreen: View {
    let shell: IOSShell
    let placeID: UUID
    @State private var conditions: ConditionsModel?

    var body: some View {
        // Reading the row registers the view for library changes (an edit rebuilds the page's model below).
        if shell.library.placeRow(id: placeID) != nil, let place = shell.library.place(id: placeID) {
            Group {
                if let conditions {
                    PlacePageScreen(place: place, conditions: conditions, library: shell.library,
                                    readout: { shell.find.spots.readout(for: $0.coordinate, elevationMeters: $0.elevationMeters) })
                } else {
                    Color.clear
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: PlaceShare.url(name: place.name, latitude: place.coordinate.latitude, longitude: place.coordinate.longitude),
                              subject: Text(verbatim: place.name)) { Label("Share", systemImage: "square.and.arrow.up") }
                }
            }
            .task(id: place) {
                conditions?.stop()
                let model = shell.makeConditions(place)
                conditions = model
                model.start()
            }
            .onDisappear { conditions?.stop() }
        } else {
            ContentUnavailableView("Place Not Found", systemImage: "mappin.slash",
                                   description: Text("This place is no longer in your library."))
        }
    }
}

enum PlaceShare {
    /// An Apple Maps link: the place's name at its exact coordinate.
    static func url(name: String, latitude: Double, longitude: Double) -> URL {
        var c = URLComponents()
        c.scheme = "https"
        c.host = "maps.apple.com"
        c.queryItems = [URLQueryItem(name: "ll", value: String(format: "%.6f,%.6f", latitude, longitude)), URLQueryItem(name: "q", value: name)]
        return c.url ?? URL(string: "https://maps.apple.com")!
    }
}
