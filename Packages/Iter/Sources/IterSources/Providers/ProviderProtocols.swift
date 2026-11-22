import Foundation
import IterModel

// The provider protocols (BLUEPRINT §6.2). Every method throws `SourceError` only. Providers are fetchers: they do not
// cache semantically (callers wrap them with `SourceCache`); an adapter may cache raw responses it reuses (NOMADS boxes).
// A provider asked about a point outside its coverage throws `.outsideCoverage` without calling the network.

// MARK: Places and discovery

/// Free text near a region (MapKit).
public protocol PlaceSearchProvider: SourceDescribing {
    func search(_ text: String, near region: GeoRegion) async throws -> [PlaceCandidate]
}

/// Structured features in an area (OSM Overpass, MapKit POI categories, USGS GNIS).
public protocol GazetteerProvider: SourceDescribing {
    func candidates(in area: DiscoveryArea, features: Set<FeatureKind>, limit: Int) async throws -> [PlaceCandidate]
}

/// Documents for the extractor (Wikipedia geosearch with extracts).
public protocol TextEvidenceProvider: SourceDescribing {
    func documents(for query: TextQuery, in area: DiscoveryArea) async throws -> [EvidenceDocument]
}

/// Geotagged, licensed photos near a point (Wikimedia Commons).
public protocol PhotoEvidenceProvider: SourceDescribing {
    func evidence(near center: Coordinate, radiusM: Double) async throws -> PhotoEvidence
}

public protocol Geocoder: SourceDescribing {
    func geocode(_ text: String, near region: GeoRegion?) async throws -> [GeocodeResult]
    func reverse(_ coordinate: Coordinate) async throws -> GeocodeResult
    /// The outline of a named area (a park), when the geocoder knows one; nil otherwise.
    func boundary(of name: String, near coordinate: Coordinate?) async throws -> GeoPolygon?
}

// MARK: Weather

/// Hourly rows across `span`. Rows are at the model's native valid times (UTC instants; never shifted to local time).
public protocol ForecastProvider: SourceDescribing {
    func forecast(at coordinate: Coordinate, span: TimeSpan) async throws -> Sourced<HourlySeries>
}

/// Latest observations near a point, nearest first. Each carries its distance and origin in its provenance.
public protocol ObservationProvider: SourceDescribing {
    func latest(near coordinate: Coordinate, within km: Double, maxAge: Duration) async throws -> [Sourced<WeatherObservation>]
}

/// Aviation reports (METAR and TAF) with station detail: distance, military flag, raw text.
public protocol StationReportProvider: SourceDescribing {
    func reports(near coordinate: Coordinate, within km: Double, limit: Int) async throws -> [Sourced<StationReport>]
}

/// 0–6 h.
public protocol NowcastProvider: SourceDescribing {
    func nowcast(at coordinate: Coordinate) async throws -> Sourced<[NowcastStep]>
}

/// Official alerts in force at a point.
public protocol AlertProvider: SourceDescribing {
    func alerts(at coordinate: Coordinate) async throws -> Sourced<[WeatherAlert]>
}

// MARK: Sky inputs

public protocol AuroraProvider: SourceDescribing {
    func aurora(at coordinate: Coordinate) async throws -> Sourced<AuroraReading>
    /// Observed, estimated and predicted 3-hour Kp, oldest first.
    func kpForecast() async throws -> Sourced<[KpPeriod]>
}

/// Analysed smoke polygons (NOAA HMS) for the UTC day containing `date`.
public protocol SmokeAnalysisProvider: SourceDescribing {
    func smoke(at coordinate: Coordinate, on date: Date) async throws -> Sourced<SmokeAnalysis>
}

/// Light pollution. The only implementation today throws `.noSource`.
public protocol SkyBrightnessProvider: SourceDescribing {
    func skyBrightness(at coordinate: Coordinate) async throws -> Sourced<SkyBrightness>
}

/// Seeing and transparency. The only implementation today throws `.noSource`.
public protocol SeeingProvider: SourceDescribing {
    func seeing(at coordinate: Coordinate, span: TimeSpan) async throws -> Sourced<[SeeingEstimate]>
}

// MARK: Terrain

public protocol TerrainProvider: SourceDescribing {
    /// Metres above sea level.
    func elevation(at coordinate: Coordinate) async throws -> Sourced<Double>
    /// The skyline around the point; `azimuthStep` in degrees (5 gives the standard 72 samples).
    func horizon(at coordinate: Coordinate, azimuthStep: Double) async throws -> Sourced<HorizonProfile>
}

// MARK: Routing

/// MapKit directions.
public protocol RoutingProvider: SourceDescribing {
    func route(from: Coordinate, to: Coordinate, departing: Date?) async throws -> Route
    func eta(from: Coordinate, to: Coordinate, departing: Date) async throws -> ETA
}

// MARK: Imagery

/// Map overlays available at a point (satellite, radar). Descriptors only.
public protocol ImageryProvider: SourceDescribing {
    func layers(at coordinate: Coordinate) -> [ImageryLayer]
}

/// Street-level imagery availability (Look Around).
public protocol StreetLevelImageryProvider: SourceDescribing {
    func isAvailable(at coordinate: Coordinate) async throws -> Bool
}

// MARK: On device

/// World Magnetic Model, computed on device.
public protocol MagneticModelProvider: SourceDescribing {
    func field(at coordinate: Coordinate, elevationM: Double, on date: Date) throws -> Sourced<MagneticField>
}

/// MGRS (NGA grid reference standard), computed on device.
public protocol GridReferenceProvider: SourceDescribing {
    /// `precision` 1...5 digits per axis (5 = 1 m).
    func mgrs(for coordinate: Coordinate, precision: Int) throws -> Sourced<String>
    func coordinate(fromMGRS text: String) throws -> Coordinate
}
