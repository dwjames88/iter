import SwiftUI
import IterCore
import IterData
import IterDesign
import IterServices
import IterFeatures

enum SettingsTab: Hashable { case general, weather, intelligence, about }

/// The Settings window: General, Weather, Apple Intelligence, About.
struct SettingsView: View {
    @State private var tab: SettingsTab

    init(initialTab: SettingsTab = AppLaunch.settingsTab ?? .general) {
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettingsPane()
                .tabItem { Label(String(localized: "General", comment: "Settings tab"), systemImage: "gearshape") }
                .tag(SettingsTab.general)
            WeatherSettingsPane()
                .tabItem { Label(String(localized: "Weather", comment: "Settings tab"), systemImage: "cloud.sun") }
                .tag(SettingsTab.weather)
            IntelligenceSettingsPane()
                .tabItem { Label(String(localized: "Apple Intelligence", comment: "Settings tab"), systemImage: "sparkles") }
                .tag(SettingsTab.intelligence)
            AboutSettingsPane()
                .tabItem { Label(String(localized: "About", comment: "Settings tab"), systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .scenePadding()
        .frame(width: IterSize.listMax + IterSpace.xxl)
        .snapshotOpaqueBackground()
    }
}

// MARK: - General

private struct GeneralSettingsPane: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKeys.preferredIntent) private var intentRaw = ""
    @AppStorage(AppSettings.temperatureUnit) private var temperatureUnit = "system"
    @AppStorage(AppSettings.defaultSetUpBuffer) private var setUpBuffer = 20

    var body: some View {
        Form {
            Section {
                Picker(selection: $intentRaw) {
                    Text("Each Spot's Best", comment: "Settings: show each spot's own best light").tag("")
                    Divider()
                    ForEach(LightIntent.allCases) { (intent: LightIntent) in
                        Label(LightText.name(intent), systemImage: LightText.symbol(intent)).tag(intent.rawValue)
                    }
                } label: { Text("Show light for", comment: "Settings field") }
                .onChange(of: intentRaw) { _, new in model.preferredIntent = LightIntent(rawValue: new) }
            } footer: {
                Text("Which light the scores show on Explore, Saved and in lists. A spot's page always shows every window.", comment: "Settings footer")
            }
            Section {
                Picker(selection: $temperatureUnit) {
                    Text("System", comment: "Temperature unit follows the system").tag("system")
                    Text("Celsius (°C)", comment: "Temperature unit").tag("celsius")
                    Text("Fahrenheit (°F)", comment: "Temperature unit").tag("fahrenheit")
                } label: { Text("Temperature", comment: "Settings field") }
            }
            Section {
                Stepper(value: $setUpBuffer, in: 0...90, step: 5) {
                    LabeledContent {
                        Text("\(setUpBuffer) min", comment: "Minutes, e.g. 20 min").monospacedDigit()
                    } label: { Text("Set-up time before a window", comment: "Settings field") }
                }
            } footer: {
                Text("How long before a light window starts that a new stop wants you set up. Each stop can change it.", comment: "Settings footer")
            }
        }
        .formStyle(.grouped)
        .onAppear { model.preferredIntent = LightIntent(rawValue: intentRaw) }
    }
}

// MARK: - Apple Intelligence

private struct IntelligenceSettingsPane: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        let availability = model.scout?.availability() ?? .unavailable("")
        Form {
            Section {
                if availability == .available {
                    Label {
                        Text("Apple Intelligence is ready", comment: "Settings Apple Intelligence status")
                    } icon: { Image(systemName: "checkmark.circle") }
                    Text("Scout understands your request with the model on this Mac, then looks up real places in Apple Maps and Iter's curated list.",
                         comment: "Settings: how Scout works")
                        .font(IterFont.caption).foregroundStyle(IterColor.textSecondary)
                } else {
                    let notice = LightText.scoutUnavailable(availability)
                    Label(notice.title, systemImage: notice.symbol)
                    Text(notice.detail).font(IterFont.caption).foregroundStyle(IterColor.textSecondary)
                    if availability == .appleIntelligenceNotEnabled, let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") {
                        Button { openURL(url) } label: { Text("Open System Settings", comment: "Button") }
                    }
                }
            } header: { Text("Scout", comment: "Settings section") }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

private struct AboutSettingsPane: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(spacing: IterSpace.md) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(height: IterSize.lightRingLarge)
                .accessibilityLabel(Text("Iter", comment: "App name"))
            Text("Iter", comment: "App name").font(IterFont.titleSection)
            Text(version).font(IterFont.caption).foregroundStyle(IterColor.textSecondary)
            Text("Be in the right place when the light is right.", comment: "Tagline")
                .font(IterFont.body)
            Text("Sun and moon times are calculated on this Mac. Weather is from the source you choose in Settings ▸ Weather: Apple Weather, OpenWeather or Windy (contains data from the Windy database). Places and drive times are from Apple Maps, alongside Iter's curated spots.",
                 comment: "About: data sources")
                .font(IterFont.caption)
                .foregroundStyle(IterColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: IterSize.listIdeal)
            VStack(alignment: .leading, spacing: IterSpace.xs) {
                Text("Data Sources and Attribution", comment: "About: heading for provider credits")
                    .font(IterFont.caption).foregroundStyle(IterColor.textSecondary)
                WeatherDataSources()
            }
            .frame(maxWidth: IterSize.listIdeal, alignment: .leading)
            .task { await model.loadAttribution() }
        }
        .padding(IterSpace.xl)
        .frame(maxWidth: .infinity)
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return String(localized: "Version \(short) (\(build))", comment: "About: version and build")
    }
}
