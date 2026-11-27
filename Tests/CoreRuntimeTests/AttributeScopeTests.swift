// SwiftUI's and UIKit's attribute scopes as apps reach them (WebFoundation's
// ScopedAttributeContainer): `text.swiftUI.foregroundColor` and `container.uiKit.font` read and
// set the scope's keys, and `AttributeContainer(dictionary)` keeps the UIKit and Foundation
// attributes of an `NSAttributedString`'s dictionary, as Harbour builds its containers.
#if os(WASI)
import Testing
import SwiftUI
import UIKit

@Suite @MainActor struct AttributeScopeTests {
    @Test func swiftUIsScopeReadsAndSetsItsKeys() throws {
        var text = AttributedString("Hello world")
        text.swiftUI.foregroundColor = .red
        #expect(text.foregroundColor == .red && text.swiftUI.foregroundColor == .red)
        let world = try #require(text.range(of: "world"))
        text[world].swiftUI.font = .headline
        #expect(text.swiftUI.font == nil && text[world].swiftUI.font == .headline)
        #expect(text.runs.count == 2 && text.runs.last?.swiftUI.font == .headline)

        var container = AttributeContainer()
        container.swiftUI.kern = 2
        container.swiftUI.underlineStyle = .single
        text.mergeAttributes(container)
        #expect(text.kern == 2 && text.swiftUI.underlineStyle == .single && text.runs.count == 2)
    }

    @Test func aDictionarysUIKitAttributes() {
        let red = UIColor.red
        let font = UIFont.boldSystemFont(ofSize: 15)
        let container = AttributeContainer([.foregroundColor: red, .font: font, NSAttributedString.Key("SomeAppKey"): 1])
        #expect(container.uiKit.foregroundColor == red && container.uiKit.font == font)
        let text = AttributedString("Bold", attributes: container)
        #expect(text.uiKit.foregroundColor == red && text.runs.count == 1)
    }

    /// EmojiText's custom emoji: a run's image URL, read by the Foundation key's type.
    @Test func aRunsImageURL() throws {
        let url = try #require(URL(string: "https://example.com/emoji.png"))
        var text = AttributedString(":blob:")
        text.imageURL = url
        let attributes = try #require(text.runs.first?.attributes)
        #expect(attributes[AttributeScopes.FoundationAttributes.ImageURLAttribute.self] == url)
        #expect(AttributeScopes.FoundationAttributes.ImageURLAttribute.name == "NSImageURL")
        // An NSAttributedString's image URL comes over with the Foundation keys.
        let container = AttributeContainer([NSAttributedString.Key("NSImageURL"): url])
        #expect(container.imageURL == url)
    }

    @Test func keysAreNamedAsUIKitNamesThem() {
        #expect(NSAttributedString.Key.baselineOffset.rawValue == "NSBaselineOffset")
        #expect(NSAttributedString.Key.shadow.rawValue == "NSShadow")
        #expect(NSAttributedString.Key.tracking.rawValue == "NSTracking")
        let container = AttributeContainer([.baselineOffset: CGFloat(3), .kern: CGFloat(1)])
        #expect(container.uiKit.baselineOffset == 3 && container.uiKit.kern == 1)
    }
}
#endif
