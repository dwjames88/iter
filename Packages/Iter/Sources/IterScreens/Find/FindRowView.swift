import SwiftUI
import IterFeatures
import IterModel
import IterSources
import IterUI

/// One result in the list: photo thumbnail if any, name, locality and kinds, distance with its drive or straight-line label,
/// the verification label and the sources. No score chip: a discovered place has no scored window until Conditions has run for it.
///
/// `Equatable` and drawn with `.equatable()`: a row that did not change is not rebuilt when another row's drive time lands.
/// It takes no hover state. The row sits on the glass card, so its fills are the `isOnGlass` ones.
struct FindRowView: View, Equatable {
    let row: FindRow
    let locality: String

    var body: some View {
        HStack(alignment: .top, spacing: IterSpace.md) {
            if row.photo != nil { FindThumbnail(photo: row.photo) }
            VStack(alignment: .leading, spacing: IterSpace.xs) {
                HStack(alignment: .firstTextBaseline, spacing: IterSpace.xs) {
                    Text(verbatim: row.name)
                        .font(IterFont.headline)
                        .foregroundStyle(IterColor.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if row.isSaved {
                        Image(systemName: "bookmark.fill")
                            .font(IterFont.caption)
                            .foregroundStyle(IterColor.accentText)
                            .accessibilityHidden(true)
                    }
                }
                let subtitle = FindText.subtitle(locality: locality, kinds: row.kindsText)
                if !subtitle.isEmpty {
                    Text(verbatim: subtitle)
                        .font(IterFont.secondary)
                        .foregroundStyle(IterColor.textSecondary)
                        .lineLimit(1)
                }
                if let line = FindText.distanceLine(distanceText: row.distanceText, drive: row.drive) {
                    Text(verbatim: line)
                        .font(IterFont.secondary)
                        .foregroundStyle(IterColor.textSecondary)
                        .lineLimit(1)
                }
                FindVerificationLine(verification: row.verification, sources: row.sourceNames)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, IterSpace.sm)
        .frame(minHeight: IterGrid.rowDouble, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: FindText.rowAccessibility(row, locality: locality)))
    }
}

/// "Confirmed" or "Single source" with a symbol (never colour alone), then the source names in a quiet tail.
struct FindVerificationLine: View, Equatable {
    let verification: Verification
    let sources: [String]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: IterSpace.xs) {
            Image(systemName: FindText.verificationSymbol(verification))
                .font(IterFont.caption)
                .foregroundStyle(verification == .confirmed ? IterColor.accentText : IterColor.textSecondary.color)
                .accessibilityHidden(true)
            Text(verbatim: FindText.verificationShort(verification))
                .font(IterFont.captionStrong)
                .foregroundStyle(IterColor.textSecondary)
            if !sources.isEmpty {
                Text(verbatim: "· " + sources.joined(separator: ", "))
                    .font(IterFont.caption)
                    .foregroundStyle(IterColor.textTertiary)
                    .lineLimit(1)
            }
        }
    }
}

/// A 48 pt thumbnail, inset and rounded, on the control fill while it loads (or when the image cannot be fetched).
struct FindThumbnail: View, Equatable {
    let photo: LicensedPhoto?
    static let size: CGFloat = 48

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: IterRadius.control, style: .continuous)
        AsyncImage(url: photo?.thumbnailURL ?? photo?.imageURL) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            ZStack {
                Rectangle().fill(ControlFill())
                Image(systemName: "photo")
                    .foregroundStyle(IterColor.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: Self.size, height: Self.size)
        .clipShape(shape)
        .accessibilityHidden(true)
    }
}

/// One typed-lookup match: your saved place or an Apple Maps result.
struct FindMatchRowView: View, Equatable {
    let match: PlaceMatch

    var body: some View {
        HStack(spacing: IterSpace.md) {
            Image(systemName: match.origin == .saved ? "bookmark.fill" : "mappin.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(match.origin == .saved ? IterColor.accentText : IterColor.textSecondary.color)
                .frame(width: FindThumbnail.size / 2 + 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: IterSpace.xxs) {
                Text(verbatim: match.name)
                    .font(IterFont.headline)
                    .foregroundStyle(IterColor.textPrimary)
                    .lineLimit(2)
                Text(verbatim: match.subtitle)
                    .font(IterFont.secondary)
                    .foregroundStyle(IterColor.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(verbatim: match.origin == .saved ? "Saved" : "Apple Maps")
                .font(IterFont.caption)
                .foregroundStyle(IterColor.textTertiary)
        }
        .padding(.vertical, IterSpace.sm)
        .frame(minHeight: IterGrid.rowDouble, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(match.name), \(match.subtitle), \(match.origin == .saved ? "saved place" : "Apple Maps")"))
    }
}
