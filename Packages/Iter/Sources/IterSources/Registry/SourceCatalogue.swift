import Foundation
import IterModel

// The registry table: one descriptor per source, reviewed against docs/rebuild/SOURCES.md §1. This file is the only place
// tiers, ranks, coverage, politeness and cache lifetimes live. Adapters take their `descriptor` from here.

extension SourceID {
    // Apple (no key, no paid team)
    public static let appleSearch: SourceID = "apple.mapkit.search"
    public static let applePOI: SourceID = "apple.mapkit.poi"
    public static let appleGeocoder: SourceID = "apple.mapkit.geocoder"
    public static let appleDirections: SourceID = "apple.mapkit.directions"
    public static let appleLookAround: SourceID = "apple.lookaround"
    // Discovery
    public static let osmOverpass: SourceID = "osm.overpass"
    public static let wikipedia: SourceID = "wikipedia.geosearch"
    public static let wikimediaCommons: SourceID = "wikimedia.commons"
    public static let usgsGNIS: SourceID = "usgs.gnis"
    // Weather
    public static let noaaNOMADS: SourceID = "noaa.nomads"
    public static let noaaHRRRSmoke: SourceID = "noaa.nomads.hrrr-smoke"
    public static let metNorway: SourceID = "metno.locationforecast"
    public static let aviationWeather: SourceID = "noaa.awc.metar"
    public static let nwsAPI: SourceID = "noaa.nws.api"
    // Sky
    public static let swpc: SourceID = "noaa.swpc"
    public static let hmsSmoke: SourceID = "noaa.nesdis.hms"
    public static let noSkyBrightness: SourceID = "iter.none.sky-brightness"
    public static let noSeeing: SourceID = "iter.none.seeing"
    // Terrain
    public static let usgsEPQS: SourceID = "usgs.epqs"
    public static let terrariumTiles: SourceID = "aws.terrain-tiles"
    // Imagery
    public static let nasaGIBS: SourceID = "nasa.gibs"
    public static let eumetsatView: SourceID = "eumetsat.view"
    public static let iemNEXRAD: SourceID = "iem.nexrad"
    // On device
    public static let worldMagneticModel: SourceID = "nga.wmm2025"
    public static let mgrs: SourceID = "nga.mgrs"
}

/// Licence keys. `Attribution.text(for:)` gives the words.
public enum LicenceKey {
    public static let noaaNCEP = "noaa.ncep"
    public static let noaaNWS = "noaa.nws"
    public static let noaaAWC = "noaa.awc"
    public static let noaaSWPC = "noaa.swpc"
    public static let noaaHMS = "noaa.nesdis.hms"
    public static let usgs = "usgs"
    public static let metNorway = "metno.cc-by-4.0"
    public static let osm = "osm.odbl"
    public static let wikipedia = "wikipedia.cc-by-sa-4.0"
    public static let commons = "wikimedia.commons.per-file"
    public static let terrainTiles = "tilezen.terrain-tiles"
    public static let nasaGIBS = "nasa.gibs"
    public static let eumetsat = "eumetsat"
    public static let iem = "iem"
    public static let apple = "apple.mapkit"
    public static let wmm = "nga.wmm"
    public static let mgrs = "nga.mgrs"
    public static let none = "iter.none"
}

/// Coverage shapes used by the catalogue. Coarse by design (tens of km of slop); they decide whether to ask.
public enum CoverageShapes {
    /// The HRRR CONUS Lambert domain, sampled along its edges from the grid definition (1799 × 1059 at 3 km).
    public static let hrrrDomain = GeoPolygon(rings: [[
        (21.14, -122.72), (22.53, -116.62), (23.54, -110.35), (24.16, -103.96), (24.36, -97.50), (24.16, -91.05),
        (23.54, -84.66), (22.53, -78.39), (21.14, -72.29), (24.45, -71.26), (27.79, -70.14), (31.16, -68.93),
        (34.53, -67.61), (37.90, -66.17), (41.25, -64.59), (44.57, -62.84), (47.84, -60.92), (49.89, -69.43),
        (51.39, -78.46), (52.31, -87.88), (52.62, -97.51), (52.31, -107.13), (51.39, -116.55), (49.89, -125.59),
        (47.84, -134.10), (44.57, -132.17), (41.25, -130.42), (37.89, -128.84), (34.53, -127.40), (31.15, -126.08),
        (27.79, -124.87), (24.45, -123.75),
    ].map { Coordinate(latitude: $0.0, longitude: $0.1) }])

