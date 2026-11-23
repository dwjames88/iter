import SwiftUI
import IterDiscovery
import IterFeatures
import IterModel
import IterUI

// OWNER: W4 (settings and sharing). CONTRACT: the shell hosts this inside its own NavigationStack (a sheet on iPhone, the
// detail on iPad). No NavigationStack of its own.

/// Settings on iPhone and iPad: one grouped list, the panes pushed from it. The same panes as the Mac (no Updates pane: the
/// App Store does that).
struct IOSSettingsScreen: View {
    let shell: IOSShell

    var body: some View {
        SettingsRoot(model: shell.settings, shell: shell)
    }
}

/// The root list. Takes the model directly so renders and tests can build it without a shell.
struct SettingsRoot: View {
    @Bindable var model: SettingsModel
    var shell: IOSShell?
    var dataMode: DataMode

    init(model: SettingsModel, shell: IOSShell?) {
        self.model = model
        self.shell = shell
        dataMode = shell?.container.dataMode ?? .live
    }

    var body: some View {
        List {
            Section {
                Picker("Map Style", selection: $model.mapStyle) {
                    ForEach(SettingsModel.mapStyles, id: \.id) { Text($0.title).tag($0.id) }
                }
                Toggle("Show Daylight", isOn: $model.showDaylight)
            } header: {
                Text("Map")
            } footer: {
                Text("Daylight shades the night side of the globe when the map is zoomed out.")
            }
            Section {
                NavigationLink("Search") { IOSSearchSettings(model: model) }
                NavigationLink("Sources & Credits") { IOSSourcesSettings(model: model) }
                if !model.keyRows.isEmpty {
                    NavigationLink("Keys") { IOSKeysSettings(model: model) }
                }
            }
            Section {
                LabeledContent("Version", value: IOSAbout.versionText)
                LabeledContent("Data", value: dataMode == .sample ? "Sample Data" : "Live")
            } header: {
                Text("About")
            } footer: {
                Text(IOSAbout.creditLine)
            }
            #if DEBUG
            if let shell { IOSDebugSection(shell: shell) }
            #endif
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The About words, read from the bundle.
enum IOSAbout {
    static let creditLine = "Iter plans photo trips with free public data. Full credits for every source are under Sources & Credits."

    static var versionText: String { versionText(Bundle.main) }

    static func versionText(_ bundle: Bundle) -> String {
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (short, build) {
        case let (s?, b?) where s != b: return "\(s) (\(b))"
        case let (s?, _): return s
        case let (_, b?): return b
        default: return "Unknown"
        }
    }
}

// MARK: - Search

struct IOSSearchSettings: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            Section {
                TextField("What I Like to Shoot", text: $model.preferenceText,
                          prompt: Text("Quiet alpine lakes at sunrise, long-exposure waterfalls, no crowds"), axis: .vertical)
                    .lineLimit(3...6)
                    .labelsHidden()
            } header: {
                Text("What I Like to Shoot")
            } footer: {
                Text("Iter matches these words when it ranks places, on this iPhone. They are never sent to a source.")
            }
            Section {
                Toggle("Use My Saved Places and Trips", isOn: $model.learnFromLibrary)
            } header: {
                Text("Learn From My Library")
            } footer: {
                Text("Places like the ones you save and plan get a small lift when Iter ranks results. It is worked out on this iPhone and never leaves it.")
            }
            Section {
                Picker("Prefer", selection: $model.ordering) {
                    ForEach(DiscoveryOrdering.allCases, id: \.self) { Text(Self.title($0)).tag($0) }
                }
                Stepper("Up to \(model.resultCap) results", value: $model.resultCap, in: SettingsModel.resultCapRange, step: 10)
            } header: {
                Text("Results")
            } footer: {
                Text("Popular puts the best-known places first, Unique the lesser-known ones, and Mixed alternates.")
            }
            Section {
                ForEach(model.discoverySources) { row in IOSSourceToggleRow(model: model, row: row) }
            } header: {
                Text("Sources")
            } footer: {
                Text("These are free public sources. Iter sends only the place and the search words, and a source you switch off is skipped on the next search.")
            }
        }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
    }

    static func title(_ ordering: DiscoveryOrdering) -> String {
        switch ordering {
        case .popular: "Popular"
        case .unique: "Unique"
        case .mixed: "Mixed"
        }
    }
}

struct IOSSourceToggleRow: View {
    let model: SettingsModel
    let row: SourceRow

