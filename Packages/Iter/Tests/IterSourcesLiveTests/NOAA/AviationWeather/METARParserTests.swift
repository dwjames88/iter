import Foundation
import Testing
import IterModel
import IterSources
@testable import IterSourcesLive

private let kt = 0.514444
private func lines(_ file: String) throws -> [String] {
    String(decoding: try Fixtures.data(file), as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init)
}

@Suite("METARParser")
struct METARParserTests {
    @Test func partialReportHasNoWindVisibilityOrSky() throws {
        let p = METARParser.parse("METAR KNID 221256Z AUTO A3006 RMK AO2 SLPNO PWINO $")
        #expect(p.stationID == "KNID")
        #expect((p.day, p.hour, p.minute) == (22, 12, 56))
        #expect(p.isAutomated)
        #expect(p.windMs == nil)
        #expect(p.windDirectionDeg == nil)
        #expect(!p.windIsVariable)
        #expect(p.gustMs == nil)
        #expect(p.visibilityKm == nil)
        #expect(p.cloudLayers.isEmpty)
        #expect(!p.hasSkyGroup)
        #expect(p.tempC == nil)
        #expect(p.dewpointC == nil)
        #expect(abs(try #require(p.altimeterHPa) - 1017.99) < 0.05)
        #expect(p.remarks == "AO2 SLPNO PWINO $")
        let c = p.conditions(time: Date(timeIntervalSince1970: 0))
        #expect(c.presentFields.isEmpty)
    }

    @Test func civilAutomatedReport() throws {
        let p = METARParser.parse("METAR KBIH 221256Z AUTO 30006KT 10SM BKN120 M02/M05 A3005 RMK AO2 SLP176 T10221050")
        #expect(p.windDirectionDeg == 300)
        #expect(abs(try #require(p.windMs) - 6 * kt) < 1e-9)
        #expect(abs(try #require(p.visibilityKm) - 16.09344) < 1e-9)
        #expect(p.cloudLayers == [CloudLayer(cover: .bkn, baseM: 12_000 * 0.3048)])
        #expect(p.tempC == -2.2)  // the T10221050 remark gives tenths
        #expect(p.dewpointC == -5.0)
        let c = p.conditions(time: Date(timeIntervalSince1970: 0))
        #expect(c.cloudTotal == 0.75)
        #expect(c.cloudLow == 0)
        #expect(c.cloudMid == 0.75)  // 3658 m is in the 2000 to 6000 m band
        #expect(c.cloudHigh == nil)
        #expect(abs(try #require(c.cloudBaseM) - 3657.6) < 1e-9)
        // Magnus: T -2.2, Td -5.0 gives 81.1 %.
        #expect(abs(try #require(c.rhPercent) - 81.1) < 0.1)
        #expect(c.gustMs == nil)
    }

    @Test func clearAndCalm() {
        let p = METARParser.parse("METAR KEDW 221255Z AUTO 00000KT 10SM CLR 00/M01 A3002 RMK AO2 SLP171 T00011015 $")
        #expect(p.windMs == 0)
        #expect(p.windDirectionDeg == 0)
        #expect(p.cloudLayers == [CloudLayer(cover: .clr, baseM: nil)])
        #expect(p.hasSkyGroup)
        #expect(p.tempC == 0.1)
        #expect(p.dewpointC == -1.5)
        let c = p.conditions(time: Date(timeIntervalSince1970: 0))
        #expect(c.cloudTotal == 0)
        #expect(c.cloudLow == 0)
        #expect(c.cloudMid == nil)  // CLR from an automated sensor says nothing above 12,000 ft
        #expect(c.cloudBaseM == nil)
    }

    @Test func skyClearIsZeroInEveryBand() {
        let c = METARParser.parse("METAR KXXX 221256Z 00000KT 10SM SKC 10/05").conditions(time: Date(timeIntervalSince1970: 0))
        #expect(c.cloudTotal == 0 && c.cloudLow == 0 && c.cloudMid == 0 && c.cloudHigh == 0)
    }

