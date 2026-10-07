import SwiftUI
import IterCore
import IterDesign
import IterServices
import IterFeatures

/// Settings ▸ Weather: which forecast source Iter uses, a fallback, and one section per provider with its status,
/// key and call allowance. A key is never shown; the field only accepts one.
struct WeatherSettingsPane: View {
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
                    Divider()
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
                VStack(alignment: .leading) {
                    Text("If the first source can't answer, Iter asks the second. A fallback is always named next to the forecast.", comment: "Settings footer")
                    if model.sampleDataEnabled {
                        Text("Scores use made-up weather, not a real forecast. Turn this off in the Debug menu.", comment: "Settings: sample data explanation")
                    }
                }
            }
            ForEach(WeatherSetup.providers, id: \.self) { source in
                WeatherProviderSection(source: source)
            }
            if setup.status(for: .appleWeather) == .notEnabled { enableSteps }
            attribution
        }
        .formStyle(.grouped)
        .task { await refresh() }
    }

    /// Loads attribution and checks what is free or already in use: Apple Weather always, a keyed provider only when it is chosen and has a key.
    private func refresh() async {
        let setup = model.weather
        await model.loadAttribution()
        for source in WeatherSetup.providers where setup.status(for: source) == .notChecked {
            if source == .appleWeather || setup.settings.order.contains(source) { await setup.check(source) }
        }
    }

    // MARK: Apple Weather setup

    private var enableSteps: some View {
        Section {
            VStack(alignment: .leading, spacing: IterSpace.sm) {
                step(1, Text("Sign in to Xcode with an Apple Developer Program account.", comment: "WeatherKit setup step"))
                step(2, Text("In Certificates, Identifiers & Profiles, enable WeatherKit for the App ID com.dwjames.iter, on both the Capabilities and App Services tabs.",
                             comment: "WeatherKit setup step"))
                step(3, Text("Build with `scripts/run.sh --weatherkit`.", comment: "WeatherKit setup step; the command is code"))
            }
            .textSelection(.enabled)
        } header: {
            Text("To turn on Apple Weather", comment: "Settings section: WeatherKit setup steps")
        } footer: {
            Text("Until a forecast source works, sun and moon times are exact and light scores stay empty.", comment: "Settings footer: what works without weather")
        }
    }

    private func step(_ n: Int, _ text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: IterSpace.sm) {
            Text("\(n).").monospacedDigit()
            text.fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Attribution

    /// Each provider's required credit, moved here from the content screens at the owner's request.
    @ViewBuilder private var attribution: some View {
        Section {
            WeatherDataSources()
        } header: { Text("Data Sources and Attribution", comment: "Settings section") }
    }
}

// MARK: - One provider

private struct WeatherProviderSection: View {
    let source: ForecastSource
    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @State private var saveError: String?

    private var setup: WeatherSetup { model.weather }
    private var status: WeatherProviderStatus { setup.status(for: source) }

    var body: some View {
        Section {
            statusRow
            if source.needsAPIKey { keyRows }
            if source == .windy { windyChoices }
            if let usage = setup.usage(for: source) { usageRow(usage.calls, usage.cap) }
            if let url = WeatherSettingsText.keyPage(source) {
                Link(destination: url) { Text("Get a key", comment: "Settings: link to a provider's API key page") }
            }
        } header: {
            Text(LightText.name(source))
        } footer: {
            Text(WeatherSettingsText.description(source))
        }
    }

    // MARK: Status

    private var statusRow: some View {
        let display = WeatherSettingsText.status(status, source: source)
        return Group {
            LabeledContent {
                if let action = display.action {
                    Button { Task { await setup.check(source) } } label: { Text(action) }
                }
            } label: {
                Label {
                    Text(display.text)
                } icon: {
                    if status == .checking {
                        ProgressView().controlSize(.small)
                    } else {
                        icon(display.icon).foregroundStyle(iconStyle(display))
                    }
                }
            }
            if case .failed(let detail) = status, !detail.isEmpty {
                Text(detail).foregroundStyle(IterColor.textSecondary).textSelection(.enabled)
            }
        }
    }

    private func iconStyle(_ display: WeatherSettingsText.Display) -> AnyShapeStyle {
        if display.icon == .rejected { return AnyShapeStyle(IterColor.danger) }
        return display.warns ? AnyShapeStyle(IterColor.warning) : AnyShapeStyle(IterColor.textSecondary)
    }

    @ViewBuilder private func icon(_ icon: WeatherSettingsText.Icon) -> some View {
        switch icon {
        case .working: Image(systemName: "checkmark.circle.fill")
        case .key: Image(systemName: "key")
        case .warning: Image(systemName: "exclamationmark.triangle.fill")
        case .rejected: Image(systemName: "xmark.octagon.fill")
        case .cap: Image(systemName: "gauge.with.dots.needle.100percent")
        case .idle: Image(systemName: "circle.dashed")
        }
    }

    // MARK: Key

