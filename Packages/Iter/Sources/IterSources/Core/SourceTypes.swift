import Foundation
import IterModel

// Value types that providers return and that IterModel does not already have. All Sendable, Codable where cached.

// MARK: Discovery

/// A geocoder hit.
public struct GeocodeResult: Codable, Hashable, Sendable {
    public var name: String
    public var coordinate: Coordinate
    /// Locality, region, country as the geocoder gave them, joined for display.
    public var formattedAddress: String?
    public var countryCode: String?
    public var timeZoneIdentifier: String?
    /// The geocoder's own region for the hit, when it has one (a park's extent).
    public var region: GeoRegion?

    public init(name: String, coordinate: Coordinate, formattedAddress: String? = nil, countryCode: String? = nil,
                timeZoneIdentifier: String? = nil, region: GeoRegion? = nil) {
        self.name = name
        self.coordinate = coordinate
        self.formattedAddress = formattedAddress
        self.countryCode = countryCode
        self.timeZoneIdentifier = timeZoneIdentifier
        self.region = region
    }
}

/// A named area's real outline (an OSM boundary relation), with what is needed to cite it.
public struct NamedBoundary: Codable, Hashable, Sendable {
    /// The name as the source gives it, e.g. "Yosemite National Park".
    public var name: String
    public var polygon: GeoPolygon
    /// The source's stable id, e.g. "relation/1643367".
    public var externalID: String?
    /// What kind of area, as the source tags it, e.g. "national_park", "protected_area", "nature_reserve".
    public var areaKind: String?
    public var citation: Citation

    public init(name: String, polygon: GeoPolygon, externalID: String? = nil, areaKind: String? = nil, citation: Citation) {
        self.name = name
        self.polygon = polygon
        self.externalID = externalID
        self.areaKind = areaKind
        self.citation = citation
    }
}

/// What a text-evidence source is asked for. IterDiscovery's `QueryPlan` maps onto this.
public struct TextQuery: Hashable, Sendable {
    public var terms: [String]
    public var features: Set<FeatureKind>
    public var limit: Int

    public init(terms: [String] = [], features: Set<FeatureKind> = [], limit: Int = 20) {
        self.terms = terms
        self.features = features
        self.limit = limit
    }
}

/// A document the extractor reads (a Wikipedia article summary near the area).
public struct EvidenceDocument: Codable, Hashable, Sendable {
    public var title: String
    public var text: String
    public var url: URL?
    /// Where the document is about, when the source geotags it.
    public var coordinate: Coordinate?
    public var citation: Citation

    public init(title: String, text: String, url: URL? = nil, coordinate: Coordinate? = nil, citation: Citation) {
        self.title = title
        self.text = text
        self.url = url
        self.coordinate = coordinate
        self.citation = citation
    }
}

/// One freely licensed photo with what is needed to credit it.
public struct LicensedPhoto: Codable, Hashable, Sendable {
    public var title: String
    public var coordinate: Coordinate?
    public var imageURL: URL?
    public var thumbnailURL: URL?
    /// The human page (Commons file page).
    public var pageURL: URL?
    /// e.g. "CC BY-SA 4.0", "CC0", "Public domain".
    public var licenceName: String
    public var licenceURL: URL?
    /// Author as plain text (HTML stripped).
    public var author: String?
    /// The credit line to show, e.g. "Photo: Jane Doe, CC BY-SA 4.0, via Wikimedia Commons".
    public var credit: String
    public var width: Int?
    public var height: Int?

    public init(title: String, coordinate: Coordinate? = nil, imageURL: URL? = nil, thumbnailURL: URL? = nil, pageURL: URL? = nil,
                licenceName: String, licenceURL: URL? = nil, author: String? = nil, credit: String, width: Int? = nil,
                height: Int? = nil) {
        self.title = title
        self.coordinate = coordinate
        self.imageURL = imageURL
        self.thumbnailURL = thumbnailURL
        self.pageURL = pageURL
        self.licenceName = licenceName
        self.licenceURL = licenceURL
        self.author = author
        self.credit = credit
        self.width = width
        self.height = height
    }
}

