import Testing
import Foundation

// A cheap guard against recording an error page: every recorded fixture (except GRIB2/ and Geomag/, owned elsewhere)
// is non-empty, JSON files parse, text files are text, PNGs have the PNG signature, and every manifest row is HTTP 200.
@Suite struct FixtureIntegrityTests {
    private let skipped: Set<String> = ["GRIB2", "Geomag"]

    private func fixtureFiles() throws -> [URL] {
        let root = Fixtures.root
        let keys: [URLResourceKey] = [.isRegularFileKey]
        let walker = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys))
        var out: [URL] = []
        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: Set(keys)).isRegularFile) == true else { continue }
            let top = url.pathComponents.dropFirst(root.pathComponents.count).first ?? ""
            if skipped.contains(top) { continue }
            out.append(url)
        }
        return out
    }

    @Test func fixturesExist() throws {
        let names = Set(try fixtureFiles().map(\.lastPathComponent))
        for expected in ["locationforecast-W.json", "locationforecast-S.json", "metar-W.json", "taf-S.txt", "stationinfo-W.json",
                         "points-W.json", "ovation_aurora_latest.json", "planetary_k_index_1m.json",
                         "noaa-planetary-k-index-forecast.json", "oneday-W.json", "oneday-S.json", "epqs-W.json",
                         "overpass-W.json", "overpass-S.json", "commons-imageinfo-W.json", "reference.json"] {
            #expect(names.contains(expected), "missing \(expected)")
        }
    }

    @Test func everyJSONFixtureParsesAndIsNonEmpty() throws {
        var count = 0
        for url in try fixtureFiles() where url.pathExtension == "json" {
            let data = try Data(contentsOf: url)
            #expect(!data.isEmpty, "\(url.lastPathComponent) is empty")
            let object = try JSONSerialization.jsonObject(with: data)
            if let dict = object as? [String: Any] { #expect(!dict.isEmpty, "\(url.lastPathComponent) is {}") }
            if let array = object as? [Any] { #expect(!array.isEmpty, "\(url.lastPathComponent) is []") }
            count += 1
        }
        #expect(count >= 20)
    }

    @Test func textAndPNGFixtures() throws {
        for url in try fixtureFiles() {
            let data = try Data(contentsOf: url)
            #expect(!data.isEmpty, "\(url.lastPathComponent) is empty")
            switch url.pathExtension {
            case "txt":
                let text = try #require(String(data: data, encoding: .utf8))
                #expect(!text.contains("<html"), "\(url.lastPathComponent) looks like an HTML error page")
            case "png":
                #expect(Array(data.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
            default: break
            }
        }
    }

    @Test func manifestRowsAreAll200AndSizesMatch() throws {
        let text = try #require(String(data: try Fixtures.data("manifest.tsv"), encoding: .utf8))
        let rows = text.split(separator: "\n").dropFirst()
        #expect(rows.count >= 30)
        for row in rows {
            let cols = row.split(separator: "\t", omittingEmptySubsequences: false)
            #expect(cols.count >= 6)
            #expect(cols[2] == "200", "\(cols[0]) was recorded with HTTP \(cols[2])")
            let size = try Data(contentsOf: Fixtures.url(String(cols[0]))).count
            #expect(String(size) == cols[3], "\(cols[0]) size differs from manifest")
        }
    }

    @Test func domainShapes() throws {
        func object(_ path: String) throws -> [String: Any] {
            try #require(JSONSerialization.jsonObject(with: try Fixtures.data(path)) as? [String: Any])
        }
        #expect((try object("Overpass/overpass-W.json")["elements"] as? [Any])?.isEmpty == false)
        #expect((try object("Overpass/overpass-S.json")["elements"] as? [Any])?.isEmpty == false)
        #expect(try object("MetNo/locationforecast-W.json")["type"] as? String == "Feature")
        #expect(try object("NWS/points-W.json")["properties"] != nil)
        #expect((try object("Wikimedia/wikipedia-geosearch-W.json")["query"] as? [String: Any])?["geosearch"] != nil)
        #expect(try object("USGS/epqs-W.json")["value"] != nil)
        let ovation = try object("SWPC/ovation_aurora_latest.json")
        #expect((ovation["coordinates"] as? [Any])?.count ?? 0 > 1000)
    }
}