    @ViewBuilder private var keyRows: some View {
        let origin = setup.keyOrigin(for: source)
        if let origin, origin != .keychain {
            LabeledContent {
                Text(WeatherSettingsText.override(origin, source: source)).foregroundStyle(IterColor.textSecondary)
            } label: { Text("API key", comment: "Settings field") }
        } else {
            HStack {
                SecureField(text: $draft, prompt: Text(origin == nil ? "Paste your key" : "Saved in Keychain. Paste to replace",
                                                        comment: "Settings: API key field prompt")) {
                    Text("API key", comment: "Settings field")
                }
                .onSubmit(save)
                Button(action: save) { Text("Save", comment: "Button") }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if origin != nil {
                    Button(role: .destructive) { remove() } label: { Text("Remove", comment: "Button") }
                }
            }
            if let saveError {
                Label(saveError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(IterColor.danger)
            }
        }
    }

    private func save() {
        do {
            try setup.setKey(draft, for: source)
            draft = ""
            saveError = nil
        } catch {
            saveError = String(localized: "Couldn't save the key to your Keychain.", comment: "Settings: Keychain error")
        }
    }

    private func remove() {
        do {
            try setup.removeKey(for: source)
            draft = ""
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

    private func usageRow(_ calls: Int, _ cap: Int) -> some View {
        Group {
            LabeledContent {
                Text(calls, format: .number).monospacedDigit()
            } label: { Text("Calls today", comment: "Settings field") }
            Stepper(value: Binding(get: { cap }, set: { setup.setCap($0, for: source) }), in: 0...10_000, step: 50) {
                Text("Daily cap: \(cap) calls", comment: "Settings: the daily call allowance of a weather provider, e.g. Daily cap: 800 calls")
            }
        }
    }
}

// MARK: - Words

enum WeatherSettingsText {
    static func description(_ source: ForecastSource) -> String {
        switch source {
        case .appleWeather:
            String(localized: "Hourly for 10 days, with cloud cover and visibility. Needs a paid Apple developer team to turn on.",
                   comment: "Settings: Apple Weather description")
        case .openWeather:
            String(localized: "Hourly for 48 hours, then daily. Total cloud only. 1,000 free calls a day.",
                   comment: "Settings: OpenWeather description")
        case .windy:
            String(localized: "Cloud by height (low, mid, high) from the GFS, ICON and NAM models. Testing keys return shuffled data.",
                   comment: "Settings: Windy description")
        case .sample:
            String(localized: "Made-up weather for demos.", comment: "Settings: sample description")
        }
    }

    static func keyPage(_ source: ForecastSource) -> URL? {
        switch source {
        case .openWeather: URL(string: "https://home.openweathermap.org/api_keys")
        case .windy: URL(string: "https://api.windy.com/keys")
        case .appleWeather, .sample: nil
        }
    }

    static func override(_ origin: APIKeyOrigin, source: ForecastSource) -> String {
        switch origin {
        case .environment:
            String(localized: "From environment (\(APIKeyResolver.variableName(for: source) ?? ""))", comment: "Settings: the key comes from an environment variable")
        case .launchArgument:
            String(localized: "From launch argument", comment: "Settings: the key comes from a launch argument")
        case .keychain:
            String(localized: "Saved in Keychain", comment: "Settings: the key is in the Keychain")
        }
    }

    enum Icon { case working, key, warning, rejected, cap, idle }

    struct Display {
        var text: String
        var icon: Icon
        var warns = false
        var action: String?
    }

    static func status(_ status: WeatherProviderStatus, source: ForecastSource) -> Display {
        let checkAgain = String(localized: "Check Again", comment: "Button")
        let check = String(localized: "Check", comment: "Button: test a weather provider now")
        switch status {
        case .working(let date):
            let time = date.formatted(date: .omitted, time: .shortened)
            return Display(text: String(localized: "Working · last update \(time)", comment: "Settings weather status, e.g. Working · last update 19:40"),
                           icon: .working, action: check)
        case .needsKey:
            return Display(text: String(localized: "Needs an API key", comment: "Settings weather status"), icon: .key, warns: true)
        case .notEnabled:
            return Display(text: String(localized: "Not enabled for this build", comment: "Settings weather status"),
                           icon: .warning, warns: true, action: checkAgain)
        case .testingKey:
            return Display(text: String(localized: "Testing key: Windy's data is shuffled, so Iter won't score from it", comment: "Settings weather status"),
                           icon: .warning, warns: true, action: check)
        case .keyRejected:
            return Display(text: String(localized: "Key rejected", comment: "Settings weather status"),
                           icon: .rejected, warns: true, action: checkAgain)
        case .dailyCap(let calls, let cap):
            return Display(text: String(localized: "Daily cap reached (\(calls) of \(cap))", comment: "Settings weather status"),
                           icon: .cap, warns: true, action: checkAgain)
        case .failed:
            let name = LightText.name(source)
            return Display(text: String(localized: "Couldn't reach \(name)", comment: "Settings weather status; the name is a weather provider"),
                           icon: .warning, warns: true, action: checkAgain)
        case .notChecked:
            return Display(text: String(localized: "Not checked yet", comment: "Settings weather status"), icon: .idle, action: check)
        case .checking:
            return Display(text: String(localized: "Checking…", comment: "Settings weather status"), icon: .idle)
        }
    }
}
