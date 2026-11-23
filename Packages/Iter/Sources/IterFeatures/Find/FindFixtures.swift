import Foundation
import Synchronization
import IterModel
import IterSources
import IterDiscovery

// Deterministic providers for previews, snapshots and tests: no network, fixed places around Canyonlands, Utah. The real
// `DiscoveryEngine` runs over them, so every result carries a genuine grounded coordinate and the engine's own statuses
// (including Reddit and Google as unavailable).

public enum FindFixtures {
    /// The fixed instant every fixture citation is retrieved at (2026-10-12 12:00 UTC).
    public static let retrievedAt = Date(timeIntervalSince1970: 1_791_806_400)
    /// Mesa Arch, Canyonlands, the fixed place used across previews.
    public static let mesaArch = Coordinate(latitude: 38.3884, longitude: -109.8680)
    public static let moab = Coordinate(latitude: 38.5733, longitude: -109.5498)
    /// Where "Canyonlands" geocodes to.
    public static let canyonlands = Coordinate(latitude: 38.45, longitude: -109.82)
    public static let query = "viewpoints near Canyonlands, Utah"

    public static let osm: SourceID = "osm.overpass"
    public static let mapKitSearch: SourceID = .appleSearch
    public static let commons: SourceID = .wikimediaCommons

    public static func descriptor(_ id: SourceID, _ name: String, kinds: Set<DataKind>, timeout: Duration = .seconds(20)) -> SourceDescriptor {
        SourceDescriptor(id: id, name: name, operatorName: name, tier: .openData, origin: SourceOrigin(tier: .openData, producer: name),
                         kinds: kinds, coverage: .global, policy: RequestPolicy(timeout: timeout), cacheTTL: .seconds(3600),
                         licence: LicenceTag(key: LicenceKey.osm, mayStore: true))
    }

    public static func citation(_ source: SourceID, _ title: String) -> Citation {
        Citation(source: source, url: URL(string: "https://example.invalid/\(title.replacingOccurrences(of: " ", with: "_"))"), title: title,
                 retrievedAt: retrievedAt, licence: LicenceTag(key: source == osm ? LicenceKey.osm : LicenceKey.apple, mayStore: true))
    }

    /// What the OpenStreetMap-style gazetteer lists.
    public static func osmPlaces() -> [PlaceCandidate] {
        [
            ("Mesa Arch", 38.3884, -109.8680, [FeatureKind.arch, .viewpoint], "n1"),
            ("Grand View Point Overlook", 38.3000, -109.8500, [.viewpoint], "n2"),
            ("Green River Overlook", 38.3980, -109.8800, [.viewpoint], "n3"),
            ("Buck Canyon Overlook", 38.4600, -109.8650, [.viewpoint], "n4"),
            ("Whale Rock", 38.4300, -109.8700, [.viewpoint], "n5"),
        ].map { name, lat, lon, kinds, id in
            PlaceCandidate(name: name, coordinate: Coordinate(latitude: lat, longitude: lon), featureKinds: kinds, source: osm, externalID: id,
                           citations: [citation(osm, name + " (OpenStreetMap)")])
        }
    }

    /// What Apple Maps place search lists (a second, independent family for two of the places, and one place only Apple Maps lists).
    public static func mapKitPlaces() -> [PlaceCandidate] {
        [
            ("Mesa Arch", 38.3885, -109.8679, [FeatureKind.viewpoint], "mk1"),
            ("Grand View Point Overlook", 38.3001, -109.8502, [.viewpoint], "mk2"),
            ("Aztec Butte Overlook", 38.4400, -109.9000, [.viewpoint], "mk3"),
        ].map { name, lat, lon, kinds, id in
            PlaceCandidate(name: name, coordinate: Coordinate(latitude: lat, longitude: lon), featureKinds: kinds, source: .appleSearch,
                           externalID: id, citations: [citation(.appleSearch, name + " (Apple Maps)")])
        }
    }

