// Link Presentation (Sources/LinkPresentation): the metadata record IceCubes fills for its share
// sheet, and the title and canonical URL a fetched page's markup gives (Gem's link previews).
import Testing
@testable import LinkPresentation

@Suite struct LinkPresentationTests {
    private let page = URL(string: "https://example.com/post/1")!

    @Test func metadataIsARecordAppsFillIn() {
        let metadata = LPLinkMetadata()
        #expect(metadata.title == nil && metadata.url == nil && metadata.imageProvider == nil)
        metadata.title = "A post"
        metadata.originalURL = page
        #expect(metadata.title == "A post" && metadata.originalURL == page)
    }

    @Test func theOpenGraphTitleWinsOverTheTitleElement() {
        let html = """
        <html><head><title>Plain title</title>
        <meta property="og:title" content="Fish &amp; Chips &#8211; Tonight">
        </head><body><meta property="og:title" content="ignored"></body></html>
        """
        let metadata = _LinkMetadataReader.metadata(html: html, original: page, loaded: page)
        #expect(metadata.title == "Fish & Chips \u{2013} Tonight")
        #expect(metadata.originalURL == page && metadata.url == page)
    }

    @Test func theTitleElementIsReadWhenNoMetaTagNamesOne() {
        let html = "<HTML><HEAD><TITLE lang=en>\n  Release   notes\n</TITLE></HEAD></HTML>"
        #expect(_LinkMetadataReader.metadata(html: html, original: page, loaded: page).title == "Release notes")
        #expect(_LinkMetadataReader.metadata(html: "<p>no head</p>", original: page, loaded: page).title == nil)
    }

    @Test func aCanonicalLinkResolvesAgainstThePage() {
        let html = #"<head><link rel="canonical" href="/post/1?ref=share"><meta name='twitter:title' content='Tweeted'></head>"#
        let metadata = _LinkMetadataReader.metadata(html: html, original: page, loaded: page)
        #expect(metadata.url?.absoluteString == "https://example.com/post/1?ref=share")
        #expect(metadata.title == "Tweeted")
        let other = _LinkMetadataReader.metadata(html: #"<meta property="og:url" content="javascript:alert(1)">"#, original: page, loaded: page)
        #expect(other.url == page)
    }

    @Test func aProviderFetchesOnceAndRefusesOtherSchemes() async {
        let provider = LPMetadataProvider()
        await #expect(throws: LPError(.metadataFetchNotAllowed)) {
            _ = try await provider.startFetchingMetadata(for: URL(string: "file:///etc/hosts")!)
        }
        await #expect(throws: LPError(.metadataFetchNotAllowed)) {
            _ = try await provider.startFetchingMetadata(for: page)
        }
        #expect(LPError.metadataFetchFailed ~= LPError(.metadataFetchFailed) as any Error)
    }
}
