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
        // uikit/controls/more (segment titles are 13 pt, the selected one medium)
        UIKitTextRequest("One", .system(size: 13)),
        UIKitTextRequest("Two", .system(size: 13)),
        UIKitTextRequest("Three", .system(size: 13)),
        UIKitTextRequest("One", .system(size: 13, weight: "medium")),
        UIKitTextRequest("Two", .system(size: 13, weight: "medium")),
        UIKitTextRequest("Three", .system(size: 13, weight: "medium")),
        // uikit/alert/*, uikit/sheet/page (alert titles 17 semibold, messages 13, actions 17 regular / semibold for cancel)
        UIKitTextRequest("Behind", .system(size: 17)),
        UIKitTextRequest("Presented", .system(size: 17)),
        UIKitTextRequest("Delete file?", .system(size: 17, weight: "semibold"), width: 244, lines: 0),
        UIKitTextRequest("This cannot be undone.", .system(size: 15), width: 244, lines: 0),
        UIKitTextRequest("Cancel", .system(size: 17, weight: "semibold")),
        UIKitTextRequest("Cancel", .system(size: 17)),
        UIKitTextRequest("Delete", .system(size: 17)),
        UIKitTextRequest("Share", .system(size: 15), width: 244, lines: 0),
        // uikit/alert/textfield, uikit/alert/textfields (13 pt fields)
        UIKitTextRequest("Rename", .system(size: 17, weight: "semibold"), width: 244, lines: 0),
        UIKitTextRequest("Enter a new name for the file.", .system(size: 15), width: 244, lines: 0),
        UIKitTextRequest("Save", .system(size: 17)),
        UIKitTextRequest("Sign In", .system(size: 17, weight: "semibold"), width: 244, lines: 0),
        UIKitTextRequest("Sign In", .system(size: 17)),
        UIKitTextRequest("Forgot Password", .system(size: 17)),
        UIKitTextRequest("Name", .system(size: 13)),
        UIKitTextRequest("Username", .system(size: 13)),
        UIKitTextRequest("Password", .system(size: 13)),
        UIKitTextRequest("corey", .system(size: 13)),
        UIKitTextRequest("Copy Link", .system(size: 20)),
        UIKitTextRequest("Save Image", .system(size: 20)),
        UIKitTextRequest("Cancel", .system(size: 20, weight: "semibold")),
        UIKitTextRequest("Copy Link", .system(size: 17)),
        UIKitTextRequest("Save Image", .system(size: 17)),
        // uikit/textview/basic: the container is the frame less the insets and the 5 pt line
        // fragment padding each side (278 in a 288 view)
        UIKitTextRequest("The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs.", .system(size: 17), width: 278, lines: 0),
        UIKitTextRequest("Two lines of\ntext", .system(size: 17), width: 190, lines: 0),
        UIKitTextRequest("Two lines of\ntext", .system(size: 17), width: 80.5, lines: 0),
        UIKitTextRequest("Padded", .system(size: 15), width: 126, lines: 0),
        UIKitTextRequest("Centred", .system(size: 17), width: 190, lines: 0),
        UIKitTextRequest("Read-only footnote text that wraps onto a second line in this width.", .system(size: 13), width: 278, lines: 0),
        // uikit/collection/selfsizing (15 pt tags)
        UIKitTextRequest("Swift", .system(size: 15)),
        UIKitTextRequest("SwiftUI", .system(size: 15)),
        UIKitTextRequest("UIKit", .system(size: 15)),
        UIKitTextRequest("Auto Layout", .system(size: 15)),
        UIKitTextRequest("Compositional", .system(size: 15)),
        UIKitTextRequest("Web", .system(size: 15)),
        // uikit/collection/headers
        UIKitTextRequest("Section 1", .system(size: 17, weight: "semibold")),
        UIKitTextRequest("Section 2", .system(size: 17, weight: "semibold")),
        UIKitTextRequest("3 items", .system(size: 13)),
        UIKitTextRequest("2 items", .system(size: 13)),
        // uikit/datepicker/compact (17 pt labels in the capsules)
        UIKitTextRequest("Sep 11, 2026", .system(size: 17)),
        UIKitTextRequest("2:30\u{202F}PM", .system(size: 17)),   // UIKit joins the time and its period with a narrow no-break space
        UIKitTextRequest("0:00\u{202F}PM", .system(size: 17)),   // the time label's monospaced digits: every digit as wide as a zero
        // uikit/nav/toolbar, uikit/nav/search
        UIKitTextRequest("Files", .system(size: 17, weight: "semibold")),
        UIKitTextRequest("Items", .system(size: 17, weight: "semibold")),
        UIKitTextRequest("Items", .system(size: 34, weight: "bold")),
        UIKitTextRequest("Search items", .system(size: 17, weight: "medium")),
        // uikit/toolbar/basic (17 pt medium titles, semibold for a done item), uikit/search/basic
        UIKitTextRequest("Cancel", .system(size: 17, weight: "medium")),
        UIKitTextRequest("Done", .system(size: 17, weight: "semibold")),
        UIKitTextRequest("Search", .system(size: 17, weight: "medium")),
        UIKitTextRequest("Swift", .system(size: 17, weight: "medium")),
        UIKitTextRequest("Minimal", .system(size: 17, weight: "medium")),
        // uikit/textview/heights
        UIKitTextRequest("Height 11", .system(size: 11), width: 190, lines: 0),
        UIKitTextRequest("Height 12", .system(size: 12), width: 190, lines: 0),
        UIKitTextRequest("Height 13", .system(size: 13), width: 190, lines: 0),
        UIKitTextRequest("Height 14", .system(size: 14), width: 190, lines: 0),
        UIKitTextRequest("Height 15", .system(size: 15), width: 190, lines: 0),
        UIKitTextRequest("Height 16", .system(size: 16), width: 190, lines: 0),
        UIKitTextRequest("Height 17", .system(size: 17), width: 190, lines: 0),
        UIKitTextRequest("Height 20", .system(size: 20), width: 190, lines: 0),
        UIKitTextRequest("Height 24", .system(size: 24), width: 190, lines: 0),
        UIKitTextRequest("Height 28", .system(size: 28), width: 190, lines: 0),
    ]

    /// The fonts whose metrics the harness records (every font a request uses).
    public static var fonts: [UIKitFixtureFont] {
        var seen: [UIKitFixtureFont] = []
        for request in all where !seen.contains(request.font) { seen.append(request.font) }
        return seen
    }
}
#endif
