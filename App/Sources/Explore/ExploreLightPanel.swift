import SwiftUI
import MapKit
import CoreLocation
import IterCore
import IterData
import IterDesign
import IterFeatures

/// The list column's second state: the selected place's light panel, replacing the list. A header with Back, Share and
/// Close, the place, its images, then the
/// spot page's own sections at panel density: Good to know (with the best window), the light timeline (the
/// centrepiece, drawn the full column width), the outlook with its openable days, hourly weather, and the actions.
///
/// Keyboard: the panel takes focus when it opens. Escape goes back
/// (and leaves Escape to Add Spot mode while that is on).
struct ExploreLightPanel: View {
    @Bindable var explore: ExploreModel
    let row: ExploreRow
    /// Start scrolled to the lower half. Debug and snapshot aid; `-IterPanelScrolled YES` sets it at launch.
    var startsScrolled = AppLaunch.panelScrolled

    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    @FocusState private var isFocused: Bool
    @State private var scrollSettling = false
    /// What Add to Trip last did, shown under the actions for a few seconds.
    @State private var added: PlaceCardActions.Added?

    private var spot: Spot { row.spot }
    /// The panel shows today at the spot; the outlook starts there.
    private var day: LocalDay { model.today(in: spot.timeZone) }
    private static let lowerHalfID = "place-panel-lower-half"

    /// How long after appearing the panel keeps re-scrolling to the lower half as its content grows (launch flag only).
    private static let settleWindow = Duration.seconds(4)
    private static let settleDelay = Duration.milliseconds(100)

