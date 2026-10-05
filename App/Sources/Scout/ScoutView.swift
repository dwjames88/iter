import SwiftUI
import MapKit
import IterCore
import IterData
import IterDesign
import IterServices
import IterFeatures

/// Scout (plan P3.7): describe a place in your own words; results land as map objects next to a list.
/// Availability comes first, progress is real, and the model's wording is labelled as the scout's.
struct ScoutView: View {
    @Environment(AppModel.self) private var app
    private let injected: ScoutModel?

    init() { injected = nil }
    init(model: ScoutModel) { injected = model }

    var body: some View {
        ScoutScreen(model: injected ?? ScoutModel.session(for: app))
    }
}

private struct ScoutScreen: View {
    @Bindable var model: ScoutModel
    @Environment(AppModel.self) private var app
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.openURL) private var openURL
    @FocusState private var fieldFocused: Bool

    private static let systemSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")

    var body: some View {
        VStack(spacing: 0) {
            if model.availability == .available { requestBar; Divider() }
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle(Text("Scout", comment: "Section title"))
        .snapshotOpaqueBackground()
    }

    // MARK: Request

    private var requestBar: some View {
        HStack(alignment: .firstTextBaseline, spacing: IterSpace.sm) {
            TextField(LightText.scoutPrompt, text: $model.request, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .focused($fieldFocused)
                .onSubmit { model.run() }
                .disabled(model.isRunning)
                .accessibilityLabel(Text("Describe the place you are looking for", comment: "VoiceOver label"))
            if model.isRunning {
                Button(role: .cancel) { model.cancel() } label: {
                    Text("Cancel", comment: "Button: stop the scout")
                }
                .keyboardShortcut(.cancelAction)
                .controlSize(.large)
                .help(Text("Stop looking", comment: "Tooltip"))
            } else {
                Button { model.run() } label: {
                    Text("Find Places", comment: "Button: run the scout")
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.canRun)
                .help(Text("Ask Scout to find places", comment: "Tooltip"))
            }
        }
        .padding(IterSpace.lg)
    }

    // MARK: States

    @ViewBuilder private var content: some View {
        if model.availability != .available, !model.isRunning, !hasResults {
            unavailable(LightText.scoutUnavailable(model.availability), openSettings: model.availability == .appleIntelligenceNotEnabled)
        } else {
            switch model.state {
            case .idle: idle
            case .running(let stage, let started): running(stage: stage, started: started)
            case .results(let found): results(found)
            case .failed(let failure): failed(failure)
            }
        }
    }

    private var hasResults: Bool {
        if case .results = model.state { return true }
        return false
    }

    private var idle: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IterSpace.lg) {
                Text("Describe the scenery, the area and the light. Scout finds real places and shows how the light looks at each.",
                     comment: "Scout idle explanation")
                    .font(IterFont.body)
                    .foregroundStyle(IterColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: IterSpace.sm) {
                    Text("Try", comment: "Heading above scout example requests")
                        .font(IterFont.captionStrong)
                        .foregroundStyle(IterColor.textSecondary)
                    ForEach(LightText.scoutExamples, id: \.self) { example in
                        Button {
                            model.request = example
                            model.run()
                        } label: {
                            HStack {
                                Image(systemName: "text.magnifyingglass").foregroundStyle(IterColor.accent)
                                Text(example).font(IterFont.body).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(IterSpace.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(IterColor.backgroundControl, in: RoundedRectangle(cornerRadius: IterRadius.card, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: IterRadius.card, style: .continuous)
                                .strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline))
                            .contentShape(RoundedRectangle(cornerRadius: IterRadius.card, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(LightText.scoutSourceLine)
                    .font(IterFont.caption)
                    .foregroundStyle(IterColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(IterSpace.lg)
            .frame(maxWidth: IterSize.listMax + IterSize.listMin, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func running(stage: ScoutProgress, started: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let _ = context.date
            let elapsed = app.now().timeIntervalSince(started)
            VStack(spacing: IterSpace.lg) {
                Spacer(minLength: 0)
                VStack(spacing: IterSpace.md) {
                    ProgressView().controlSize(.large)
                    Text(LightText.scoutStage(stage))
                        .font(IterFont.headline)
                    HStack(spacing: IterSpace.xs) {
                        ForEach(0..<LightText.scoutStageCount, id: \.self) { i in
                            Capsule()
                                .fill(i <= LightText.scoutStageIndex(stage) ? IterColor.accent : IterColor.separator)
                                .frame(width: IterSpace.xl, height: IterSpace.xs)
                        }
                    }
                    .accessibilityHidden(true)
                    Text("Step \(LightText.scoutStageIndex(stage) + 1) of \(LightText.scoutStageCount)", comment: "Scout progress, e.g. Step 2 of 4")
                        .font(IterFont.caption)
                        .foregroundStyle(IterColor.textSecondary)
                    if elapsed >= Self.slowAfter {
                        VStack(spacing: IterSpace.xxs) {
                            Text(LightText.scoutElapsed(elapsed))
                                .font(IterFont.time)
                                .foregroundStyle(IterColor.textSecondary)
                            Text(LightText.scoutSlow)
                                .font(IterFont.caption)
                                .foregroundStyle(IterColor.textSecondary)
                        }
                    }
                }
                Button { model.cancel() } label: { Text("Cancel", comment: "Button: stop the scout") }
                    .controlSize(.large)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(LightText.scoutStage(stage)))
        }
    }

    private static let slowAfter: TimeInterval = 10

    private func unavailable(_ notice: LightText.ScoutNotice, openSettings: Bool = false, retry: Bool = false) -> some View {
        ContentUnavailableView {
            Label(notice.title, systemImage: notice.symbol)
        } description: {
            Text(notice.detail)
        } actions: {
            if retry {
                Button { model.run() } label: { Text("Try Again", comment: "Button") }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canRun)
            }
            if openSettings, let url = Self.systemSettingsURL {
                Button { openURL(url) } label: { Text("Open System Settings", comment: "Button: opens Apple Intelligence & Siri settings") }
                    .buttonStyle(.borderedProminent)
            }
            Button { navigation.show(.explore) } label: {
                Text("Search Places in Explore", comment: "Button: use ordinary place search instead of Scout")
            }
        }
    }

    private func failed(_ failure: ScoutFailure) -> some View {
        if case .unavailable(let a) = failure {
            return unavailable(LightText.scoutUnavailable(a), openSettings: a == .appleIntelligenceNotEnabled)
        }
        return unavailable(LightText.scoutFailure(failure), retry: true)
    }

    // MARK: Results

    private func results(_ found: [ScoutSuggestion]) -> some View {
        ScoutResultsView(model: model, found: found)
    }
}

/// The result list and map, side by side.
private struct ScoutResultsView: View {
    let model: ScoutModel
    let found: [ScoutSuggestion]
    @Environment(AppModel.self) private var app
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.renderMode) private var renderMode
    @State private var selection: String?
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        HStack(spacing: 0) {
            list
                .frame(minWidth: IterSize.listMin, idealWidth: IterSize.listIdeal, maxWidth: IterSize.listMax)
            Divider()
            map
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { if selection == nil { selection = found.first?.id } }
    }

    private var list: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: IterSpace.sm) {
                Text("\(found.count) places for \u{201C}\(model.submittedRequest)\u{201D}", comment: "Scout results header, with the request")
                    .font(IterFont.subheadline)
                    .foregroundStyle(IterColor.textSecondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if app.sampleDataEnabled { SampleDataLabel(style: .inline) }
            }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, IterSpace.lg)
                .padding(.vertical, IterSpace.sm)
            List(found, selection: $selection) { suggestion in
                ScoutResultRow(model: model, suggestion: suggestion)
                    .tag(suggestion.id)
                    .listRowSeparator(.visible)
            }
            .listStyle(.inset)
            .contextMenu(forSelectionType: String.self) { _ in } primaryAction: { ids in
                if let id = ids.first, let s = found.first(where: { $0.id == id }) { navigation.open(SpotRoute(spot: s.spot)) }
            }
            Divider()
            VStack(alignment: .leading, spacing: IterSpace.xs) {
                Text(LightText.scoutSourceLine)
                    .font(IterFont.caption)
                    .foregroundStyle(IterColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                WeatherAttributionView()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(IterSpace.md)
        }
    }

    @ViewBuilder private var map: some View {
        if renderMode == .snapshot {
            MapStandIn(pins: found.map { .init(id: $0.id, coordinate: $0.spot.coordinate, label: $0.spot.name, selected: $0.id == selection) })
        } else {
            Map(position: $position, selection: $selection) {
                ForEach(found) { s in
                    Marker(s.spot.name, systemImage: LightText.symbol(s.spot.category), coordinate: CLLocationCoordinate2D(latitude: s.spot.coordinate.latitude, longitude: s.spot.coordinate.longitude))
                        .tint(IterColor.accent)
                        .tag(s.id)
                }
            }
            .mapControls { MapZoomStepper(); MapCompass() }
            .onChange(of: selection) { _, id in
                guard let s = found.first(where: { $0.id == id }) else { return }
                withAnimation { position = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: s.spot.coordinate.latitude, longitude: s.spot.coordinate.longitude),
                                                                     span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1))) }
            }
            .onAppear {
                if let region = GeoRegion.enclosing(found.map(\.spot.coordinate), padding: 0.4, minimumDelta: 0.2) {
                    position = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: region.center.latitude, longitude: region.center.longitude),
                                                         span: MKCoordinateSpan(latitudeDelta: region.latitudeDelta, longitudeDelta: region.longitudeDelta)))
                }
            }
        }
    }
}

