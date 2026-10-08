import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// The spot page, pushed from any section (SpotRoute). OWNER: Explore.
/// The detail register of the light panel at full density: overline, big title, status band, headline time, fact chips,
/// then the shared spot sections. Save, Add to Trip, Share and Open in Maps live in the toolbar.
struct SpotPageScreen: View {
    let route: SpotRoute
    @Environment(AppModel.self) private var model
    @State private var page: SpotModel?
    @State private var editing: PlaceRecord?
    @State private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let page {
                content(page)
            } else {
                Color.clear
            }
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .task {
            guard page == nil else { return }
            let made = SpotModel(app: model, spot: route.spot, initialDay: route.day)
            page = made
            await made.start()
        }
        .sheet(item: $editing) { record in SpotEditorSheet(mode: .edit(record)) }
        .confirmationDialog(LightText.deleteTitle(spot.name), isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(LightText.deleteSpot, role: .destructive) { deleteSpot() }
        } message: {
            Text(LightText.deleteMessage(stops: record?.stops?.count ?? 0))
        }
    }

    /// The spot as the store has it now (a user's spot can be edited from this page).
    private var spot: Spot {
        let base = page?.spot ?? route.spot
        guard base.origin == .user, model.store.revision >= 0, let id = UUID(uuidString: base.id), let record = model.store.place(id: id) else { return base }
        return record.spot
    }

    private var record: PlaceRecord? {
        guard spot.origin == .user, model.store.revision >= 0, let id = UUID(uuidString: spot.id) else { return nil }
        return model.store.place(id: id)
    }

    private func deleteSpot() {
        guard let record else { return }
        model.store.deletePlace(record)
        dismiss()
    }

    private func content(_ page: SpotModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IterSpace.xl) {
                header(page)
                VStack(alignment: .leading, spacing: IterSpace.xl) {
                    LookAroundSection(coordinate: spot.coordinate)
                    SpotFactsSection(spot: spot, page: page)
                    LightTimelineSection(page: page)
                    OutlookSection(page: page)
                    HourlyWeatherSection(page: page)
                    WindySection(coordinate: spot.coordinate)
                }
                .environment(\.spotDensity, .panel)
                Color.clear.frame(height: 60)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { WeatherStatusBanner(status: model.weatherStatus) }
        .scrollBounceBehavior(.basedOnSize)
        .onChange(of: spot) { _, new in page.update(spot: new) }
    }

    private func header(_ page: SpotModel) -> some View {
        let next = page.upcomingWindows.first
        return VStack(alignment: .leading, spacing: IterSpace.lg) {
            VStack(alignment: .leading, spacing: IterSpace.xs) {
                Text([LightText.name(spot.category), spot.locality].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(IterColor.textSecondary)
                    .lineLimit(2)
                Text(spot.name)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(IterColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.horizontal, IterSpace.lg)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let _ = context.date
                LightStatusBand(status: LightStatus(window: next?.window, isLoading: page.isLoadingForecast, now: model.now()),
                                showsScore: next == nil)
            }
            if let next {
                LightHeadline(window: next.window, zone: page.timeZone,
                              dayLabel: LightText.relativeDay(next.day, today: page.today),
                              isLoading: page.isLoadingForecast, isTomorrow: next.day != page.today)
                    .padding(.horizontal, IterSpace.lg)
            }
            facts.padding(.horizontal, IterSpace.lg)
        }
    }

    private var facts: some View {
        ScrollView(.horizontal) {
            HStack(spacing: IterSpace.sm) {
                if let minutes = spot.walkInMinutes {
                    FactChip(symbol: "figure.walk", text: String(localized: "\(minutes) min walk", comment: "Fact chip: walk from parking"))
                }
                if let meters = model.location.coordinate.map({ $0.distance(to: spot.coordinate) }) {
                    FactChip(symbol: "location", text: LightText.distance(meters: meters))
                }
                if let elevation = spot.elevationMeters {
                    FactChip(symbol: "mountain.2", text: LightText.elevation(elevation))
                }
                ProvenanceTag(origin: spot.origin)
            }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if spot.origin != .user {
                let saved = model.store.revision >= 0 && model.store.isSaved(spotID: spot.id)
                Button { model.store.setSaved(spot, !saved) } label: {
                    Label(saved ? LightText.saved : LightText.save, systemImage: saved ? "bookmark.fill" : "bookmark")
                }
            }
            AddToTripMenu(spot: spot).labelStyle(.iconOnly)
            ShareLink(item: SpotHeaderView.shareURL(for: spot), subject: Text(spot.name), message: Text(SpotHeaderView.shareMessage(for: spot))) {
                Label(LightText.share, systemImage: "square.and.arrow.up")
            }
            Menu {
                Button { ExploreActions.openInMaps(spot) } label: { Label(LightText.openInMaps, systemImage: "map") }
                Button { ExploreActions.copyCoordinates(spot) } label: {
                    Label(String(localized: "Copy coordinates", comment: "Menu item"), systemImage: "doc.on.doc")
                }
                if let record {
                    Divider()
                    Button { editing = record } label: { Label(LightText.edit, systemImage: "pencil") }
                    Button(role: .destructive) { confirmingDelete = true } label: { Label(LightText.delete, systemImage: "trash") }
                }
            } label: {
                Label(String(localized: "More", comment: "Toolbar menu"), systemImage: "ellipsis")
            }
        }
    }
}
