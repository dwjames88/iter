import Foundation
import Testing
import IterModel
import IterSources
@testable import IterSourcesLive

// Live smoke run against the real services. Off unless ITER_LIVE=1, and run only by the phase lead (never in worker
// loops). One shared SourceHTTP so per-host spacing applies; the User-Agent is "Iter/0.0-dev" with no contact.
// About 40 requests in total, most of them small NOMADS boxes.

private let live = ProcessInfo.processInfo.environment["ITER_LIVE"] == "1"
private let livePointW = Coordinate(latitude: 36.5785, longitude: -118.2923)
private let livePointS = Coordinate(latitude: 46.5586, longitude: 8.5610)

@Suite("Live smoke (ITER_LIVE=1)", .enabled(if: live), .serialized)
struct LiveSmokeTests {
    static let http = SourceHTTP(userAgent: UserAgent(version: "0.0-dev"))

    private func next12h() -> TimeSpan {
        let now = Date()
        return TimeSpan(start: now, end: now.addingTimeInterval(12 * 3600))
    }

    private func pct(_ v: Double?) -> String { v.map { String(format: "%5.1f", $0 * 100) } ?? "  nil" }

    private func compare(_ label: String, noaa: HourlySeries, metno: HourlySeries) {
        print("[live] \(label) cloud % (total/low/mid/high)  NOAA vs MET Norway, same UTC hour")
        for h in noaa.hours.prefix(12) {
            guard let m = metno.hours.first(where: { abs($0.time.timeIntervalSince(h.time)) < 1 }) else { continue }
            print("[live]  \(h.time)  NOAA \(pct(h.cloudTotal)) \(pct(h.cloudLow)) \(pct(h.cloudMid)) \(pct(h.cloudHigh))"
                  + "  |  MET \(pct(m.cloudTotal)) \(pct(m.cloudLow)) \(pct(m.cloudMid)) \(pct(m.cloudHigh))"
                  + "  |  T \(h.tempC.map { String(format: "%.1f", $0) } ?? "nil") / \(m.tempC.map { String(format: "%.1f", $0) } ?? "nil") C")
        }
    }

    private func check(_ series: HourlySeries) {
        #expect(!series.hours.isEmpty)
        for h in series.hours {
            for v in [h.cloudTotal, h.cloudLow, h.cloudMid, h.cloudHigh].compactMap({ $0 }) { #expect((0...1).contains(v)) }
            if let t = h.tempC { #expect((-60...50).contains(t)) }
        }
    }

    @Test func whitneyUS() async throws {
        let span = next12h()
        let noaa = try await NOMADSForecastProvider(http: Self.http).forecast(at: livePointW, span: span)
        print("[live] W NOAA: \(noaa.value.hours.count) rows, model \(noaa.provenance.model ?? "-"), grid point \(noaa.provenance.distanceKm.map { String(format: "%.2f km", $0) } ?? "-")")
        if let h = noaa.value.hours.first {
            print("[live] W NOAA first row \(h.time): vis \(h.visibilityKm.map { String(format: "%.1f km", $0) } ?? "nil"), dew \(h.dewpointC ?? .nan), RH \(h.rhPercent ?? .nan), wind \(h.windMs ?? .nan) m/s from \(h.windDirDeg ?? .nan), gust \(h.gustMs ?? .nan), precip \(h.precipMm ?? .nan) mm, smoke \(h.smokeUgm3 ?? .nan) ug/m3, AOD \(h.aod550 ?? .nan)")
        }
        check(noaa.value)
        let metno = try await MetNorwayProvider(http: Self.http).forecast(at: livePointW, span: span)
        check(metno.value)
        compare("W", noaa: noaa.value, metno: metno.value)

        let reports = try await AviationWeatherProvider(http: Self.http).reports(near: livePointW, within: 100, limit: 4)
        #expect(!reports.isEmpty)
        for r in reports.map(\.value) {
            print("[live] W METAR \(r.stationID) \(String(format: "%.1f km", r.distanceKm)) military=\(r.isMilitary) cloud \(pct(r.observation.conditions.cloudTotal)) T \(r.observation.conditions.tempC ?? .nan) :: \(r.rawMETAR)")
            #expect(r.distanceKm <= 100)
        }

        let alerts = try await NWSProvider(http: Self.http).alerts(at: livePointW)
        print("[live] W NWS alerts: \(alerts.value.count) \(alerts.value.map(\.event))")

        let aurora = try await SWPCAuroraProvider(http: Self.http).aurora(at: livePointW)
        print("[live] W aurora \(aurora.value.probabilityPercent)% (OVATION obs \(aurora.value.observedAt), for \(aurora.value.forecastFor)), Kp now \(aurora.value.kpNow ?? .nan)")
        #expect((0...100).contains(aurora.value.probabilityPercent))

        let epqs = try await USGSElevationProvider(http: Self.http).elevation(at: livePointW)
        let tiles = try await TerrariumTerrainProvider(http: Self.http).elevation(at: livePointW)
        print("[live] W elevation EPQS \(epqs.value) m, Terrarium z12 \(tiles.value) m, diff \(epqs.value - tiles.value) m")
        #expect(abs(epqs.value - 4416) < 30)
        #expect(abs(epqs.value - tiles.value) < 30)
    }

    @Test func swissAlpsNonUS() async throws {
        let span = next12h()
        let noaa = try await NOMADSForecastProvider(http: Self.http).forecast(at: livePointS, span: span)
        print("[live] S NOAA: \(noaa.value.hours.count) rows, model \(noaa.provenance.model ?? "-")")
        check(noaa.value)
        let metno = try await MetNorwayProvider(http: Self.http).forecast(at: livePointS, span: span)
        check(metno.value)
        compare("S", noaa: noaa.value, metno: metno.value)

        let reports = try await AviationWeatherProvider(http: Self.http).reports(near: livePointS, within: 100, limit: 4)
        #expect(!reports.isEmpty)
        for r in reports.map(\.value) {
            print("[live] S METAR \(r.stationID) \(String(format: "%.1f km", r.distanceKm)) military=\(r.isMilitary) cloud \(pct(r.observation.conditions.cloudTotal)) T \(r.observation.conditions.tempC ?? .nan) :: \(r.rawMETAR)")
        }
    }
}
