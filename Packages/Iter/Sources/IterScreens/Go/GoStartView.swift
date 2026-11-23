import SwiftUI
import IterModel
import IterFeatures
import IterUI

/// Not running: a list of trips to start. Choosing one opens its start step: one prominent "Start Trip" (from the first
/// stop), or pick a later stop (mid-trip, or a later day) and say you are already there.
public struct GoStartView: View {
    let trips: [GoTripChoice]
    let permissionStep: GoPermissionStep?
    let actions: GoActions
    @State private var selectedID: UUID?

    /// `initialSelection` opens a trip's start step directly (previews and renders).
    public init(trips: [GoTripChoice], permissionStep: GoPermissionStep? = nil, actions: GoActions, initialSelection: UUID? = nil) {
        self.trips = trips
        self.permissionStep = permissionStep
        self.actions = actions
        _selectedID = State(initialValue: initialSelection)
    }

    public var body: some View {
        if let trip = trips.first(where: { $0.id == selectedID }) {
            GoStartDetail(trip: trip, actions: actions, back: { selectedID = nil })
        } else {
            list
        }
    }

    @ViewBuilder private var list: some View {
        if trips.isEmpty {
            VStack(spacing: IterSpace.lg) {
                if let permissionStep {
                    GoPermissionRow(step: permissionStep, actions: actions).padding(.horizontal, IterSpace.lg)
                }
                ContentUnavailableView {
                    Label("No Trips to Start", systemImage: "road.lanes")
                } description: {
                    Text("Plan a trip in Iter, then start it here for leave times, drive times and the live sky.")
                }
            }
        } else {
            List {
                if let permissionStep {
                    Section {
                        GoPermissionRow(step: permissionStep, actions: actions)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
                Section {
                    ForEach(trips) { trip in
                        Button { selectedID = trip.id } label: { tripRow(trip) }
                            .buttonStyle(.plain)
                    }
                } header: {
                    Text("Choose a trip").font(IterFont.headline).textCase(nil)
                }
            }
        }
    }

    private func tripRow(_ trip: GoTripChoice) -> some View {
        HStack(spacing: IterSpace.md) {
            VStack(alignment: .leading, spacing: IterSpace.xxs) {
                Text(trip.name).font(IterFont.headline).foregroundStyle(IterColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(GoFlow.dateSpan(trip)) · \(stopCount(trip.stops.count))")
                    .font(IterFont.subheadline).foregroundStyle(IterColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: IterSpace.sm)
            Image(systemName: "chevron.right").font(IterFont.subheadline).foregroundStyle(IterColor.textTertiary).accessibilityHidden(true)
        }
        .frame(minHeight: IterSize.hitTarget)
        .contentShape(Rectangle())
    }

    private func stopCount(_ n: Int) -> String { n == 1 ? "1 stop" : "\(n) stops" }
}

/// The start step of one trip.
struct GoStartDetail: View {
    let trip: GoTripChoice
    let actions: GoActions
    let back: () -> Void
    @State private var fromStop: UUID?
    @State private var alreadyThere = false
    @Environment(\.goFlatButtons) private var flat

    var body: some View {
        let days = GoFlow.stopsByDay(trip)
        let firstID = trip.stops.min { $0.number < $1.number }?.id
        let chosenID = fromStop ?? firstID
        List {
            Section {
                Button {
                    let stopID = GoFlow.startStopID(selected: fromStop, in: trip)
                    let there = alreadyThere
                    Task { await actions.start(trip.id, stopID, there) }
                } label: {
                    Text("Start Trip").font(IterFont.headline).frame(maxWidth: .infinity, minHeight: IterSize.hitTarget)
                }
                .goProminentButton(flat: flat)
                .listRowInsets(EdgeInsets(top: IterSpace.sm, leading: IterSpace.lg, bottom: IterSpace.sm, trailing: IterSpace.lg))
                .listRowBackground(Color.clear)
            } footer: {
                if let chosen = trip.stops.first(where: { $0.id == chosenID }) {
                    Text(alreadyThere ? "Begins at \(chosen.name), as if you had arrived." : "Starts from \(chosen.name).")
                        .font(IterFont.subheadline)
                }
            }
            Section {
                Toggle("I'm already there", isOn: $alreadyThere)
                    .frame(minHeight: IterSize.hitTarget)
            }
            ForEach(days) { day in
                Section {
                    ForEach(day.stops) { stop in
                        Button { fromStop = stop.id } label: { stopRow(stop, selected: stop.id == chosenID) }
                            .buttonStyle(.plain)
                    }
                } header: {
                    Text("Day \(day.dayIndex + 1) · \(TimeText.day(trip.startDay.adding(days: day.dayIndex)))")
                        .font(IterFont.headline).textCase(nil)
                }
            }
        }
        .navigationTitle(trip.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { back() } label: { Label("Trips", systemImage: "chevron.backward") }
            }
        }
    }

    private func stopRow(_ stop: GoTripChoice.StopChoice, selected: Bool) -> some View {
        HStack(spacing: IterSpace.md) {
            NumberBadge(number: stop.number, size: IterSize.iconLarge + IterSpace.xs)
            Text(stop.name).font(IterFont.body).foregroundStyle(IterColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: IterSpace.sm)
            if let kind = stop.windowKind {
                Image(systemName: LightText.symbol(kind)).foregroundStyle(IterColor.textSecondary).accessibilityLabel(LightText.name(kind))
            }
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? IterColor.accent : IterColor.textTertiary.color)
                .accessibilityLabel(selected ? "Starting here" : "Start here")
        }
        .frame(minHeight: IterSize.hitTarget)
        .contentShape(Rectangle())
    }
}