    /// The contiguous US, coarse (coastal waters within a few tens of km count).
    public static let conus = GeoPolygon(rings: [[
        (48.4, -124.9), (49.0, -123.2), (49.0, -95.2), (49.4, -95.1), (48.0, -89.6), (46.5, -84.5), (45.3, -82.5),
        (43.0, -82.4), (41.7, -82.6), (42.5, -79.0), (43.3, -79.0), (43.6, -76.5), (45.0, -74.7), (45.0, -71.5),
        (47.5, -69.2), (47.4, -67.8), (44.8, -66.9), (43.5, -69.8), (41.2, -69.8), (40.4, -73.9), (38.8, -74.9),
        (35.2, -75.4), (32.0, -80.8), (30.5, -81.3), (25.1, -80.2), (24.4, -81.9), (26.5, -82.3), (29.7, -84.2),
        (30.2, -88.0), (29.0, -89.2), (29.5, -94.0), (26.0, -97.1), (27.5, -99.5), (29.8, -101.5), (29.0, -103.2),
        (31.8, -106.5), (31.3, -108.2), (31.3, -111.1), (32.5, -114.8), (32.5, -117.2), (34.4, -120.6),
        (40.4, -124.5), (43.0, -124.6),
    ].map { Coordinate(latitude: $0.0, longitude: $0.1) }])

    static func box(_ south: Double, _ west: Double, _ north: Double, _ east: Double) -> GeoRegion {
        GeoRegion(center: Coordinate(latitude: (south + north) / 2, longitude: (west + east) / 2),
                  latitudeDelta: north - south, longitudeDelta: east - west)
    }

    /// Alaska (mainland and the eastern Aleutians), Hawaii, Puerto Rico and the US Virgin Islands, Guam.
    public static let usOutside = [box(51.0, -170.0, 71.6, -129.9), box(18.8, -160.4, 22.4, -154.7),
                                   box(17.6, -67.4, 18.6, -64.5), box(13.2, 144.6, 13.7, 145.0)]

    /// The United States and territories (CONUS polygon plus boxes).
    public static let unitedStates = Coverage.union([.polygons([conus]), .regions(usOutside)])

    /// North America for HMS smoke analysis.
    public static let northAmerica = Coverage.regions([box(14.0, -170.0, 75.0, -50.0)])

    /// Usable geostationary discs (±65° great-circle from the sub-satellite point, simplified to boxes).
    public static let goesWest = Coverage.regions([box(-65, -180, 65, -72), box(-65, 158, 65, 180)])
    public static let goesEast = Coverage.regions([box(-65, -140, 65, -10)])
    public static let himawari = Coverage.regions([box(-65, 76, 65, 180), box(-65, -180, 65, -155)])
    public static let meteosatZero = Coverage.regions([box(-65, -65, 65, 65)])
}

/// The catalogue of every source the app knows.
public enum SourceCatalogue {
    private static func url(_ s: String) -> URL? { URL(string: s) }

    // MARK: Origins

    static let noaaNCEP = SourceOrigin(tier: .government, producer: "NOAA NCEP")
    static let apple = SourceOrigin(tier: .openData, producer: "Apple")

    // MARK: Weather

    /// HRRR (US, 3 km, to 48 h) stitched into GFS (global, 0.25°, to 16 days) through the NOMADS GRIB filter.
    public static let noaaNOMADS = SourceDescriptor(
        id: .noaaNOMADS, name: "NOAA HRRR and GFS", operatorName: "NOAA NCEP", tier: .government, origin: noaaNCEP,
        kinds: [.forecast, .nowcast], coverage: .global,
        // NOMADS throttles heavy users; one request per box, cycle and forecast hour, well under 60 a minute.
        policy: RequestPolicy(spacing: .milliseconds(600), maxConcurrent: 2, perMinute: 50, timeout: .seconds(30),
                              maxRetries: 2, initialBackoff: .seconds(5), conditional: false),
        cacheTTL: .seconds(3600), licence: LicenceTag(key: LicenceKey.noaaNCEP, mayStore: true),
        termsURL: url("https://nomads.ncep.noaa.gov/"), ranks: [.forecast: 10, .nowcast: 10])

