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
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: "flask").foregroundStyle(IterColor.warning)
            }
            .padding(IterSpace.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(IterColor.backgroundControl, in: RoundedRectangle(cornerRadius: IterRadius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: IterRadius.control, style: .continuous)
                .strokeBorder(IterColor.warning, lineWidth: IterStroke.thin))
        }
    }
}
