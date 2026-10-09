import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// The light panel inside the sheet (Flighty detail layout at 390 pt): overline, big title, round close, "3 of 16" with
/// previous and next, the status band, the headline time, fact chips, then the shared spot sections at panel density,
/// two-up cards, and a floating action pill with one accent primary.
struct ExplorePlaceDetail: View {
    @Bindable var explore: ExploreModel
    let row: ExploreRow

    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation

    private var spot: Spot { row.spot }
    private var day: LocalDay { model.today(in: spot.timeZone) }
    /// Pushed on the phone's Explore stack: the title, previous, next and Close are the navigation bar's.
    var usesNavigationBar = false

    var body: some View {
        if usesNavigationBar {
            detail
                .navigationTitle(spot.name)
                .navigationSubtitle(overline)
                .navigationBarTitleDisplayMode(.large)
                .navigationBarBackButtonHidden()
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { explore.selectPrevious() } label: {
                            Label(String(localized: "Previous place", comment: "VoiceOver"), systemImage: "chevron.up")
                        }
                        .disabled(!explore.canSelectPrevious)
                        Button { explore.selectNext() } label: {
                            Label(String(localized: "Next place", comment: "VoiceOver"), systemImage: "chevron.down")
                        }
                        .disabled(!explore.canSelectNext)
                    }
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .close) { explore.closePanel() }
                    }
                }
        } else {
            detail
        }
    }

    private var detail: some View {
        VStack(spacing: 0) {
            if !usesNavigationBar { header }
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: IterSpace.xl) {
                    VStack(alignment: .leading, spacing: IterSpace.lg) {
                        actionRow.padding(.horizontal, IterSpace.lg)
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            let _ = context.date
                            LightStatusBand(status: LightStatus(window: row.window, isLoading: row.isLoading, now: model.now()),
                                            showsScore: row.window == nil)
                        }
                        if let window = row.window {
                            LightHeadline(window: window, zone: spot.timeZone,
                                          dayLabel: LightText.isTomorrow(row) ? String(localized: "Tomorrow", comment: "Panel: the window is tomorrow") : nil,
                                          isLoading: row.isLoading, isTomorrow: LightText.isTomorrow(row))
                                .padding(.horizontal, IterSpace.lg)
                        }
                        facts.padding(.horizontal, IterSpace.lg)
                    }
                    SpotImages(spot: spot)
                    DetailSections(app: model, spot: spot, day: day)
                        .id(DetailKey(spotID: spot.id, day: day))
                    footer.padding(.horizontal, IterSpace.lg).id("lower")
                    Color.clear.frame(height: IterSpace.lg)
                }
            }
            .id(spot.id)
            .scrollBounceBehavior(.basedOnSize)
            .task(id: spot.id) {
                guard AppLaunch.panelScrolled else { return }
                try? await Task.sleep(for: .seconds(3))
                proxy.scrollTo("lower", anchor: .center)
            }
            }
        }
        .environment(\.spotDensity, .panel)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Place panel for \(spot.name)", comment: "VoiceOver"))
    }

    // MARK: Header

    private var overline: String {
        [LightText.name(spot.category), spot.locality].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            HStack(alignment: .top, spacing: IterSpace.sm) {
                VStack(alignment: .leading, spacing: IterSpace.xs) {
                    Text(overline)
                        .font(.subheadline)
                        .foregroundStyle(IterColor.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(spot.name)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(IterColor.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: IterSpace.sm)
                Button { explore.closePanel() } label: {
                    Label(String(localized: "Back to places", comment: "VoiceOver: close the place panel"), systemImage: "xmark")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
            }
            if let position = explore.panelPosition {
                HStack(spacing: IterSpace.sm) {
                    Text("\(position.index) of \(position.count)", comment: "Place panel header: the place's position in the list, e.g. 3 of 16")
                        .font(.subheadline).monospacedDigit()
                        .foregroundStyle(IterColor.textSecondary)
                        .accessibilityLabel(Text("Place \(position.index) of \(position.count)", comment: "VoiceOver"))
                    Spacer()
                    GlassEffectContainer(spacing: IterSpace.sm) {
                        HStack(spacing: IterSpace.sm) {
                            stepButton("chevron.up", String(localized: "Previous place", comment: "VoiceOver"), enabled: explore.canSelectPrevious) { explore.selectPrevious() }
                            stepButton("chevron.down", String(localized: "Next place", comment: "VoiceOver"), enabled: explore.canSelectNext) { explore.selectNext() }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, IterSpace.lg)
        .padding(.bottom, IterSpace.md)
    }

    private func stepButton(_ symbol: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: symbol)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    // MARK: Facts

    private var facts: some View {
        ScrollView(.horizontal) {
            HStack(spacing: IterSpace.sm) {
                if let minutes = spot.walkInMinutes {
                    FactChip(symbol: "figure.walk", text: String(localized: "\(minutes) min walk", comment: "Fact chip: walk from parking"))
                }
                if explore.hasLocation, let meters = row.distanceMeters {
                    FactChip(symbol: "location", text: LightText.distance(meters: meters))
                }
                if let seconds = row.driveSeconds {
                    FactChip(symbol: "car", text: TimeText.duration(seconds))
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

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            if let forecast = model.forecasts.state(for: spot.coordinate).forecast {
                ForecastSourceLine(info: ForecastSourceInfo(forecast)).font(.footnote)
            }
            Button {
                ExploreActions.open(spot, day: row.day ?? day, navigation: navigation)
            } label: {
                HStack {
                    Text("Show full page", comment: "Place panel: open the spot's full page").font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(IterColor.accent)
        }
    }

    // MARK: Actions

    /// The place card's action row, as in Maps: Add to Trip is the main action; Save, Share and More beside it.
    private var actionRow: some View {
        HStack(spacing: IterSpace.sm) {
            AddToTripMenu(spot: spot)
                .placeAction(isProminent: true)
            if spot.origin != .user {
                let saved = model.store.revision >= 0 && model.store.isSaved(spotID: spot.id)
                Button { model.store.setSaved(spot, !saved) } label: {
                    Label(saved ? LightText.saved : LightText.save, systemImage: saved ? "bookmark.fill" : "bookmark")
                }
                .placeAction()
            }
            ShareLink(item: SpotHeaderView.shareURL(for: spot), subject: Text(spot.name), message: Text(SpotHeaderView.shareMessage(for: spot))) {
                Label(LightText.share, systemImage: "square.and.arrow.up")
            }
            .placeAction()
            Menu {
                Button { ExploreActions.openInMaps(spot) } label: { Label(LightText.openInMaps, systemImage: "map") }
                Button { ExploreActions.copyCoordinates(spot) } label: {
                    Label(String(localized: "Copy Coordinates", comment: "Menu item"), systemImage: "doc.on.doc")
                }
                Button { ExploreActions.open(spot, day: row.day ?? day, navigation: navigation) } label: {
                    Label(String(localized: "Show Full Page", comment: "Menu item"), systemImage: "arrow.right.circle")
                }
            } label: {
                Label(String(localized: "More", comment: "Place card action: more actions"), systemImage: "ellipsis")
            }
            .placeAction()
        }
    }
}

private struct DetailKey: Hashable { let spotID: String; let day: LocalDay }

/// The spot page's sections at panel density, for the selected place. Owns its `SpotModel`, keyed by spot and day.
private struct DetailSections: View {
    let app: AppModel
    let spot: Spot
    let day: LocalDay
    @State private var page: SpotModel?

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.xl) {
            if let page {
                SpotFactsSection(spot: spot, page: page)
                LightTimelineSection(page: page)
                OutlookSection(page: page)
                HourlyWeatherSection(page: page)
            } else {
                SpotFactsSection(spot: spot)
            }
        }
        .task(id: DetailKey(spotID: spot.id, day: day)) {
            page = nil
            let made = SpotModel(app: app, spot: spot, initialDay: day)
            page = made
            await made.start()
        }
    }
}