/// Geotagged photo density near a point, and the photos themselves.
public struct PhotoEvidence: Codable, Hashable, Sendable {
    public var center: Coordinate
    public var radiusM: Double
    /// Photos found within the radius (the source's cap applies).
    public var count: Int
    public var photos: [LicensedPhoto]

    public init(center: Coordinate, radiusM: Double, count: Int, photos: [LicensedPhoto]) {
        self.center = center
        self.radiusM = radiusM
        self.count = count
        self.photos = photos
    }
}

// MARK: Observations

/// One station's latest aviation report, parsed, plus the raw text.
public struct StationReport: Codable, Hashable, Sendable {
    public var stationID: String
    public var stationName: String?
    public var coordinate: Coordinate
    public var elevationM: Double?
    /// Great-circle distance from the asked point.
    public var distanceKm: Double
    /// True when the station is a military airfield (derived from the station name or a curated list; see adapter).
    public var isMilitary: Bool
    public var observedAt: Date
    public var rawMETAR: String
    public var rawTAF: String?
    /// What was parsed. Missing groups stay nil (a report without a sky group has no cloud values).
    public var observation: WeatherObservation
    /// Cloud layers as reported, lowest first.
    public var cloudLayers: [CloudLayer]
    /// Present weather groups as reported, e.g. ["-RA", "BR"].
    public var weather: [String]
    /// Flight category when the source gives one (VFR, MVFR, IFR, LIFR).
    public var flightCategory: String?

    public init(stationID: String, stationName: String? = nil, coordinate: Coordinate, elevationM: Double? = nil, distanceKm: Double,
                isMilitary: Bool, observedAt: Date, rawMETAR: String, rawTAF: String? = nil, observation: WeatherObservation,
                cloudLayers: [CloudLayer] = [], weather: [String] = [], flightCategory: String? = nil) {
        self.stationID = stationID
        self.stationName = stationName
        self.coordinate = coordinate
        self.elevationM = elevationM
        self.distanceKm = distanceKm
        self.isMilitary = isMilitary
        self.observedAt = observedAt
        self.rawMETAR = rawMETAR
        self.rawTAF = rawTAF
        self.observation = observation
        self.cloudLayers = cloudLayers
        self.weather = weather
        self.flightCategory = flightCategory
    }
}

/// A reported cloud layer. Cover in oktas-derived fractions: FEW 0.19, SCT 0.44, BKN 0.75, OVC 1.0 (midpoints).
public struct CloudLayer: Codable, Hashable, Sendable {
    public enum Cover: String, Codable, Sendable { case skc, clr, nsc, few, sct, bkn, ovc, vv }
    public var cover: Cover
    /// Base above ground, metres; nil when not reported.
    public var baseM: Double?
    /// "CB" or "TCU" when reported.
    public var type: String?

    public init(cover: Cover, baseM: Double?, type: String? = nil) {
        self.cover = cover
        self.baseM = baseM
        self.type = type
    }

    public var fraction: Double {
        switch cover {
        case .skc, .clr, .nsc: 0
        case .few: 0.19
        case .sct: 0.44
        case .bkn: 0.75
        case .ovc, .vv: 1
        }
    }
}

/// An official weather alert (NWS).
public struct WeatherAlert: Codable, Hashable, Sendable, Identifiable {
    public enum Severity: String, Codable, Sendable { case extreme, severe, moderate, minor, unknown }
    public var id: String
    /// e.g. "High Wind Warning".
    public var event: String
    public var headline: String?
    public var severity: Severity
    /// "Immediate", "Expected", ... as given.
    public var urgency: String?
    public var certainty: String?
    public var areaDescription: String?
    public var onset: Date?
    public var ends: Date?
    public var expires: Date?
    public var senderName: String?
    public var description: String?
    public var instruction: String?
    public var url: URL?

    public init(id: String, event: String, headline: String? = nil, severity: Severity, urgency: String? = nil,
                certainty: String? = nil, areaDescription: String? = nil, onset: Date? = nil, ends: Date? = nil,
                expires: Date? = nil, senderName: String? = nil, description: String? = nil, instruction: String? = nil,
                url: URL? = nil) {
        self.id = id
        self.event = event
        self.headline = headline
        self.severity = severity
        self.urgency = urgency
        self.certainty = certainty
        self.areaDescription = areaDescription
        self.onset = onset
        self.ends = ends
        self.expires = expires
        self.senderName = senderName
        self.description = description
        self.instruction = instruction
        self.url = url
    }
}

