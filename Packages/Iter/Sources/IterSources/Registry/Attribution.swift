import Foundation

/// The words the UI shows for a licence key. `short` goes on a map or a card, `full` in the credits screen.
public struct AttributionText: Sendable, Hashable {
    public var key: String
    public var short: String
    public var full: String
    public var url: URL?

    public init(key: String, short: String, full: String, url: URL? = nil) {
        self.key = key
        self.short = short
        self.full = full
        self.url = url
    }
}

/// Attribution wording per `LicenceKey`, taken from docs/rebuild/SOURCES.md and the fixtures README.
public enum Attribution {
    /// The Tilezen terrain credit list (docs/attribution.md of tilezen/joerd). An app that shows tiles anywhere carries all of it.
    public static let terrainCredits: [String] = [
        "ArcticDEM terrain data DEM(s) were created from DigitalGlobe, Inc., imagery and funded under National Science Foundation awards 1043681, 1559691, and 1542736;",
        "Australia terrain data (c) Commonwealth of Australia (Geoscience Australia) 2017;",
        "Austria terrain data (c) offene Daten Oesterreichs - Digitales Gelaendemodell (DGM) Oesterreich;",
        "Canada terrain data contains information licensed under the Open Government Licence - Canada;",
        "Europe terrain data produced using Copernicus data and information funded by the European Union - EU-DEM layers;",
        "Global ETOPO1 terrain data U.S. National Oceanic and Atmospheric Administration",
        "Mexico terrain data source: INEGI, Continental relief, 2016;",
        "New Zealand terrain data Copyright 2011 Crown copyright (c) Land Information New Zealand and the New Zealand Government (All rights reserved);",
        "Norway terrain data (c) Kartverket;",
        "United Kingdom terrain data (c) Environment Agency copyright and/or database right 2015. All rights reserved;",
        "United States 3DEP (formerly NED) and global GMTED2010 and SRTM terrain data courtesy of the U.S. Geological Survey.",
    ]

    /// Every key in `LicenceKey`.
    public static let allKeys: [String] = all.map(\.key)

    public static func text(for key: String) -> AttributionText? { all.first { $0.key == key } }

    private static func u(_ s: String) -> URL? { URL(string: s) }

