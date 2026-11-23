import SwiftUI
import IterGoActivity

/// The one place the sheet reaches the per-phase sections in `Sections/` (hero card, alerts, conditions, freshness).
@MainActor enum GoSections {
    @ViewBuilder static func hero(snapshot: GoSnapshot, now: Date, actions: GoActions) -> some View {
        GoHeroCard(snapshot: snapshot, now: now, actions: actions)
    }

    @ViewBuilder static func alerts(snapshot: GoSnapshot, now: Date) -> some View {
        GoAlertsSection(snapshot: snapshot, now: now)
    }

    @ViewBuilder static func conditions(snapshot: GoSnapshot, now: Date) -> some View {
        GoConditionsSection(snapshot: snapshot, now: now)
    }

    @ViewBuilder static func freshness(snapshot: GoSnapshot, now: Date) -> some View {
        GoFreshnessNote(snapshot: snapshot, now: now)
    }
}