// MARK: Sky

/// Aurora at a point now (OVATION nowcast) with the planetary K index.
public struct AuroraReading: Codable, Hashable, Sendable {
    /// OVATION probability of visible aurora overhead, 0...100 percent, at the nearest 1° grid cell.
    public var probabilityPercent: Double
    public var observedAt: Date
    /// The OVATION forecast time (about 30–90 minutes after observation).
    public var forecastFor: Date
    /// Latest estimated planetary Kp, if fetched.
    public var kpNow: Double?
    public var kpObservedAt: Date?

    public init(probabilityPercent: Double, observedAt: Date, forecastFor: Date, kpNow: Double? = nil, kpObservedAt: Date? = nil) {
        self.probabilityPercent = probabilityPercent
        self.observedAt = observedAt
        self.forecastFor = forecastFor
        self.kpNow = kpNow
        self.kpObservedAt = kpObservedAt
    }
}

/// One 3-hour Kp period from the SWPC forecast product.
public struct KpPeriod: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case observed, estimated, predicted }
    public var start: Date
    public var kp: Double
    public var kind: Kind
    /// NOAA G scale when given, e.g. "G1".
    public var noaaScale: String?

    public init(start: Date, kp: Double, kind: Kind, noaaScale: String? = nil) {
        self.start = start
        self.kp = kp
        self.kind = kind
        self.noaaScale = noaaScale
    }
}

/// Analysed smoke over a point for a day (NOAA HMS).
public struct SmokeAnalysis: Codable, Hashable, Sendable {
    public enum Density: String, Codable, Sendable, Comparable {
        case none, light, medium, heavy
        private var order: Int { switch self { case .none: 0; case .light: 1; case .medium: 2; case .heavy: 3 } }
        public static func < (a: Density, b: Density) -> Bool { a.order < b.order }
    }
    /// The densest polygon containing the point, `.none` when no polygon contains it.
    public var density: Density
    /// The analysis day (UTC midnight of the file's date).
    public var day: Date
    /// Polygons in the file (all densities), for context.
    public var polygonCount: Int
    /// Satellite time span of the containing polygon(s), when given.
    public var validFrom: Date?
    public var validTo: Date?

    public init(density: Density, day: Date, polygonCount: Int, validFrom: Date? = nil, validTo: Date? = nil) {
        self.density = density
        self.day = day
        self.polygonCount = polygonCount
        self.validFrom = validFrom
        self.validTo = validTo
    }
}

/// Night-sky brightness. No commercial-safe source exists yet; the slot returns `.noSource`.
public struct SkyBrightness: Codable, Hashable, Sendable {
    public var bortle: Double?
    /// Zenith brightness, mag/arcsec².
    public var magnitudesPerArcsec2: Double?

    public init(bortle: Double? = nil, magnitudesPerArcsec2: Double? = nil) {
        self.bortle = bortle
        self.magnitudesPerArcsec2 = magnitudesPerArcsec2
    }
}

/// Astronomical seeing and transparency. No commercial-safe source exists yet; the slot returns `.noSource`.
public struct SeeingEstimate: Codable, Hashable, Sendable {
    public var time: Date
    /// Arcseconds.
    public var seeingArcsec: Double?
    /// 0...1, 1 = perfectly transparent.
    public var transparency: Double?

    public init(time: Date, seeingArcsec: Double? = nil, transparency: Double? = nil) {
        self.time = time
        self.seeingArcsec = seeingArcsec
        self.transparency = transparency
    }
}

// MARK: Imagery

