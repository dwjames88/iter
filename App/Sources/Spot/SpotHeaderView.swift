import SwiftUI
import MapKit
import CoreLocation
import IterCore
import IterData
import IterDesign
import IterFeatures

/// Name, place, provenance, and the page's actions: Add to Trip, Save, Open in Maps, Share, and for the user's own
/// spots Delete, and Edit for any saved or own spot (both undoable through the store).
struct SpotHeaderView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let spot: Spot
    /// The spot's next event (the first upcoming window; SpotModel has no separate next-event API), and what to read it in.
    var nextEvent: (day: LocalDay, window: LightWindow)?
    var today: LocalDay?
    var zone: TimeZone?
    @State private var editing: PlaceRecord?
    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: IterGrid.inset) {
            VStack(alignment: .leading, spacing: IterSpace.xs) {
                Text(spot.name)
                    .font(.largeTitle.bold())
                    .foregroundStyle(IterColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: IterSpace.sm) {
                    if !spot.locality.isEmpty {
                        Text(spot.locality)
                        Text(verbatim: "·")
                    }
                    ProvenanceTag(origin: spot.origin)
                    Text(verbatim: "·")
                    Label(LightText.name(spot.category), systemImage: LightText.symbol(spot.category))
                }
                .font(IterFont.secondary)
                .foregroundStyle(IterColor.textSecondary)
            }
            if let nextEvent, let zone, let today {
                HStack(alignment: .firstTextBaseline, spacing: IterSpace.sm) {
                    EventScore(window: nextEvent.window, zone: zone, timeStyle: .start, variant: .large,
                               isTomorrow: nextEvent.day != today)
                    Text(LightText.relativeDay(nextEvent.day, today: today))
                        .font(IterFont.secondary)
                        .foregroundStyle(IterColor.textSecondary)
                }
            }
            // Maps' action tiles: a fixed width while they fit, else an equal share of the row.
            ViewThatFits(in: .horizontal) {
                actions(tileWidth: Self.tileWidth)
                actions(tileWidth: nil)
            }
        }
        .sheet(item: $editing) { record in
            PlaceEditorSheet(record: record)
        }
        .focusedSceneValue(\.editLocation, editable.map { record in EditLocationAction { editing = record } })
        .confirmationDialog(LightText.deleteTitle(spot.name), isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(LightText.deleteSpot, role: .destructive) { deleteSpot() }
        } message: {
            Text(LightText.deleteMessage(stops: record?.stops?.count ?? 0))
        }
        #if os(macOS)
        .onDeleteCommand { if record != nil { requestDelete() } }
        #endif
    }

    // MARK: Actions

    private static let tileWidth: CGFloat = 112

    private func actions(tileWidth: CGFloat?) -> some View {
        HStack(spacing: IterSpace.sm) {
            AddToTripMenu(spot: spot)
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .placeAction(isProminent: true)
                .frame(width: tileWidth)
                .help(String(localized: "Add this spot to a trip day", comment: "Help"))
            if spot.origin != .user {
                let saved = model.store.revision >= 0 && model.store.isSaved(spotID: spot.id)
                Button {
                    model.store.setSaved(spot, !saved)
                } label: {
                    Label(saved ? LightText.saved : LightText.save, systemImage: saved ? "bookmark.fill" : "bookmark")
                }
                .keyboardShortcut("d")
                .frame(width: tileWidth)
                .help(saved ? String(localized: "Remove from Saved", comment: "Help") : String(localized: "Save this spot", comment: "Help"))
            }
            Button(action: openInMaps) {
                Label(LightText.openInMaps, systemImage: "map")
            }
            .frame(width: tileWidth)
            .help(String(localized: "Open this location in Apple Maps", comment: "Help"))
            ShareLink(item: Self.shareURL(for: spot), subject: Text(spot.name), message: Text(Self.shareMessage(for: spot))) {
                Label(LightText.share, systemImage: "square.and.arrow.up")
            }
            .frame(width: tileWidth)
            .help(String(localized: "Share this location", comment: "Help"))
            if let editable {
                Button { editing = editable } label: { Label(LightText.edit, systemImage: "pencil") }
                    .frame(width: tileWidth)
                    .help(String(localized: "Edit this location", comment: "Help"))
            }
            if record != nil {
                Button(role: .destructive) { requestDelete() } label: { Label(LightText.delete, systemImage: "trash") }
                    .frame(width: tileWidth)
                    .help(String(localized: "Delete this spot", comment: "Help"))
            }
            if tileWidth != nil { Spacer(minLength: 0) }
        }
        .placeAction()
    }

    /// The record to edit: the user's own spot, or any place saved to Locations.
    private var editable: PlaceRecord? {
        guard model.store.revision >= 0 else { return nil }
        return model.store.editableRecord(for: spot)
    }

    /// The record that can be deleted: the user's own spots.
    private var record: PlaceRecord? {
        guard spot.origin == .user, model.store.revision >= 0, let id = UUID(uuidString: spot.id) else { return nil }
        return model.store.place(id: id)
    }

    private func requestDelete() {
        guard let record else { return }
        if (record.stops?.count ?? 0) > 0 {
            confirmingDelete = true
        } else {
            deleteSpot()
        }
    }

    private func deleteSpot() {
        guard let record else { return }
        model.store.deletePlace(record)
        dismiss()
    }

    private func openInMaps() {
        let item = MKMapItem(location: CLLocation(latitude: spot.coordinate.latitude, longitude: spot.coordinate.longitude), address: nil)
        item.name = spot.name
        item.openInMaps(launchOptions: nil)
    }

    // MARK: Sharing

    static func shareURL(for spot: Spot) -> URL {
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [
            URLQueryItem(name: "ll", value: String(format: "%.5f,%.5f", spot.coordinate.latitude, spot.coordinate.longitude)),
            URLQueryItem(name: "q", value: spot.name),
        ]
        return components.url ?? URL(string: "https://maps.apple.com/")!
    }

    static func shareMessage(for spot: Spot) -> String {
        String(format: "%@ · %.5f, %.5f", spot.name, spot.coordinate.latitude, spot.coordinate.longitude)
    }
}
