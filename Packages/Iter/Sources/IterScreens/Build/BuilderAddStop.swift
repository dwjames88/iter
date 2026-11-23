import SwiftUI
import IterFeatures
import IterModel
import IterUI

/// Add Stop for one day: saved places, nearest to where the day starts from first, each with its compact score for that day. Adding
/// keeps the list open so several stops can go in; a tick marks what is in.
struct AddStopPopover: View {
    let model: BuildModel
    let day: Int
    @State private var query = ""
    @State private var list = BuildAddStopList(anchorName: nil, candidates: [])
    @State private var added: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: IterSpace.xs) {
                TextField(text: $query, prompt: Text("Search saved places", comment: "Add stop search field")) {
                    Text("Search", comment: "Accessibility label")
                }
                .textFieldStyle(.roundedBorder)
                if let anchor = list.anchorName {
                    Text("Nearest to \(anchor) first", comment: "Add stop list order, naming the stop the distances are from")
                        .font(BuilderType.caption).foregroundStyle(IterColor.textSecondary)
                }
            }
            .padding(IterSpace.lg)
            Divider()
            if list.candidates.isEmpty {
                ContentUnavailableView {
                    Label(query.isEmpty ? String(localized: "No Saved Places", comment: "Add stop empty state")
                                        : String(localized: "No Matches", comment: "Add stop empty search"), systemImage: "mappin.slash")
                } description: {
                    Text(query.isEmpty ? "Save places in Find to add them here." : "Try a different name.", comment: "Add stop empty state explanation")
                }
            } else {
                List(list.candidates) { candidate in
                    AddStopRow(candidate: candidate, isAdded: added.contains(candidate.id) || candidate.isOnDay,
                               zone: candidate.place.timeZone) {
                        if model.addStop(candidate.place, day: day) != nil { added.insert(candidate.id) }
                        refresh()
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 360, height: 380)
        .onAppear {
            model.requestAddStopScores(forDay: day)
            refresh()
        }
        .onChange(of: query) { refresh() }
        // The forecasts arrive a moment after the popover opens.
        .task {
            for _ in 0..<5 {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                refresh()
            }
        }
    }

    private func refresh() {
        let next = model.addStopList(forDay: day, query: query)
        if next != list { list = next }
    }
}

private struct AddStopRow: View {
    let candidate: BuildAddCandidate
    let isAdded: Bool
    let zone: TimeZone
    let add: () -> Void

    var body: some View {
        Button(action: add) {
            HStack(spacing: IterSpace.sm) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(candidate.place.name).font(IterFont.body).foregroundStyle(IterColor.textPrimary).lineLimit(1)
                    Text(detail).font(BuilderType.caption).foregroundStyle(IterColor.textSecondary).lineLimit(1)
                }
                Spacer(minLength: IterSpace.sm)
                if let window = candidate.window {
                    ScoreChip(kind: window.kind, start: window.start, score: window.score, zone: zone, size: .compact, timeStyle: .start)
                }
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(isAdded ? IterColor.textSecondary.color : IterColor.accent)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Add \(candidate.place.name)", comment: "VoiceOver: add a place to the trip"))
        .accessibilityValue(isAdded ? Text("Added", comment: "VoiceOver value") : Text(verbatim: ""))
    }

    private var detail: String {
        let place = candidate.place
        guard let meters = candidate.distanceMeters else { return place.locality }
        let distance = TimeText.distance(meters: meters)
        return place.locality.isEmpty ? distance : "\(place.locality) · \(distance)"
    }
}