/// A tile or WMS overlay the map can draw. Descriptors only; no rendering in this layer.
public struct ImageryLayer: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case satelliteVisible, satelliteInfrared, satelliteGeoColor, radar, nightLights }
    public enum Scheme: String, Codable, Sendable {
        /// `{z}/{x}/{y}` Web Mercator (EPSG:3857) tiles.
        case xyz
        /// WMTS in EPSG:4326 with GIBS-style `{TileMatrix}/{TileRow}/{TileCol}`.
        case wmtsGeographic
        /// WMS GetMap with `{bbox}`, `{width}`, `{height}` placeholders.
        case wms
    }
    public var id: String
    public var source: SourceID
    public var title: String
    public var kind: Kind
    public var scheme: Scheme
    /// Placeholders: {z} {x} {y} (xyz), {TileMatrix} {TileRow} {TileCol} (wmtsGeographic), {bbox} {width} {height}
    /// (wms) and {time} (ISO 8601 UTC, already snapped to `timeStep`) where the layer is time-dimensioned.
    public var urlTemplate: String
    public var minZoom: Int
    public var maxZoom: Int
    /// Zoom levels (tile matrices) known to be populated, when only some are (GIBS).
    public var populatedZooms: [Int]?
    public var tileSize: Int
    /// Spacing of available times; nil for a static layer.
    public var timeStep: Duration?
    /// How far behind real time the newest image usually is.
    public var typicalLatency: Duration?
    public var coverage: Coverage
    public var attribution: String
    public var licence: LicenceTag

    public init(id: String, source: SourceID, title: String, kind: Kind, scheme: Scheme, urlTemplate: String, minZoom: Int,
                maxZoom: Int, populatedZooms: [Int]? = nil, tileSize: Int = 256, timeStep: Duration? = nil,
                typicalLatency: Duration? = nil, coverage: Coverage, attribution: String, licence: LicenceTag) {
        self.id = id
        self.source = source
        self.title = title
        self.kind = kind
        self.scheme = scheme
        self.urlTemplate = urlTemplate
        self.minZoom = minZoom
        self.maxZoom = maxZoom
        self.populatedZooms = populatedZooms
        self.tileSize = tileSize
        self.timeStep = timeStep
        self.typicalLatency = typicalLatency
        self.coverage = coverage
        self.attribution = attribution
        self.licence = licence
    }
}

// Coverage is used inside a Codable type; it encodes as a tagged structure.
extension Coverage: Codable {
    private enum CodingKeys: String, CodingKey { case kind, regions, polygons, parts }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "regions": self = .regions(try c.decode([GeoRegion].self, forKey: .regions))
        case "polygons": self = .polygons(try c.decode([GeoPolygon].self, forKey: .polygons))
        case "union": self = .union(try c.decode([Coverage].self, forKey: .parts))
        default: self = .global
        }
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .global: try c.encode("global", forKey: .kind)
        case .regions(let r): try c.encode("regions", forKey: .kind); try c.encode(r, forKey: .regions)
        case .polygons(let p): try c.encode("polygons", forKey: .kind); try c.encode(p, forKey: .polygons)
        case .union(let u): try c.encode("union", forKey: .kind); try c.encode(u, forKey: .parts)
        }
    }
}

// MARK: On device

/// The geomagnetic field at a point and date (World Magnetic Model).
public struct MagneticField: Codable, Hashable, Sendable {
    /// Declination, degrees; positive when magnetic north is east of true north.
    public var declinationDegrees: Double
    public var inclinationDegrees: Double
    /// Total intensity, nanotesla.
    public var totalIntensityNT: Double
    /// The date the field was computed for.
    public var date: Date
    /// True when the point is in a blackout or caution zone near the magnetic poles (horizontal intensity < 6000 nT / 2000 nT).
    public var nearMagneticPole: Bool

    public init(declinationDegrees: Double, inclinationDegrees: Double, totalIntensityNT: Double, date: Date, nearMagneticPole: Bool) {
        self.declinationDegrees = declinationDegrees
        self.inclinationDegrees = inclinationDegrees
        self.totalIntensityNT = totalIntensityNT
        self.date = date
        self.nearMagneticPole = nearMagneticPole
    }

    /// Converts a true bearing to a magnetic one: magnetic = true − declination (east declination positive).
    public func magneticBearing(fromTrue bearing: Double) -> Double {
        let m = (bearing - declinationDegrees).truncatingRemainder(dividingBy: 360)
        return m < 0 ? m + 360 : m
    }
}
