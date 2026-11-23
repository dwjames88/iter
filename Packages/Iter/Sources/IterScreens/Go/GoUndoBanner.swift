import SwiftUI
import IterGoActivity
import IterUI

/// "Arrived at Mesa Arch · 1:40 left" with a Not Yet button: the 2-minute undo of an automatic transition (D12).
/// `.live` draws the countdown with `Text(timerInterval:)`, which ticks on its own; `.frozen` draws the value at `now`.
struct GoUndoBanner: View {
    let undo: GoUndoInfo
    let now: Date
    let actions: GoActions
    @Environment(\.goClockMode) private var clockMode

    var body: some View {
        HStack(alignment: .center, spacing: IterSpace.md) {
            VStack(alignment: .leading, spacing: IterSpace.xs) {
                Text(GoFlow.undoSentence(undo))
                    .font(IterFont.headline)
                    .foregroundStyle(IterColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                timeLeft
                    .font(IterFont.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(IterColor.textSecondary)
            }
            Spacer(minLength: IterSpace.sm)
            Button("Not Yet") { Task { await actions.notYet() } }
                .buttonStyle(.bordered)
                .tint(IterColor.accent)
                .controlSize(.large)
        }
        .goScreenCard()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var timeLeft: some View {
        switch clockMode {
        case .live:
            HStack(spacing: IterSpace.xs) {
                Text(timerInterval: min(now, undo.expiresAt)...undo.expiresAt, countsDown: true, showsHours: false)
                Text("left")
            }
        case .frozen:
            Text("\(GoFlow.clockText(seconds: GoFlow.undoSecondsLeft(undo, now: now))) left")
        }
    }
}