    var body: some View {
        if row.isToggleable {
            Toggle(isOn: Binding(get: { row.isOn }, set: { model.setSource(row.id, enabled: $0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                    Text(row.originLabel).font(.caption).foregroundStyle(.secondary)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                Text(row.originLabel).font(.caption).foregroundStyle(.secondary)
                Text(IOSSourceText.status(row.status)).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The words for a source's state (the Mac's).
enum IOSSourceText {
    static func status(_ status: SourceRowStatus) -> String {
        switch status {
        case .enabled: "On"
        case .disabled: "Off"
        case .offByDefault: "Off Until You Turn It On"
        case .needsKey: "Needs a Key"
        case .unavailable(let reason): "Unavailable: \(reason.prefix(1).uppercased() + reason.dropFirst())"
        }
    }

    static func timing(_ timing: ToggleTiming) -> String? {
        switch timing {
        case .nextSearch: "Applies on the next search."
        case .nextLaunch: "Applies the next time Iter opens."
        case .never: nil
        }
    }
}

// MARK: - Sources & Credits

struct IOSSourcesSettings: View {
    let model: SettingsModel

    var body: some View {
        Form {
            ForEach(model.rowsByTier, id: \.tier) { group in
                Section {
                    ForEach(group.rows) { row in IOSSourceCreditRow(model: model, row: row) }
                } header: {
                    Text(Self.title(group.tier))
                }
            }
            Section {
                ForEach(model.namedGaps) { gap in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(gap.title).font(IterFont.bodyEmphasis)
                        Text(gap.explanation).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } header: {
                Text("What No Source Supplies Yet")
            }
        }
        .navigationTitle("Sources & Credits")
        .navigationBarTitleDisplayMode(.inline)
    }

    static func title(_ tier: SourceTier) -> String {
        switch tier {
        case .military: "Military-Origin Sources"
        case .government: "Government Sources"
        case .openData: "Open Data"
        case .userKey: "Your Own Access"
        case .device: "On This Device"
        }
    }
}

struct IOSSourceCreditRow: View {
    let model: SettingsModel
    let row: SourceRow

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.name).font(IterFont.bodyEmphasis)
                Spacer(minLength: IterSpace.sm)
                if row.isToggleable {
                    Toggle(isOn: Binding(get: { row.isOn }, set: { model.setSource(row.id, enabled: $0) })) { EmptyView() }
                        .labelsHidden()
                        .accessibilityLabel(Text("Use \(row.name)"))
                } else if case .unavailable = row.status {
                    EmptyView()
                } else {
                    Text(IOSSourceText.status(row.status)).font(.callout).foregroundStyle(.secondary)
                }
            }
            if case .unavailable = row.status {
                Text(IOSSourceText.status(row.status)).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(row.originLabel).font(.callout).foregroundStyle(row.isMilitaryOrigin ? IterColor.accentText : Color.secondary)
            Text("\(row.coverage). \(row.kinds.joined(separator: ", ")).")
                .font(.caption).foregroundStyle(.secondary)
            if row.isToggleable, row.status != .enabled {
                Text(IOSSourceText.status(row.status)).font(.caption).foregroundStyle(.secondary)
            }
            if let timing = IOSSourceText.timing(row.toggleTiming), row.isToggleable {
                Text(timing).font(.caption).foregroundStyle(.secondary)
            }
            if case .unavailable = row.status {} else {
                Text(row.attributionFull)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let terms = row.termsURL {
                Link("Terms of Use", destination: terms).font(.caption)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Keys

struct IOSKeysSettings: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section {
                ForEach(model.keyRows) { row in IOSKeyRow(model: model, row: row) }
            } footer: {
                Text(model.keysSummary)
            }
        }
        .navigationTitle("Keys")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct IOSKeyRow: View {
    let model: SettingsModel
    let row: KeyRow
    @State private var draft = ""
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SecureField(row.sourceName, text: $draft,
                        prompt: Text(row.hasKey ? "Saved in Keychain. Paste to replace" : (row.isRequired ? "Paste your key (required)" : "Paste your key")))
            HStack {
                Button("Save") { save() }.disabled(draft.isEmpty)
                if row.hasKey { Button("Remove", role: .destructive) { remove() } }
            }
            .buttonStyle(.borderless)
            if let failure { Text(failure).font(.caption).foregroundStyle(.red) }
        }
    }

    private func save() {
        do { try model.setKey(draft, for: row.id); draft = ""; failure = nil } catch { failure = "Couldn't save the key to your Keychain." }
    }

    private func remove() {
        do { try model.removeKey(for: row.id); failure = nil } catch { failure = "Couldn't remove the key from your Keychain." }
    }
}

// MARK: - Debug (DEBUG builds only)

#if DEBUG
/// What the Debug section's actions say when they fail.
enum IOSDebugText {
    static let sampleKey = "IterDebugSampleData"

    static func reason(_ error: any Error) -> String {
        if let e = error as? DebugActionError, e == .refusedOnRealStore {
            return "This is your real library, so Iter won't change it from here. Turn on Use Sample Data, reopen Iter, and try again."
        }
        return error.localizedDescription
    }
}

/// Debug builds only: sample data, seeding and reset. Both actions refuse the real store.
struct IOSDebugSection: View {
    let shell: IOSShell
    @AppStorage(IOSDebugText.sampleKey) private var useSampleData = false
    @State private var confirmsReset = false
    @State private var notice: String?

    var body: some View {
        Section {
            LabeledContent("Data Mode Now", value: shell.container.dataMode == .sample ? "Sample Data" : "Live")
            Toggle("Use Sample Data", isOn: $useSampleData)
            Button("Seed Sample Trip") { seed() }
            Button("Reset All Data…", role: .destructive) { confirmsReset = true }
        } header: {
            Text("Debug (Debug Builds Only)")
        } footer: {
            Text("Takes effect the next time Iter opens. Seeding and resetting only work on a sample or scratch library, never your real one.")
        }
        .confirmationDialog("Reset All Data?", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Reset All Data", role: .destructive) { reset() }
        } message: {
            Text("This removes every trip, place and folder from this library.")
        }
        .alert("Debug", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK") { notice = nil }
        } message: {
            Text(notice ?? "")
        }
    }

    private func seed() {
        do {
            _ = try shell.container.seedSampleTrip()
            shell.library.refresh()
            notice = "Added the sample trip."
        } catch {
            notice = "Couldn't seed the sample trip. " + IOSDebugText.reason(error)
        }
    }

    private func reset() {
        do {
            try shell.container.resetLibrary()
            shell.library.refresh()
            notice = "Removed everything from this library."
        } catch {
            notice = "Couldn't reset. " + IOSDebugText.reason(error)
        }
    }
}
#endif
