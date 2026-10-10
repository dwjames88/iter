import Foundation
import IterCore
import IterServices

/// Canned answers for screenshots: `-IterDiscoveryStub results` (Discovery) and `-IterScoutStub results` (the names Ask
/// proposes for Search Here). Both are honoured only with `-IterInMemoryStore YES` (see `AppLaunch`), so they never touch
/// real data, and they need no network. The places are real, named landmarks with approximate coordinates; nothing here
/// ships a score or a forecast.
enum StubPlaces {
    struct Entry {
        var name: String
        var latitude: Double
        var longitude: Double
        var feature: FeatureKind
        var elevationMeters: Double?
        var sources: Set<DiscoverySourceID>
        var why: String

        var coordinate: Coordinate { Coordinate(latitude: latitude, longitude: longitude) }
    }

    static let all: [Entry] = [
        // Glacier National Park
        Entry(name: "Mount Cleveland", latitude: 48.9297, longitude: -113.8478, feature: .peak, elevationMeters: 3190,
              sources: [.openStreetMap, .wikipedia], why: "The park's highest summit."),
        Entry(name: "Mount Siyeh", latitude: 48.7367, longitude: -113.6636, feature: .peak, elevationMeters: 3052,
              sources: [.openStreetMap, .wikipedia], why: "Tallest peak in the Lewis Range's southern half."),
        Entry(name: "Mount Gould", latitude: 48.7664, longitude: -113.7177, feature: .peak, elevationMeters: 2912,
              sources: [.openStreetMap, .wikipedia], why: "Rises above Grinnell Glacier."),
        Entry(name: "Reynolds Mountain", latitude: 48.7000, longitude: -113.7215, feature: .peak, elevationMeters: 2781,
              sources: [.openStreetMap, .wikipedia], why: "Seen across Logan Pass."),
        Entry(name: "Mount Oberlin", latitude: 48.6967, longitude: -113.7290, feature: .peak, elevationMeters: 2489,
              sources: [.openStreetMap], why: "A short climb from Logan Pass."),
        Entry(name: "Grinnell Point", latitude: 48.7556, longitude: -113.7167, feature: .peak, elevationMeters: 2210,
              sources: [.openStreetMap, .wikivoyage], why: "Reflects in Swiftcurrent Lake."),
        Entry(name: "Hidden Lake Overlook", latitude: 48.6955, longitude: -113.7180, feature: .viewpoint, elevationMeters: 2100,
              sources: [.wikivoyage, .openStreetMap], why: "Boardwalk to a lake below Bearhat Mountain."),
        Entry(name: "Lake McDonald", latitude: 48.5985, longitude: -113.9150, feature: .lake, elevationMeters: 964,
              sources: [.wikipedia, .openStreetMap], why: "The park's largest lake, with coloured stones."),
        // Moab
        Entry(name: "Corona Arch", latitude: 38.5775, longitude: -109.6300, feature: .arch, elevationMeters: 1250,
              sources: [.wikipedia, .openStreetMap], why: "A large arch with a rope swing beneath."),
        Entry(name: "Dead Horse Point", latitude: 38.4837, longitude: -109.7414, feature: .viewpoint, elevationMeters: 1780,
              sources: [.wikipedia, .wikivoyage], why: "Overlooks a gooseneck of the Colorado River."),
        Entry(name: "Fisher Towers", latitude: 38.7253, longitude: -109.3078, feature: .peak, elevationMeters: 1660,
              sources: [.wikipedia, .openStreetMap], why: "Red sandstone spires."),
        // Yosemite
        Entry(name: "Glacier Point", latitude: 37.7306, longitude: -119.5735, feature: .viewpoint, elevationMeters: 2199,
              sources: [.wikipedia, .openStreetMap], why: "Looks across the valley at Half Dome."),
        Entry(name: "Olmsted Point", latitude: 37.8097, longitude: -119.4850, feature: .viewpoint, elevationMeters: 2400,
              sources: [.wikivoyage, .openStreetMap], why: "Granite domes on Tioga Road."),
        Entry(name: "Half Dome", latitude: 37.7459, longitude: -119.5332, feature: .peak, elevationMeters: 2693,
              sources: [.wikipedia, .openStreetMap], why: "Yosemite's best-known granite dome."),
    ]

    /// The areas the stub engine can name; anything else is "not found", as a real lookup of an unknown place would be.
    static let areas: [(keys: [String], name: String, region: GeoRegion)] = [
        (["glacier"], "Glacier National Park", GeoRegion(center: Coordinate(latitude: 48.76, longitude: -113.79), latitudeDelta: 0.9, longitudeDelta: 1.1)),
        (["moab", "arches", "canyonlands"], "Moab", GeoRegion(center: Coordinate(latitude: 38.6, longitude: -109.55), latitudeDelta: 0.5, longitudeDelta: 0.7)),
        (["yosemite"], "Yosemite National Park", GeoRegion(center: Coordinate(latitude: 37.8, longitude: -119.5), latitudeDelta: 0.7, longitudeDelta: 0.9)),
    ]

    /// Names for Ask to propose in `region`: the nearest few canned landmarks that lie inside it. Search Here confirms
    /// each with the app's place search, so a name only appears if the search finds it.
    static func proposals(in region: GeoRegion) -> [RegionProposal] {
        all.filter { region.contains($0.coordinate) }
            .sorted { region.center.distance(to: $0.coordinate) < region.center.distance(to: $1.coordinate) }
            .prefix(3)
            .map { RegionProposal(name: $0.name, why: $0.why) }
    }
}

/// The screenshot Discovery behind `-IterDiscoveryStub results`: canned places with their sources, a Reddit that reports
/// itself unavailable (so the quiet line shows), no network.
struct StubDiscovery: Discovering {
    func resolveArea(named name: String, fallbackSearch: (any PlaceSearching)?) async -> DiscoveryArea? {
        let lowered = name.lowercased()
        guard let area = StubPlaces.areas.first(where: { $0.keys.contains { lowered.contains($0) } }) else { return nil }
        return DiscoveryArea(name: area.name, region: area.region)
    }

    func discover(area: DiscoveryArea, feature: FeatureKind?, text: String?, settings: DiscoverySettings) async throws -> DiscoveryReport {
        try await Task.sleep(for: .milliseconds(300))
        let entries = StubPlaces.all.filter { area.contains($0.coordinate) && (feature == nil || $0.feature == feature) }
        let places = entries.map {
            DiscoveredPlace(name: $0.name, coordinate: $0.coordinate, elevationMeters: $0.elevationMeters, feature: $0.feature,
                            sources: $0.sources, links: [], mentions: 0, why: $0.why)
        }
        var statuses: [DiscoverySourceID: DiscoverySourceStatus] = [.reddit: .unavailable("Stub")]
        for source in [DiscoverySourceID.openStreetMap, .wikipedia, .wikivoyage] {
            statuses[source] = .ok(places.filter { $0.sources.contains(source) }.count)
        }
        return DiscoveryReport(places: places, statuses: statuses, area: area)
    }
}
