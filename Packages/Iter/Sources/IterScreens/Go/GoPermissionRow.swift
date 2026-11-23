import SwiftUI
import IterGoActivity
import IterFeatures
import IterUI

/// ONE calm inline row for the next thing Go needs: an icon, one plain sentence of why, one bordered button. Never a
/// wall: the rest of the screen stays fully usable whatever the answer.
struct GoPermissionRow: View {
    let step: GoPermissionStep
    let actions: GoActions

    var body: some View {
        let copy = GoFlow.permissionCopy(step)
        HStack(alignment: .center, spacing: IterSpace.md) {
            Image(systemName: copy.symbol)
                .font(IterFont.headline)
                .foregroundStyle(IterColor.textSecondary)
                .frame(width: IterSize.iconLarge)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: IterSpace.sm) {
                Text(copy.sentence)
                    .font(IterFont.subheadline)
                    .foregroundStyle(IterColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(copy.button) { run(copy.action) }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .frame(minHeight: IterSize.hitTarget)
            }
        }
        .goScreenCard()
        .accessibilityElement(children: .contain)
    }

    private func run(_ action: GoFlow.PermissionCopy.Action) {
        switch action {
        case .allowWhenInUse: actions.requestLocationWhenInUse()
        case .allowAlways: actions.requestLocationAlways()
        case .allowNotifications: Task { await actions.requestNotifications() }
        case .openSettings: actions.openSettings()
        }
    }
}
