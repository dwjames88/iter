import Foundation
import IterModel
import IterSources
import IterStore
import IterDiscovery

// Selection and the place card: what Save, Add to Trip, Open in Maps and Look Around act on.

extension FindModel {
    // MARK: Selecting

    /// Selects a result row, a typed match, or a saved or own place pin by id (what `FindPin.id` and `FindRow.id` carry).
    /// Does not move the map.
    public func select(_ id: String?) {
        guard let id else { deselect(); return }
        if let d = raw.first(where: { $0.id == id }) {
            show(card: discoveredCard(d), id: id, coordinate: d.coordinate.value)
            startDriveTimesForSelection()
        } else if let m = matches.first(where: { $0.id == id }) {
            show(card: placeCard(m.place, kind: m.origin == .saved ? .saved : .match), id: id, coordinate: m.coordinate)
        } else if id.hasPrefix("place:"), let uuid = UUID(uuidString: String(id.dropFirst(6))), let place = library.places.value(id: uuid) {
            show(card: placeCard(place, kind: place.origin == .user ? .own : .saved), id: id, coordinate: place.coordinate)
        } else {
            deselect()
        }
    }

    /// Opens the card for a place the shell already has (a saved place's page, a trip stop).
    public func selectPlace(_ place: Place) {
        let current = library.places.current(place)
        show(card: placeCard(current, kind: current.origin == .user ? .own : (library.places.isSaved(current) ? .saved : .match)),
             id: "place:\(current.id.uuidString)", coordinate: current.coordinate)
    }

    public func deselect() {
        selectionGeneration += 1
        lookTask?.cancel()
        selectedID = nil
        card = nil
        if cardScore != nil { cardScore = nil }
        lookAround = .unknown
    }

    private func show(card newCard: PlaceCard, id: String, coordinate: Coordinate) {
        selectionGeneration += 1
        selectedID = id
        card = newCard
        cardScore = scoreValues[id]
        refreshScoreRequests()
        checkLookAround(at: coordinate)
        resolveTimeZone(for: id, place: newCard.place)
    }

    private func startDriveTimesForSelection() {
        guard phase == .finished, location.current != nil, let id = selectedID, driveSeconds[id] == nil, !driveFailed.contains(id),
              !fetchingDrive.contains(id) else { return }
        startDriveTimes()
    }

    // MARK: Cards

    func placeForRow(_ d: DiscoveredPlace) -> Place {
        if let p = places[d.id] { return p }
        var place = d.makePlace(timeZoneIdentifier: OwnSpotEditor.estimatedTimeZone(at: d.coordinate.value), locality: area?.name ?? "",
                                discoveredAt: now(), id: UUID())
        place.externalID = d.id
        place.createdAt = now()
        places[d.id] = place
        return place
    }

    func discoveredCard(_ d: DiscoveredPlace) -> PlaceCard {
        let place = placeForRow(d)
        let row = makeRow(d)
        let names = sourceNames
        let cites = d.citations.enumerated().map { i, c in
            CardCitation(id: "\(c.source.rawValue)#\(i)", title: c.title, sourceName: name(of: c.source, in: names), url: c.url,
                         licence: c.licence.flatMap { Attribution.text(for: $0.key)?.short ?? $0.key })
        }
        return PlaceCard(id: d.id, kind: library.places.isSaved(place) ? .saved : .discovered, name: d.name, locality: place.locality,
                         why: row.why, whyIsModelWritten: row.whyIsModelWritten, sourceNames: row.sourceNames, verification: d.verification,
                         verificationLabel: row.verificationLabel, citations: cites, photo: row.photo, distanceText: row.distanceText,
                         drive: row.drive, lightSuit: row.lightSuit, isSaved: library.places.isSaved(place), coordinate: d.coordinate.value,
                         place: place)
    }

    func placeCard(_ place: Place, kind: PlaceCard.Kind) -> PlaceCard {
        let names = sourceNames
        let km = location.current.map { $0.distance(to: place.coordinate) / 1000 }
        let isOwn = place.origin == .user
        let verification: Verification? = isOwn ? .userPlaced : place.verification
        let label: String? = verification.map {
            switch $0 {
            case .confirmed: "Confirmed by \(max(2, place.sources.count)) sources"
            case .singleSource: "One source: " + (place.sources.first.map { name(of: $0, in: names) } ?? "unknown")
            case .userPlaced: "Placed by you"
            }
        }
        let cites = place.citations.enumerated().map { i, c in
            CardCitation(id: "\(c.source.rawValue)#\(i)", title: c.title, sourceName: name(of: c.source, in: names), url: c.url,
                         licence: c.licence.flatMap { Attribution.text(for: $0.key)?.short ?? $0.key })
        }
        let facing = place.facing != nil
        return PlaceCard(id: "place:\(place.id.uuidString)", kind: kind, name: place.name, locality: place.locality,
                         why: place.blurb.isEmpty ? nil : place.blurb, whyIsModelWritten: false,
                         sourceNames: place.sources.map { name(of: $0, in: names) }, verification: verification, verificationLabel: label,
                         citations: cites, photo: nil,
                         distanceText: km.map { "\($0 < 10 ? String(format: "%.1f", $0) : "\(Int($0.rounded()))") km from you" },
                         drive: driveTime(id: "place:\(place.id.uuidString)", km: km, basis: .fromYou),
                         lightSuit: LightSuit(facingKnown: facing, value: nil,
                                              note: facing ? "Faces \(Int(place.facing!.rounded()))°" : "No facing is known for this place."),
                         isSaved: library.places.isSaved(place), coordinate: place.coordinate, place: place)
    }

