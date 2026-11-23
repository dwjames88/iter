import SwiftUI
import IterModel
import IterGoActivity
import IterUI

/// Official alerts in force at the next stop: event, headline, severity word and end time, each with an icon (severity is
/// never colour alone). Nothing when there are none.
public struct GoAlertsSection: View {
    public let snapshot: GoSnapshot
    public let now: Date

    @Environment(\.locale) private var locale

    public init(snapshot: GoSnapshot, now: Date) {
        self.snapshot = snapshot
        self.now = now
    }

    public var body: some View {
        if !snapshot.alerts.isEmpty {
            let zone = GoText.zone(for: GoText.subjectStop(snapshot))
            VStack(alignment: .leading, spacing: IterSpace.sm) {
                ForEach(snapshot.alerts) { alert in
                    let level = GoText.alertLevel(alert.severity)
                    let ink = level == .danger ? IterColor.danger : IterColor.warning
                    HStack(alignment: .top, spacing: IterSpace.sm) {
                        Image(systemName: GoText.alertSymbol(level)).foregroundStyle(ink)
                            .frame(width: IterSize.iconLarge).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: IterSpace.xxs) {
                            Text(verbatim: alert.event).font(IterFont.headline).foregroundStyle(IterColor.textPrimary)
                            if let h = alert.headline {
                                Text(verbatim: h).font(IterFont.callout).foregroundStyle(IterColor.textSecondary)
                            }
                            Text(verbatim: GoText.alertDetail(alert, zone: zone, locale: locale))
                                .font(IterFont.captionStrong).foregroundStyle(ink)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .goCard()
        }
    }
}