    private static let all: [AttributionText] = [
        AttributionText(
            key: LicenceKey.noaaNCEP, short: "Data: NOAA/NCEP",
            full: "Forecast data from NOAA National Centers for Environmental Prediction (HRRR, GFS, HRRR smoke). US government work, public domain. No endorsement by NOAA is implied.",
            url: u("https://nomads.ncep.noaa.gov/")),
        AttributionText(
            key: LicenceKey.noaaNWS, short: "Data: NOAA/National Weather Service",
            full: "Alerts and observations from the NOAA National Weather Service. US government work, public domain. No endorsement by NOAA is implied.",
            url: u("https://www.weather.gov/documentation/services-web-api")),
        AttributionText(
            key: LicenceKey.noaaAWC, short: "Data: NOAA Aviation Weather Center",
            full: "METAR and TAF reports from the NOAA/NWS Aviation Weather Center, including military airfields. US government work, public domain. No endorsement by NOAA is implied.",
            url: u("https://aviationweather.gov/data/api/")),
        AttributionText(
            key: LicenceKey.noaaSWPC, short: "Data: NOAA Space Weather Prediction Center",
            full: "Aurora and geomagnetic data from the NOAA Space Weather Prediction Center. US government work, public domain. No endorsement by NOAA is implied.",
            url: u("https://www.swpc.noaa.gov/")),
        AttributionText(
            key: LicenceKey.noaaHMS, short: "Data: NOAA Hazard Mapping System",
            full: "Smoke analysis from the NOAA NESDIS Hazard Mapping System. US government work, public domain. No endorsement by NOAA is implied.",
            url: u("https://www.ospo.noaa.gov/products/land/hms.html")),
        AttributionText(
            key: LicenceKey.usgs, short: "Data: USGS",
            full: "Elevation and place names from the U.S. Geological Survey (3DEP via The National Map; Geographic Names). US government work, public domain; credit requested. No endorsement by USGS is implied.",
            url: u("https://www.usgs.gov/information-policies-and-instructions/copyrights-and-credits")),
        AttributionText(
            key: LicenceKey.metNorway, short: "Data from MET Norway (CC BY 4.0)",
            full: "Weather forecast data from the Norwegian Meteorological Institute (MET Norway), licensed CC BY 4.0 (also NLOD).",
            url: u("https://api.met.no/doc/License")),
        AttributionText(
            key: LicenceKey.osm, short: "\u{00A9} OpenStreetMap contributors (ODbL)",
            full: "Map data \u{00A9} OpenStreetMap contributors, available under the Open Database License (ODbL 1.0).",
            url: u("https://www.openstreetmap.org/copyright")),
        AttributionText(
            key: LicenceKey.wikipedia, short: "Text from Wikipedia (CC BY-SA 4.0)",
            full: "Text from Wikipedia, licensed CC BY-SA 4.0; follow each article link for its authors. Titles and coordinates are facts.",
            url: u("https://creativecommons.org/licenses/by-sa/4.0/")),
        AttributionText(
            key: LicenceKey.commons, short: "Photos from Wikimedia Commons; licence per photo",
            full: "Photos from Wikimedia Commons. Each file has its own licence (for example CC0, CC BY, CC BY-SA); credit the author named with each photo.",
            url: u("https://commons.wikimedia.org/wiki/Commons:Reusing_content_outside_Wikimedia")),
        AttributionText(
            key: LicenceKey.terrainTiles, short: "Terrain: Tilezen Terrain Tiles; USGS, NASA/NGA, and national agencies",
            full: "Terrain Tiles by Tilezen on AWS Open Data. " + terrainCredits.joined(separator: " "),
            url: u("https://registry.opendata.aws/terrain-tiles/")),
        AttributionText(
            key: LicenceKey.nasaGIBS, short: "Imagery: NASA GIBS / NOAA GOES / JMA Himawari",
            full: "Satellite imagery served by NASA Global Imagery Browse Services (GIBS) from NOAA GOES and JMA Himawari.",
            url: u("https://nasa-gibs.github.io/gibs-api-docs/")),
        AttributionText(
            key: LicenceKey.eumetsat, short: "Contains EUMETSAT data",
            full: "Contains EUMETSAT data (Meteosat imagery). The licence for real-time imagery in a sold app has not been checked, so this source is off unless the user turns it on, and its imagery is never stored on disk.",
            url: u("https://www.eumetsat.int/data-policy")),
        AttributionText(
            key: LicenceKey.iem, short: "Radar tiles: Iowa Environmental Mesonet (NEXRAD)",
            full: "NEXRAD radar composite tiles from the Iowa Environmental Mesonet, Iowa State University, from NOAA NWS NEXRAD data. The terms have not been fully reviewed, so this source is off unless the user turns it on, and its tiles are never stored on disk.",
            url: u("https://mesonet.agron.iastate.edu/disclaimer.php")),
        AttributionText(
            key: LicenceKey.apple, short: "Apple Maps",
            full: "Search, geocoding, directions and Look Around from Apple Maps. Results are kept in memory only and are not stored.",
            url: u("https://www.apple.com/legal/internet-services/maps/")),
        AttributionText(
            key: LicenceKey.wmm, short: "World Magnetic Model 2025, NGA and UK DGC (US Government work)",
            full: "World Magnetic Model 2025, developed by NOAA NCEI and the British Geological Survey for the US National Geospatial-Intelligence Agency and the UK Defence Geographic Centre. US Government work, computed on this device.",
            url: u("https://www.ncei.noaa.gov/products/world-magnetic-model")),
        AttributionText(
            key: LicenceKey.mgrs, short: "MGRS (NGA standard)",
            full: "Military Grid Reference System, a National Geospatial-Intelligence Agency standard, computed on this device."),
        AttributionText(
            key: LicenceKey.none, short: "No source",
            full: "No source supplies this data, so none is shown."),
    ]
}
