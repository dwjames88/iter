import Testing
import Foundation
import IterModel
import IterSources
@testable import IterSourcesLive

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let whitney = Coordinate(latitude: 36.5785, longitude: -118.2923)
private let gotthard = Coordinate(latitude: 46.5586, longitude: 8.5610)

@Suite("Commons mapping")
struct CommonsMappingTests {
    @Test func imageinfoWestLicencesAndAuthors() throws {
        let r = try CommonsMapping.photos(from: try Fixtures.data("Wikimedia/commons-imageinfo-W.json"))
        #expect(r.filesFound == 3)
        #expect(r.photos.map(\.licenceName) == ["CC0", "CC BY-SA 3.0", "CC BY-SA 4.0"])
        #expect(r.photos.map(\.author) == ["Jeremy Bishop tidesinourveins", "Yamil Gonzales", "MakeUkraineGreatAgain"])
        let first = r.photos[0]
        #expect(first.title == "Good Morning from Mount Whitney (Unsplash).jpg")
        #expect(first.credit == "Photo: Jeremy Bishop tidesinourveins, CC0, via Wikimedia Commons")
        #expect(first.licenceURL?.absoluteString == "http://creativecommons.org/publicdomain/zero/1.0/deed.en")
        #expect(first.coordinate == Coordinate(latitude: 36.578499, longitude: -118.292260))
        #expect(first.pageURL?.absoluteString == "https://commons.wikimedia.org/wiki/File:Good_Morning_from_Mount_Whitney_(Unsplash).jpg")
        #expect(first.imageURL?.absoluteString.hasPrefix("https://upload.wikimedia.org/wikipedia/commons/7/72/Good_Morning") == true)
        #expect(first.thumbnailURL == nil && first.width == nil)  // the recorded request did not ask for them
        #expect(r.photos[2].licenceURL?.absoluteString == "https://creativecommons.org/licenses/by-sa/4.0")
        #expect(r.photos[2].credit == "Photo: MakeUkraineGreatAgain, CC BY-SA 4.0, via Wikimedia Commons")
    }

    @Test func imageinfoSouthLicencesAndAuthors() throws {
        let r = try CommonsMapping.photos(from: try Fixtures.data("Wikimedia/commons-imageinfo-S.json"))
        #expect(r.filesFound == 3)
        #expect(r.photos.map(\.licenceName) == ["CC BY-SA 3.0", "CC BY 3.0", "CC BY 3.0"])
        #expect(r.photos.map(\.author) == ["Santiago Puig Vilado…", "marco mini", "marco mini"])
        #expect(r.photos[1].title == "Airolo, Switzerland - panoramio (3).jpg")
        #expect(r.photos[1].licenceURL?.absoluteString == "https://creativecommons.org/licenses/by/3.0")
        #expect(r.photos[1].coordinate == Coordinate(latitude: 46.558485, longitude: 8.561001))
        #expect(r.photos[0].credit == "Photo: Santiago Puig Vilado…, CC BY-SA 3.0, via Wikimedia Commons")
    }

    @Test func plainGeosearchGivesDensity() throws {
        let w = try CommonsMapping.geosearch(from: try Fixtures.data("Wikimedia/commons-geosearch-W.json"))
        #expect(w.count == 10)
        #expect(w[0].title == "File:AlKor19.jpg" && w[0].distanceM == 1.7)
        #expect(try CommonsMapping.density(from: try Fixtures.data("Wikimedia/commons-geosearch-W.json")) == 10)
        #expect(try CommonsMapping.density(from: try Fixtures.data("Wikimedia/commons-geosearch-S.json")) == 10)
        #expect(try CommonsMapping.density(from: Data(#"{"batchcomplete":""}"#.utf8)) == 0)
    }

