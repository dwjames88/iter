import IterGoActivity
import IterModel
import IterUI
import SwiftUI

/// A countdown: `Text(timerInterval:)` while live (ticks with no updates), a frozen string otherwise. Digits are monospaced.
struct GoCountdownText: View {
    let target: Date
    let clock: GoClock
    var font: Font = .system(size: 32, weight: .semibold)
    var alignment: TextAlignment = .leading

    var body: some View {
        timer
            .font(font)
            .monospacedDigit()
            .multilineTextAlignment(alignment)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private var timer: Text { Self.text(target: target, clock: clock) }

    /// The countdown as a `Text`, so callers can concatenate it ("Leave " + 1:24:10).
    static func text(target: Date, clock: GoClock) -> Text {
        let remaining = target.timeIntervalSince(clock.now)
        if clock.isLive, remaining > 0 {
            return Text(timerInterval: clock.now...target, pauseTime: nil, countsDown: true, showsHours: remaining >= 3600)
        }
        return Text(verbatim: GoPresentation.frozen(remaining))
    }
}

/// The score chip for the window Go is heading into: live score, else forecast; low confidence styled by `ScoreChip`.
struct GoChip: View {
    let p: GoPresentation
    var size: ScoreChip.Size = .small
    var timeStyle: ScoreChip.TimeStyle = .start

    var body: some View {
        if let kind = p.content.windowKind, let start = p.content.windowStart {
            ScoreChip(kind: kind, start: start, score: p.score, zone: p.zone, size: size, timeStyle: timeStyle,
                      isLowConfidence: p.isLowConfidence)
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
        .lineLimit(1)
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
