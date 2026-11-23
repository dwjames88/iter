import SwiftUI
import IterFeatures
import IterModel
import IterSky
import IterUI

/// A module card (HIERARCHY): `ModuleFill`, `radius/card`, 16 inset, the title at the top-left with a leading symbol.
struct ModuleCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            Label {
                Text(verbatim: title)
            } icon: {
                Image(systemName: symbol)
            }
            .font(IterFont.moduleTitle)
            .foregroundStyle(IterColor.textSecondary)
            .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(IterGrid.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ModuleFill(), in: RoundedRectangle(cornerRadius: IterRadius.card, style: .continuous))
    }
}

/// A grey block standing where a value will be. Never a number; static, so Reduce Motion needs no special case.
struct SkeletonBar: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12

    var body: some View {
        RoundedRectangle(cornerRadius: IterRadius.badge, style: .continuous)
            .fill(IterColor.separator.opacity(0.7))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .accessibilityHidden(true)
    }
}

/// The score chip of the place's headline window. The score cross-fades when a better forecast replaces it (the model bumps
/// `scoreRevision`), and the chip never goes empty in between.
struct HeadlineChip: View {
    let model: ConditionsModel
    var size: ScoreChip.Size = .large
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let revision = model.scoreRevision
        ZStack {
            chip.id(revision).transition(.opacity)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: revision)
    }

    private var chip: some View {
        let h = model.headline
        let kind = h?.kind ?? model.place.defaultSession
        let span = model.windows.first { $0.kind == kind }?.span ?? model.timeline.windows.first { $0.kind == kind }?.span
        return ScoreChip(kind: kind, start: span?.start ?? model.scrubTime, end: nil, score: h?.value, zone: model.place.timeZone,
                         size: size, timeStyle: .start, isLowConfidence: h?.confidence == .low,
                         isLoading: h == nil && model.status == .loading)
    }
}

/// The state line at the top of the stack: loading, quick, near-term, stale, offline, out of coverage, unavailable.
struct ConditionsStateLine: View {
    let model: ConditionsModel

    var body: some View {
        if let line = ConditionsFormat.stateLine(model.status, placeName: model.place.name, generatedAt: model.generatedAt,
                                                 offlineNote: model.offlineNote, zone: model.place.timeZone) {
            Group {
                switch line.tone {
                case .info:
                    HStack(alignment: .firstTextBaseline, spacing: IterSpace.xs) {
                        if model.isUpdating { ProgressView().controlSize(.mini) } else { Image(systemName: "info.circle") }
                        Text(verbatim: line.text)
                    }
                    .font(IterFont.secondary)
                    .foregroundStyle(IterColor.textSecondary)
                case .data:
                    if let data = line.data {
                        VStack(alignment: .leading, spacing: IterSpace.xs) {
                            DataStateView(data, now: model.generatedAt ?? .distantPast, zone: model.place.timeZone)
                            if case .stale = data { Text(verbatim: line.text).font(IterFont.secondary).foregroundStyle(IterColor.textSecondary) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}

extension ConditionsModel {
    /// Whether the selected day is today at the place (the "Now" button only means something then).
    var selectedDayIsToday: Bool { outlook.contains { $0.isToday && $0.isSelected } }
}
