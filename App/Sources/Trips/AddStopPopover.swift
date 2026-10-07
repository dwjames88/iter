import SwiftUI
import IterCore
import IterDesign
import IterFeatures

/// "Add stop" for one day (C55, C56): saved and curated spots, nearest to where the day starts from first, each one
/// line with its score for that day. Adding keeps the list open so several stops can go in; a tick marks what is in.
struct AddStopPopover: View {
    @Environment(AppModel.self) private var model
    let builder: TripBuilderModel
    let day: Int

    @AppStorage(AppSettings.defaultSetUpBuffer) private var defaultBuffer = 20
    @State private var query = ""
    @State private var added: Set<String> = []

    var body: some View {
        let list = builder.addStopList(forDay: day, query: query)
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: IterSpace.xs) {
                searchField
                if let anchor = list.anchor {
                    Text("Nearest to \(anchor.name) first", comment: "Add stop list order, naming the stop the distances are from")
                        .font(IterFont.caption)
                        .foregroundStyle(IterColor.textSecondary)
                }
            }
            .padding(IterSpace.lg)
            Divider()
            if list.candidates.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List(list.candidates) { candidate in
                    AddStopRow(candidate: candidate, day: builder.plan?.day(self.day), isAdded: added.contains(candidate.id) || candidate.isOnDay) {
                        if builder.addStop(candidate.spot, toDay: day, defaultBufferMinutes: defaultBuffer) != nil {
                            added.insert(candidate.id)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(width: IterSize.listIdeal + IterSize.sidebarIdeal / 2, height: IterSize.arcHeight * 3)
    }

    private var searchField: some View {
        HStack(spacing: IterSpace.sm) {
            TextField(String(localized: "Search spots", comment: "Add stop search field"), text: $query)
                .textFieldStyle(.roundedBorder)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("Clear search", comment: "Accessibility label"))
            }
        }
    }
}

private struct AddStopRow: View {
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
                if let window = window { EventScore(window: window, zone: candidate.spot.timeZone, timeStyle: .start, variant: .compact) }
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle")
                    .font(IterFont.callout)
                    .foregroundStyle(isAdded ? IterColor.textSecondary.color : IterColor.accent)
                    .accessibilityHidden(true)
            }
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

    /// The window this stop would get, scored for the day being added to. Read-only: the row asks for the forecast
    /// when it appears and reads it back here.
    private var window: LightWindow? {
        guard let day else { return nil }
        let state = model.forecasts.state(for: candidate.spot.coordinate)
        let light = model.engine.dayLight(for: candidate.spot, on: day, forecast: state.forecast,
                                          unavailable: state.unavailableReason, now: model.now())
        return light.window(candidate.spot.defaultSession)
    }
}
