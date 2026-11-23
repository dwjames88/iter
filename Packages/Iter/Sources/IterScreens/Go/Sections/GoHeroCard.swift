import SwiftUI
import IterModel
import IterGo
import IterGoActivity
import IterUI

/// The big glanceable card at the top of the Go sheet, one layout per phase: before departure (leave-by), driving
/// (arrival), at a stop (the window and the cost of staying) and paused. Values in, `GoActions` out; never the model.
/// Solid content card; the buttons are the system glass styles in one `GlassEffectContainer`, one prominent per card.
///
/// The hero time uses `IterFont.titleSpot`, the largest token; there is no bigger one and none is invented here.
public struct GoHeroCard: View {
    public let snapshot: GoSnapshot
    public let now: Date
    public let actions: GoActions

    @Environment(\.goClockMode) private var clock
    @Environment(\.locale) private var locale

    public init(snapshot: GoSnapshot, now: Date, actions: GoActions) {
        self.snapshot = snapshot
        self.now = now
        self.actions = actions
    }

    public var body: some View {
        if let kind = GoText.heroKind(snapshot) {
            VStack(alignment: .leading, spacing: IterSpace.md) {
                switch kind {
                case .beforeDeparture: before
                case .driving: driving
                case .atStop: atStop
                case .paused: paused
                }
            }
            .goCard()
            .accessibilityElement(children: .contain)
        }
    }

    // MARK: Before departure

    @ViewBuilder private var before: some View {
        let next = snapshot.next
        header("Next Stop", status: GoText.statusWord(snapshot, locale: locale))
        if let next { Text(verbatim: next.name).font(IterFont.titleSection).foregroundStyle(IterColor.textPrimary).lineLimit(2) }
        VStack(alignment: .leading, spacing: IterSpace.xs) {
            bigTime(GoText.leaveHeadline(snapshot, locale: locale),
                    ink: snapshot.leave?.status == .late ? IterColor.warning : IterColor.textPrimary.color)
            if let c = GoText.leaveCountdown(snapshot, now: now, locale: locale) {
                countdown(c.text, tone: c.tone, target: snapshot.leave?.leaveBy)
            }
        }
        VStack(alignment: .leading, spacing: IterSpace.xs) {
            if let drive = snapshot.drive {
                GoLine("car") { Text(verbatim: GoText.driveLine(drive, locale: locale)) }
                GoLine(GoText.etaQualitySymbol(drive.source)) { Text(verbatim: GoText.etaQuality(drive.source, locale: locale)) }
            }
            if let line = GoText.arrivalAgainstLight(snapshot, locale: locale) {
                GoLine("flag.checkered") { Text(verbatim: line) }
            }
            if let line = GoText.eveningBefore(snapshot, locale: locale) {
                GoLine("moon.stars") { Text(verbatim: line).foregroundStyle(IterColor.textPrimary) }
            }
            if let line = GoText.earliestDeparture(snapshot, now: now, locale: locale) {
                GoLine("hourglass") { Text(verbatim: line) }
            }
        }
        .font(IterFont.callout)
        .foregroundStyle(IterColor.textSecondary)
        buttons {
            navigateButton()
            plain("Leave Now", symbol: "figure.walk.departure") { await actions.leaveNow() }
        }
    }

    // MARK: Driving

    @ViewBuilder private var driving: some View {
        header("Heading To", status: nil)
        if let next = snapshot.next { Text(verbatim: next.name).font(IterFont.titleSection).foregroundStyle(IterColor.textPrimary).lineLimit(2) }
        let status = GoText.drivingStatus(snapshot, locale: locale)
        VStack(alignment: .leading, spacing: IterSpace.xs) {
            bigTime(GoText.arriveHeadline(snapshot, locale: locale), ink: status.tone == .late ? IterColor.warning : IterColor.textPrimary.color)
            if let c = GoText.arriveCountdown(snapshot, now: now, locale: locale) {
                countdown(c, tone: .normal, target: snapshot.drive?.arrival)
            }
        }
        VStack(alignment: .leading, spacing: IterSpace.xs) {
            GoLine(status.symbol) { Text(verbatim: status.text) }
                .foregroundStyle(tint(status.tone))
            if let drive = snapshot.drive {
                GoLine(GoText.etaQualitySymbol(drive.source)) {
                    Text(verbatim: "\(GoText.etaQuality(drive.source, locale: locale)) · \(GoText.driveLine(drive, locale: locale))")
                }
                .foregroundStyle(IterColor.textSecondary)
            }
        }
        .font(IterFont.callout)
        if let alt = GoText.alternative(snapshot, locale: locale) {
            VStack(alignment: .leading, spacing: IterSpace.sm) {
                Divider()
                Text(verbatim: alt.title).font(IterFont.headline).foregroundStyle(IterColor.textPrimary)
                Text(verbatim: alt.detail).font(IterFont.callout).foregroundStyle(IterColor.textSecondary)
                buttons {
                    // Skipping the current target makes the engine move on to the next-best stop it is already offering.
                    plain("Go There Instead", symbol: "arrow.triangle.turn.up.right.diamond") { await actions.skip(nil) }
                }
            }
        }
        buttons {
            navigateButton()
            plain("I'm Here", symbol: "mappin.and.ellipse") { await actions.arrived() }
        }
    }