    /// HRRR near-surface smoke (MASSDEN), column smoke (COLMD) and aerosol optical thickness (AOTK), CONUS only.
    public static let noaaHRRRSmoke = SourceDescriptor(
        id: .noaaHRRRSmoke, name: "NOAA HRRR smoke", operatorName: "NOAA NCEP", tier: .government, origin: noaaNCEP,
        kinds: [.smoke, .aerosol], coverage: .polygons([CoverageShapes.hrrrDomain]),
        policy: noaaNOMADS.policy, cacheTTL: .seconds(3600), licence: noaaNOMADS.licence, termsURL: noaaNOMADS.termsURL,
        ranks: [.smoke: 10, .aerosol: 10])

    /// MET Norway locationforecast 2.0 (global fallback: cloud layers and fog, no visibility).
    public static let metNorway = SourceDescriptor(
        id: .metNorway, name: "MET Norway Locationforecast", operatorName: "Norwegian Meteorological Institute",
        tier: .government, origin: SourceOrigin(tier: .government, producer: "MET Norway"),
        kinds: [.forecast], coverage: .global,
        // Terms: honour Expires, use If-Modified-Since, under 20 requests/s summed over all installs.
        policy: RequestPolicy(spacing: .seconds(1), maxConcurrent: 1, timeout: .seconds(20), maxRetries: 2,
                              initialBackoff: .seconds(5), conditional: true, honourExpires: true),
        cacheTTL: .seconds(3600), licence: LicenceTag(key: LicenceKey.metNorway, mayStore: true),
        termsURL: url("https://api.met.no/doc/TermsOfService"), ranks: [.forecast: 20])

    /// METAR and TAF from aviationweather.gov, military airfields included (military-origin via NOAA for those stations).
    public static let aviationWeather = SourceDescriptor(
        id: .aviationWeather, name: "Aviation weather reports (METAR/TAF)", operatorName: "NOAA Aviation Weather Center",
        tier: .military,
        origin: SourceOrigin(tier: .military, producer: "US military airfields and civil stations",
                             distributor: "NOAA Aviation Weather Center"),
        kinds: [.observation], coverage: .global,
        // Published limit 100 requests a minute; we stay far below.
        policy: RequestPolicy(spacing: .seconds(1), maxConcurrent: 2, perMinute: 60, timeout: .seconds(15), maxRetries: 2),
        cacheTTL: .seconds(600), licence: LicenceTag(key: LicenceKey.noaaAWC, mayStore: true),
        termsURL: url("https://aviationweather.gov/data/api/"), ranks: [.observation: 10])

    /// api.weather.gov: alerts and station observations (US only; no cloud layers, so not a forecast source here).
    public static let nwsAPI = SourceDescriptor(
        id: .nwsAPI, name: "National Weather Service", operatorName: "NOAA National Weather Service", tier: .government,
        origin: SourceOrigin(tier: .government, producer: "NOAA National Weather Service"),
        kinds: [.alerts, .observation], coverage: CoverageShapes.unitedStates,
        // Unpublished limit; a 429 means retry after about 5 s.
        policy: RequestPolicy(spacing: .seconds(1), maxConcurrent: 2, timeout: .seconds(15), maxRetries: 2,
                              initialBackoff: .seconds(5)),
        cacheTTL: .seconds(300), licence: LicenceTag(key: LicenceKey.noaaNWS, mayStore: true),
        termsURL: url("https://www.weather.gov/documentation/services-web-api"), ranks: [.alerts: 10, .observation: 20])

    // MARK: Sky

    public static let swpc = SourceDescriptor(
        id: .swpc, name: "NOAA Space Weather Prediction Center", operatorName: "NOAA SWPC", tier: .government,
        origin: SourceOrigin(tier: .government, producer: "NOAA Space Weather Prediction Center"),
        kinds: [.aurora], coverage: .global,
        policy: RequestPolicy(spacing: .seconds(1), maxConcurrent: 1, timeout: .seconds(30), maxRetries: 2),
        cacheTTL: .seconds(900), licence: LicenceTag(key: LicenceKey.noaaSWPC, mayStore: true),
        termsURL: url("https://www.swpc.noaa.gov/"), ranks: [.aurora: 10])

