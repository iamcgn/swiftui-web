// `AttributedString(localized:)`, as Mlem builds its account captions and its guest banner: the
// localized text read as inline Markdown, with a value interpolated into it.
#if os(WASI) || canImport(Darwin)
import Testing
import Foundation
import SwiftUI

@Suite struct LocalizedAttributedStringTests {
    @Test func aLocalizedValueKeepsItsInterpolatedText() throws {
        let host = "lemmy.world"
        var banner = AttributedString(localized: "Viewing \(host) as guest")
        #expect(String(banner.characters) == "Viewing lemmy.world as guest")
        let range = try #require(banner.range(of: host))
        banner[range].font = .body.weight(.semibold)
        #expect(banner.runs.count == 3)
        let caption: AttributedString = .init(localized: "Guest")
        #expect(String(caption.characters) == "Guest")
    }

    @Test func itsMarkdownIsRead() {
        let styled = AttributedString(localized: "**Unsupported** _instance_")
        #expect(String(styled.characters) == "Unsupported instance")
        #expect(styled.runs.first?.inlinePresentationIntent == .stronglyEmphasized)
        let keyed = AttributedString(localized: "mlem.unsupported", defaultValue: "Unsupported")
        #expect(String(keyed.characters) == "Unsupported")
    }
}
#endif
