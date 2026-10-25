import SwiftUI
import IterDesign

/// Every screen that shows sample weather carries this label.
struct SampleDataLabel: View {
    enum Style { case inline, banner }
    var style: Style = .inline

    var body: some View {
        switch style {
        case .inline:
            Label(String(localized: "Sample data", comment: "Label on scores made from sample weather"), systemImage: "flask")
                .labelStyle(.titleAndIcon)
                .font(IterFont.secondary)
                .foregroundStyle(IterColor.textSecondary)
        case .banner:
            Label {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Sample data", comment: "Banner title when sample weather is on")
                        .font(IterFont.captionStrong)
                    Text("Scores use made-up weather. Turn off in the Debug menu.", comment: "Banner explanation")
                        .font(IterFont.caption)
                        .foregroundStyle(IterColor.textSecondary)
                        // No `fixedSize(vertical:)` here: the banner sits in the sidebar column, and a height that depends
                        // on the width makes the column's minimum size change during AppKit's constraints pass. With the
                        // trip inspector open that never settled and AppKit threw "more Update Constraints in Window
                        // passes than there are views". Unfixed, the text still wraps to the lines it needs.
                        .lineLimit(nil)
                }
            } icon: {
                Image(systemName: "flask").foregroundStyle(IterColor.warning)
            }
            .padding(IterSpace.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ControlFill(), in: RoundedRectangle(cornerRadius: IterRadius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: IterRadius.control, style: .continuous)
                .strokeBorder(IterColor.warning, lineWidth: IterStroke.thin))
        }
    }
}