    @Test func nonFreeAndUnlicensedFilesAreSkippedAndThumbnailAndSizeAreRead() throws {
        // SYNTHETIC: hand-written imageinfo in the recorded shape plus the `iiurlwidth` / `size` fields.
        func page(_ id: Int, _ index: Int, licence: String?, extra: String = "") -> String {
            let lic = licence.map { #","LicenseShortName":{"value":"\#($0)"}"# } ?? ""
            return #""\#(id)":{"pageid":\#(id),"ns":6,"title":"File:P\#(id).jpg","index":\#(index),"imageinfo":[{"url":"https://u/\#(id).jpg","thumburl":"https://u/t\#(id).jpg","width":4000,"height":3000,"descriptionurl":"https://c/\#(id)","extmetadata":{"Artist":{"value":"A &amp; B <b>C</b>"}\#(lic)\#(extra)}}]}"#
        }
        let json = #"{"query":{"pages":{"# + [page(1, 2, licence: "Fair use"), page(2, 1, licence: nil), page(3, 3, licence: "Public domain"),
                                         page(4, 4, licence: "CC BY-NC 4.0"), page(5, 5, licence: "CC BY 4.0", extra: #","NonFree":{"value":"true"}"#),
                                         page(6, 0, licence: "CC BY-SA 4.0")].joined(separator: ",") + "}}}"
        let r = try CommonsMapping.photos(from: Data(json.utf8))
        #expect(r.filesFound == 6)
        #expect(r.photos.map(\.title) == ["P6.jpg", "P3.jpg"])
        #expect(r.photos[0].author == "A & B C")
        #expect(r.photos[0].thumbnailURL?.absoluteString == "https://u/t6.jpg")
        #expect(r.photos[0].width == 4000 && r.photos[0].height == 3000)
        #expect(r.photos[1].licenceName == "Public domain")
    }

    @Test func htmlStrippingAndEntities() {
        #expect(CommonsMapping.plainText("<a href=\"x\">Jane&nbsp;Doe</a> &amp; <i>Joe</i> &#233;&#x41;") == "Jane Doe & Joe éA")
        #expect(CommonsMapping.plainText("<div class=\"fn value\">\n<a href=\"//x\">Yamil Gonzales</a></div>") == "Yamil Gonzales")
        #expect(CommonsMapping.plainText("AT&T & more") == "AT&T & more")
    }
}

@Suite("Commons provider")
struct CommonsProviderTests {
    @Test func oneRequestInTheRecordedFormAndPhotosAreMapped() async throws {
        let http = StubHTTPClient()
        http.on(urlContaining: "commons.wikimedia.org", reply: .ok(try Fixtures.data("Wikimedia/commons-imageinfo-W.json")))
        let provider = CommonsProvider(http: http, clock: ManualSourceClock(now: t0), fileLimit: 3, thumbnailWidth: 0)
        let ev = try await provider.evidence(near: whitney, radiusM: 10_000)
        #expect(http.requests.count == 1)
        // Exactly the recorded request, with `size` added to `iiprop`.
        #expect(http.requests[0].url.absoluteString == "https://commons.wikimedia.org/w/api.php?action=query&generator=geosearch&ggscoord=36.5785%7C-118.2923&ggsradius=10000&ggsnamespace=6&ggslimit=3&prop=imageinfo&iiprop=url%7Cextmetadata%7Csize&format=json")
        #expect(ev.count == 3 && ev.photos.count == 3)
        #expect(ev.center == whitney && ev.radiusM == 10_000)
        #expect(ev.photos.map(\.licenceName) == ["CC0", "CC BY-SA 3.0", "CC BY-SA 4.0"])
    }

    @Test func thumbnailWidthAndRadiusClamp() async throws {
        let http = StubHTTPClient()
        http.on(urlContaining: "commons.wikimedia.org", reply: .ok(try Fixtures.data("Wikimedia/commons-imageinfo-S.json")))
        let ev = try await CommonsProvider(http: http).evidence(near: gotthard, radiusM: 50_000)
        #expect(ev.radiusM == 10_000)
        let url = http.requests[0].url.absoluteString
        #expect(url.contains("ggscoord=46.5586%7C8.561&ggsradius=10000&ggsnamespace=6&ggslimit=20"))
        #expect(url.contains("&iiurlwidth=640&format=json"))
        #expect(ev.photos.map(\.licenceName) == ["CC BY-SA 3.0", "CC BY 3.0", "CC BY 3.0"])
    }

    @Test func failureIsASourceError() async throws {
        let http = StubHTTPClient()
        http.on(urlContaining: "commons.wikimedia.org", reply: .status(503))
        await #expect(throws: SourceError.self) { try await CommonsProvider(http: http).evidence(near: whitney, radiusM: 500) }
    }
}
