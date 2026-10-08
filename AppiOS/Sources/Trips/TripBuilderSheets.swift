import SwiftUI
import MapKit
import IterCore
import IterData
import IterDesign
import IterFeatures

// MARK: - Route map

/// The route for the selected day: its drive legs in the route colour (other days dimmed), numbered stop pins.
/// Selecting a pin scrolls the plan to that stop. Own view: the Mac `TripRouteMap` is excluded from the iOS target.
struct TripRouteMapView: View {
    let builder: TripBuilderModel
    @Binding var selectedDay: Int?
    let onSelectStop: (UUID) -> Void

    @State private var position: MapCameraPosition
    @State private var selection: UUID?
    @AppStorage(MapStyleChoice.storageKey) private var mapStyleRaw = MapStyleChoice.default.rawValue

    init(builder: TripBuilderModel, selectedDay: Binding<Int?>, onSelectStop: @escaping (UUID) -> Void) {
        self.builder = builder
        _selectedDay = selectedDay
        self.onSelectStop = onSelectStop
        if let region = MapCameraPolicy.fit(builder.fitCoordinates) {
            _position = State(initialValue: .region(Self.region(region)))
        } else {
            _position = State(initialValue: .automatic)
        }
    }

    private func isActive(_ day: Int) -> Bool { selectedDay == nil || selectedDay == day }

    var body: some View {
        Map(position: $position, selection: $selection) {
            // Read from the model's draw list, which only changes with the geometry (not with a forecast or a time).
            let content = builder.mapContent
            ForEach(content.legs) { leg in
                let path = leg.path.map(Self.coordinate)
                if isActive(leg.day) {
                    MapPolyline(coordinates: path).stroke(IterColor.backgroundWindow, lineWidth: IterStroke.routeCasing)
                    MapPolyline(coordinates: path).stroke(IterColor.route, lineWidth: IterStroke.route)
                } else {
                    MapPolyline(coordinates: path).stroke(IterColor.routeInactive, lineWidth: IterStroke.routeInactive)
                }
            }
            ForEach(content.pins) { pin in
                Annotation(pin.name, coordinate: Self.coordinate(pin.coordinate), anchor: .center) {
                    self.pin(pin)
                }
                .tag(pin.id)
            }
        }
        .mapStyle(MapStyleChoice(stored: mapStyleRaw).mapStyle())
        .mapControls { MapCompass() }
        .overlay(alignment: .bottomTrailing) { MapStyleMenu().padding(IterSpace.sm) }
        .onChange(of: selection) { _, id in
            if let id { onSelectStop(id); selection = nil }
        }
        .onChange(of: selectedDay) { builder.setFocusDay(selectedDay); refit() }
        .onChange(of: builder.fitCoordinates) { refit() }
        .accessibilityLabel(Text("Route map", comment: "Accessibility label"))
    }

    private func refit() {
        guard let region = MapCameraPolicy.fit(builder.fitCoordinates) else { return }
        withAnimation(.smooth) { position = .region(Self.region(region)) }
    }

    private func pin(_ pin: TripMapPin) -> some View {
        let active = isActive(pin.day)
        return Text(pin.number, format: .number)
            .font(IterFont.captionStrong)
            .monospacedDigit()
            .foregroundStyle(active ? IterColor.onAccent : IterColor.backgroundWindow)
            .frame(width: IterSize.mapPinSelected, height: IterSize.mapPinSelected)
            .background(active ? IterColor.accentEmphasis : IterColor.mapPinInactive, in: Circle())
            .overlay(Circle().strokeBorder(IterColor.backgroundWindow, lineWidth: IterStroke.thin))
            .opacity(active ? 1 : 0.55)
            .accessibilityLabel(Text("Stop \(pin.number), \(pin.name)", comment: "VoiceOver: map pin"))
    }

    private static func region(_ r: GeoRegion) -> MKCoordinateRegion {
        MKCoordinateRegion(center: coordinate(r.center),
                           span: MKCoordinateSpan(latitudeDelta: min(r.latitudeDelta, 120), longitudeDelta: min(r.longitudeDelta, 300)))
    }

    private static func coordinate(_ c: Coordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude)
    }
}

// MARK: - Add stop