    @Test func europeanFormat() throws {
        let p = METARParser.parse("METAR LSMM 221320Z AUTO 10003KT 070V130 9999NDV -RA FEW008 SCT017 BKN029 05/04 Q1006 RMK")
        #expect(p.windDirectionDeg == 100)
        #expect(abs(try #require(p.windMs) - 3 * kt) < 1e-9)
        #expect(p.visibilityKm == 10)
        #expect(p.weather == ["-RA"])
        #expect(p.cloudLayers.map(\.cover) == [.few, .sct, .bkn])
        #expect(abs(try #require(p.cloudLayers[2].baseM) - 2900 * 0.3048) < 1e-9)
        #expect(p.altimeterHPa == 1006)
        #expect(p.remarks == nil)  // "RMK" with nothing after it
    }

    @Test func trendGroupsAreIgnored() throws {
        let p = METARParser.parse("METAR LSZH 221320Z VRB01KT 4500 RA SCT008 BKN021 05/04 Q1006 TEMPO 5000 NSW BKN008")
        #expect(p.windIsVariable)
        #expect(p.windDirectionDeg == nil)
        #expect(p.visibilityKm == 4.5)
        #expect(p.weather == ["RA"])
        #expect(p.cloudLayers.count == 2)
        let c = p.conditions(time: Date(timeIntervalSince1970: 0))
        #expect(c.cloudBaseM == 2100 * 0.3048)  // BKN021, not the TEMPO BKN008
        #expect(c.windDirDeg == nil)
        #expect(c.cloudLow == 0.44 || c.cloudLow == 0.75)
    }

    @Test func recentWeatherIsNotPresentWeather() {
        let p = METARParser.parse("METAR LSMA 221320Z AUTO 00000KT 7000NDV -RA SCT008 OVC014 05/04 Q1006 RERA RMK")
        #expect(p.weather == ["-RA"])
        #expect(p.visibilityKm == 7)
    }

    @Test func gustsStatuteMilesFractionsAndConvectiveTypes() throws {
        let p = METARParser.parse("METAR KXXX 221350Z 24015G25KT 1 1/2SM +TSRA BR FEW008CB BKN025TCU OVC040 M05/M07 A2992")
        #expect(p.windDirectionDeg == 240)
        #expect(abs(try #require(p.windMs) - 15 * kt) < 1e-9)
        #expect(abs(try #require(p.gustMs) - 25 * kt) < 1e-9)
        #expect(abs(try #require(p.visibilityKm) - 1.5 * 1.609344) < 1e-9)
        #expect(p.weather == ["+TSRA", "BR"])
        #expect(p.cloudLayers.map(\.type) == ["CB", "TCU", nil])
        #expect(p.tempC == -5)
        #expect(p.dewpointC == -7)
        #expect(abs(try #require(p.altimeterHPa) - 1013.2) < 0.1)
    }

    @Test func visibilityVariants() {
        #expect(METARParser.parse("METAR KXXX 221350Z 24005KT P6SM FEW100 10/05").visibilityKm! == 6 * 1.609344)
        #expect(METARParser.parse("METAR KXXX 221350Z 24005KT M1/4SM FG VV002 10/10").visibilityKm! == 0.25 * 1.609344)
        #expect(METARParser.parse("METAR KXXX 221350Z 24005KT 1/2SM FG VV002 10/10").visibilityKm! == 0.5 * 1.609344)
        #expect(METARParser.parse("METAR EDDF 221350Z 24005KT 0800 FG VV002 10/10 Q1020").visibilityKm == 0.8)
        let fog = METARParser.parse("METAR KXXX 221350Z 24005KT 1/4SM FG VV002 10/10").conditions(time: Date(timeIntervalSince1970: 0))
        #expect(fog.cloudTotal == 1)
        #expect(abs(fog.cloudBaseM! - 60.96) < 1e-9)
    }

    @Test func cavokAndOtherWindUnits() throws {
        let p = METARParser.parse("METAR LFPG 221400Z 15005MPS CAVOK 08/03 Q1018 NOSIG")
        #expect(p.isCAVOK)
        #expect(p.visibilityKm == 10)
        #expect(p.windMs == 5)
        #expect(p.windDirectionDeg == 150)
        #expect(!p.hasSkyGroup)
        #expect(p.conditions(time: Date(timeIntervalSince1970: 0)).cloudTotal == nil)
        let kmh = METARParser.parse("METAR XXXX 221400Z 18036KMH 9999 NSC 08/03")
        #expect(abs(try #require(kmh.windMs) - 10) < 1e-9)
        #expect(kmh.cloudLayers == [CloudLayer(cover: .nsc, baseM: nil)])
    }