    var body: some View {
        VStack(spacing: 0) {
            header
            WeatherStatusBanner(status: explore.weatherStatus)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: IterSpace.xl) {
                        VStack(alignment: .leading, spacing: IterSpace.lg) {
                            placeHeader
                            actionRow
                            lightSummary
                            SpotImages(spot: spot)
                                .clipShape(RoundedRectangle(cornerRadius: PlaceActionMetrics.cornerRadius, style: .continuous))
                        }
                        .padding(.horizontal, IterGrid.inset)
                        .padding(.top, IterGrid.inset - IterSpace.xl)
                        PanelSections(app: model, spot: spot, day: day, lowerHalfID: Self.lowerHalfID)
                            .id(PanelKey(spotID: spot.id, day: day))
                        actions
                            .padding(.horizontal, IterGrid.inset)
                            .padding(.bottom, IterGrid.inset)
                    }
                }
                .id(spot.id)
                // A scrolled-to section keeps one section gap under the header; the first block's padding cancels it at the top.
                .contentMargins(.top, IterSpace.xl, for: .scrollContent)
                .scrollBounceBehavior(.basedOnSize)
                .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentSize.height }) { _, _ in
                    // The forecast and sections load and grow the content; keep the lower half at the top meanwhile.
                    guard scrollSettling else { return }
                    Task {
                        try? await Task.sleep(for: Self.settleDelay)
                        proxy.scrollTo(Self.lowerHalfID, anchor: .top)
                    }
                }
                .task(id: spot.id) {
                    guard startsScrolled else { return }
                    scrollSettling = true
                    try? await Task.sleep(for: Self.settleDelay)
                    proxy.scrollTo(Self.lowerHalfID, anchor: .top)
                    try? await Task.sleep(for: Self.settleWindow)
                    scrollSettling = false
                }
            }
        }
        .frame(maxHeight: .infinity)
        .layoutGrid()
        .environment(\.spotDensity, .panel)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.escape) {
            // Add Spot mode owns Escape (its banner's Cancel), as sheets do.
            guard !explore.isAddingSpot else { return .ignored }
            explore.closePanel()
            return .handled
        }
        .onAppear { isFocused = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Place panel for \(spot.name)", comment: "VoiceOver"))
    }

    // MARK: Header (as a Maps place card: Back leading; Share and Close trailing, round glass buttons)

    private var header: some View {
        PlaceCardHeader(spot: spot, onBack: { explore.closePanel() }, onClose: { explore.select(nil) })
    }

    // MARK: Place

    /// Name, where it is, and the next event: centred, as a Maps place card's header.
    private var placeHeader: some View {
        VStack(spacing: IterSpace.xs) {
            Text(spot.name)
                .font(.title.bold())
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: IterSpace.xs) {
                let hasDistance = explore.hasLocation && row.distanceMeters != nil
                if !spot.locality.isEmpty {
                    Text(spot.locality).lineLimit(1)
                }
                if hasDistance, let meters = row.distanceMeters {
                    if !spot.locality.isEmpty { dot }
                    Text(LightText.distance(meters: meters)).lineLimit(1).fixedSize()
                }
                if !spot.locality.isEmpty || hasDistance { dot }
                ProvenanceTag(origin: spot.origin)
                    .fixedSize()
                    .layoutPriority(1)
            }
            .font(IterFont.secondary)
            .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var dot: some View {
        Text(verbatim: "·").accessibilityHidden(true)
    }

    /// The next window as a Maps-style feature row under the actions.
    @ViewBuilder private var lightSummary: some View {
        if let window = row.window {
            LightWindowRow(window: window, zone: spot.timeZone,
                           day: LightText.isTomorrow(row) ? String(localized: "Tomorrow", comment: "Place panel: the next window is tomorrow")
                                                          : String(localized: "Today", comment: "Place panel: the next window is today"),
                           isLoading: row.isLoading)
        }
    }

    // MARK: Actions

    /// The card's action row, as in Maps: Add to Trip is the main action; Save and Open in Maps beside it.
    private var actionRow: some View {
        VStack(spacing: IterSpace.sm) {
            HStack(spacing: IterSpace.sm) {
                AddToTripMenu(spot: spot, label: added == nil ? String(localized: "Add to Trip", comment: "Button")
                                                              : String(localized: "Added", comment: "Place card: Add to Trip just worked"),
                              onAdded: didAdd)
                    .menuStyle(.button)
                    .menuIndicator(.hidden)
                    .placeAction(isProminent: true)
                if spot.origin != .user {
                    saveButton.placeAction()
                }
                Button { cardActions.openInMaps(spot) } label: {
                    Label(LightText.openInMaps, systemImage: "map")
                }
                .placeAction()
                .help(String(localized: "Open this location in Apple Maps", comment: "Help"))
            }
            if let added {
                HStack(spacing: IterSpace.xs) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(IterColor.accentText)
                    Text(added.message).lineLimit(1)
                    Button(String(localized: "Show Trip", comment: "Place card: open the trip the spot was just added to")) {
                        navigation.show(.trip(added.tripID))
                    }
                    .linkButtonStyle()
                    .foregroundStyle(IterColor.accentText)
                }
                .font(IterFont.secondary)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .transition(.opacity)
                .accessibilityElement(children: .combine)
            }
        }
        .animation(.snappy(duration: 0.2), value: added)
        .task(id: added) {
            guard added != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            added = nil
        }
    }

    private func didAdd(_ result: PlaceCardActions.Added) { added = result }

    private var cardActions: PlaceCardActions {
        PlaceCardActions(store: model.store, tomorrow: { [model] in model.today(in: $0.timeZone).adding(days: 1) },
                         openInMaps: ExploreActions.openInMaps)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: IterSpace.lg) {
            VStack(alignment: .leading, spacing: IterSpace.sm) {
                if let forecast = model.forecasts.state(for: spot.coordinate).forecast {
                    ForecastSourceLine(info: ForecastSourceInfo(forecast))
                        .font(IterFont.secondary)
                }
                Button {
                    ExploreActions.open(spot, day: row.day ?? day, navigation: navigation)
                } label: {
                    Text("Show Full Page", comment: "Place panel: open the spot's full page")
                        .font(IterFont.secondary)
                }
                .linkButtonStyle()
                .help(String(localized: "Open the spot page", comment: "Tooltip"))
            }
        }
    }

    private var saveButton: some View {
        let saved = isSaved
        return Button {
            cardActions.toggleSaved(spot)
        } label: {
            if saved {
                Label(String(localized: "Saved", comment: "Place panel: the spot is saved"), systemImage: "bookmark.fill")
            } else {
                Label(String(localized: "Save", comment: "Place panel: save the spot"), systemImage: "bookmark")
            }
        }
        .help(saved ? String(localized: "Remove from Saved", comment: "Tooltip") : String(localized: "Save this spot", comment: "Tooltip"))
    }

    private var isSaved: Bool {
        _ = model.store.revision
        return model.store.isSaved(spotID: spot.id)
    }
}

private struct PanelKey: Hashable { let spotID: String; let day: LocalDay }

/// The spot page's own sections at panel density. Owns its `SpotModel`; keyed by spot and day so a new selection (Up
/// or Down) starts a new model.
private struct PanelSections: View {
    let app: AppModel
    let spot: Spot
    let day: LocalDay
    let lowerHalfID: String
    /// Built once per (spot, day) in `.task(id:)`, never in `init` (an `init` runs on every parent body pass).
    @State private var page: SpotModel?

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.xl) {
            if let page {
                SpotFactsSection(spot: spot, page: page)
                LightTimelineSection(page: page)
                OutlookSection(page: page)
                    .id(lowerHalfID)
                HourlyWeatherSection(page: page)
            } else {
                SpotFactsSection(spot: spot)
            }
        }
        .task(id: PanelKey(spotID: spot.id, day: day)) {
            page = nil
            let made = SpotModel(app: app, spot: spot, initialDay: day)
            page = made
            await made.start()
            if AppLaunch.outlookOpen { made.toggleDayExpanded(day.adding(days: 1)) }
        }
    }
}
