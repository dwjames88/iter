import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// The list column's second state: the selected place's light panel, replacing the list. A header with Back and the
/// place's position in the list (Up and Down step through the list without leaving), the place, its images, then the
/// spot page's own sections at panel density: Good to know (with the best window), the light timeline (the
/// centrepiece, drawn the full column width), the outlook with its openable days, hourly weather, and the actions.
///
/// Keyboard: the panel takes focus when it opens. Up and Down step to the previous and next place; Escape goes back
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
            Divider()
            WeatherStatusBanner(status: explore.weatherStatus)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: IterSpace.xl) {
                        VStack(alignment: .leading, spacing: IterSpace.lg) {
                            placeHeader
                                .padding(.horizontal, IterGrid.inset)
                            // Edge to edge of the column.
                            SpotImages(spot: spot)
                        }
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
        .background(IterColor.backgroundContent, ignoresSafeAreaEdges: [])
        .layoutGrid()
        .environment(\.spotDensity, .panel)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { explore.selectPrevious(); return .handled }
        .onKeyPress(.downArrow) { explore.selectNext(); return .handled }
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

    // MARK: Header (the column header: Back, position, previous and next)

    private var header: some View {
        HStack(spacing: IterSpace.sm) {
            Button {
                explore.closePanel()
            } label: {
                Label {
                    Text("Places", comment: "Place panel: back to the list of places")
                } icon: {
                    Image(systemName: "chevron.left")
                }
                .font(IterFont.subheadline)
                .foregroundStyle(IterColor.accent)
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Back to places (Esc)", comment: "Tooltip on the place panel's back button"))
            .accessibilityLabel(Text("Back to places", comment: "VoiceOver"))
            Spacer(minLength: 0)
            if let position = explore.panelPosition {
                Text("\(position.index) of \(position.count)", comment: "Place panel header: the place's position in the list, e.g. 3 of 16")
                    .font(IterFont.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(IterColor.textSecondary)
                    .accessibilityLabel(Text("Place \(position.index) of \(position.count)", comment: "VoiceOver"))
            }
            HStack(spacing: IterSpace.xs) {
                Button { explore.selectPrevious() } label: { Image(systemName: "chevron.up") }
                    .disabled(!explore.canSelectPrevious)
                    .help(String(localized: "Previous place (Up Arrow)", comment: "Tooltip"))
                    .accessibilityLabel(Text("Previous place", comment: "VoiceOver"))
                Button { explore.selectNext() } label: { Image(systemName: "chevron.down") }
                    .disabled(!explore.canSelectNext)
                    .help(String(localized: "Next place (Down Arrow)", comment: "Tooltip"))
                    .accessibilityLabel(Text("Next place", comment: "VoiceOver"))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(IterColor.textSecondary)
        }
        .padding(.horizontal, IterGrid.inset)
        .padding(.vertical, IterSpace.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Place

    /// Name and where it is on the leading side; the next event as the large unit on the name's baseline.
    private var placeHeader: some View {
        VStack(alignment: .leading, spacing: IterSpace.xs) {
            HStack(alignment: .firstTextBaseline, spacing: IterSpace.sm) {
                Text(spot.name)
                    .font(IterFont.titleSpot)
                    .foregroundStyle(IterColor.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: IterSpace.sm)
                lightSummary
            }
            // Beneath both the name and the unit, so the locality has the column's full width.
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
            .foregroundStyle(IterColor.textSecondary)
        }
    }

    private var dot: some View {
        Text(verbatim: "·").accessibilityHidden(true)
    }

    /// The next window as the large event unit, "Tomorrow" beside it on the same baseline.
    @ViewBuilder private var lightSummary: some View {
        if let window = row.window {
            HStack(alignment: .firstTextBaseline, spacing: IterSpace.sm) {
                if LightText.isTomorrow(row) {
                    Text("Tomorrow", comment: "Place panel: the next window is tomorrow")
                        .font(IterFont.secondary)
                        .foregroundStyle(IterColor.textSecondary)
                }
                EventScore(window: window, zone: spot.timeZone, timeStyle: .start, variant: .large,
                           isLoading: row.isLoading, isTomorrow: LightText.isTomorrow(row))
            }
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(LightText.rowLight(row) ?? "")
        }
    }

    // MARK: Actions

    private var actions: some View {
        VStack(alignment: .leading, spacing: IterSpace.lg) {
            HStack(spacing: IterSpace.sm) {
                if spot.origin != .user {
                    saveButton
                }
                AddToTripMenu(spot: spot)
                    .menuStyle(.button)
                    .fixedSize()
                Spacer(minLength: 0)
            }
            .controlSize(.regular)
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
            model.store.setSaved(spot, !saved)
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