    public static var mesaArchPhoto: LicensedPhoto {
        LicensedPhoto(title: "Mesa Arch at sunrise", coordinate: mesaArch, imageURL: URL(string: "https://example.invalid/mesa.jpg"),
                      thumbnailURL: URL(string: "https://example.invalid/mesa-thumb.jpg"),
                      pageURL: URL(string: "https://commons.example.invalid/File:Mesa_Arch.jpg"), licenceName: "CC BY-SA 4.0",
                      licenceURL: URL(string: "https://creativecommons.org/licenses/by-sa/4.0/"), author: "A. Photographer",
                      credit: "Photo: A. Photographer, CC BY-SA 4.0, via Wikimedia Commons", width: 4000, height: 2667)
    }

    /// A gazetteer that answers after `delay` (default at once), or fails with `error`, or never answers when `hangs`.
    public struct Gazetteer: GazetteerProvider {
        public var descriptor: SourceDescriptor
        public var places: [PlaceCandidate]
        public var delay: Duration = .zero
        public var error: SourceError?
        public var hangs = false

        public init(descriptor: SourceDescriptor = FindFixtures.descriptor(FindFixtures.osm, "OpenStreetMap (Overpass)", kinds: [.gazetteer]),
                    places: [PlaceCandidate] = FindFixtures.osmPlaces(), delay: Duration = .zero, error: SourceError? = nil, hangs: Bool = false) {
            self.descriptor = descriptor
            self.places = places
            self.delay = delay
            self.error = error
            self.hangs = hangs
        }

        public func candidates(in area: DiscoveryArea, features: Set<FeatureKind>, limit: Int) async throws -> [PlaceCandidate] {
            if hangs { try await Task.sleep(for: .seconds(3600)) }
            if delay > .zero { try await Task.sleep(for: delay) }
            if let error { throw error }
            return places
        }
    }

    public struct PlaceSearch: PlaceSearchProvider {
        public var descriptor = FindFixtures.descriptor(.appleSearch, "Apple Maps", kinds: [.places])
        public var places: [PlaceCandidate] = FindFixtures.mapKitPlaces()
        public var delay: Duration = .zero
        public init(places: [PlaceCandidate] = FindFixtures.mapKitPlaces(), delay: Duration = .zero) {
            self.places = places
            self.delay = delay
        }
        public func search(_ text: String, near region: GeoRegion) async throws -> [PlaceCandidate] {
            if delay > .zero { try await Task.sleep(for: delay) }
            return places
        }
    }

    public struct PhotoSource: PhotoEvidenceProvider {
        public var descriptor = FindFixtures.descriptor(FindFixtures.commons, "Wikimedia Commons", kinds: [.photoEvidence])
        public init() {}
        public func evidence(near center: Coordinate, radiusM: Double) async throws -> PhotoEvidence {
            let nearMesa = center.distance(to: FindFixtures.mesaArch) < 2000
            return PhotoEvidence(center: center, radiusM: radiusM, count: nearMesa ? 41 : 3, photos: nearMesa ? [FindFixtures.mesaArchPhoto] : [])
        }
    }

    /// Geocodes "canyonlands" and reverse-geocodes any point to a fixed Utah answer (zone America/Denver).
    public struct FixtureGeocoder: IterSources.Geocoder {
        public var descriptor = FindFixtures.descriptor(.appleGeocoder, "Apple Maps", kinds: [.geocode])
        public var reverseName: String? = "Dropped Place"
        public var reverseAddress: String? = "Canyonlands National Park, UT"
        public var reverseZone: String? = "America/Denver"
        public var failsReverse = false
        public init(reverseName: String? = "Dropped Place", reverseAddress: String? = "Canyonlands National Park, UT",
                    reverseZone: String? = "America/Denver", failsReverse: Bool = false) {
            self.reverseName = reverseName
            self.reverseAddress = reverseAddress
            self.reverseZone = reverseZone
            self.failsReverse = failsReverse
        }
        public func geocode(_ text: String, near region: GeoRegion?) async throws -> [GeocodeResult] {
            let lower = text.lowercased()
            if lower.contains("canyonlands") {
                return [GeocodeResult(name: "Canyonlands", coordinate: FindFixtures.canyonlands, formattedAddress: "Canyonlands, UT",
                                      countryCode: "US", timeZoneIdentifier: "America/Denver")]
            }
            if lower.contains("moab") {
                return [GeocodeResult(name: "Moab", coordinate: FindFixtures.moab, formattedAddress: "Moab, UT", countryCode: "US",
                                      timeZoneIdentifier: "America/Denver")]
            }
            return []
        }
        public func reverse(_ coordinate: Coordinate) async throws -> GeocodeResult {
            if failsReverse { throw SourceError.offline }
            return GeocodeResult(name: reverseName ?? "", coordinate: coordinate, formattedAddress: reverseAddress, countryCode: "US",
                                 timeZoneIdentifier: reverseZone)
        }
        public func boundary(of name: String, near coordinate: Coordinate?) async throws -> GeoPolygon? { nil }
    }

