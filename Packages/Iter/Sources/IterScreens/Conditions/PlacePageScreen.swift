import SwiftUI
import MapKit
import CoreLocation
import IterFeatures
import IterModel
import IterUI

/// A place's own page (sidebar, a saved place, or "Open Place Page" from a card or a stop): header (name, locality, the one
/// score chip of the headline window), actions (Add to Trip, Save, Edit, Open in Maps), the Conditions modules, then the facts.
public struct PlacePageScreen: View {
    let place: Place
    let conditions: ConditionsModel
    let library: LibraryModel
    @Environment(AppNavigator.self) private var navigator: AppNavigator?
    /// MGRS and magnetic declination for the place, with where each came from. The shell passes
    /// `{ find.spots.readout(for: $0.coordinate, elevationMeters: $0.elevationMeters) }`; nil leaves them out.
    let readout: ((Place) -> PositionReadout)?
    @State private var isSaved = false

    public init(place: Place, conditions: ConditionsModel, library: LibraryModel, readout: ((Place) -> PositionReadout)? = nil) {
        self.place = place; self.conditions = conditions; self.library = library; self.readout = readout
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IterSpace.xl) {
                header
                actions
                // Leads with when to go (the old spot page did); the place's facts follow the conditions.
                ConditionsStack(model: conditions)
                PlaceFacts(place: place, readout: readout?(place))
            }
            .padding(IterSpace.xl)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(place.name)
        .onAppear {
            isSaved = library.isSaved(place)
            conditions.beginViewing()
        }
        .onDisappear { conditions.endViewing() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: IterGrid.laneGap) {
            VStack(alignment: .leading, spacing: IterSpace.xs) {
                Text(verbatim: place.name).font(IterFont.titleSpot).foregroundStyle(IterColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if !place.locality.isEmpty {
                    Text(verbatim: place.locality).font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
                }
                Label(LightText.name(place.category), systemImage: LightText.symbol(place.category))
                    .font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
                if let h = conditions.headline {
                    Text(verbatim: ConditionsFormat.headlineTitle(kind: h.kind, timeline: conditions.timeline, windows: conditions.windows, zone: place.timeZone))
                        .font(IterFont.headline).foregroundStyle(IterColor.textPrimary).padding(.top, IterSpace.xs)
                }
            }
            Spacer(minLength: 0)
            HeadlineChip(model: conditions, size: .large)
        }
    }

    private var actions: some View {
        PlaceActionRow(spacing: IterSpace.sm) {
            Menu {
                Button("New Trip with This Place", systemImage: "plus") {
                    navigator?.present(.newTrip(templateID: nil, firstPlace: place.id))
                }
                if !library.trips.isEmpty {
                    Divider()
                    ForEach(library.trips.prefix(10)) { trip in
                        Button(trip.name) { library.addPlace(place, toTrip: trip.id) }
                    }
                }
            } label: {
                Label("Add to Trip", systemImage: "plus")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .placeAction(isProminent: true)
            if place.origin != .user {
                Button {
                    if isSaved { library.unsavePlace(place) } else { library.savePlace(place) }
                    isSaved = library.isSaved(place)
                } label: {
                    Label(isSaved ? "Saved" : "Save", systemImage: isSaved ? "bookmark.fill" : "bookmark")
                }
                .placeAction()
            }
            if library.place(id: place.id) != nil {
                Button { navigator?.present(.editPlace(place.id)) } label: { Label("Edit", systemImage: "pencil") }
                    .placeAction()
            }
            Button(action: openInMaps) { Label("Open in Maps", systemImage: "map") }
                .placeAction()
        }
    }

    private func openInMaps() {
        let item = MKMapItem(location: CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude), address: nil)
        item.name = place.name
        item.openInMaps()
    }
}

/// Coordinates, elevation, walk-in, facing, category, best light, notes and citations: what is known, and "unknown" for the rest.
struct PlaceFacts: View {
    let place: Place
    var readout: PositionReadout?

    var body: some View {
        ModuleCard(title: "Facts", symbol: "list.bullet") {
            VStack(alignment: .leading, spacing: IterSpace.sm) {
                fact("Coordinates", PlaceFactsText.coordinates(place.coordinate))
                if let readout {
                    if let mgrs = readout.mgrs { fact("MGRS", mgrs) }
                    if let declination = readout.declinationText { fact("Declination", declination) }
                }
                fact("Elevation", PlaceFactsText.elevation(place.elevationMeters))
                fact("Walk-In", PlaceFactsText.walkIn(place.walkInMinutes))
                fact("Facing", place.facing.map(ConditionsFormat.azimuth) ?? "Unknown")
                fact("Category", LightText.name(place.category))
                if !place.bestLight.isEmpty { fact("Best Light", place.bestLight.map(LightText.name).joined(separator: ", ")) }
                fact("Time Zone", place.timeZoneIdentifier.replacingOccurrences(of: "_", with: " "))
                if let readout {
                    let sources = FindText.readoutSources(readout)
                    if !sources.isEmpty {
                        VStack(alignment: .leading, spacing: IterSpace.xxs) { ForEach(sources, id: \.self) { Text(verbatim: $0) } }
                            .font(IterFont.caption).foregroundStyle(IterColor.textTertiary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !place.notes.isEmpty {
                    Text(verbatim: place.notes).font(IterFont.body).foregroundStyle(IterColor.textPrimary).fixedSize(horizontal: false, vertical: true)
                        .padding(.top, IterSpace.xs)
                }
                if !place.citations.isEmpty {
                    VStack(alignment: .leading, spacing: IterSpace.xs) {
                        Text("Sources for This Place").font(IterFont.secondary.weight(.semibold)).foregroundStyle(IterColor.textSecondary)
                        ForEach(Array(place.citations.enumerated()), id: \.offset) { _, c in
                            if let url = c.url { Link(c.title, destination: url).font(IterFont.secondary).foregroundStyle(IterColor.accentText) }
                            else { Text(verbatim: c.title).font(IterFont.secondary).foregroundStyle(IterColor.textSecondary) }
                        }
                    }
                    .padding(.top, IterSpace.xs)
                }
            }
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: IterGrid.laneGap) {
            Text(verbatim: label).font(IterFont.body).foregroundStyle(IterColor.textSecondary).frame(width: 96, alignment: .leading)
            Text(verbatim: value).font(IterFont.body).foregroundStyle(IterColor.textPrimary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

enum PlaceFactsText {
    /// "38.3884\u{00B0} N, 109.8680\u{00B0} W".
    static func coordinates(_ c: Coordinate) -> String {
        String(format: "%.4f\u{00B0} %@, %.4f\u{00B0} %@", abs(c.latitude), c.latitude >= 0 ? "N" : "S", abs(c.longitude), c.longitude >= 0 ? "E" : "W")
    }

    static func elevation(_ meters: Double?) -> String {
        guard let meters else { return "Unknown" }
        return "\(Int(meters.rounded()).formatted()) m"
    }

    static func walkIn(_ minutes: Int?) -> String {
        guard let minutes else { return "Unknown" }
        return minutes == 0 ? "At the car" : "\(minutes) min"
    }
}