    func refreshCardDrive(_ id: String) {
        guard var c = card, c.id == id, let d = raw.first(where: { $0.id == id }) else { return }
        let row = makeRow(d)
        c.drive = row.drive
        if c != card { card = c }
    }

    // MARK: Time zone and Look Around

    /// The real time zone of a place (a reverse lookup) replaces the longitude estimate on the cached place, so saving it
    /// later stores the right zone.
    private func resolveTimeZone(for id: String, place: Place) {
        guard !zoneResolved.contains(id), zoneTasks[id] == nil else { return }
        let geocoder = self.geocoder
        let timeout = configuration.lookupTimeout
        let coordinate = place.coordinate
        zoneTasks[id] = Task { [weak self] in
            let result = await withTimeout(timeout) { try await geocoder.reverse(coordinate) }
            guard let self else { return }
            self.zoneTasks[id] = nil
            guard let zone = result?.timeZoneIdentifier, TimeZone(identifier: zone) != nil else { return }
            self.zoneResolved.insert(id)
            let key = self.places[id] != nil ? id : (self.places.first { $0.value.id == place.id }?.key ?? id)
            if var p = self.places[key] { p.timeZoneIdentifier = zone; self.places[key] = p }
            if var c = self.card, c.place.id == place.id {
                c.place.timeZoneIdentifier = zone
                self.card = c
            }
        }
    }

    private func checkLookAround(at coordinate: Coordinate) {
        lookTask?.cancel()
        guard let streetLevel else { lookAround = .satelliteFallback; return }
        lookAround = .checking
        let mine = selectionGeneration
        let timeout = configuration.lookupTimeout
        lookTask = Task { [weak self] in
            let available = await withTimeout(timeout) { try await streetLevel.isAvailable(at: coordinate) }
            guard let self, self.selectionGeneration == mine, !Task.isCancelled else { return }
            self.lookAround = available == true ? .available : .satelliteFallback
        }
    }

    // MARK: Save, Add to Trip, Open in Maps

    /// Saves or unsaves the selected place (one undo, "Save Place" or "Remove Place"). Waits briefly for the real time zone
    /// of a freshly selected place so the saved copy has it.
    public func setSaved(_ saved: Bool) async {
        guard let id = selectedID, var c = card else { return }
        if saved, let task = zoneTasks[id] { await task.value }
        guard selectedID == id, let current = card else { return }
        c = current
        library.places.setSaved(c.place, saved)
        c.isSaved = library.places.isSaved(c.place)
        if c.kind != .own { c.kind = c.isSaved ? .saved : (raw.contains { $0.id == id } ? .discovered : .match) }
        card = c
        if let d = raw.first(where: { $0.id == id }) { _ = d; refreshRow(id) }
        refreshLibraryPins()
    }

    /// The toggle behind the Save / Saved button.
    public func toggleSaved() {
        guard let c = card else { return }
        Task { [weak self] in await self?.setSaved(!c.isSaved) }
    }

    /// The trips the Add to Trip menu lists, newest first, ahead of "New Trip…".
    public func tripChoices() -> [TripChoice] {
        library.trips.all().map { TripChoice(id: $0.id, name: $0.name, dayCount: $0.dayCount, stopCount: $0.stops?.count ?? 0) }
    }

    /// Adds the selected place to a trip (saving it with the stop, as the store does). `day` is zero-based.
    @discardableResult
    public func addToTrip(_ tripID: UUID, day: Int = 0) -> Bool {
        guard let c = card, let trip = library.trips.trip(id: tripID) else { return false }
        library.trips.addStop(c.place, to: trip, day: day)
        var updated = c
        updated.isSaved = library.places.isSaved(c.place)
        card = updated
        refreshLibraryPins()
        return true
    }

    /// New Trip…: creates a trip starting `startDay` with `dayCount` days and adds the selected place to its first day.
    @discardableResult
    public func addToNewTrip(named name: String, startDay: LocalDay, dayCount: Int = 1) -> UUID? {
        guard card != nil else { return nil }
        let trip = library.trips.create(name: name, startDay: startDay, dayCount: dayCount)
        return addToTrip(trip.id) ? trip.id : nil
    }

    /// What Open in Maps hands the shell: the name and exact coordinate of the selected place.
    public var mapsTarget: (name: String, coordinate: Coordinate)? { card.map { ($0.name, $0.coordinate) } }

    // MARK: Own spots on the Find map

    /// A click on the map in Add Spot mode: drops a pin and selects the new spot's card.
    @discardableResult
    public func dropPin(at coordinate: Coordinate) async -> DroppedSpot? {
        guard let dropped = await spots.drop(at: coordinate) else { return nil }
        refreshLibraryPins()
        selectPlace(dropped.place)
        return dropped
    }

    /// Moves the selected own spot (drag drop, typed fields, Adjust Location) and refreshes its card and pin.
    public func didMoveSpot(_ id: UUID) {
        refreshLibraryPins()
        if let place = library.places.value(id: id), selectedID == "place:\(id.uuidString)" { selectPlace(place) }
    }
}
