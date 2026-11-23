import SwiftUI
import MapKit
import IterFeatures
import IterModel
import IterUI

/// Words and values the place card derives; pure, so tests check them.
enum FindCardText {
    /// "Canyonlands · 23 km from you · 25 min drive · Confirmed by 3 sources".
    static func detailLine(_ card: PlaceCard) -> String {
        [card.locality, FindText.distanceLine(distanceText: card.distanceText, drive: card.drive), card.verificationLabel]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The date a citation was retrieved, matched to the place's own citation list (the card's id is "source#index").
    static func retrievedAt(_ citation: CardCitation, in place: Place) -> Date? {
        guard let hash = citation.id.lastIndex(of: "#"), let i = Int(citation.id[citation.id.index(after: hash)...]),
              place.citations.indices.contains(i), place.citations[i].title == citation.title else {
            return place.citations.first { $0.title == citation.title }?.retrievedAt
        }
        return place.citations[i].retrievedAt
    }

    /// "Mesa Arch (OpenStreetMap) · OpenStreetMap · Retrieved Oct 12, 2026 · ODbL" pieces after the title.
    static func citationDetail(_ citation: CardCitation, retrieved: Date?, locale: Locale = .current) -> String {
        var parts = [citation.sourceName]
        if let retrieved { parts.append("Retrieved " + retrieved.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale))) }
        if let licence = citation.licence { parts.append(licence) }
        return parts.joined(separator: " · ")
    }

    /// An Apple Maps link for Share: the place's name at its exact coordinate.
    static func shareURL(name: String, coordinate: Coordinate) -> URL {
        var c = URLComponents()
        c.scheme = "https"
        c.host = "maps.apple.com"
        c.queryItems = [URLQueryItem(name: "ll", value: String(format: "%.6f,%.6f", coordinate.latitude, coordinate.longitude)),
                        URLQueryItem(name: "q", value: name)]
        return c.url ?? URL(string: "https://maps.apple.com")!
    }

    static func placeID(from id: String) -> UUID? {
        id.hasPrefix("place:") ? UUID(uuidString: String(id.dropFirst(6))) : nil
    }
}

/// The place card on the floating panel: Back, Share and Close glass circles, the place, one action row, the picture, why it
/// the place's conditions (the headline window and best day), the picture, why it is listed, where that comes from, the honest
/// light note, and a link to the place's page. The header carries the card's one score.
struct FindPlaceCard: View {
    @Bindable var model: FindModel
    let card: PlaceCard
    let conditions: ConditionsModel?
    var onBack: () -> Void
    var onClose: () -> Void
    @Environment(AppNavigator.self) private var navigator: AppNavigator?
    @State private var trips: [TripChoice]
    @State private var addedTo: String?

    init(model: FindModel, card: PlaceCard, conditions: ConditionsModel?, onBack: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.model = model
        self.card = card
        self.conditions = conditions
        self.onBack = onBack
        self.onClose = onClose
        _trips = State(initialValue: model.tripChoices())
    }