    /// A router that answers with the straight line times 1.3 at 70 km/h, plus a fixed minute, after `delay`; never when `hangs`.
    /// Counts calls and the most that ran at once.
    public final class Routing: RoutingProvider, Sendable {
        public let descriptor = FindFixtures.descriptor(.appleDirections, "Apple Maps Directions", kinds: [.routing, .eta])
        public let delay: Duration
        public let hangs: Bool
        private struct Counts { var calls = 0; var running = 0; var peak = 0; var cancelled = 0; var destinations: [Coordinate] = [] }
        private let counts = Mutex(Counts())

        public init(delay: Duration = .zero, hangs: Bool = false) {
            self.delay = delay
            self.hangs = hangs
        }

        public var calls: Int { counts.withLock { $0.calls } }
        public var peakConcurrency: Int { counts.withLock { $0.peak } }
        public var cancelledCalls: Int { counts.withLock { $0.cancelled } }
        public var destinations: [Coordinate] { counts.withLock { $0.destinations } }

        public func route(from: Coordinate, to: Coordinate, departing: Date?) async throws -> Route { throw SourceError.noSource }

        public func eta(from: Coordinate, to: Coordinate, departing: Date) async throws -> ETA {
            counts.withLock { $0.calls += 1; $0.running += 1; $0.peak = max($0.peak, $0.running); $0.destinations.append(to) }
            defer { counts.withLock { $0.running -= 1 } }
            do {
                if hangs { try await Task.sleep(for: .seconds(3600)) }
                if delay > .zero { try await Task.sleep(for: delay) }
            } catch {
                counts.withLock { $0.cancelled += 1 }
                throw SourceError.cancelled
            }
            let seconds = from.distance(to: to) * 1.3 / (70_000.0 / 3600.0) + 60
            return ETA(seconds: seconds, arrival: departing.addingTimeInterval(seconds), departing: departing)
        }
    }

    /// Look Around coverage: available only near `coveredNear`.
    public struct StreetLevel: StreetLevelImageryProvider {
        public var descriptor = FindFixtures.descriptor(.appleLookAround, "Apple Look Around", kinds: [.imagery])
        public var coveredNear: Coordinate?
        public init(coveredNear: Coordinate? = FindFixtures.moab) { self.coveredNear = coveredNear }
        public func isAvailable(at coordinate: Coordinate) async throws -> Bool {
            guard let c = coveredNear else { return false }
            return c.distance(to: coordinate) < 5000
        }
    }

    /// An engine over the fixtures: OpenStreetMap, Apple Maps place search, Commons photos, one geocoder, no model.
    public static func engine(gazetteer: Gazetteer = Gazetteer(), configuration: DiscoveryConfiguration = fastConfiguration) -> DiscoveryEngine {
        DiscoveryEngine(providers: DiscoveryProviders(geocoders: [FixtureGeocoder()], gazetteers: [gazetteer], placeSearch: [PlaceSearch()],
                                                      photoEvidence: [PhotoSource()]),
                        model: nil, clock: SystemSourceClock(), configuration: configuration)
    }

    public static var fastConfiguration: DiscoveryConfiguration {
        DiscoveryConfiguration(sourceTimeoutOverride: .seconds(2), planTimeout: .seconds(2), extractionTimeout: .seconds(2), explanationTimeout: .seconds(2))
    }
}