    public static let hmsSmoke = SourceDescriptor(
        id: .hmsSmoke, name: "NOAA Hazard Mapping System smoke", operatorName: "NOAA NESDIS", tier: .government,
        origin: SourceOrigin(tier: .government, producer: "NOAA NESDIS"),
        kinds: [.smoke], coverage: CoverageShapes.northAmerica,
        policy: RequestPolicy(spacing: .seconds(1), maxConcurrent: 1, timeout: .seconds(30), maxRetries: 2),
        cacheTTL: .seconds(3600), licence: LicenceTag(key: LicenceKey.noaaHMS, mayStore: true),
        termsURL: url("https://www.ospo.noaa.gov/products/land/hms.html"), ranks: [.smoke: 20])

    /// Honest slot: there is no commercial-safe sky-brightness source (SOURCES.md §1.2). Always throws `.noSource`.
    public static let noSkyBrightness = SourceDescriptor(
        id: .noSkyBrightness, name: "Sky brightness (no source yet)", operatorName: "none", tier: .device,
        origin: SourceOrigin(tier: .device, producer: "none"), kinds: [.lightPollution], coverage: .global,
        cacheTTL: .seconds(86_400), licence: LicenceTag(key: LicenceKey.none, mayStore: true), ranks: [.lightPollution: 1000])

    /// Honest slot: there is no commercial-safe seeing source. Always throws `.noSource`.
    public static let noSeeing = SourceDescriptor(
        id: .noSeeing, name: "Seeing and transparency (no source yet)", operatorName: "none", tier: .device,
        origin: SourceOrigin(tier: .device, producer: "none"), kinds: [.seeing], coverage: .global,
        cacheTTL: .seconds(86_400), licence: LicenceTag(key: LicenceKey.none, mayStore: true), ranks: [.seeing: 1000])

    // MARK: Terrain

    public static let usgsEPQS = SourceDescriptor(
        id: .usgsEPQS, name: "USGS 3DEP point elevation", operatorName: "USGS The National Map", tier: .government,
        origin: SourceOrigin(tier: .government, producer: "USGS 3DEP"),
        kinds: [.elevation], coverage: CoverageShapes.unitedStates,
        policy: RequestPolicy(spacing: .milliseconds(500), maxConcurrent: 2, timeout: .seconds(15), maxRetries: 2),
        cacheTTL: .seconds(30 * 86_400), licence: LicenceTag(key: LicenceKey.usgs, mayStore: true),
        termsURL: url("https://www.usgs.gov/information-policies-and-instructions/copyrights-and-credits"),
        ranks: [.elevation: 10])

    /// Terrarium PNG tiles on AWS Open Data: a blend of government elevation models (3DEP, SRTM, GMTED, EU-DEM, ...).
    public static let terrariumTiles = SourceDescriptor(
        id: .terrariumTiles, name: "Terrain Tiles (Terrarium)", operatorName: "Tilezen on AWS Open Data", tier: .government,
        origin: SourceOrigin(tier: .government, producer: "USGS, NASA/NGA (SRTM), and national mapping agencies",
                             distributor: "Tilezen on AWS Open Data"),
        kinds: [.elevation, .horizon], coverage: .global,
        policy: RequestPolicy(spacing: .milliseconds(100), maxConcurrent: 4, timeout: .seconds(20), maxRetries: 2),
        cacheTTL: .seconds(90 * 86_400), licence: LicenceTag(key: LicenceKey.terrainTiles, mayStore: true),
        termsURL: url("https://registry.opendata.aws/terrain-tiles/"), ranks: [.elevation: 20, .horizon: 10])

    // MARK: Imagery

    public static let nasaGIBS = SourceDescriptor(
        id: .nasaGIBS, name: "NASA GIBS satellite imagery", operatorName: "NASA ESDIS", tier: .government,
        origin: SourceOrigin(tier: .government, producer: "NOAA GOES and JMA Himawari", distributor: "NASA GIBS"),
        kinds: [.imagery, .satelliteCloud], coverage: .global,
        policy: RequestPolicy(spacing: .milliseconds(100), maxConcurrent: 4, timeout: .seconds(20), maxRetries: 1),
        cacheTTL: .seconds(600), licence: LicenceTag(key: LicenceKey.nasaGIBS, mayStore: true),
        termsURL: url("https://nasa-gibs.github.io/gibs-api-docs/"), ranks: [.imagery: 10, .satelliteCloud: 10])

