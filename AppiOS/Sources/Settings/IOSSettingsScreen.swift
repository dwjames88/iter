import SwiftUI
import UIKit
import IterCore
import IterData
import IterDesign
import IterServices
import IterFeatures

/// Settings on iOS: a grouped form. Weather, Apple Intelligence and About are pushed pages; Location, Updates and General
/// sit inline. `-IterSettingsTab weather|intelligence|about` pushes that page at launch.
struct IOSSettingsScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(ShellState.self) private var shell
    @State private var launchPage: SettingsTab?
    @State private var didLaunch = false
    @AppStorage(AppSettings.temperatureUnit) private var temperatureUnit = "system"
    @AppStorage(AppSettings.defaultSetUpBuffer) private var setUpBuffer = 20

    var body: some View {
        Form {
            Section {
                NavigationLink { WeatherSettingsPage() } label: {
                    row(String(localized: "Weather", comment: "Settings row"), symbol: "cloud.sun",
                        detail: LightText.name(model.weather.settings.primary))
                }
                NavigationLink { IntelligenceSettingsPage() } label: {
                    row(String(localized: "Apple Intelligence", comment: "Settings row"), symbol: "sparkles",
                        detail: IOSSettingsText.intelligenceSummary(model.scout?.availability() ?? .unavailable("")))
                }
            }
            locationSection
            generalSection
            Section {
                LabeledContent {
                    Text(IOSSettingsText.version).monospacedDigit()
                } label: { Text("This build", comment: "Settings row: the installed version") }
            } header: {
                Text("Updates", comment: "Settings section")
            } footer: {
                Text("Updates arrive through TestFlight. There is nothing to check from inside Iter.", comment: "Settings footer: how updates work")
            }
            Section {
                Button {
                    Task { await shell.showWelcome(model.onboarding) }
                } label: {
                    Label(String(localized: "Welcome to Iter", comment: "Help menu item: reopens the first-run guide\nOnboarding: welcome title"), systemImage: "hand.wave")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .foregroundStyle(IterColor.textPrimary)
                NavigationLink { AboutSettingsPage() } label: {
                    row(String(localized: "About Iter", comment: "Settings row"), symbol: "info.circle", detail: IOSSettingsText.version)
                }
            }
        }
        .navigationTitle(String(localized: "Settings", comment: "Screen title"))
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(item: $launchPage) { tab in
            switch tab {
            case .weather: WeatherSettingsPage()
            case .intelligence: IntelligenceSettingsPage()
            case .about: AboutSettingsPage()
            case .general, .updates: EmptyView()
            }
        }
        .onAppear {
            guard !didLaunch else { return }
            didLaunch = true
            #if DEBUG
            IOSKeySaving.applyLaunchSwitch(model.weather)
            #endif
            if let tab = AppLaunch.settingsTab, tab != .general, tab != .updates { launchPage = tab }
        }
    }

    private func row(_ title: String, symbol: String, detail: String) -> some View {
        LabeledContent {
            Text(detail).foregroundStyle(IterColor.textSecondary).lineLimit(1)
        } label: {
            Label(title, systemImage: symbol)
        }
        .frame(minHeight: 44)
    }

    // MARK: Location

    @ViewBuilder private var locationSection: some View {
        let location = model.location
        Section {
            LabeledContent {
                Text(IOSSettingsText.name(location.authorization)).foregroundStyle(IterColor.textSecondary)
            } label: {
                Label(String(localized: "Location access", comment: "Settings row"), systemImage: "location")
            }
            switch location.authorization {
            case .notDetermined:
                Button { location.start() } label: { Text("Allow Location Access", comment: "Button") }
            case .denied, .restricted:
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: { Text("Open Settings", comment: "Button: opens the iOS Settings app") }
            case .authorized:
                EmptyView()
            }
        } header: {
            Text("Location", comment: "Settings section")
        } footer: {
            Text("Iter uses your location only to show spots near you. It is never stored on a server.", comment: "Settings footer: location privacy")
        }
    }

    // MARK: General

    private var generalSection: some View {
        Section {
            Picker(selection: $temperatureUnit) {
                Text("System", comment: "Temperature unit follows the system").tag("system")
                Text("Celsius (°C)", comment: "Temperature unit").tag("celsius")
                Text("Fahrenheit (°F)", comment: "Temperature unit").tag("fahrenheit")
            } label: { Text("Temperature", comment: "Settings field") }
            Stepper(value: $setUpBuffer, in: 0...90, step: 5) {
                Text("Set-up time: \(setUpBuffer) min", comment: "Settings field with its value, e.g. Set-up time: 20 min")
            }
        } header: {
            Text("General", comment: "Settings section")
        } footer: {
            Text("Set-up time is how long before a light window starts that a new stop wants you ready. Each stop can change it.", comment: "Settings footer")
        }
    }
}