    private var canEdit: Bool { card.isOwn || card.isSaved }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IterSpace.lg) {
                header
                title
                actions
                if let addedTo {
                    Label("Added to \(addedTo)", systemImage: "checkmark.circle.fill")
                        .font(IterFont.secondary)
                        .foregroundStyle(IterColor.accentText)
                        .padding(.horizontal, IterSpace.lg)
                }
                Group {
                    // The point of the card first: the headline window and the best day. Then the place itself.
                    if let conditions { ConditionsSummary(model: conditions, showsChip: model.cardScore == nil) }
                    if card.isOwn, let id = FindCardText.placeID(from: card.id) {
                        FindCoordinateSection(model: model, placeID: id, coordinate: card.coordinate, elevationMeters: card.place.elevationMeters)
                        Label("Drag the pin to move it, or choose Adjust Location.", systemImage: "hand.draw")
                            .font(IterFont.caption)
                            .foregroundStyle(IterColor.textTertiary)
                    }
                    FindImagery(coordinate: card.coordinate, availability: model.lookAround)
                    if let why = card.why { whyLine(why) }
                    if !card.sourceNames.isEmpty, !card.isOwn {
                        Text(verbatim: "Listed by " + card.sourceNames.joined(separator: ", "))
                            .font(IterFont.caption)
                            .foregroundStyle(IterColor.textTertiary)
                    }
                    if !card.citations.isEmpty { citations }
                    if let photo = card.photo { FindPhotoView(photo: photo) }
                    lightNote
                    if canEdit {
                        Button { navigator?.open(.place(card.place.id)) } label: { Text("Open Place Page") }
                            #if os(macOS)
                            .buttonStyle(.link)
                            #else
                            .buttonStyle(.borderless)
                            #endif
                            .foregroundStyle(IterColor.accentText)
                    }
                }
                .padding(.horizontal, IterSpace.lg)
            }
            .padding(.bottom, IterSpace.xl)
        }
        .scrollIndicators(.automatic)
        .onAppear { trips = model.tripChoices() }
        .onChange(of: card.id) { addedTo = nil; trips = model.tripChoices() }
        #if os(macOS)
        .onExitCommand(perform: onBack)
        #endif
    }

    // MARK: Header

    private var header: some View {
        GlassEffectContainer(spacing: IterSpace.sm) {
            HStack(spacing: IterSpace.sm) {
                Button(action: onBack) { Label("Back", systemImage: "chevron.backward") }
                    .help("Back to Results (Esc)")
                Spacer(minLength: 0)
                ShareLink(item: FindCardText.shareURL(name: card.name, coordinate: card.coordinate), subject: Text(verbatim: card.name),
                          message: Text(verbatim: "\(card.name), \(FindText.coordinateLine(card.coordinate))")) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .help("Share this place")
                Button(action: onClose) { Label("Close", systemImage: "xmark") }
                    .help("Close")
            }
            .buttonStyle(GlassCircleButtonStyle())
        }
        .padding(.horizontal, GlassCircleButtonStyle.inset)
        .padding(.top, GlassCircleButtonStyle.inset)
    }

    private var title: some View {
        HStack(alignment: .top, spacing: IterGrid.laneGap) {
            titleText
            Spacer(minLength: 0)
            // The card's one score, in its header.
            if let score = model.cardScore { FindScoreChip(score: score, size: .large).equatable() }
        }
        .padding(.horizontal, IterSpace.lg)
    }

    private var titleText: some View {
        VStack(alignment: .leading, spacing: IterSpace.xs) {
            Text(verbatim: card.name)
                .font(IterFont.titleSpot)
                .foregroundStyle(IterColor.textPrimary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .firstTextBaseline, spacing: IterSpace.xs) {
                if let v = card.verification {
                    Image(systemName: FindText.verificationSymbol(v)).foregroundStyle(IterColor.textSecondary).accessibilityHidden(true)
                }
                Text(verbatim: FindCardText.detailLine(card)).lineLimit(3)
            }
            .font(IterFont.secondary)
            .foregroundStyle(IterColor.textSecondary)
        }
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: IterSpace.sm) {
            Menu {
                ForEach(trips) { trip in
                    Button { add(to: trip) } label: { Text(verbatim: trip.name) }
                }
                if !trips.isEmpty { Divider() }
                Button("New Trip…") { newTrip() }
            } label: {
                Label("Add to Trip", systemImage: "plus")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .placeAction(isProminent: true)
            if !card.isOwn {
                Button { model.toggleSaved() } label: {
                    Label(card.isSaved ? "Saved" : "Save", systemImage: card.isSaved ? "bookmark.fill" : "bookmark")
                }
                .placeAction()
            }
            if canEdit {
                Button { navigator?.present(.editPlace(card.place.id)) } label: { Label("Edit", systemImage: "pencil") }
                    .placeAction()
            }
            Button { openInMaps() } label: { Label("Open in Maps", systemImage: "map") }
                .placeAction()
        }
        .padding(.horizontal, IterSpace.lg)
    }

    private func add(to trip: TripChoice) {
        if model.addToTrip(trip.id) { addedTo = trip.name }
        trips = model.tripChoices()
    }

    /// Saves the place first, so the New Trip sheet can name it as the first stop.
    private func newTrip() {
        Task {
            await model.setSaved(true)
            if let current = model.card { navigator?.present(.newTrip(templateID: nil, firstPlace: current.place.id)) }
        }
    }

    private func openInMaps() {
        guard let target = model.mapsTarget else { return }
        let item = MKMapItem(location: CLLocation(latitude: target.coordinate.latitude, longitude: target.coordinate.longitude), address: nil)
        item.name = target.name
        item.openInMaps()
    }

    // MARK: Content

    private func whyLine(_ why: String) -> some View {
        VStack(alignment: .leading, spacing: IterSpace.xs) {
            Text(verbatim: why).font(IterFont.callout).foregroundStyle(IterColor.textPrimary).fixedSize(horizontal: false, vertical: true)
            if card.whyIsModelWritten {
                Label("Written by Apple Intelligence", systemImage: "sparkles")
                    .font(IterFont.caption)
                    .foregroundStyle(IterColor.textTertiary)
            }
        }
    }

    private var citations: some View {
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            Text("Sources").font(IterFont.moduleTitle).foregroundStyle(IterColor.textSecondary)
            ForEach(card.citations) { c in
                VStack(alignment: .leading, spacing: IterSpace.xxs) {
                    if let url = c.url {
                        Link(destination: url) { Text(verbatim: c.title).multilineTextAlignment(.leading) }
                            .font(IterFont.secondary)
                            .foregroundStyle(IterColor.accentText)
                    } else {
                        Text(verbatim: c.title).font(IterFont.secondary).foregroundStyle(IterColor.textPrimary)
                    }
                    Text(verbatim: FindCardText.citationDetail(c, retrieved: FindCardText.retrievedAt(c, in: card.place)))
                        .font(IterFont.caption)
                        .foregroundStyle(IterColor.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(IterSpace.md)
        .background(ModuleFill(), in: RoundedRectangle(cornerRadius: IterRadius.card, style: .continuous))
    }

    private var lightNote: some View {
        Label {
            Text(verbatim: card.lightSuit.text)
        } icon: {
            Image(systemName: card.lightSuit.facingKnown ? "sun.max.fill" : "sun.max")
        }
        .font(IterFont.secondary)
        .foregroundStyle(IterColor.textSecondary)
    }
}
