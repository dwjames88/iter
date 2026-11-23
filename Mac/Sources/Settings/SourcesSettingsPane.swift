import SwiftUI
import IterFeatures
import IterModel
import IterUI

/// Settings ▸ Sources & Credits: every source, grouped by who made the data, with the honest origin line, its status, what it
/// covers and supplies, and the full attribution text. What no source supplies is named at the end.
struct SourcesSettingsPane: View {
    let model: SettingsModel

    var body: some View {
        Form {
            ForEach(model.rowsByTier, id: \.tier) { group in
                Section {
                    ForEach(group.rows) { row in SourceCreditRow(model: model, row: row) }
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
        .formStyle(.grouped)
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

/// One source in the credits list.
struct SourceCreditRow: View {
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
                        .toggleStyle(.switch)
                        .accessibilityLabel(Text("Use \(row.name)"))
                } else if case .unavailable = row.status {
                    // Shown as its own line below, so a long reason wraps under the name.
                    EmptyView()
                } else {
                    Text(SourceText.status(row.status)).font(.callout).foregroundStyle(.secondary)
                }
            }
            if case .unavailable = row.status {
                Text(SourceText.status(row.status)).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(row.originLabel).font(.callout).foregroundStyle(row.isMilitaryOrigin ? IterColor.accentText : Color.secondary)
            Text("\(row.coverage). \(row.kinds.joined(separator: ", ")).")
                .font(.caption).foregroundStyle(.secondary)
            if row.isToggleable, row.status != .enabled {
                Text(SourceText.status(row.status)).font(.caption).foregroundStyle(.secondary)
            }
            if let timing = SourceText.timing(row.toggleTiming), row.isToggleable {
                Text(timing).font(.caption).foregroundStyle(.secondary)
            }
            // An unavailable source has no credit to give; its attribution only repeats the reason shown above.
            if case .unavailable = row.status {} else {
                Text(row.attributionFull)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let terms = row.termsURL {
                Link("Terms of Use", destination: terms).font(.caption)
            }
        }
        .padding(.vertical, 2)
    }
}