    @Test func missingDewpointAndSpeci() {
        let p = METARParser.parse("SPECI KXXX 221350Z 24005KT 10SM CLR 10/ A3000")
        #expect(p.isSpecial)
        #expect(p.tempC == 10)
        #expect(p.dewpointC == nil)
        #expect(p.conditions(time: Date(timeIntervalSince1970: 0)).rhPercent == nil)
    }

    @Test func observationTimeResolvesDayOfMonth() throws {
        let p = METARParser.parse("METAR KNID 221256Z AUTO A3006")
        let t = try #require(p.observationTime(relativeTo: Date(timeIntervalSince1970: 1_795_353_600)))  // 2026-11-22T13:20Z
        #expect(t.timeIntervalSince1970 == 1_795_352_160)
        // Reference early on the 1st: day 31 belongs to the previous month.
        let prior = METARParser.parse("METAR KNID 312356Z AUTO")
        let ref = ISO8601DateFormatter().date(from: "2026-12-01T00:10:00Z")!
        #expect(prior.observationTime(relativeTo: ref) == ISO8601DateFormatter().date(from: "2026-10-31T23:56:00Z"))
    }

    @Test func garbageAndEmptyDoNotCrash() {
        #expect(METARParser.parse("").stationID == nil)
        let p = METARParser.parse("???? /// xx")
        #expect(p.windMs == nil && p.visibilityKm == nil && p.cloudLayers.isEmpty)
    }

    // MARK: Every fixture line, cross-checked against the feed's own JSON

    @Test(arguments: ["W", "S"])
    func everyFixtureLineMatchesTheJSON(_ area: String) throws {
        let raws = try lines("AviationWeather/metar-\(area).txt")
        let records = try AviationWeatherMapping.records(from: Fixtures.data("AviationWeather/metar-\(area).json"))
        #expect(raws.count == records.count)
        for raw in raws {
            let p = METARParser.parse(raw)
            let id = try #require(p.stationID)
            let r = try #require(records.first { $0.icaoId == id }, "no JSON for \(id)")
            #expect(r.rawOb == raw, "raw text of \(id)")
            #expect(p.tempC == r.temp, "temp \(id)")  // tenths from the T group when present
            #expect(p.dewpointC == r.dewp, "dewpoint \(id)")
            if let wspd = r.wspd {
                #expect(abs((p.windMs ?? -1) / kt - wspd) < 1e-6, "wind \(id)")
            } else {
                #expect(p.windMs == nil, "wind \(id)")
            }
            switch r.wdir {
            case .number(let d)?: #expect(p.windDirectionDeg == d, "wdir \(id)")
            case .text("VRB")?: #expect(p.windIsVariable && p.windDirectionDeg == nil, "VRB \(id)")
            default: #expect(p.windDirectionDeg == nil, "wdir \(id)")
            }
            #expect(p.cloudLayers.count == (r.clouds?.count ?? 0) || (r.clouds?.isEmpty == true && p.cloudLayers.count == 1), "clouds \(id)")
            for (mine, theirs) in zip(p.cloudLayers, r.clouds ?? []) {
                #expect(mine.cover.rawValue == theirs.cover?.lowercased(), "cover \(id)")
                #expect(abs((mine.baseM ?? -1) / 0.3048 - (theirs.base ?? -1)) < 1e-6, "base \(id)")
            }
            if let v = r.visib?.number {
                let mine = try #require(p.visibilityKm, "visibility \(id)")
                if r.visib?.isCapped == true { #expect(mine >= v * 1.609344 - 1e-9, "visibility \(id)") } else {
                    #expect(abs(mine - v * 1.609344) < 0.05, "visibility \(id)")
                }
            }  // the feed omits `visib` for NDV groups; the raw text still has a value
            if let wx = r.wxString { #expect(p.weather == wx.split(separator: " ").map(String.init), "weather \(id)") } else {
                #expect(p.weather.isEmpty, "weather \(id)")
            }
        }
    }
}
