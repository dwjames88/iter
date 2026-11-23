import SwiftUI
import IterFeatures
import IterUI

/// The one-time tip on the card of one of your own spots: how to move it. Content layer (a quiet module fill, not glass). It
/// stays until "Got It" or until the pin is moved, then `OneTimeNotices` keeps it away for good. Not TipKit: the package does not
/// link it, and a plain persisted flag renders the same in a headless screenshot.
struct MoveSpotTip: View {
    let message: LocalizedStringKey
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: IterSpace.md) {
            Image(systemName: "hand.draw")
                .font(.title3)
                .foregroundStyle(IterColor.accentText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: IterSpace.xs) {
                Text("Move This Spot", comment: "Tip title: how to move one of your own spots")
                    .font(IterFont.bodyEmphasis)
                    .foregroundStyle(IterColor.textPrimary)
                Text(message)
                    .font(IterFont.secondary)
                    .foregroundStyle(IterColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onDismiss) { Text("Got It", comment: "Button: dismiss a tip") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(IterColor.accentText)
                    .frame(minHeight: 32)
            }
            Spacer(minLength: 0)
        }
        .padding(IterSpace.md)
        .background(ModuleFill(), in: RoundedRectangle(cornerRadius: IterRadius.card, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

/// Today, Tomorrow and Near You, shown before anything is searched. System bordered capsule buttons at 44 pt, monochrome;
/// each runs the matching search (`FindModel.runQuickChoice`).
struct FindQuickChoiceChips: View {
    @Bindable var model: FindModel

    static func title(_ choice: FindQuickChoice) -> LocalizedStringKey {
        switch choice {
        case .today: "Today"
        case .tomorrow: "Tomorrow"
        case .nearYou: "Near You"
        }
    }

    private var chips: some View {
        ForEach(FindQuickChoice.allCases) { choice in
            Button { model.runQuickChoice(choice) } label: {
                Text(Self.title(choice))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.regular)
            .tint(IterColor.textPrimary.color)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            // Three across; at the largest type sizes they scroll instead of truncating.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: IterSpace.sm) { chips }
                ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: IterSpace.sm) { chips } }
            }
            if let notice = model.notice {
                Text(verbatim: notice).font(IterFont.caption).foregroundStyle(IterColor.textSecondary)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
