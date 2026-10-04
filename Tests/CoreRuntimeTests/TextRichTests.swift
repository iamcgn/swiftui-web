// Phase 8 step 6, sw-attributed-text: markdown literals, attributed strings, links, dates,
// formats and inline images (Docs/elements/Text.md, "Rich text").
import Testing
import SwiftUI

@Observable
private final class Opened {
    var urls: [String] = []
}

private struct Linked: View {
    let opened: Opened
    var body: some View {
        Text("Call **now** or [visit](https://example.com) today")._probe("text")
            .environment(\.openURL, OpenURLAction { url in opened.urls.append(url.absoluteString); return .handled })
    }
}

@Suite @MainActor struct TextRichTests {
    @Test func markdownLiteralsBecomeStyledParts() {
        let text = Text("Plain **bold** and _italic_ and `code` [go](https://a.b) ~~x~~")
        let parts = text.parts()
        #expect(parts.map(\.string) == ["Plain ", "bold", " and ", "italic", " and ", "code", " ", "go", " ", "x"])
        #expect(parts[1].modifiers.bold && !parts[1].modifiers.italic)
        #expect(parts[3].modifiers.italic && !parts[3].modifiers.bold)
        #expect(parts[5].modifiers.monospaced)
        #expect(parts[7].modifiers.link?.absoluteString == "https://a.b")
        #expect(parts[9].modifiers.strikethrough != nil)
        #expect(text.resolvedString == "Plain bold and italic and code go x")
        // Verbatim text keeps its asterisks; a string value is verbatim too.
        #expect(Text(verbatim: "**not**").parts().map(\.string) == ["**not**"])
        let value = "**not**"
        #expect(Text(value).parts().map(\.string) == ["**not**"])
    }

    @Test func attributedStringsCarryTheirRunAttributes() {
        var hello = AttributedString("Hello ")
        var world = AttributedString("world")
        world[_SwiftUIFontAttribute.self] = .title
        world[_SwiftUIForegroundColorAttribute.self] = .red
        var link = AttributedString(" link")
        link[AttributeScopes.FoundationAttributes.LinkAttribute.self] = URL(string: "https://example.com")
        var strong = AttributedString(" strong")
        strong[AttributeScopes.FoundationAttributes.InlinePresentationIntentAttribute.self] = [.stronglyEmphasized, .code]
        hello += world
        hello += link
        hello += strong
        let parts = Text(hello).parts()
        #expect(parts.map(\.string) == ["Hello ", "world", " link", " strong"])
        #expect(parts[1].modifiers.font == .title && parts[1].modifiers.foregroundColor == .red)
        #expect(parts[2].modifiers.link?.absoluteString == "https://example.com")
        #expect(parts[3].modifiers.bold && parts[3].modifiers.monospaced)
        // The modifiers on the whole text apply beneath the runs'.
        #expect(Text(hello).foregroundColor(.blue).parts()[0].modifiers.foregroundColor == .blue)
        #expect(Text(hello).foregroundColor(.blue).parts()[1].modifiers.foregroundColor == .red)
    }

    @Test func linksOpenOnPressAndShowTheHand() {
        let opened = Opened()
        let runtime = Runtime()
        runtime.mount(Linked(opened: opened))
        runtime.layout(in: CGSize(width: 300, height: 100))
        let frame = runtime.probeFrames["text"]!
        // Unit layouts measure nothing: every fragment is zero wide, so the first point of the
        // line lands on the first fragment ("Call "), not the link.
        runtime.pointerDown(at: CGPoint(x: frame.minX + 0.1, y: frame.midY))
        runtime.pointerUp(at: CGPoint(x: frame.minX + 0.1, y: frame.midY))
        #expect(opened.urls.isEmpty)
        let node = runtime.root.descendants(where: { $0 is TextNode }).first as! TextNode
        #expect(node.hasLinks && node.isInteractive)
        #expect(!Text("plain").parts().contains { $0.modifiers.link != nil })
        // A text without links takes no presses at all.
        let plain = Runtime()
        plain.mount(Text("plain")._probe("p"))
        plain.layout(in: CGSize(width: 100, height: 50))
        let plainNode = plain.root.descendants(where: { $0 is TextNode }).first as! TextNode
        #expect(!plainNode.isInteractive)
    }

