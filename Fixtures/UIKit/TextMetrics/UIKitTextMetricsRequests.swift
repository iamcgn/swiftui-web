// Every (string, font, width, lines) the UIKit fixtures show. The Catalyst harness measures each
// with a real UILabel and writes Fixtures/Goldens/uikit/text-metrics.json; UIKitWeb's headless
// text engine replays those numbers so Tier A layout stays exact, and the same file records each
// font's UIKit metrics (ascender, descender, line height, cap and x heights), which
// UIFontMetricsTests holds UIFont to.
#if canImport(UIKit)
import UIKit

public enum UIKitTextMetricsRequests {
    public static let all: [UIKitTextRequest] = [
        // uikit/label/basic
        UIKitTextRequest("Hello, UIKit", .system(size: 17)),
        UIKitTextRequest("Title", .style("title")),
        UIKitTextRequest("Headline", .style("headline")),
        UIKitTextRequest("Body", .style("body")),
        UIKitTextRequest("Footnote", .style("footnote")),
        UIKitTextRequest("Bold 13", .system(size: 13, weight: "semibold")),   // boldSystemFont is SF Semibold on iOS
        UIKitTextRequest("Semibold 20", .system(size: 20, weight: "semibold")),
        UIKitTextRequest("Centred", .system(size: 17)),
        // uikit/label/wrapping
        UIKitTextRequest("The quick brown fox jumps over the lazy dog", .system(size: 17)),
        UIKitTextRequest("The quick brown fox jumps over the lazy dog", .system(size: 17), width: 200, lines: 0),
        UIKitTextRequest("The quick brown fox jumps over the lazy dog", .system(size: 17), width: 200, lines: 2),
        UIKitTextRequest("The quick brown fox jumps over the lazy dog", .system(size: 17), width: 120, lines: 1),
        // uikit/button/basic: a system button's title is 15 pt; a configured button's is the body
        // style in a label without a line limit (Docs/elements/UIKit/UIButton.md)
        UIKitTextRequest("Tap", .system(size: 15)),
        UIKitTextRequest("Disabled", .system(size: 15)),
        UIKitTextRequest("Plain", .style("body"), lines: 0),
        UIKitTextRequest("Gray", .style("body"), lines: 0),
        UIKitTextRequest("Tinted", .style("body"), lines: 0),
        UIKitTextRequest("Filled", .style("body"), lines: 0),
        UIKitTextRequest("Plain", .system(size: 17), lines: 0),
        // uikit/stack/basic
        UIKitTextRequest("First", .system(size: 17)),
        UIKitTextRequest("Second line", .system(size: 17)),
        UIKitTextRequest("Third", .system(size: 17)),
        UIKitTextRequest("−", .system(size: 15)),
        UIKitTextRequest("+", .system(size: 15)),
        UIKitTextRequest("Count: 0", .system(size: 17)),
        UIKitTextRequest("A longer caption", .system(size: 17)),
        // uikit/controls/basic (text fields measure their text without a line limit)
        UIKitTextRequest("Hello", .system(size: 17), lines: 0),
        UIKitTextRequest("Placeholder", .system(size: 17), lines: 0),
        UIKitTextRequest("Plain field", .system(size: 17), lines: 0),
        UIKitTextRequest("secret", .system(size: 17), lines: 0),
        UIKitTextRequest("••••••", .system(size: 17), lines: 0),
        // ios/representable/* (SwiftUI fixtures hosting UIKit views; Fixtures/Sources/Representable)
        UIKitTextRequest("Hello", .system(size: 17)),
        UIKitTextRequest("Hello, world", .system(size: 17)),
        UIKitTextRequest("The quick brown fox jumps over the lazy dog", .system(size: 17), lines: 0),
        UIKitTextRequest("The quick brown fox jumps over the lazy dog", .system(size: 17), width: 120, lines: 0),
        UIKitTextRequest("Field", .system(size: 17), lines: 0),
        UIKitTextRequest("Inside", .system(size: 17)),
        // uikit/autolayout/*
        UIKitTextRequest("Pinned label", .system(size: 17)),
        UIKitTextRequest("Stretched", .system(size: 17)),
        UIKitTextRequest("A long label that needs room", .system(size: 17)),
        UIKitTextRequest("Short", .system(size: 17)),
        UIKitTextRequest("Title", .system(size: 17)),
        UIKitTextRequest("Subtitle text", .system(size: 17)),
        UIKitTextRequest("Hg", .system(size: 17)),
        UIKitTextRequest("Hg", .system(size: 11)),
        UIKitTextRequest("Hg", .system(size: 13)),
        UIKitTextRequest("Hg", .system(size: 20)),
        UIKitTextRequest("Hg", .system(size: 28)),
        UIKitTextRequest("Hg", .system(size: 34)),
        // uikit/nav/*, uikit/tabs/basic (bar titles are 17 pt semibold, large titles 34 pt bold, tab titles 10 pt medium)
        UIKitTextRequest("Settings", .system(size: 17, weight: "semibold")),
        UIKitTextRequest("Detail", .system(size: 17, weight: "semibold")),
        UIKitTextRequest("Inbox", .system(size: 17, weight: "semibold")),
        UIKitTextRequest("Settings", .system(size: 34, weight: "bold")),
        UIKitTextRequest("Content", .system(size: 17)),
        UIKitTextRequest("Detail content", .system(size: 17)),
        UIKitTextRequest("Home content", .system(size: 17)),
        UIKitTextRequest("Search content", .system(size: 17)),
        UIKitTextRequest("Edit", .system(size: 17, weight: "medium")),
        UIKitTextRequest("Home", .system(size: 10, weight: "semibold")),
        UIKitTextRequest("Home", .system(size: 10, weight: "medium")),
        UIKitTextRequest("Search", .system(size: 10, weight: "semibold")),
        UIKitTextRequest("Search", .system(size: 10, weight: "medium")),
        // uikit/table/* (cell titles 17 pt, subtitle details 15 pt, value1 details 17 pt secondary, headers 13 pt / grouped 13 pt, footers 13 pt)
        UIKitTextRequest("First row", .system(size: 17)),
        UIKitTextRequest("Second row", .system(size: 17)),
        UIKitTextRequest("Third row", .system(size: 17)),
        UIKitTextRequest("Fourth row", .system(size: 17)),
        UIKitTextRequest("Title", .system(size: 17)),
        UIKitTextRequest("Another title", .system(size: 17)),
        UIKitTextRequest("Detail text", .system(size: 15)),
        UIKitTextRequest("More detail", .system(size: 15)),
        UIKitTextRequest("Name", .system(size: 17)),
        UIKitTextRequest("Software", .system(size: 17)),
        UIKitTextRequest("Brightness", .system(size: 17)),
        UIKitTextRequest("iPhone", .system(size: 17)),
        UIKitTextRequest("26.0", .system(size: 17)),
        // Section headers are 17 pt semibold labels without a line limit; footers 13 pt in the card's width less 32.
        UIKitTextRequest("Header", .system(size: 17, weight: "semibold"), lines: 0),
        UIKitTextRequest("General", .system(size: 17, weight: "semibold"), lines: 0),
        UIKitTextRequest("Display", .system(size: 17, weight: "semibold"), lines: 0),
        UIKitTextRequest("A footer note.", .system(size: 13), lines: 0),
        UIKitTextRequest("A footer note.", .system(size: 13), width: 256, lines: 0),
    ]

    /// The fonts whose metrics the harness records (every font a request uses).
    public static var fonts: [UIKitFixtureFont] {
        var seen: [UIKitFixtureFont] = []
        for request in all where !seen.contains(request.font) { seen.append(request.font) }
        return seen
    }
}
#endif
