// NSString's searching, comparing, line and path members (WebFoundation's NSStringMethods.swift
// on wasm): what StyledTextKit's trimming, file-name handling and older string code call
// through `as NSString`. The cases are Apple's documented answers and run against Foundation
// on macOS and Linux too, so the wasm forms answer as Apple's do.
import Testing
import WebFoundation

@Suite struct NSStringMethodsTests {
    private func ns(_ string: String) -> NSString { NSString(string: string) }

    @Test func searchesAnswerInUTF16Ranges() {
        let text = ns("Hello hello")
        #expect(text.range(of: "hello") == NSRange(location: 6, length: 5))
        #expect(text.range(of: "hello", options: .caseInsensitive) == NSRange(location: 0, length: 5))
        #expect(text.range(of: "hello", options: [.caseInsensitive, .backwards]) == NSRange(location: 6, length: 5))
        #expect(text.range(of: "Hello", options: [], range: NSRange(location: 1, length: 10)).location == NSNotFound)
        #expect(text.range(of: "llo", options: [], range: NSRange(location: 4, length: 7)) == NSRange(location: 8, length: 3))
        #expect(ns("😀 hi").range(of: "hi") == NSRange(location: 3, length: 2))

        let padded = ns("  hello  ")
        #expect(padded.rangeOfCharacter(from: .letters) == NSRange(location: 2, length: 1))
        #expect(padded.rangeOfCharacter(from: .whitespaces, options: .backwards) == NSRange(location: 8, length: 1))
        #expect(padded.rangeOfCharacter(from: .decimalDigits).location == NSNotFound)
        #expect(padded.rangeOfCharacter(from: .letters, options: [], range: NSRange(location: 4, length: 5)) == NSRange(location: 4, length: 1))

        #expect(text.hasPrefix("Hell") && text.hasSuffix("llo") && text.contains("o h") && !text.contains("xyz"))
        #expect(text.localizedCaseInsensitiveContains("HELLO H"))
    }

    /// StyledTextKit's `trimCharactersInSet`: trailing whitespace found backwards until none is left.
    @Test func trimmingFromTheEndAsStyledTextKitDoes() {
        let string = NSMutableAttributedString(string: "title \n ")
        var range = NSString(string: string.string).rangeOfCharacter(from: .whitespacesAndNewlines, options: .backwards)
        while range.length != 0 && NSMaxRange(range) == string.length {
            string.replaceCharacters(in: range, with: "")
            range = NSString(string: string.string).rangeOfCharacter(from: .whitespacesAndNewlines, options: .backwards)
        }
        #expect(string.string == "title")
    }

    @Test func comparisonsPiecesAndCopies() {
        #expect(ns("a").caseInsensitiveCompare("A") == .orderedSame)
        #expect(ns("a").compare("b") == .orderedAscending)
        #expect(ns("File 10").localizedStandardCompare("File 2") == .orderedDescending)
        #expect(ns("abc").compare("ABC", options: .caseInsensitive) == .orderedSame)
        #expect(ns("a, b, c").components(separatedBy: ", ") == ["a", "b", "c"])
        #expect(ns("a,b;c").components(separatedBy: CharacterSet(charactersIn: ",;")) == ["a", "b", "c"])
        #expect(ns("  x  ").trimmingCharacters(in: .whitespaces) == "x")
        #expect(ns("abc").appending("def") == "abcdef")
        #expect(ns("abc").padding(toLength: 6, withPad: "xy", startingAt: 1) == "abcyxy")
        #expect(ns("abcdef").padding(toLength: 2, withPad: " ", startingAt: 0) == "ab")
        #expect(ns("one two one").replacingOccurrences(of: "one", with: "1", options: [], range: NSRange(location: 4, length: 7)) == "one two 1")
        #expect(ns("hello world").capitalized == "Hello World")
    }

    @Test func linesAndParagraphs() {
        let text = ns("one\ntwo\r\nthree")
        #expect(text.lineRange(for: NSRange(location: 0, length: 0)) == NSRange(location: 0, length: 4))
        #expect(text.lineRange(for: NSRange(location: 5, length: 0)) == NSRange(location: 4, length: 5))
        #expect(text.lineRange(for: NSRange(location: 2, length: 4)) == NSRange(location: 0, length: 9))
        #expect(text.lineRange(for: NSRange(location: 10, length: 0)) == NSRange(location: 9, length: 5))
        #expect(text.lineRange(for: NSRange(location: 3, length: 0)) == NSRange(location: 0, length: 4))

        let separated = ns("a\u{2028}b\nc")
        #expect(separated.lineRange(for: NSRange(location: 0, length: 0)) == NSRange(location: 0, length: 2))
        #expect(separated.paragraphRange(for: NSRange(location: 0, length: 0)) == NSRange(location: 0, length: 4))
        #expect(separated.paragraphRange(for: NSRange(location: 4, length: 0)) == NSRange(location: 4, length: 1))
    }

    @Test func pathsAsTheDocumentationAnswers() {
        #expect(ns("/tmp").appendingPathComponent("scratch.tiff") == "/tmp/scratch.tiff")
        #expect(ns("/tmp/").appendingPathComponent("scratch.tiff") == "/tmp/scratch.tiff")
        #expect(ns("/").appendingPathComponent("scratch.tiff") == "/scratch.tiff")
        #expect(ns("").appendingPathComponent("scratch.tiff") == "scratch.tiff")

        #expect(ns("/tmp/scratch.tiff").deletingLastPathComponent == "/tmp")
        #expect(ns("/tmp/lock/").deletingLastPathComponent == "/tmp")
        #expect(ns("/tmp/").deletingLastPathComponent == "/")
        #expect(ns("/tmp").deletingLastPathComponent == "/")
        #expect(ns("/").deletingLastPathComponent == "/")
        #expect(ns("scratch.tiff").deletingLastPathComponent == "")

        #expect(ns("/tmp/scratch.tiff").deletingPathExtension == "/tmp/scratch")
        #expect(ns("/tmp/").deletingPathExtension == "/tmp")
        #expect(ns("scratch.bundle/").deletingPathExtension == "scratch")
        #expect(ns(".tiff").deletingPathExtension == ".tiff")
        #expect(ns("/").deletingPathExtension == "/")

        #expect(ns("/tmp/scratch.old").appendingPathExtension("tiff") == "/tmp/scratch.old.tiff")
        #expect(ns("/tmp/").appendingPathExtension("tiff") == "/tmp.tiff")
        #expect(ns("scratch").appendingPathExtension("tiff") == "scratch.tiff")

        #expect(ns("tmp/scratch").pathComponents == ["tmp", "scratch"])
        #expect(ns("/tmp/scratch").pathComponents == ["/", "tmp", "scratch"])
        #expect(ns("/tmp/scratch.tiff").lastPathComponent == "scratch.tiff")
        #expect(ns("/tmp/scratch.tiff").pathExtension == "tiff")
        #expect(ns("/tmp").isAbsolutePath && !ns("tmp").isAbsolutePath)
        #expect(NSString.path(withComponents: ["/", "tmp", "scratch.tiff"]) == "/tmp/scratch.tiff")
        #expect(ns("/nonexistent/./a/../b").standardizingPath == "/nonexistent/b")
    }
}