private struct ScoutResultRow: View {
    let model: ScoutModel
    let suggestion: ScoutSuggestion
    @Environment(AppModel.self) private var app
    @Environment(AppNavigation.self) private var navigation

    private var spot: Spot { suggestion.spot }
    private var isSaved: Bool { _ = app.store.revision; return app.store.isSaved(spotID: spot.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(spot.name).font(IterFont.headline)
                    if !spot.locality.isEmpty {
                        Text(spot.locality).font(IterFont.subheadline).foregroundStyle(IterColor.textSecondary)
                    }
                }
                Spacer(minLength: IterSpace.sm)
                ProvenanceTag(origin: suggestion.provenance == .curated ? .curated : .appleMaps)
            }
            HStack(spacing: IterSpace.md) {
                light
                if let drive = suggestion.driveSeconds {
                    Label(LightText.scoutDrive(drive), systemImage: "car")
                        .font(IterFont.caption)
                        .foregroundStyle(IterColor.textSecondary)
                }
            }
            if !suggestion.why.isEmpty {
                VStack(alignment: .leading, spacing: IterSpace.xxs) {
                    Label(LightText.scoutNoteLabel, systemImage: "sparkles")
                        .font(IterFont.captionStrong)
                        .foregroundStyle(IterColor.textSecondary)
                    Text(suggestion.why)
                        .font(IterFont.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: IterSpace.sm) {
                Button { navigation.open(SpotRoute(spot: spot)) } label: { Text("Open", comment: "Button: open a spot") }
                Button { app.store.setSaved(spot, !isSaved) } label: {
                    Label(isSaved ? String(localized: "Saved", comment: "Button state: spot is saved") : String(localized: "Save", comment: "Button: save a spot"),
                          systemImage: isSaved ? "bookmark.fill" : "bookmark")
                }
                .help(isSaved ? Text("Remove from Saved", comment: "Tooltip") : Text("Save this spot", comment: "Tooltip"))
                AddToTripMenu(spot: spot)
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .menuStyle(.button)
        }
        .padding(.vertical, IterSpace.sm)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var light: some View {
        switch model.light(for: suggestion) {
        case .scored(let day, let window):
            HStack(spacing: IterSpace.sm) {
                LightBadge(window: window, style: .compact)
                Text(TimeText.day(day)).font(IterFont.caption).foregroundStyle(IterColor.textSecondary)
            }
        case .noForecast(let reason):
            HStack(spacing: IterSpace.sm) {
                NoForecastRing(diameter: IterSize.iconMedium)
                Text(LightText.noForecastShort(reason)).font(IterFont.caption).foregroundStyle(IterColor.textSecondary)
            }
            .help(LightText.noForecastReason(reason))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(LightText.noForecastReason(reason))
        case .loading:
            HStack(spacing: IterSpace.sm) {
                ProgressView().controlSize(.small)
                Text("Checking the forecast", comment: "Scout result: forecast loading").font(IterFont.caption).foregroundStyle(IterColor.textSecondary)
            }
        }
    }
}
