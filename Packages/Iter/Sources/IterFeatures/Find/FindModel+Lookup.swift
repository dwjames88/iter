import Foundation
import IterModel
import IterSources
import IterStore
import IterDiscovery

// The typed lookup: your saved places and Apple Maps, run on Return. Saved matches show at once; Apple Maps fills in.

extension FindModel {
    func lookUp(_ query: String) {
        cancel()
        resetResults()
        notice = nil
        lookupGeneration += 1
        let mine = lookupGeneration
        phase = .lookingUp
        let needle = Self.fold(query)
        matches = library.places.savedValues().filter { Self.fold($0.name + " " + $0.locality).contains(needle) }.map { place in
            PlaceMatch(id: "place:\(place.id.uuidString)", name: place.name, subtitle: place.locality.isEmpty ? "Saved place" : place.locality,
                       coordinate: place.coordinate, origin: .saved, place: place)
        }
        rebuildMapContent()
        let search = placeSearch
        let around = region ?? location.current.map { GeoRegion(center: $0, latitudeDelta: 1, longitudeDelta: 1) }
            ?? GeoRegion(center: Coordinate(latitude: 20, longitude: 0), latitudeDelta: 120, longitudeDelta: 300)
        let timeout = configuration.lookupTimeout
        lookupTask = Task { [weak self] in
            let found = await withTimeout(timeout) { try await search.search(query, near: around) }
            guard let self, self.lookupGeneration == mine, !Task.isCancelled else { return }
            let known = Set(self.matches.map { Self.fold($0.name) })
            for c in found ?? [] {
                guard let coordinate = c.coordinate, !known.contains(Self.fold(c.name)) || c.source != .appleSearch else { continue }
                let id = "maps:\(c.id)"
                self.matches.append(PlaceMatch(id: id, name: c.name, subtitle: c.snippet ?? "Apple Maps", coordinate: coordinate, origin: .appleMaps,
                                               place: self.placeFromCandidate(c, coordinate: coordinate, id: id)))
            }
            self.phase = .finished
            self.rebuildMapContent()
        }
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func placeFromCandidate(_ c: PlaceCandidate, coordinate: Coordinate, id: String) -> Place {
        if let cached = places[id] { return cached }
        var place = Place(id: UUID(), externalID: c.externalID ?? c.id, name: c.name, locality: c.snippet ?? "", coordinate: coordinate,
                          timeZoneIdentifier: OwnSpotEditor.estimatedTimeZone(at: coordinate), category: .landscape,
                          elevationMeters: c.elevationMeters, origin: .appleMaps, sources: [c.source], citations: c.citations,
                          discoveredAt: now())
        place.createdAt = now()
        places[id] = place
        return place
    }
}
