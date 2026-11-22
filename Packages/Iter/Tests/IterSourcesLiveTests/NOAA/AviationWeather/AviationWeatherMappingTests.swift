import Foundation
import Testing
import IterModel
import IterSources
@testable import IterSourcesLive

private let whitney = Coordinate(latitude: 36.5785, longitude: -118.2923)
private let gotthard = Coordinate(latitude: 46.5586, longitude: 8.5610)
private let kt = 0.514444

@Suite("AviationWeatherMapping")
struct AviationWeatherMappingTests {
    private func reports(_ area: String, from origin: Coordinate, tafs: [String: String] = [:]) throws -> [StationReport] {
        try AviationWeatherMapping.reports(from: Fixtures.data("AviationWeather/metar-\(area).json"), origin: origin, tafs: tafs)
    }

    @Test func whitneyOrderAndDistances() throws {
        let r = try reports("W", from: whitney)
        #expect(r.map(\.stationID) == ["KO26", "KBIH", "KNID", "KEDW"])
        #expect(abs(r[0].distanceKm - 21.5) < 0.1)
        #expect(abs(r[1].distanceKm - 88.3) < 0.1)
        #expect(abs(r[2].distanceKm - 112.8) < 0.1)
        #expect(abs(r[3].distanceKm - 189.6) < 0.1)
    }

    @Test func militaryFlagsAtWhitney() throws {
        let r = try reports("W", from: whitney)
        let flags = Dictionary(uniqueKeysWithValues: r.map { ($0.stationID, $0.isMilitary) })
        #expect(flags == ["KO26": false, "KBIH": false, "KNID": true, "KEDW": true])
    }

    @Test func lonePineValues() throws {
        let r = try #require(try reports("W", from: whitney).first)
        #expect(r.stationName == "Lone Pine Arpt, CA, US")
        #expect(r.elevationM == 3680)
        #expect(r.observedAt == Date(timeIntervalSince1970: 1_795_354_500))  // 13:35Z
        #expect(r.rawMETAR == "METAR KO26 221335Z AUTO 35004KT 10SM CLR M02/M05 A3010 RMK A01")
        #expect(r.flightCategory == "VFR")
        let c = r.observation.conditions
        #expect(c.tempC == -2 && c.dewpointC == -5)
        #expect(c.windDirDeg == 350)
        #expect(abs(c.windMs! - 4 * kt) < 1e-9)
        #expect(abs(c.visibilityKm! - 16.09344) < 1e-9)
        #expect(c.cloudTotal == 0)
        #expect(r.cloudLayers == [CloudLayer(cover: .clr, baseM: nil)])
        #expect(r.observation.time == r.observedAt)
        #expect(r.observation.stationName == r.stationName)
    }

    @Test func partialKNIDHasNilNotZero() throws {
        let r = try #require(try reports("W", from: whitney).first { $0.stationID == "KNID" })
        #expect(r.isMilitary)
        #expect(r.observation.conditions.presentFields.isEmpty)
        #expect(r.cloudLayers.isEmpty)
        #expect(r.weather.isEmpty)
        #expect(r.flightCategory == nil)
        #expect(r.rawMETAR == "METAR KNID 221256Z AUTO A3006 RMK AO2 SLPNO PWINO $")
    }

    @Test func bishopCloudBands() throws {
        let c = try #require(try reports("W", from: whitney).first { $0.stationID == "KBIH" }).observation.conditions
        #expect(c.cloudTotal == 0.75)
        #expect(c.cloudLow == 0)
        #expect(c.cloudMid == 0.75)
        #expect(c.cloudHigh == nil)
        #expect(abs(c.cloudBaseM! - 3657.6) < 1e-9)
        #expect(abs(c.windMs! - 6 * kt) < 1e-9)
    }

    @Test func swissOrderAndMilitary() throws {
        let r = try reports("S", from: gotthard)
        #expect(r.map(\.stationID) == ["LSMM", "LSMA", "LSZC", "LSZL", "LSME", "LSZA", "LSZH", "LIMC"])
        #expect(abs(r[0].distanceKm - 40.07) < 0.1)
        let mil = Set(r.filter(\.isMilitary).map(\.stationID))
        #expect(mil == ["LSMM", "LSMA", "LSME"])
        #expect(r.first { $0.stationID == "LSMM" }?.stationName == "Meiringen Arpt, BE, CH")
    }

