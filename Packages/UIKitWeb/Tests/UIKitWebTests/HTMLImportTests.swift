// uk-html-import (Drawing/HTMLImport.swift): `NSAttributedString(data:options:documentAttributes:)`
// reads plain text and HTML as UIKit's importer does: tag styles, style-sheet rules by
// specificity, inline styles, links, lists, line breaks and collapsed white space, entities, and
// the Times 12 base with monospaced code in Courier; RTF is refused.
import Testing
import UIKit
@testable import UIKitWebCore

@Suite struct HTMLImportTests {
    /// The HTML reader behind `NSAttributedString(data:options:documentAttributes:)`. Called
    /// directly because on macOS AppKit's document types share the initializer's names.
    static func read(_ html: String) -> NSAttributedString {
        var importer = HTMLImport(defaults: [:])
        return importer.read(html)
    }

    static func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> UIColor {
        UIColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
    }

    static func attributes(_ text: NSAttributedString, at word: String) -> [NSAttributedString.Key: Any] {
        let string = text.string
        guard let found = string.range(of: word) else { return [:] }
        return text.attributes(at: string.utf16.distance(from: string.utf16.startIndex, to: found.lowerBound), effectiveRange: nil)
    }

    @Test func tagsGiveTheirStyles() throws {
        let text = Self.read("""
        <p>Hello <b>bold</b> <i>slant</i> <a href="https://example.com/a">link</a> <s>gone</s></p>
        <h1>Title</h1><p>Two&nbsp;words &amp; <code>code</code><br>next</p>
        """)
        #expect(text.string == "Hello bold slant link gone\nTitle\nTwo\u{00A0}words & code\nnext\n")
        let plain = try #require(Self.attributes(text, at: "Hello")[.font] as? UIFont)
        #expect(plain.familyName == "Times New Roman" && plain.pointSize == 12 && plain.weight == .regular)
        #expect((Self.attributes(text, at: "bold")[.font] as? UIFont)?.weight == .bold)
        #expect((Self.attributes(text, at: "slant")[.font] as? UIFont)?.resolved.italic == true)
        let link = Self.attributes(text, at: "link")
        #expect((link[.link] as? URL)?.absoluteString == "https://example.com/a")
        #expect(link[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
        #expect(Self.attributes(text, at: "gone")[.strikethroughStyle] as? Int == NSUnderlineStyle.single.rawValue)
        let title = try #require(Self.attributes(text, at: "Title")[.font] as? UIFont)
        #expect(title.pointSize == 24 && title.weight == .bold)
        let code = try #require(Self.attributes(text, at: "code")[.font] as? UIFont)
        #expect(code.familyName == "Courier" && code.pointSize == 9.75)
        #expect(Self.attributes(text, at: "Hello")[.foregroundColor] as? UIColor == UIColor.black)
    }

    @Test func styleSheetsApplyBySpecificityThenInlineStyles() throws {
        let text = Self.read("""
        <html><head><title>Doc &amp; co</title><style>
        /* a comment */ .note { color: red; font-weight: bold } span.note { color: #00f }
        #key { color: rgb(0, 128, 0) } div .deep { background-color: #ff0; font-size: 20px }
        @media print { .note { color: black } } a:hover { color: purple }
        </style></head><body>
        <span class="note">one</span> <b class="note">two</b> <span id="key" class="note">three</span>
        <div><em><span class="deep">four</span></em></div><span style="color: #123456; font-style: italic">five</span>
        <span class="deep">six</span> <span style="display:none">hidden</span>
        </body></html>
        """)
        #expect(text.string == "one two three\nfour\nfive six\n")
        #expect(Self.attributes(text, at: "one")[.foregroundColor] as? UIColor == Self.color(0, 0, 255))
        #expect(Self.attributes(text, at: "two")[.foregroundColor] as? UIColor == Self.color(255, 0, 0))
        #expect((Self.attributes(text, at: "two")[.font] as? UIFont)?.weight == .bold)
        #expect(Self.attributes(text, at: "three")[.foregroundColor] as? UIColor == Self.color(0, 128, 0))
        let four = Self.attributes(text, at: "four")
        #expect(four[.backgroundColor] as? UIColor == Self.color(255, 255, 0))
        #expect((four[.font] as? UIFont)?.pointSize == 15)
        #expect((four[.font] as? UIFont)?.resolved.italic == true)
        #expect(Self.attributes(text, at: "five")[.foregroundColor] as? UIColor == Self.color(0x12, 0x34, 0x56))
        #expect(Self.attributes(text, at: "six")[.backgroundColor] == nil)
        #expect(!text.string.contains("hidden"))
        #expect(!text.string.contains("Doc"))
    }

    @Test func preformattedTextAndListsKeepTheirShape() throws {
        let text = Self.read("<pre>\n  a  b\n c</pre><ul><li>one<li>two</ul><ol><li>x</li><li>y</li></ol>")
        #expect(text.string == "  a  b\n c\n\t•\tone\n\t•\ttwo\n\t1.\tx\n\t2.\ty\n")
    }

    // The initializer itself, where AppKit's document types don't share its names.
    #if !canImport(AppKit)
    @Test func plainTextAndOtherFormats() throws {
        let plain = try NSAttributedString(data: Data("<b>not html</b>".utf8), options: [.documentType: NSAttributedString.DocumentType.plain], documentAttributes: nil)
        #expect(plain.string == "<b>not html</b>")
        #expect((plain.attributes(at: 0, effectiveRange: nil)[.font] as? UIFont)?.familyName == "Helvetica")
        // Without a type, markup is read as HTML.
        #expect(try NSAttributedString(data: Data("<p>guessed</p>".utf8), options: [:], documentAttributes: nil).string == "guessed\n")
        #expect(throws: (any Error).self) { try NSAttributedString(data: Data("{\\rtf1 hello}".utf8), options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) }
        let latin = try NSAttributedString(data: Data([0x63, 0x61, 0x66, 0xE9]), options: [.documentType: NSAttributedString.DocumentType.plain,
                                                                                              .characterEncoding: String.Encoding.isoLatin1.rawValue],
                                           documentAttributes: nil)
        #expect(latin.string == "café")
    }
    #endif
}
