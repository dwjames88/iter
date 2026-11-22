import Foundation
import IterCore

/// The curated catalogue, loaded once from `Resources/curated-spots.json`.
/// Curated spots are not stored in SwiftData; a saved curated spot is a `PlaceRecord` with `curatedID` set.
public enum CuratedSpots {
    public static let all: [Spot] = load()

    private static let byID: [String: Spot] = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    public static func spot(id: String) -> Spot? { byID[id] }

    private static func load() -> [Spot] {
        guard let url = Bundle.module.url(forResource: "curated-spots", withExtension: "json") else {
            assertionFailure("curated-spots.json missing from the IterData bundle")
            return []
        }
        do {
            return try JSONDecoder().decode([Spot].self, from: Data(contentsOf: url))
        } catch {
            assertionFailure("curated-spots.json failed to decode: \(error)")
            return []
        }
    }
}
