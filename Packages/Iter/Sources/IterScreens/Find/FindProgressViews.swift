import SwiftUI
import IterFeatures
import IterModel
import IterUI

/// The discovery run's progress: one line (sources done of total, elapsed), a bar, Cancel while it runs, and the per-source
/// list in a disclosure. A slow or down source shows in its row and never holds the results back.
struct FindProgressSection: View {
    let progress: FindProgress
    let phase: FindPhase
    let chips: [SourceChip]
    let onCancel: () -> Void
    @State private var isExpanded: Bool

    init(progress: FindProgress, phase: FindPhase, chips: [SourceChip], isExpanded: Bool = false, onCancel: @escaping () -> Void) {
        self.progress = progress
        self.phase = phase
        self.chips = chips
        self.onCancel = onCancel
        _isExpanded = State(initialValue: isExpanded)
    }

    private var line: String { FindText.progressLine(progress, phase: phase) }

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            if !line.isEmpty || progress.isRunning {
                HStack(spacing: IterSpace.sm) {
                    if progress.isRunning { ProgressView().controlSize(.small) }
                    Text(verbatim: line)
                        .font(IterFont.secondary)
                        .foregroundStyle(IterColor.textSecondary)
                        .monospacedDigit()
                    Spacer(minLength: 0)
                    if progress.isRunning {
                        Button("Cancel", action: onCancel)
                            .controlSize(.small)
                            .keyboardShortcut(.cancelAction)
                            .help("Stop the search; places already found stay")
                    }
                }
                if progress.isRunning, let fraction = progress.fraction {
                    ProgressView(value: fraction).progressViewStyle(.linear)
                }
            }
            if !chips.isEmpty {
                DisclosureGroup(isExpanded: $isExpanded) {
                    FindSourceList(chips: chips).padding(.top, IterSpace.xs)
                } label: {
                    HStack(spacing: IterSpace.xs) {
                        Text("Sources")
                            .font(IterFont.captionStrong)
                            .foregroundStyle(IterColor.textSecondary)
                        if let trouble = FindText.sourceTrouble(chips) {
                            Text(verbatim: "· " + trouble)
                                .font(IterFont.caption)
                                .foregroundStyle(IterColor.warning)
                        }
                    }
                }
                .font(IterFont.caption)
            }
        }
        .padding(IterSpace.md)
        .background(ModuleFill(), in: RoundedRectangle(cornerRadius: IterRadius.card, style: .continuous))
    }
}

/// Every source of the run with its state. Reddit and Google appear here, named as unavailable, with the plain reason.
struct FindSourceList: View {
    let chips: [SourceChip]

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            ForEach(chips) { chip in
                FindSourceRow(display: FindText.sourceDisplay(chip)).equatable()
            }
        }
    }
}

struct FindSourceRow: View, Equatable {
    let display: FindText.SourceDisplay

    private var tint: Color {
        switch display.tone {
        case .normal: IterColor.accentText
        case .quiet: IterColor.textTertiary.color
        case .warning: IterColor.warning
        case .danger: IterColor.danger
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: IterSpace.sm) {
            Group {
                if display.isWorking { ProgressView().controlSize(.mini) } else { Image(systemName: display.symbol).foregroundStyle(tint) }
            }
            .frame(width: 16)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: display.name)
                    .font(IterFont.captionStrong)
                    .foregroundStyle(IterColor.textPrimary)
                Text(verbatim: display.detail)
                    .font(IterFont.caption)
                    .foregroundStyle(display.tone == .danger ? IterColor.danger : (display.tone == .warning ? IterColor.warning : IterColor.textSecondary.color))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(display.name), \(display.detail)"))
    }
}

/// "Basic search: AI unavailable (Apple Intelligence is turned off)": what planned this search, said plainly.
struct FindPlanLine: View, Equatable {
    let text: String
    let isBasic: Bool

    var body: some View {
        Label {
            Text(verbatim: text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: isBasic ? "magnifyingglass" : "sparkles")
        }
        .font(IterFont.caption)
        .foregroundStyle(IterColor.textSecondary)
    }
}

/// System toggle chips for the kinds in the results, and a way back to all.
struct FindFilterChips: View {
    let filters: [KindFilter]
    let onToggle: (FeatureKind) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: IterSpace.sm) {
                ForEach(filters) { filter in
                    Toggle(isOn: Binding(get: { filter.isOn }, set: { _ in onToggle(filter.kind) })) {
                        Text(verbatim: "\(filter.title) \(filter.count)").monospacedDigit()
                    }
                    .toggleStyle(.button)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 1)
        }
        .scrollClipDisabled()
    }
}

/// Search Here: a system glass capsule. Shown only when the map no longer matches the list; it never moves the map.
struct FindSearchHereButton: View {
    let action: () -> Void

    var body: some View {
        GlassEffectContainer {
            Button(action: action) { Label("Search Here", systemImage: "magnifyingglass").foregroundStyle(.primary) }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .help("Search the part of the map you can see")
        }
    }
}
