import IterGoActivity
import IterModel
import IterUI
import SwiftUI

/// The Live Activity on the Lock Screen and as a banner. Takes values only (no `ActivityViewContext`), so the same view is
/// rendered in the extension and in the hosted tests. The system supplies the background.
struct GoActivityView: View {
    let tripName: String
    let content: GoActivityContent
    let clock: GoClock
    var isStale = false
    var zone: TimeZone = .current

    private var p: GoPresentation { GoPresentation(content, clock: clock, zone: zone, isStale: isStale) }

    var body: some View {
        let p = p
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            HStack(alignment: .top, spacing: IterSpace.md) {
                VStack(alignment: .leading, spacing: 2) {
                    if !p.isFinished {
                        Text(verbatim: tripName)
                            .font(IterFont.caption)
                            .foregroundStyle(IterColor.textSecondary)
                            .lineLimit(1)
                    }
                    // When the run is over the trip's name is the title; "Trip complete" is the headline below.
                    Text(verbatim: p.isFinished && !tripName.isEmpty ? tripName : p.title)
                        .font(IterFont.headline)
                        .foregroundStyle(IterColor.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
                if p.score != nil || p.content.windowKind != nil {
                    VStack(alignment: .trailing, spacing: 2) {
                        GoChip(p: p)
                        if let word = p.scoreKindWord {
                            Text(verbatim: word).font(IterFont.caption).foregroundStyle(IterColor.textSecondary)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(alignment: .lastTextBaseline, spacing: IterSpace.md) {
                GoHeadline(p: p, size: 30)
                Spacer(minLength: 0)
                if let line = p.clockLine {
                    Text(verbatim: line)
                        .font(IterFont.subheadline)
                        .foregroundStyle(IterColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            GoAgeLine(p: p)
        }
        .padding(IterSpace.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(p.accessibilityText)
    }
}
