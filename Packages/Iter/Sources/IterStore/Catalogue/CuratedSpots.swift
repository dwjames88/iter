import CryptoKit
import Foundation
import IterModel

/// The curated catalogue, loaded once from `Resources/curated-spots.json` as IterModel places (curated origin, the slug
/// in `curatedID`). Curated places are not stored in SwiftData; a saved curated place is a `PlaceRecord` with
/// `curatedID` set.
///
/// A catalogue place's `id` is derived from its slug, so it is the same on every launch and every device. The record
/// created when a user saves it gets its own id (as the old store did).
public enum CuratedSpots {
    public static let all: [Place] = load()

    private static let bySlug: [String: Place] = Dictionary(all.compactMap { place in
        place.curatedID.map { ($0, place) }
    }, uniquingKeysWith: { first, _ in first })

    /// The catalogue place with this slug.
    public static func spot(id slug: String) -> Place? { bySlug[slug] }

    /// The stable id of the catalogue place `slug`: the first 16 bytes of SHA-256 of "iter.curated.<slug>", as a
    /// version-5-shaped UUID.
    public static func stableID(forSlug slug: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data("iter.curated.\(slug)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// The JSON shape: the old `Spot`.
    private struct SpotDTO: Decodable {
        var id: String
        var name: String
        var locality: String
        var coordinate: Coordinate
        var timeZoneIdentifier: String
        var category: PlaceCategory
        var bestLight: [BestLight]
        var facing: Double?
        var blurb: String
        var notes: String
        var walkInMinutes: Int?
        var elevationMeters: Double?
        var popularity: Int
        var tags: [String]

        var place: Place {
            Place(id: CuratedSpots.stableID(forSlug: id), curatedID: id, name: name, locality: locality,
                  coordinate: coordinate, timeZoneIdentifier: timeZoneIdentifier, category: category, bestLight: bestLight,
                  facing: facing, blurb: blurb, notes: notes, walkInMinutes: walkInMinutes,
                  elevationMeters: elevationMeters, popularity: popularity, tags: tags, origin: .curated)
        }
    }

    private static func load() -> [Place] {
        guard let url = Bundle.module.url(forResource: "curated-spots", withExtension: "json") else {
            assertionFailure("curated-spots.json missing from the IterStore bundle")
            return []
        }
        do {
            return try JSONDecoder().decode([SpotDTO].self, from: Data(contentsOf: url)).map(\.place)
        } catch {
            assertionFailure("curated-spots.json failed to decode: \(error)")
            return []
        }
    }
}
