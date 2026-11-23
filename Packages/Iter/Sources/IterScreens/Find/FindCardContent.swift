import SwiftUI
import IterFeatures
import IterModel
import IterUI

/// What the floating card holds, chosen from the model's state (see `FindCardMode`): the place card, the discovery results
/// with progress, the typed lookup, or the suggestions for text not yet run. Needs no map, so it renders alone in snapshots.
struct FindCardContent: View {
    @Bindable var model: FindModel
    var conditions: ConditionsModel?
    var showsSearchHere = false
    var initiallyShowsSources = false
    var onClose: () -> Void = {}

    var body: some View {
        switch FindCardMode.of(model) {
        case .place:
            if let card = model.card {
                FindPlaceCard(model: model, card: card, conditions: conditions, onBack: { model.deselect() }, onClose: {
                    model.deselect()
                    onClose()
                })
            }
        case .results: FindResultsCard(model: model, showsSearchHere: showsSearchHere, initiallyShowsSources: initiallyShowsSources)
        case .lookup, .suggestions: FindLookupCard(model: model)
        case .hidden: EmptyView()
        }
    }
}

extension FindCardMode {
    /// The mode for a model's current state.
    @MainActor static func of(_ model: FindModel) -> FindCardMode {
        resolve(hasCard: model.card != nil, phase: model.phase, hasChips: !model.chips.isEmpty, hasRows: !model.rows.isEmpty,
                hasMatches: !model.matches.isEmpty, hasText: model.suggestions.lookup != nil)
    }
}

/// The calm hint over the map before anything is searched.
struct FindEmptyHint: View {
    var body: some View {
        VStack(spacing: IterSpace.sm) {
            Image(systemName: "binoculars")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(IterColor.textSecondary)
                .accessibilityHidden(true)
            Text("Search for a place, or ask for spots")
                .font(IterFont.headline)
                .foregroundStyle(IterColor.textPrimary)
            Text("waterfalls in Yosemite")
                .font(IterFont.secondary)
                .foregroundStyle(IterColor.textSecondary)
        }
        .multilineTextAlignment(.center)
        .padding(IterSpace.xl)
        .background(IterColor.backgroundContent, in: RoundedRectangle(cornerRadius: IterRadius.panel, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: IterRadius.panel, style: .continuous).strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .accessibilityElement(children: .combine)
    }
}
