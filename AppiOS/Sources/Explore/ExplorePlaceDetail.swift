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
    var drag: SheetDrag?

    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation

    private var spot: Spot { row.spot }
    private var day: LocalDay { model.today(in: spot.timeZone) }

    var body: some View {
        VStack(spacing: 0) {
            header.sheetDrag(drag)
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: IterSpace.xl) {
                    VStack(alignment: .leading, spacing: IterSpace.lg) {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            let _ = context.date
                            LightStatusBand(status: LightStatus(window: row.window, isLoading: row.isLoading, now: model.now()))
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
                    twoUp.padding(.horizontal, IterSpace.lg).id("lower")
                    footer.padding(.horizontal, IterSpace.lg)
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
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar.background(IterColor.backgroundContent) }
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
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(0.8)
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
                RoundGlassButton(systemImage: "xmark", label: String(localized: "Back to places", comment: "VoiceOver: close the place panel")) {
                    explore.closePanel()
                }
            }
            if let position = explore.panelPosition {
                HStack(spacing: IterSpace.sm) {
                    Text("\(position.index) of \(position.count)", comment: "Place panel header: the place's position in the list, e.g. 3 of 16")
                        .font(.subheadline).monospacedDigit()
                        .foregroundStyle(IterColor.textSecondary)
                        .accessibilityLabel(Text("Place \(position.index) of \(position.count)", comment: "VoiceOver"))
                    Spacer()
                    stepButton("chevron.up", String(localized: "Previous place", comment: "VoiceOver"), enabled: explore.canSelectPrevious) { explore.selectPrevious() }
                    stepButton("chevron.down", String(localized: "Next place", comment: "VoiceOver"), enabled: explore.canSelectNext) { explore.selectNext() }
                }
            }
        }
        .padding(.horizontal, IterSpace.lg)
        .padding(.bottom, IterSpace.md)
    }

    private func stepButton(_ symbol: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                .frame(width: 44, height: 36)
                .background(IterColor.backgroundModule, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? IterColor.textPrimary : IterColor.textDisabled)
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

    // MARK: Two-up and footer

    private var isSaved: Bool {
        _ = model.store.revision
        return model.store.isSaved(spotID: spot.id)
    }

    private var twoUp: some View {
        HStack(spacing: IterSpace.md) {
            if spot.origin != .user {
                Button { model.store.setSaved(spot, !isSaved) } label: {
                    Label(isSaved ? LightText.saved : LightText.save, systemImage: isSaved ? "bookmark.fill" : "bookmark")
                }
                .buttonStyle(.plain)
                .labelStyle(TwoUpCardLabelStyle(hint: isSaved ? String(localized: "Tap to remove", comment: "Card hint") : String(localized: "Tap to keep it", comment: "Card hint")))
            }
            AddToTripMenu(spot: spot)
                .buttonStyle(.plain)
                .labelStyle(TwoUpCardLabelStyle(hint: String(localized: "Pick a trip day", comment: "Card hint")))
        }
    }

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

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: IterSpace.md) {
            SpotActionPill(spot: spot, day: row.day ?? day)
            Spacer(minLength: 0)
            AddToTripMenu(spot: spot).labelStyle(PrimaryPillLabelStyle())
        }
        .padding(.horizontal, IterSpace.lg)
        .padding(.bottom, IterSpace.sm)
        .padding(.top, IterSpace.sm)
    }
}

/// Share, Open in Maps, More: the floating glass pill shared by the panel and the spot page.
struct SpotActionPill: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    let spot: Spot
    var day: LocalDay?

    var body: some View {
        ActionPill {
            ShareLink(item: SpotHeaderView.shareURL(for: spot), subject: Text(spot.name), message: Text(SpotHeaderView.shareMessage(for: spot))) {
                PillIconLabel(systemImage: "square.and.arrow.up")
            }
            .accessibilityLabel(LightText.share)
            Button { ExploreActions.openInMaps(spot) } label: { PillIconLabel(systemImage: "map") }
                .accessibilityLabel(LightText.openInMaps)
            Menu {
                if spot.origin != .user {
                    let saved = model.store.revision >= 0 && model.store.isSaved(spotID: spot.id)
                    Button { model.store.setSaved(spot, !saved) } label: {
                        Label(saved ? LightText.saved : LightText.save, systemImage: saved ? "bookmark.fill" : "bookmark")
                    }
                }
                Button { ExploreActions.copyCoordinates(spot) } label: {
                    Label(String(localized: "Copy coordinates", comment: "Menu item"), systemImage: "doc.on.doc")
                }
                if let day {
                    Button { ExploreActions.open(spot, day: day, navigation: navigation) } label: {
                        Label(String(localized: "Show full page", comment: "Menu item"), systemImage: "arrow.right.circle")
                    }
                }
            } label: {
                PillIconLabel(systemImage: "ellipsis")
            }
            .accessibilityLabel(Text("More", comment: "VoiceOver: more actions"))
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
                LightTimelineSection(page: page)
                DayWindowsSection(page: page)
                WhenToGoSection(page: page)
                SkyArcSection(page: page)
                HourlyWeatherSection(page: page)
            }
            SpotFactsSection(spot: spot)
        }
        .task(id: DetailKey(spotID: spot.id, day: day)) {
            page = nil
            let made = SpotModel(app: app, spot: spot, initialDay: day)
            page = made
            await made.start()
        }
    }
}