    /// Meteosat via EUMETSAT's view WMS. Licence for real-time imagery in a sold app not yet read: off by default.
    public static let eumetsatView = SourceDescriptor(
        id: .eumetsatView, name: "EUMETSAT Meteosat imagery", operatorName: "EUMETSAT", tier: .government,
        origin: SourceOrigin(tier: .government, producer: "EUMETSAT"),
        kinds: [.imagery, .satelliteCloud], coverage: CoverageShapes.meteosatZero,
        policy: RequestPolicy(spacing: .milliseconds(250), maxConcurrent: 2, timeout: .seconds(20), maxRetries: 1),
        cacheTTL: .seconds(900), licence: LicenceTag(key: LicenceKey.eumetsat, mayStore: false),
        termsURL: url("https://www.eumetsat.int/data-policy"), ranks: [.imagery: 20, .satelliteCloud: 20],
        enabledByDefault: false)

    /// IEM NEXRAD composite tiles (US radar). University service; terms not yet read: off by default.
    public static let iemNEXRAD = SourceDescriptor(
        id: .iemNEXRAD, name: "IEM NEXRAD radar", operatorName: "Iowa Environmental Mesonet", tier: .openData,
        origin: SourceOrigin(tier: .government, producer: "NOAA NWS NEXRAD", distributor: "Iowa Environmental Mesonet"),
        kinds: [.imagery], coverage: .polygons([CoverageShapes.conus]),
        policy: RequestPolicy(spacing: .milliseconds(100), maxConcurrent: 4, timeout: .seconds(15), maxRetries: 1),
        cacheTTL: .seconds(300), licence: LicenceTag(key: LicenceKey.iem, mayStore: false),
        termsURL: url("https://mesonet.agron.iastate.edu/disclaimer.php"), ranks: [.imagery: 30], enabledByDefault: false)

    // MARK: Discovery

    public static let osmOverpass = SourceDescriptor(
        id: .osmOverpass, name: "OpenStreetMap (Overpass)", operatorName: "OpenStreetMap contributors", tier: .openData,
        origin: SourceOrigin(tier: .openData, producer: "OpenStreetMap contributors"),
        kinds: [.gazetteer], coverage: .global,
        // Public instances are shared and return 502/504 when busy. The client timeout (60 s) is longer than the
        // server-side `[timeout:25]` we send, so the server always answers first.
        policy: RequestPolicy(spacing: .seconds(2), maxConcurrent: 1, timeout: .seconds(60), maxRetries: 2,
                              initialBackoff: .seconds(10), conditional: false),
        cacheTTL: .seconds(7 * 86_400), licence: LicenceTag(key: LicenceKey.osm, mayStore: true),
        termsURL: url("https://wiki.openstreetmap.org/wiki/Overpass_API#Public_Overpass_API_instances"),
        ranks: [.gazetteer: 20])

    public static let usgsGNIS = SourceDescriptor(
        id: .usgsGNIS, name: "USGS Geographic Names (GNIS)", operatorName: "USGS The National Map", tier: .government,
        origin: SourceOrigin(tier: .government, producer: "USGS / US Board on Geographic Names"),
        kinds: [.gazetteer], coverage: CoverageShapes.unitedStates,
        policy: RequestPolicy(spacing: .seconds(1), maxConcurrent: 1, timeout: .seconds(30), maxRetries: 2),
        cacheTTL: .seconds(30 * 86_400), licence: LicenceTag(key: LicenceKey.usgs, mayStore: true),
        termsURL: url("https://www.usgs.gov/us-board-on-geographic-names"), ranks: [.gazetteer: 30])

    public static let wikipedia = SourceDescriptor(
        id: .wikipedia, name: "Wikipedia", operatorName: "Wikimedia Foundation", tier: .openData,
        origin: SourceOrigin(tier: .openData, producer: "Wikipedia contributors"),
        kinds: [.textEvidence], coverage: .global,
        // API etiquette: serial requests with a descriptive User-Agent.
        policy: RequestPolicy(spacing: .seconds(1), maxConcurrent: 1, timeout: .seconds(15), maxRetries: 2),
        cacheTTL: .seconds(7 * 86_400), licence: LicenceTag(key: LicenceKey.wikipedia, mayStore: true),
        termsURL: url("https://foundation.wikimedia.org/wiki/Policy:Terms_of_Use"), ranks: [.textEvidence: 10])

