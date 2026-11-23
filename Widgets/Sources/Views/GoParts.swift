import IterGoActivity
import IterModel
import IterUI
import SwiftUI

/// A countdown in words ("21 min, 4 sec", "2 hr, 54 min"). Live: `Text(date, style: .relative)`, which the system keeps current
/// with no updates from the app (checked: it advanced across a minute boundary in a running hosting controller, where the
/// `SystemFormatStyle` formats `.offset` and `.reference` did not). Frozen: the same words as a string.
struct GoCountdownText: View {
    let target: Date
    let clock: GoClock
    var font: Font = .system(size: 32, weight: .semibold)
    var alignment: TextAlignment = .leading
    /// Compact places let the words wrap after the comma ("21 min," over "4 sec") so the width can stay fixed.
    var lineLimit = 1

    var body: some View {
        Self.text(target: target, clock: clock)
            .font(font)
            .monospacedDigit()
            .multilineTextAlignment(alignment)
            .lineLimit(lineLimit)
            .minimumScaleFactor(0.6)
    }

    /// The countdown as a `Text`, so callers can concatenate it ("Leave " + 2 hr, 54 min).
    static func text(target: Date, clock: GoClock) -> Text {
        let remaining = target.timeIntervalSince(clock.now)
        if clock.isLive, remaining > 0 { return Text(target, style: .relative) }
        return Text(verbatim: GoPresentation.durationWords(remaining))
    }
}

/// The score chip for the window Go is heading into: live score, else forecast; low confidence styled by `ScoreChip`.
struct GoChip: View {
    let p: GoPresentation
    var size: ScoreChip.Size = .small
    var timeStyle: ScoreChip.TimeStyle = .start

    var body: some View {
        if let kind = p.content.windowKind, let start = p.content.windowStart {
            // Low confidence is styled by the chip itself; an old reading is weakened on top of that.
            ScoreChip(kind: kind, start: start, score: p.score, zone: p.zone, size: size, timeStyle: timeStyle,
                      isLowConfidence: p.isLowConfidence)
                .opacity(p.isDim ? p.chipOpacity / (p.isLowConfidence ? IterEvent.lowConfidenceOpacity : 1) : 1)
        }
    }
}

/// The honest age line: "As of 16:10", "Offline · as of 16:10". Hidden when the data is fresh and online.
struct GoAgeLine: View {
    let p: GoPresentation
    var font: Font = IterFont.caption

    var body: some View {
        if let text = p.ageText {
            Label {
                Text(verbatim: text)
            } icon: {
                Image(systemName: p.content.isOffline ? "wifi.slash" : "clock.arrow.circlepath")
            }
            .font(font)
            .foregroundStyle(IterColor.warning)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }
}

/// The main fact: a label over the countdown, or the status sentence ("Leave now", "Late by 6 min", "Paused", "Trip complete").
/// Late and missed read in the warning colour with a symbol, so colour is never the only signal.
struct GoHeadline: View {
    let p: GoPresentation
    var size: CGFloat = 32
    var showsLabel = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let status = p.status {
                if showsLabel, let countdown = p.countdown {
                    Text(verbatim: countdown.label).font(IterFont.caption).foregroundStyle(IterColor.textSecondary)
                    GoCountdownText(target: countdown.target, clock: p.clock, font: .system(size: size, weight: .semibold))
                        .foregroundStyle(p.isDim ? IterColor.textSecondary : IterColor.textPrimary)
                    statusLine(status, size: size * 0.5)
                } else {
                    statusLine(status, size: size * 0.8)
                }
            } else if let countdown = p.countdown {
                if showsLabel { Text(verbatim: countdown.label).font(IterFont.caption).foregroundStyle(IterColor.textSecondary) }
                GoCountdownText(target: countdown.target, clock: p.clock, font: .system(size: size, weight: .semibold))
                    .foregroundStyle(p.isDim ? IterColor.textSecondary : IterColor.textPrimary)
            }
        }
    }

    private func statusLine(_ status: (text: String, tone: GoPresentation.Tone), size: CGFloat) -> some View {
        Label {
            Text(verbatim: status.text)
        } icon: {
            if let symbol = Self.symbol(status.tone, phase: p.phase) { Image(systemName: symbol) }
        }
        .font(.system(size: size, weight: .semibold))
        .foregroundStyle(Self.color(status.tone))
        .lineLimit(2)
        .minimumScaleFactor(0.6)
    }

    static func color(_ tone: GoPresentation.Tone) -> Color {
        switch tone {
        case .normal: IterColor.textPrimary.color
        case .warning: IterColor.warning
        case .accent: IterColor.accentText
        }
    }

    static func symbol(_ tone: GoPresentation.Tone, phase: GoPhase) -> String? {
        switch tone {
        case .warning: "exclamationmark.triangle.fill"
        case .accent: "car.fill"
        case .normal:
            switch phase {
            case .paused: "pause.circle.fill"
            case .finished: "checkmark.circle.fill"
            default: nil
            }
        }
    }
}
