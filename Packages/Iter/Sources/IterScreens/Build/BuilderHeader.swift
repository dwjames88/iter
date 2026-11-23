import SwiftUI
import IterFeatures
import IterModel
import IterUI

/// The header card: the trip name (renamed in place), Share and More as round glass buttons, the facts, then the start place with
/// the first leave-by, the conditions progress and, for a pinned trip, the offline pack.
struct BuilderHeaderView: View {
    let model: BuildModel
    let header: BuildHeader
    @Environment(AppNavigator.self) private var navigator
    @Environment(LibraryModel.self) private var library: LibraryModel?
    @State private var exporting: BuildExportFormat?
    @State private var exportFailed = false

    var body: some View {
        TripHeaderCard(title: header.name, meta: meta, onRename: { model.rename($0) }) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    if model.isLoadingDrives {
                        ProgressView().controlSize(.small)
                            .help(Text("Fetching drive times", comment: "Tooltip"))
                            .accessibilityLabel(Text("Fetching drive times", comment: "Accessibility label"))
                    }
                    // The document is built when the share is performed, not on every pass of this body.
                    ShareLink(item: exportItem(.v2), preview: SharePreview(header.name)) {
                        Label(String(localized: "Share", comment: "Button"), systemImage: "square.and.arrow.up")
                    }
                    .help(Text("Share this trip as an Iter file", comment: "Tooltip"))
                    moreMenu
                }
                .buttonStyle(GlassCircleButtonStyle(diameter: 36))
            }
        } accessory: {
            VStack(alignment: .leading, spacing: 8) {
                StartPlaceLine(model: model)
                ConditionsProgressLine(model: model)
                PackBadge(state: model.packState, isPinned: header.isPinned)
            }
        }
        .fileExporter(isPresented: Binding(get: { exporting != nil }, set: { if !$0 { exporting = nil } }),
                      item: exporting.map { exportItem($0) }, contentTypes: [.iterTrip], defaultFilename: model.suggestedFileName) { result in
            if case .failure = result { exportFailed = true }
        }
        .alert(Text("Couldn't Export Trip", comment: "Alert title"), isPresented: $exportFailed) {
            Button { exportFailed = false } label: { Text("OK", comment: "Alert button") }
        } message: {
            Text("The trip couldn't be saved to that location.", comment: "Export error")
        }
    }

    private func exportItem(_ format: BuildExportFormat) -> TripExportItem {
        TripExportItem(fileName: model.suggestedFileName) { [model] in try? model.exportDocument(format: format) }
    }

    private var meta: [TripMetaItem] {
        var items = [
            TripMetaItem.dates(from: header.startDay, to: header.endDay, help: Text("Change Dates…", comment: "Tooltip")) {
                navigator.present(.changeDates(tripID: model.tripID))
            },
            TripMetaItem.size(days: header.dayCount, stops: header.stopCount),
        ]
        if header.drivingSeconds >= 60 {
            var driving = TripMetaItem.driving(seconds: header.drivingSeconds, meters: header.drivingMeters)
            if header.drivingIncludesEstimate {
                driving.text += " " + String(localized: "(estimated)", comment: "Trip driving total that includes estimated drives")
            }
            items.append(driving)
        }
        return items
    }

    private var moreMenu: some View {
        Menu {
            Button { navigator.present(.changeDates(tripID: model.tripID)) } label: {
                Text("Change Dates…", comment: "Menu item")
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            Divider()
            Button { exporting = .v2 } label: { Text("Export…", comment: "Menu item") }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Button { exporting = .v1ForOlderIter } label: { Text("Export for Older Iter…", comment: "Menu item") }
            if let library {
                Button {
                    if let copy = library.duplicateTrip(model.tripID) { navigator.open(.trip(copy)) }
                } label: { Text("Duplicate", comment: "Menu item") }
            }
            Button { model.setPinned(!header.isPinned) } label: {
                Text(header.isPinned ? "Unpin Trip" : "Pin Trip", comment: "Menu item")
            }
            if let library {
                Divider()
                Button(role: .destructive) {
                    navigator.open(.allTrips)
                    library.deleteTrip(model.tripID)
                } label: { Text("Delete Trip", comment: "Menu item") }
            }
        } label: {
            Label(String(localized: "More", comment: "Button"), systemImage: "ellipsis")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .help(Text("Change dates, export, duplicate, pin or delete this trip", comment: "Tooltip"))
    }
}

/// "Starting from Salt Lake City • Leave by 06:05", or Set Start Place. The menu lists the trip's lodging, its other stops, then
/// saved places.
struct StartPlaceLine: View {
    let model: BuildModel

    var body: some View {
        Menu {
            ForEach(model.startPlaceCandidates()) { place in
                Button { model.setStartPlace(place.id) } label: {
                    Text(place.locality.isEmpty ? place.name : "\(place.name), \(place.locality)")
                }
            }
            if model.startPlace != nil {
                Divider()
                Button { model.setStartPlace(nil) } label: { Text("No Start Place", comment: "Menu item") }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "house").foregroundStyle(IterColor.textSecondary).accessibilityHidden(true)
                Text(text).monospacedDigit().foregroundStyle(IterColor.textSecondary).lineLimit(1)
            }
            .font(BuilderType.body)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Text("Where day 1 starts, so the first stop has a leave-by time", comment: "Tooltip"))
    }

    private var text: String {
        guard let start = model.startPlace else { return String(localized: "Set Start Place", comment: "Button: choose where day 1 starts") }
        let name = start.name
        guard let leave = start.firstLeaveBy else { return String(localized: "Starting from \(name)", comment: "Where day 1 starts") }
        let time = TimeText.time(leave, in: start.timeZone)
        return String(localized: "Starting from \(name) • Leave by \(time)", comment: "Where day 1 starts and when to leave it")
    }
}

/// "Conditions: 4 of 9 stops ready; NOAA forecast still loading for 3".
struct ConditionsProgressLine: View {
    let model: BuildModel

    var body: some View {
        let progress = model.conditionsProgress
        if !progress.text.isEmpty {
            HStack(spacing: 8) {
                if progress.isComplete {
                    Image(systemName: "checkmark.circle").foregroundStyle(IterColor.textSecondary).accessibilityHidden(true)
                } else {
                    ProgressView().controlSize(.mini)
                }
                Text(progress.text).foregroundStyle(IterColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(BuilderType.body)
        }
    }
}

/// The offline conditions pack of a pinned trip.
struct PackBadge: View {
    let state: BuildPackState
    let isPinned: Bool

    var body: some View {
        if isPinned, let text = Self.text(state) {
            Label {
                Text(text)
            } icon: {
                Image(systemName: Self.symbol(state))
            }
            .font(BuilderType.body)
            .foregroundStyle(state == .failed ? AnyShapeStyle(IterColor.warning) : AnyShapeStyle(IterColor.textSecondary))
        }
    }

    static func text(_ state: BuildPackState, locale: Locale = .current) -> String? {
        switch state {
        case .none: nil
        case .building: String(localized: "Building the offline pack…", comment: "A pinned trip's offline conditions pack is being built")
        case .ready(let builtAt):
            String(localized: "Available offline, updated \(builtAt.formatted(.relative(presentation: .named)))", comment: "A pinned trip's offline pack is ready")
        case .failed: String(localized: "The offline pack couldn't be built", comment: "A pinned trip's offline pack failed")
        }
    }

    static func symbol(_ state: BuildPackState) -> String {
        switch state {
        case .none, .building: "arrow.down.circle"
        case .ready: "checkmark.circle"
        case .failed: "exclamationmark.triangle.fill"
        }
    }
}
