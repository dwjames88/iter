import SwiftUI
import IterDiscovery
import IterFeatures

/// Settings ▸ Search: what you like to shoot, how results are ordered and capped, and which sources Find may use.
struct SearchSettingsPane: View {
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
                Text("Iter matches these words when it ranks places, on this Mac. They are never sent to a source.")
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
                ForEach(model.discoverySources) { row in SourceToggleRow(model: model, row: row) }
            } header: {
                Text("Sources")
            } footer: {
                Text("These are free public sources. Iter sends only the place and the search words, and a source you switch off is skipped on the next search.")
            }
        }
        .formStyle(.grouped)
    }

    static func title(_ ordering: DiscoveryOrdering) -> String {
        switch ordering {
        case .popular: "Popular"
        case .unique: "Unique"
        case .mixed: "Mixed"
        }
    }
}

/// One discovery source: a switch when it can be switched, else its status and reason.
struct SourceToggleRow: View {
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
            // Name, then its origin and its state as secondary lines (a long reason wraps under the name, not beside it).
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                Text(row.originLabel).font(.caption).foregroundStyle(.secondary)
                Text(SourceText.status(row.status)).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The words for a source's state.
enum SourceText {
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