// MARK: - Words

enum IOSSettingsText {
    static var version: String { VersionText.current }

    static func name(_ authorization: LocationAuthorization) -> String {
        switch authorization {
        case .notDetermined: String(localized: "Not asked yet", comment: "Location permission state")
        case .denied: String(localized: "Off", comment: "Location permission state: denied")
        case .restricted: String(localized: "Restricted", comment: "Location permission state")
        case .authorized: String(localized: "On while using Iter", comment: "Location permission state")
        }
    }

    static func intelligenceSummary(_ availability: ScoutAvailability) -> String {
        availability == .available ? String(localized: "Ready", comment: "Apple Intelligence state")
                                   : String(localized: "Unavailable", comment: "Apple Intelligence state")
    }

    /// iPhone and iPad wording for why Ask Iter cannot run (the shared helper says "Mac").
    static func unavailable(_ availability: ScoutAvailability) -> (title: String, detail: String, symbol: String) {
        switch availability {
        case .available:
            ("", "", "sparkles")
        case .deviceNotEligible:
            (String(localized: "This device can't run Apple Intelligence", comment: "Ask unavailable title on iOS"),
             String(localized: "Ask Iter needs Apple Intelligence, which this iPhone or iPad doesn't support. Searching places in Explore works without it.",
                    comment: "Ask unavailable detail on iOS: device not eligible"),
             "iphone.slash")
        case .appleIntelligenceNotEnabled:
            (String(localized: "Apple Intelligence is turned off", comment: "Ask unavailable title"),
             String(localized: "Turn on Apple Intelligence in the Settings app, under Apple Intelligence & Siri, to describe the place you want in your own words.",
                    comment: "Ask unavailable detail on iOS: not enabled"),
             "sparkles")
        case .modelNotReady:
            (String(localized: "Apple Intelligence is still downloading", comment: "Ask unavailable title"),
             String(localized: "Ask Iter will be ready when the download finishes. It can take a while the first time.", comment: "Ask unavailable detail: model not ready"),
             "arrow.down.circle")
        case .unavailable:
            (String(localized: "Ask Iter isn't available right now", comment: "Ask unavailable title"),
             String(localized: "Apple Intelligence reported it can't run. Searching places in Explore still works.", comment: "Ask unavailable detail: other reason"),
             "exclamationmark.triangle")
        }
    }
}

// MARK: - Apple Intelligence

private struct IntelligenceSettingsPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        let availability = model.scout?.availability() ?? .unavailable("")
        let notice = IOSSettingsText.unavailable(availability)
        Form {
            Section {
                if availability == .available {
                    Label(String(localized: "Apple Intelligence is ready", comment: "Settings Apple Intelligence status"), systemImage: "checkmark.circle")
                } else {
                    Label(notice.title, systemImage: notice.symbol)
                    if availability == .appleIntelligenceNotEnabled, let url = URL(string: UIApplication.openSettingsURLString) {
                        Button { openURL(url) } label: { Text("Open Settings", comment: "Button: opens the iOS Settings app") }
                    }
                }
            } header: {
                Text("Ask Iter", comment: "Settings section: the Apple Intelligence search in Explore")
            } footer: {
                if availability == .available {
                    Text("Ask Iter, in search, understands your request with the model on this device, then looks up real places in Apple Maps and Iter's curated list.",
                         comment: "Settings: how Ask Iter works on iOS")
                } else {
                    Text(notice.detail)
                }
            }
        }
        .navigationTitle(String(localized: "Apple Intelligence", comment: "Screen title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - About

private struct AboutSettingsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                VStack(spacing: IterSpace.sm) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: IterSize.lightRingLarge)
                        .accessibilityLabel(Text("Iter", comment: "App name"))
                    Text("Iter", comment: "App name").font(IterFont.titleSection)
                    Text(IOSSettingsText.version).foregroundStyle(IterColor.textSecondary)
                    Text("Be in the right place when the light is right.", comment: "Tagline").multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, IterSpace.sm)
            }
            Section {
                WeatherDataSources()
            } header: {
                Text("Data Sources and Attribution", comment: "About: heading for provider credits")
            } footer: {
                Text("Sun and moon times are calculated on this device. Weather is from the source you choose in Settings > Weather: OpenWeather or Windy (contains data from the Windy database). Places and drive times are from Apple Maps, alongside Iter's curated spots.",
                     comment: "About: data sources on iOS")
            }
        }
        .navigationTitle(String(localized: "About", comment: "Screen title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadAttribution() }
    }
}