    // MARK: At a stop

    @ViewBuilder private var atStop: some View {
        header("Now Shooting", status: nil)
        if let cur = snapshot.current { Text(verbatim: cur.name).font(IterFont.titleSection).foregroundStyle(IterColor.textPrimary).lineLimit(2) }
        if let w = GoText.windowLeft(snapshot, now: now, locale: locale) {
            Text(verbatim: w).font(IterFont.titleSpot).foregroundStyle(IterColor.textPrimary).monospacedDigit()
                .minimumScaleFactor(0.6).lineLimit(2)
        }
        if let stay = GoText.stayCost(snapshot, locale: locale) {
            GoLine(stay.warns ? "exclamationmark.triangle.fill" : "checkmark.circle") { Text(verbatim: stay.text) }
                .font(IterFont.callout)
                .foregroundStyle(stay.warns ? IterColor.warning : IterColor.textSecondary.color)
        }
        buttons {
            plain("Done Here", symbol: "checkmark", prominent: true) { await actions.doneHere() }
            if snapshot.next != nil {
                plain("Skip Next", symbol: "forward.end") { await actions.skip(nil) }
            }
        }
        if let next = snapshot.next {
            buttons {
                Button { actions.navigate(NavigationHandoff(destination: next.coordinate, name: next.name)) } label: {
                    Label { Text("Navigate to \(next.name)") } icon: { Image(systemName: "location.fill") }
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: IterSize.hitTarget)
                }
                .buttonStyle(.glass)
            }
        }
    }

    // MARK: Paused

    @ViewBuilder private var paused: some View {
        header("Paused", status: nil)
        Text(verbatim: GoText.pausedTitle).font(IterFont.titleSection).foregroundStyle(IterColor.textPrimary)
        if let d = GoText.pausedDetail(snapshot, locale: locale) {
            Text(verbatim: d).font(IterFont.callout).foregroundStyle(IterColor.textSecondary)
        }
        buttons { plain("Resume", symbol: "play.fill", prominent: true) { await actions.resume() } }
    }

    // MARK: Pieces

    private func header(_ title: LocalizedStringKey, status: (text: String, symbol: String, tone: GoText.LeaveTone)?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(IterFont.captionStrong).foregroundStyle(IterColor.textSecondary)
            Spacer(minLength: IterSpace.sm)
            if let status {
                Label { Text(verbatim: status.text) } icon: { Image(systemName: status.symbol) }
                    .font(IterFont.captionStrong)
                    .foregroundStyle(tint(status.tone))
            }
        }
    }

    private func tint(_ tone: GoText.LeaveTone) -> Color {
        switch tone {
        case .normal: IterColor.textSecondary.color
        case .now: IterColor.accentText
        case .late: IterColor.warning
        }
    }

    private func bigTime(_ text: String, ink: Color) -> some View {
        Text(verbatim: text)
            .font(IterFont.titleSpot)
            .foregroundStyle(ink)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    /// "in 42 min": in `.live` mode a self-updating relative text while the target is ahead; plain text otherwise.
    @ViewBuilder private func countdown(_ text: String, tone: GoText.LeaveTone, target: Date?) -> some View {
        Group {
            if clock == .live, tone == .normal, let target, target.timeIntervalSince(now) > TripText.nowTolerance {
                Text("in \(Text(target, style: .relative))")
            } else {
                Text(verbatim: text)
            }
        }
        .font(IterFont.headline)
        .foregroundStyle(tone == .late ? IterColor.warning : IterColor.textPrimary.color)
    }

    private func buttons(@ViewBuilder _ content: () -> some View) -> some View {
        GlassEffectContainer(spacing: IterSpace.sm) {
            HStack(spacing: IterSpace.sm) { content() }
        }
        .controlSize(.large)
    }

    private func navigateButton() -> some View {
        Button {
            if let next = snapshot.next { actions.navigate(NavigationHandoff(destination: next.coordinate, name: next.name)) }
        } label: {
            Label { Text("Navigate") } icon: { Image(systemName: "location.fill") }
                .frame(maxWidth: .infinity, minHeight: IterSize.hitTarget)
        }
        .buttonStyle(.glassProminent)
    }

    @ViewBuilder
    private func plain(_ title: LocalizedStringKey, symbol: String, prominent: Bool = false,
                       run: @escaping @MainActor () async -> Void) -> some View {
        let label = Label { Text(title) } icon: { Image(systemName: symbol) }
            .frame(maxWidth: .infinity, minHeight: IterSize.hitTarget)
        if prominent {
            Button { Task { await run() } } label: { label }.buttonStyle(.glassProminent)
        } else {
            Button { Task { await run() } } label: { label }.buttonStyle(.glass)
        }
    }
}