    @Test func swissValues() throws {
        let r = try reports("S", from: gotthard)
        func cond(_ id: String) throws -> HourlyConditions { try #require(r.first { $0.stationID == id }).observation.conditions }
        // VRB wind: speed kept, direction nil.
        let lsza = try cond("LSZA")
        #expect(lsza.windDirDeg == nil)
        #expect(abs(lsza.windMs! - 2 * kt) < 1e-9)
        #expect(lsza.visibilityKm == 10)  // "6+" capped in the JSON; the raw 9999 says 10 km
        #expect(lsza.cloudLow == 0.44)  // SCT015 = 457 m
        #expect(lsza.cloudMid == 0.75)  // BKN076 = 2316 m
        #expect(abs(lsza.cloudBaseM! - 7600 * 0.3048) < 1e-9)
        // Numeric visibility in statute miles: 5.59 SM (9000 m).
        #expect(abs(try cond("LSZC").visibilityKm! - 5.59 * 1.609344) < 1e-9)
        #expect(abs(try cond("LSZH").visibilityKm! - 2.8 * 1.609344) < 1e-9)
        // Alpine military field: calm wind has direction 0 as reported.
        let lsmm = try cond("LSMM")
        #expect(lsmm.windDirDeg == 100)
        let lsmmReport = try #require(r.first { $0.stationID == "LSMM" })
        #expect(lsmmReport.weather == ["-RA"])
        #expect(lsmmReport.cloudLayers.map(\.cover) == [.few, .sct, .bkn])
        #expect(lsmmReport.flightCategory == nil)
        #expect(try #require(r.first { $0.stationID == "LSZH" }).flightCategory == "IFR")
        // Low-band overcast.
        let lsma = try cond("LSMA")
        #expect(lsma.cloudTotal == 1 && lsma.cloudLow == 1)
        #expect(abs(lsma.cloudBaseM! - 1400 * 0.3048) < 1e-9)
        #expect(abs(lsma.tempC! - 5) < 1e-9)
        #expect(abs(lsma.rhPercent! - 93.2) < 0.5)
    }

    @Test func tafAttachment() throws {
        let raw = String(decoding: try Fixtures.data("AviationWeather/taf-W.txt"), as: UTF8.self)
        let tafs = AviationWeatherMapping.tafs(fromRaw: raw)
        #expect(Set(tafs.keys) == ["KBIH", "KEDW", "KNID"])
        #expect(tafs["KBIH"]?.hasPrefix("TAF KBIH 221136Z 2212/2312 34007KT P6SM FEW120") == true)
        #expect(tafs["KBIH"]?.contains("FM230400 32006KT P6SM BKN120") == true)
        #expect(tafs["KEDW"]?.hasPrefix("TAF AMD KEDW") == true)
        #expect(tafs["KNID"]?.hasPrefix("TAF COR KNID") == true)
        #expect(tafs["KO26"] == nil)

        let r = try reports("W", from: whitney, tafs: tafs)
        #expect(r.first { $0.stationID == "KO26" }?.rawTAF == nil)
        #expect(r.first { $0.stationID == "KBIH" }?.rawTAF == tafs["KBIH"])
    }

    @Test func swissTafsSplitOnReportBoundaries() throws {
        let raw = String(decoding: try Fixtures.data("AviationWeather/taf-S.txt"), as: UTF8.self)
        let tafs = AviationWeatherMapping.tafs(fromRaw: raw)
        #expect(Set(tafs.keys) == Set(["LIMC", "LSMA", "LSZC", "LSZA", "LSZL", "LSME", "LSZH", "LSMM"]))
        #expect(tafs["LIMC"]?.hasPrefix("TAF LIMC 221100Z 2212/2318") == true)
        #expect(tafs["LSMA"]?.hasPrefix("TAF AMD LSMA") == true)
        #expect(tafs["LIMC"]?.contains("LSMA") == false)
        #expect(tafs["LSMA"]?.contains("PROB30") == true)
    }

    @Test func emptyAndMalformed() throws {
        #expect(try AviationWeatherMapping.reports(from: Data(), origin: whitney).isEmpty)
        #expect(try AviationWeatherMapping.reports(from: Data("[]".utf8), origin: whitney).isEmpty)
        #expect(throws: SourceError.self) { try AviationWeatherMapping.reports(from: Data("<html>".utf8), origin: whitney) }
        // A record with no position or time is dropped, not zero-filled.
        let json = #"[{"icaoId":"KXXX","rawOb":"METAR KXXX"},{"icaoId":"KYYY","obsTime":1795354500,"lat":36.6,"lon":-118.3,"rawOb":"METAR KYYY 221335Z"}]"#
        let r = try AviationWeatherMapping.reports(from: Data(json.utf8), origin: whitney)
        #expect(r.map(\.stationID) == ["KYYY"])
        #expect(r[0].observation.conditions.presentFields.isEmpty)
    }
}

@Suite("MilitaryStations")
struct MilitaryStationsTests {
    @Test func curatedIDs() {
        for id in ["KNID", "KNFL", "KEDW", "KLSV", "KNKX", "KNZY", "KVBG", "KSKA", "KDMA", "KBAB", "KBIF", "KHMN", "ETAR", "LIPA",
                   "ETAD", "EGUN", "EGUL", "RJTY", "RODN", "PAED", "PHNG", "LSMM", "LSME"] {
            #expect(MilitaryStations.isMilitary(icaoID: id, name: nil), "\(id)")
        }
        #expect(MilitaryStations.isMilitary(icaoID: "knid", name: nil))
    }

    @Test func nameMarkers() {
        for name in ["Whiteman AFB, MO, US", "Oceana NAS, VA, US", "Naval Air Station Key West", "China Lake NAWS", "Miramar MCAS",
                     "Fort Rucker (Cairns AAF)", "Fort Wainwright Army Airfield", "Ramstein Air Base", "Willow Grove ANGB",
                     "Fort Dix JRB", "Dover Air Force Base"] {
            #expect(MilitaryStations.isMilitary(icaoID: "KXXX", name: name), "\(name)")
        }
    }

    @Test func civilStationsAreNotMarked() {
        for (id, name) in [("KBIH", "Bishop Rgnl, CA, US"), ("KO26", "Lone Pine Arpt, CA, US"), ("LSZH", "Zürich Intl Arpt, ZH, CH"),
                           ("KBNA", "Nashville Intl, TN, US"), ("KMIA", "Miami Intl, FL, US"), ("EGLL", "London Heathrow, GB")] {
            #expect(!MilitaryStations.isMilitary(icaoID: id, name: name), "\(id)")
        }
        #expect(!MilitaryStations.isMilitary(icaoID: "KBIH", name: nil))
    }
}
