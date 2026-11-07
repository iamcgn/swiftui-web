// URLComponents' ranges into its string, as swift-http-types reads them to build a request's
// scheme, authority and path. The cases run against Foundation on macOS and Linux too.
import Testing
import WebFoundation

@Suite struct URLComponentsRangeTests {
    private func pieces(_ components: URLComponents) -> [String?] {
        let string = components.string ?? ""
        let ranges = [components.rangeOfScheme, components.rangeOfUser, components.rangeOfPassword, components.rangeOfHost,
                      components.rangeOfPort, components.rangeOfPath, components.rangeOfQuery, components.rangeOfFragment]
        return ranges.map { $0.map { String(string[$0]) } }
    }

    @Test func everyPieceOfAFullURL() throws {
        let components = try #require(URLComponents(string: "https://ann:secret@example.com:8443/a/b%20c?x=1&y=2#top"))
        #expect(pieces(components) == ["https", "ann", "secret", "example.com", "8443", "/a/b%20c", "x=1&y=2", "top"])
    }

    @Test func missingPiecesHaveNoRange() throws {
        let components = try #require(URLComponents(string: "http://example.com/index.html"))
        #expect(pieces(components) == ["http", nil, nil, "example.com", nil, "/index.html", nil, nil])
    }

    @Test func aUserWithoutAPassword() throws {
        let components = try #require(URLComponents(string: "ftp://ann@files.example/pub"))
        #expect(pieces(components) == ["ftp", "ann", nil, "files.example", nil, "/pub", nil, nil])
    }

    @Test func aRelativeReference() throws {
        let components = try #require(URLComponents(string: "docs/page?q=1"))
        #expect(pieces(components) == [nil, nil, nil, nil, nil, "docs/page", "q=1", nil])
    }

    @Test func rangesFollowChangedComponents() throws {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.example"
        components.path = "/v1/items"
        components.queryItems = [URLQueryItem(name: "page", value: "2")]
        #expect(components.string == "https://api.example/v1/items?page=2")
        #expect(pieces(components) == ["https", nil, nil, "api.example", nil, "/v1/items", "page=2", nil])
    }
}