/// Saved and curated spots for one day, nearest to where the day starts first, each with its score for that day. Adding
/// keeps the sheet open so several stops can go in; a tick marks what is in.
struct AddStopSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let builder: TripBuilderModel
    let day: Int

    @AppStorage(AppSettings.defaultSetUpBuffer) private var defaultBuffer = 20
    @State private var query = ""
    @State private var added: Set<String> = []

    var body: some View {
        let list = builder.addStopList(forDay: day, query: query)
        NavigationStack {
            List {
                if let anchor = list.anchor {
                    Text("Nearest to \(anchor.name) first", comment: "Add stop list order, naming the stop the distances are from")
                        .font(IterFont.caption)
                        .foregroundStyle(IterColor.textSecondary)
                        .listRowBackground(Color.clear)
                }
                ForEach(list.candidates) { candidate in
                    AddStopRowView(candidate: candidate, day: builder.plan?.day(day), isAdded: added.contains(candidate.id) || candidate.isOnDay) {
                        if builder.addStop(candidate.spot, toDay: day, defaultBufferMinutes: defaultBuffer) != nil {
                            added.insert(candidate.id)
                        }
                    }
                }
                if list.candidates.isEmpty { ContentUnavailableView.search(text: query).listRowBackground(Color.clear) }
            }
            .listStyle(.plain)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text("Search spots", comment: "Add stop search field"))
            .navigationTitle(Text("Add stop · Day \(day + 1)", comment: "Add stop sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done", comment: "Button")) { dismiss() }
                }
            }
        }
    }
}

private struct AddStopRowView: View {
    @Environment(AppModel.self) private var model
    let candidate: AddStopCandidate
    let day: LocalDay?
    let isAdded: Bool
    let add: () -> Void

    var body: some View {
        Button(action: add) {
            HStack(spacing: IterSpace.sm) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: IterSpace.xs) {
                        Text(candidate.spot.name).font(IterFont.body).foregroundStyle(IterColor.textPrimary).lineLimit(1)
                        if candidate.isSaved {
                            Image(systemName: "bookmark.fill").font(IterFont.caption).foregroundStyle(IterColor.textSecondary)
                                .accessibilityLabel(Text("Saved", comment: "Accessibility label"))
                        }
                    }
                    Text(detail).font(IterFont.caption).foregroundStyle(IterColor.textSecondary).lineLimit(1)
                }
                Spacer(minLength: IterSpace.sm)
                if let window { EventScore(window: window, zone: candidate.spot.timeZone, timeStyle: .start, variant: .compact) }
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle")
                    .font(IterFont.callout)
                    .foregroundStyle(isAdded ? IterColor.textSecondary.color : IterColor.accent)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: IterSize.hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear { model.forecasts.request(candidate.spot.coordinate) }
        .accessibilityLabel(Text("Add \(candidate.spot.name)", comment: "VoiceOver: add a spot to the trip"))
        .accessibilityValue(isAdded ? Text("Added", comment: "VoiceOver value") : Text(verbatim: ""))
    }

    private var detail: String {
        if let meters = candidate.distanceMeters {
            return String(localized: "\(candidate.spot.locality) · \(TimeText.distance(meters))", comment: "Add stop row: place and distance from the anchor stop")
        }
        return candidate.spot.locality
    }

    private var window: LightWindow? {
        guard let day else { return nil }
        let state = model.forecasts.state(for: candidate.spot.coordinate)
        let light = model.engine.dayLight(for: candidate.spot, on: day, forecast: state.forecast,
                                          unavailable: state.unavailableReason, now: model.now())
        return light.window(candidate.spot.defaultSession)
    }
}

// MARK: - Change dates

struct ChangeDatesScreenSheet: View {
    @Environment(\.dismiss) private var dismiss
    let builder: TripBuilderModel
    @State private var startDay: LocalDay
    @State private var dayCount: Int

    private static let utc = TimeZone(identifier: "UTC")!

    init(builder: TripBuilderModel) {
        self.builder = builder
        _startDay = State(initialValue: builder.plan?.startDay ?? LocalDay(year: 1970, month: 1, day: 1))
        _dayCount = State(initialValue: builder.plan?.dayCount ?? 1)
    }

    private var displaced: Int { builder.stopsDisplaced(byDayCount: dayCount) }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(String(localized: "Starts", comment: "Change dates field"),
                           selection: Binding(get: { startDay.noon(in: Self.utc) }, set: { startDay = LocalDay($0, in: Self.utc) }),
                           displayedComponents: .date)
                    .environment(\.timeZone, Self.utc)
                Picker(String(localized: "Days", comment: "Change dates field"), selection: $dayCount) {
                    ForEach(1...TripsHomeModel.maximumDayCount, id: \.self) { days in
                        Text("^[\(days) day](inflect: true)", comment: "Number of days in a trip, e.g. 3 days").tag(days)
                    }
                }
                LabeledContent(String(localized: "Ends", comment: "Change dates field")) {
                    Text(TimeText.day(startDay.adding(days: dayCount - 1)))
                }
                if displaced > 0 {
                    Label {
                        Text("^[\(displaced) stop](inflect: true) will move to Day \(dayCount), the new last day. You can undo this.",
                             comment: "Warning when shortening a trip moves stops; the number is how many")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .foregroundStyle(IterColor.warning)
                }
            }
            .navigationTitle(Text("Change Dates", comment: "Sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", comment: "Button")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save", comment: "Button: apply the new dates")) {
                        builder.setDates(start: startDay, dayCount: dayCount)
                        dismiss()
                    }
                }
            }
        }
    }
}
