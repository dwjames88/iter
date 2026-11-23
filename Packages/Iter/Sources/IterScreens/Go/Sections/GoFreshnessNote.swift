import SwiftUI
import IterModel
import IterGoActivity
import IterUI

/// One quiet note about how current the numbers are: offline, stale drive time / conditions / location, power saving,
/// an old snapshot. Nothing when everything is fresh. Stale and offline lines carry a symbol, never colour alone.
public struct GoFreshnessNote: View {
    public let snapshot: GoSnapshot
    public let now: Date

    @Environment(\.locale) private var locale

    public init(snapshot: GoSnapshot, now: Date) {
        self.snapshot = snapshot
        self.now = now
    }

    public var body: some View {
        let lines = GoText.freshnessLines(snapshot, now: now, locale: locale)
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: IterSpace.xs) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: IterSpace.xs) {
                        Image(systemName: line.symbol).frame(width: IterSize.iconMedium).accessibilityHidden(true)
                        Text(verbatim: line.text)
                    }
                    .foregroundStyle(line.warns ? IterColor.warning : IterColor.textSecondary.color)
                }
            }
            .font(IterFont.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}