// MARK: - Weather

private struct WeatherSettingsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let setup = model.weather
        Form {
            Section {
                Picker(selection: Binding(get: { setup.settings.primary }, set: { setup.selectPrimary($0) })) {
                    ForEach(WeatherSetup.providers, id: \.self) { source in Text(LightText.name(source)).tag(source) }
                } label: { Text("Use", comment: "Settings: the forecast source Iter uses") }
                Picker(selection: Binding(get: { setup.settings.fallback }, set: { setup.selectFallback($0) })) {
                    Text("None", comment: "Settings: no fallback forecast source").tag(ForecastSource?.none)
                    ForEach(WeatherSetup.providers.filter { $0 != setup.settings.primary }, id: \.self) { source in
                        Text(LightText.name(source)).tag(Optional(source))
                    }
                } label: { Text("If it fails, try", comment: "Settings: the fallback forecast source") }
                if model.sampleDataEnabled {
                    LabeledContent {
                        SampleDataLabel(style: .inline)
                    } label: { Text("Sample Data", comment: "Settings field") }
                }
            } header: {
                Text("Forecast source", comment: "Settings section")
            } footer: {
                Text("If the first source can't answer, Iter asks the second. A fallback is always named next to the forecast.", comment: "Settings footer")
            }
            ForEach(WeatherSetup.providers, id: \.self) { source in
                if source == .appleWeather {
                    AppleWeatherSection()
                } else {
                    ProviderSection(source: source)
                }
            }
            Section {
                WeatherDataSources()
            } header: { Text("Data Sources and Attribution", comment: "Settings section") }
        }
        .navigationTitle(String(localized: "Weather", comment: "Screen title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
    }

    private func refresh() async {
        let setup = model.weather
        await model.loadAttribution()
        for source in WeatherSetup.providers where setup.status(for: source) == .notChecked {
            if source != .appleWeather, setup.settings.order.contains(source) { await setup.check(source) }
        }
    }
}

/// Apple Weather needs the WeatherKit capability on a paid developer team, which this build does not have. Said plainly.
private struct AppleWeatherSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let status = model.weather.status(for: .appleWeather)
        Section {
            Label {
                Text(status == .notEnabled || status == .notChecked
                     ? String(localized: "Not available in this build", comment: "Settings weather status on iOS")
                     : WeatherSettingsText.status(status, source: .appleWeather).text)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(IterColor.warning)
            }
        } header: {
            Text(LightText.name(.appleWeather))
        } footer: {
            Text("Apple Weather needs a paid Apple Developer team with WeatherKit turned on. This build is signed with a free team, so use OpenWeather or Windy.",
                 comment: "Settings: why Apple Weather is off on iOS")
        }
    }
}

private struct ProviderSection: View {
    let source: ForecastSource
    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @State private var saveError: String?
    @FocusState private var focused: Bool

    private var setup: WeatherSetup { model.weather }

    var body: some View {
        Section {
            statusRow
            keyRows
            if source == .windy { windyChoices }
            if let usage = setup.usage(for: source) { usageRows(usage.calls, usage.cap) }
            if let url = WeatherSettingsText.keyPage(source) {
                Link(destination: url) { Text("Get a key", comment: "Settings: link to a provider's API key page") }
                    .frame(minHeight: 44, alignment: .leading)
            }
        } header: {
            Text(LightText.name(source))
        } footer: {
            Text(WeatherSettingsText.description(source))
        }
    }