    public static let wikimediaCommons = SourceDescriptor(
        id: .wikimediaCommons, name: "Wikimedia Commons", operatorName: "Wikimedia Foundation", tier: .openData,
        origin: SourceOrigin(tier: .openData, producer: "Wikimedia Commons contributors"),
        kinds: [.photoEvidence], coverage: .global,
        policy: RequestPolicy(spacing: .seconds(1), maxConcurrent: 1, timeout: .seconds(15), maxRetries: 2),
        cacheTTL: .seconds(7 * 86_400), licence: LicenceTag(key: LicenceKey.commons, mayStore: true),
        termsURL: url("https://commons.wikimedia.org/wiki/Commons:Reusing_content_outside_Wikimedia"),
        ranks: [.photoEvidence: 10])

    // MARK: Apple

    // MapKit results are kept in memory only (`mayStore: false`); a place the user saves is the user's data, not a cache.
    private static let appleLicence = LicenceTag(key: LicenceKey.apple, mayStore: false)
    private static let applePolicy = RequestPolicy(spacing: .milliseconds(250), maxConcurrent: 2, perMinute: 50,
                                                   timeout: .seconds(20), maxRetries: 1, conditional: false)

    public static let appleSearch = SourceDescriptor(
        id: .appleSearch, name: "Apple Maps search", operatorName: "Apple", tier: .openData, origin: apple,
        kinds: [.places], coverage: .global, policy: applePolicy, cacheTTL: .seconds(86_400), licence: appleLicence,
        ranks: [.places: 10])

    public static let applePOI = SourceDescriptor(
        id: .applePOI, name: "Apple Maps points of interest", operatorName: "Apple", tier: .openData, origin: apple,
        kinds: [.gazetteer], coverage: .global, policy: applePolicy, cacheTTL: .seconds(86_400), licence: appleLicence,
        ranks: [.gazetteer: 10])

    public static let appleGeocoder = SourceDescriptor(
        id: .appleGeocoder, name: "Apple Maps geocoder", operatorName: "Apple", tier: .openData, origin: apple,
        kinds: [.geocode], coverage: .global, policy: applePolicy, cacheTTL: .seconds(86_400), licence: appleLicence,
        ranks: [.geocode: 10])

    public static let appleDirections = SourceDescriptor(
        id: .appleDirections, name: "Apple Maps directions", operatorName: "Apple", tier: .openData, origin: apple,
        kinds: [.routing, .eta], coverage: .global, policy: applePolicy, cacheTTL: .seconds(600), licence: appleLicence,
        ranks: [.routing: 10, .eta: 10])

    public static let appleLookAround = SourceDescriptor(
        id: .appleLookAround, name: "Apple Look Around", operatorName: "Apple", tier: .openData, origin: apple,
        kinds: [.imagery], coverage: .global, policy: applePolicy, cacheTTL: .seconds(7 * 86_400), licence: appleLicence,
        ranks: [.imagery: 50])

    // MARK: On device

    public static let worldMagneticModel = SourceDescriptor(
        id: .worldMagneticModel, name: "World Magnetic Model 2025", operatorName: "NGA and UK Defence Geographic Centre",
        tier: .military,
        origin: SourceOrigin(tier: .military, producer: "NGA and UK Defence Geographic Centre", distributor: "NOAA NCEI",
                             computedOnDevice: true),
        kinds: [.magnetic], coverage: .global, cacheTTL: .seconds(365 * 86_400),
        licence: LicenceTag(key: LicenceKey.wmm, mayStore: true),
        termsURL: url("https://www.ncei.noaa.gov/products/world-magnetic-model"), ranks: [.magnetic: 1])

    public static let mgrs = SourceDescriptor(
        id: .mgrs, name: "Military Grid Reference System", operatorName: "NGA", tier: .military,
        origin: SourceOrigin(tier: .military, producer: "NGA", computedOnDevice: true),
        kinds: [.gridReference], coverage: .global, cacheTTL: .seconds(365 * 86_400),
        licence: LicenceTag(key: LicenceKey.mgrs, mayStore: true), ranks: [.gridReference: 1])

    /// Every descriptor, in no particular order.
    public static let all: [SourceDescriptor] = [
        noaaNOMADS, noaaHRRRSmoke, metNorway, aviationWeather, nwsAPI, swpc, hmsSmoke, noSkyBrightness, noSeeing,
        usgsEPQS, terrariumTiles, nasaGIBS, eumetsatView, iemNEXRAD, osmOverpass, usgsGNIS, wikipedia, wikimediaCommons,
        appleSearch, applePOI, appleGeocoder, appleDirections, appleLookAround, worldMagneticModel, mgrs,
    ]

    public static func descriptor(_ id: SourceID) -> SourceDescriptor? { all.first { $0.id == id } }
}
