import Foundation
import IterModel
import IterSources

/// Freely licensed geotagged photos near a point, from Wikimedia Commons, in one request.
/// `count` is the number of files the search found; `photos` holds those with a recognised free licence.
public struct CommonsProvider: PhotoEvidenceProvider {
    static let apiBase = "https://commons.wikimedia.org/w/api.php"

    public let descriptor: SourceDescriptor
    private let http: any HTTPClient
    private let clock: any SourceClock
    private let fileLimit: Int
    private let thumbnailWidth: Int

    public init(http: any HTTPClient, clock: any SourceClock = SystemSourceClock(),
                descriptor: SourceDescriptor = SourceCatalogue.wikimediaCommons, fileLimit: Int = 20, thumbnailWidth: Int = 640) {
        self.http = http
        self.clock = clock
        self.descriptor = descriptor
        self.fileLimit = min(50, max(1, fileLimit))
        self.thumbnailWidth = thumbnailWidth
    }

    static func imageinfoURL(center: Coordinate, radiusM: Int, limit: Int, thumbnailWidth: Int) -> URL {
        var s = apiBase + "?action=query&generator=geosearch&ggscoord=\(WikimediaAPI.coordParam(center))&ggsradius=\(radiusM)"
        s += "&ggsnamespace=6&ggslimit=\(limit)&prop=imageinfo&iiprop=url%7Cextmetadata%7Csize"
        if thumbnailWidth > 0 { s += "&iiurlwidth=\(thumbnailWidth)" }
        return URL(string: s + "&format=json")!
    }

    public func evidence(near center: Coordinate, radiusM: Double) async throws -> PhotoEvidence {
        let radius = WikimediaAPI.clampRadius(radiusM)
        let url = Self.imageinfoURL(center: center, radiusM: radius, limit: fileLimit, thumbnailWidth: thumbnailWidth)
        do {
            let response = try await http.send(.get(url, from: descriptor))
            let result = try CommonsMapping.photos(from: response.body)
            return PhotoEvidence(center: center, radiusM: Double(radius), count: result.filesFound, photos: result.photos)
        } catch { throw SourceError.wrap(error) }
    }
}