    private var statusRow: some View {
        let status = setup.status(for: source)
        let display = WeatherSettingsText.status(status, source: source)
        return Group {
            LabeledContent {
                if let action = display.action {
                    Button { Task { await setup.check(source) } } label: { Text(action) }
                        .buttonStyle(.borderless)
                }
            } label: {
                Label {
                    Text(display.text)
                } icon: {
                    if status == .checking {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: symbol(display.icon)).foregroundStyle(tint(display))
                    }
                }
            }
            if case .failed(let detail) = status, !detail.isEmpty {
                Text(detail).font(IterFont.footnote).foregroundStyle(IterColor.textSecondary)
            }
        }
    }

    private func symbol(_ icon: WeatherSettingsText.Icon) -> String {
        switch icon {
        case .working: "checkmark.circle.fill"
        case .key: "key"
        case .warning: "exclamationmark.triangle.fill"
        case .rejected: "xmark.octagon.fill"
        case .cap: "gauge.with.dots.needle.100percent"
        case .idle: "circle.dashed"
        }
    }

    private func tint(_ display: WeatherSettingsText.Display) -> AnyShapeStyle {
        if display.icon == .rejected { return AnyShapeStyle(IterColor.danger) }
        return display.warns ? AnyShapeStyle(IterColor.warning) : AnyShapeStyle(IterColor.textSecondary)
    }

    // MARK: Key

    @ViewBuilder private var keyRows: some View {
        let origin = setup.keyOrigin(for: source)
        if let origin, origin != .keychain {
            LabeledContent {
                Text(WeatherSettingsText.override(origin, source: source)).foregroundStyle(IterColor.textSecondary)
            } label: { Text("API key", comment: "Settings field") }
        } else {
            if origin == .keychain {
                LabeledContent {
                    Button(role: .destructive) { remove() } label: { Text("Remove", comment: "Button") }
                        .buttonStyle(.borderless)
                } label: {
                    Label(String(localized: "Saved in Keychain", comment: "Settings: the key is in the Keychain"), systemImage: "lock.fill")
                }
            }
            SecureField(text: $draft, prompt: Text(origin == nil ? "Paste your key" : "Paste a new key to replace it",
                                                   comment: "Settings: API key field prompt")) {
                Text("API key", comment: "Settings field")
            }
            .focused($focused)
            .textContentType(.password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .onSubmit(save)
            .frame(minHeight: 44)
            Button(action: save) { Text("Save Key", comment: "Button") }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if let saveError {
                Label(saveError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(IterColor.danger)
            }
        }
    }

    private func save() {
        do {
            try IOSKeySaving.save(draft, for: source, in: setup)
            draft = ""
            focused = false
            saveError = nil
        } catch {
            saveError = String(localized: "Couldn't save the key to your Keychain.", comment: "Settings: Keychain error")
        }
    }

    private func remove() {
        do {
            try setup.removeKey(for: source)
            saveError = nil
        } catch {
            saveError = String(localized: "Couldn't remove the key from your Keychain.", comment: "Settings: Keychain error")
        }
    }

    // MARK: Windy

    @ViewBuilder private var windyChoices: some View {
        Picker(selection: Binding(get: { setup.settings.windyKeyType }, set: { setup.setWindyKeyType($0) })) {
            Text("Testing", comment: "Windy key type").tag(WindyKeyType.testing)
            Text("Professional", comment: "Windy key type").tag(WindyKeyType.professional)
        } label: { Text("Key type", comment: "Settings field") }
        Picker(selection: Binding(get: { setup.settings.windyModelMode }, set: { setup.setWindyModelMode($0) })) {
            Text("Best for the spot", comment: "Windy model choice").tag(WindyModelMode.bestForSpot)
            Text("GFS everywhere", comment: "Windy model choice").tag(WindyModelMode.forceGFS)
        } label: { Text("Model", comment: "Settings field") }
    }

    // MARK: Calls

    @ViewBuilder private func usageRows(_ calls: Int, _ cap: Int) -> some View {
        LabeledContent {
            Text(calls, format: .number).monospacedDigit()
        } label: { Text("Calls today", comment: "Settings field") }
        Stepper(value: Binding(get: { cap }, set: { setup.setCap($0, for: source) }), in: 0...10_000, step: 50) {
            Text("Daily cap: \(cap) calls", comment: "Settings: the daily call allowance of a weather provider, e.g. Daily cap: 800 calls")
        }
    }
}