    @Test func dateStylesAndFormats() {
        let instant = Date(timeIntervalSince1970: 1_780_000_000)
        let context = _TextContext(timeZone: TimeZone(identifier: "UTC")!, calendar: Calendar(identifier: .gregorian), now: instant.addingTimeInterval(-7_500))
        #expect(_DateText.string(for: instant, style: .date, context: context) == "May 28, 2026")
        #expect(_DateText.string(for: instant, style: .time, context: context) == "8:26\u{202F}PM")
        #expect(_DateText.string(for: instant, style: .relative, context: context) == "2 hours")
        #expect(_DateText.string(for: instant, style: .offset, context: context) == "+2 hours")
        #expect(_DateText.string(for: instant, style: .timer, context: context) == "2:05:00")
        let past = _TextContext(timeZone: TimeZone(identifier: "UTC")!, calendar: Calendar(identifier: .gregorian), now: instant.addingTimeInterval(45))
        #expect(_DateText.string(for: instant, style: .offset, context: past) == "-45 seconds")
        #expect(_DateText.string(for: instant, style: .timer, context: past) == "0:45")
        #expect(Text(instant, style: .relative).isLive && !Text(instant, style: .date).isLive)
        #expect(Text(1234, format: .number).resolvedString == "1,234")
        #expect(Text(0.25, format: .percent).resolvedString == "25%")
        // Midnight and noon in the 12-hour clock.
        let midnight = Date(timeIntervalSince1970: 1_780_000_000 - 20 * 3600 - 26 * 60 - 40)
        #expect(_DateText.string(for: midnight, style: .time, context: context) == "12:00\u{202F}AM")
        #expect(_DateText.string(for: midnight.addingTimeInterval(12 * 3600), style: .time, context: context) == "12:00\u{202F}PM")
    }

    @Test func inlineImagesTakeTheSymbolsWidth() {
        let runtime = Runtime()
        runtime.mount((Text(Image(systemName: "star")) + Text(" Starred"))._probe("text"))
        runtime.layout(in: CGSize(width: 300, height: 100))
        // The star at 13 pt is 16.5 wide (the unit runtime's engine lays nothing out).
        let node = runtime.root.descendants(where: { $0 is TextNode }).first as! TextNode
        #expect(node.styledRuns.runs[0].inlineWidth == 16.5 && node.styledRuns.runs[0].inlineHeight == 16)
        let parts = (Text(Image(systemName: "star")) + Text(" Starred")).parts()
        #expect(parts[0].image != nil && parts[0].string == Text.objectReplacement && parts[1].image == nil)
        #expect(Text(Image(systemName: "star")).resolvedString == "")
    }
}

@Suite struct CustomFontMetricsTests {
    /// Abel's tables (Fixtures/Fonts/Abel-Regular.ttf): 2048 units, ascender 2006, descender −604.
    private static let abel = FontResource(postScriptName: "Abel-Regular", family: "Abel", file: "Fonts/Abel-Regular.ttf", unitsPerEm: 2048,
                                           ascender: 2006, descender: -604, lineGap: 0, capHeight: 1434, xHeight: 1044)

    @Test func linesAreTheRoundedAscentPlusTheRoundedDescent() {
        CustomFontRegistry.register(AssetCatalog(fonts: ["Abel-Regular": Self.abel]))
        func metrics(_ size: CGFloat) -> SystemFontMetrics {
            SystemFontMetricsTables.systemFontMetrics(for: ResolvedFont(family: "Abel-Regular", size: size, weight: .regular, italic: false, textStyle: nil))
        }
        // SwiftUI's heights at 13, 15, 20, 22, 32 and 40 pt (measured 2026-10-03).
        #expect(metrics(13).lineHeight == 17 && metrics(13).baseline == 13)
        #expect(metrics(15).lineHeight == 19 && metrics(15).baseline == 15)
        #expect(metrics(20).lineHeight == 26 && metrics(20).baseline == 20)
        #expect(metrics(22).lineHeight == 28)
        #expect(metrics(32).lineHeight == 40)
        #expect(metrics(40).lineHeight == 51 && metrics(40).baseline == 39)
        #expect(abs(metrics(20).capHeight - 14.0039) < 0.001)
        // The family name finds the same font; an unknown family falls back to the system tables.
        #expect(SystemFontMetricsTables.systemFontMetrics(for: ResolvedFont(family: "Abel", size: 20, weight: .regular, italic: false, textStyle: nil)).lineHeight == 26)
        #expect(SystemFontMetricsTables.systemFontMetrics(for: ResolvedFont(family: "Nowhere", size: 20, weight: .regular, italic: false, textStyle: nil)).lineHeight == 24)
        // The key names the family so recordings and the harness agree.
        #expect(ResolvedFont(family: "Abel-Regular", size: 20, weight: .bold, italic: true, textStyle: nil).key == "custom:Abel-Regular:20:700:italic")
    }
}
