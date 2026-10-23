import SwiftUI
import IterCore
import IterDesign
import IterFeatures

/// A day's conflicts in one line, under the header. Each conflict is spelled out on its own stop or drive.
struct DayConflictRow: View {
    let count: Int

    var body: some View {
        Label {
            Text("^[\(count) conflict](inflect: true) on this day", comment: "Day summary: how many schedule conflicts the day has")
                .font(IterFont.subheadline)
                .foregroundStyle(IterColor.textPrimary)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(IterColor.warning)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, IterSpace.xs)
        .accessibilityElement(children: .combine)
    }
}
