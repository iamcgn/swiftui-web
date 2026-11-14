// Highlighted code as HighlightSwift makes it (Docs/elements/UIKit/Drawing.md, "Documents"):
// highlight.js's HTML read into an NSAttributedString, its fonts taken off, converted with
// `AttributedString(_:including: \.uiKit)` and shown by `Text`, each token in its theme colour.
// The UIKit scope is UIKitWeb's on wasm; natively it is Apple's.
#if os(WASI)
import Testing
import SwiftUI

@Suite @MainActor struct HTMLAttributedTextTests {
    static let html = """
    <style>
    pre code.hljs{display:block;overflow-x:auto;padding:1em}code.hljs{padding:3px 5px}.hljs{color:#383a42}\
    .hljs ::selection,.hljs::selection{color:#383a42}.hljs-comment,.hljs-quote{color:#a0a1a7;font-style:italic}\
    .hljs-doctag,.hljs-keyword{color:#a626a4}
    </style>
    <pre><code class="hljs"><span class="hljs-keyword">let</span> x = 1 <span class="hljs-comment">// one &amp; two</span></code></pre>
    """

    static func color(_ hex: Int) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    static func read() throws -> NSMutableAttributedString {
        let data = try #require(html.data(using: .utf8))
        return try NSMutableAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html,
                                                                  .characterEncoding: String.Encoding.utf8.rawValue],
                                             documentAttributes: nil)
    }

    @Test func highlightedCodeReadsWithItsThemeColours() throws {
        let read = try Self.read()
        #expect(read.string == "let x = 1 // one & two\n")
        let keyword = read.attributes(at: 0, effectiveRange: nil)
        #expect(keyword[.foregroundColor] as? UIColor == Self.color(0xa626a4))
        let font = try #require(keyword[.font] as? UIFont)
        #expect(font.familyName == "Courier")
        #expect(font.pointSize == 9.75)
        #expect(read.attributes(at: 4, effectiveRange: nil)[.foregroundColor] as? UIColor == Self.color(0x383a42))
        let comment = read.attributes(at: 10, effectiveRange: nil)
        #expect(comment[.foregroundColor] as? UIColor == Self.color(0xa0a1a7))
        #expect((comment[.font] as? UIFont)?.resolved.italic == true)
    }

    @Test func textShowsTheConvertedRuns() throws {
        let read = try Self.read()
        read.removeAttribute(.font, range: NSMakeRange(0, read.length))
        let trimmed = read.attributedSubstring(from: NSRange(location: 0, length: read.length - 1))
        let attributed = try AttributedString(trimmed, including: \.uiKit)
        #expect(String(attributed.characters) == "let x = 1 // one & two")
        let runs = attributed.runs
        #expect(runs.count == 3)
        #expect(runs.first?[AttributeScopes.UIKitAttributes.ForegroundColorAttribute.self] == Self.color(0xa626a4))
        #expect(runs.first?[AttributeScopes.UIKitAttributes.FontAttribute.self] == nil)

        let parts = Text(attributed).parts()
        #expect(parts.map(\.string) == ["let", " x = 1 ", "// one & two"])
        #expect(parts[0].modifiers.foregroundColor == Color(uiColor: Self.color(0xa626a4)))
        #expect(parts[1].modifiers.foregroundColor == Color(uiColor: Self.color(0x383a42)))
        #expect(parts[2].modifiers.foregroundColor == Color(uiColor: Self.color(0xa0a1a7)))
        // Back to an NSAttributedString, the colours are kept under UIKit's keys.
        let back = NSAttributedString(attributed)
        #expect(back.attributes(at: 0, effectiveRange: nil)[.foregroundColor] as? UIColor == Self.color(0xa626a4))
    }

    @Test func fontsAndDecorationsShowInText() throws {
        let data = try #require("<p><u>under</u> <s>struck</s> <code>mono</code> <i>slant</i></p>".data(using: .utf8))
        let read = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil)
        let parts = Text(try AttributedString(read, including: \.uiKit)).parts()
        let byString = Dictionary(parts.map { ($0.string, $0.modifiers) }, uniquingKeysWith: { first, _ in first })
        #expect(byString["under"]?.underline != nil)
        #expect(byString["struck"]?.strikethrough != nil)
        #expect(byString["mono"]?.monospaced == true)
        #expect(byString["slant"]?.italic == true)
        #expect(byString["under"]?.font != nil)
    }
}
#endif
