// The Foundation members a text engine calls (Runestone keeps its text in an `NSMutableString`,
// hands tree-sitter the UTF-16 bytes through `getBytes`, widens edits to whole characters,
// checks character sets with `isSubset(of:)` and adds its caret timer to the run loop). The
// wasm forms are WebFoundation's (NSMutableString.swift, Responder.swift, Lifecycle.swift);
// these run against Foundation on macOS and Linux too.
import Testing
import WebFoundation

private final class Count: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func bump() { lock.withLock { value += 1 } }
    var current: Int { lock.withLock { value } }
}

@Suite struct TextEngineFoundationTests {
    @Test func mutableStringsEditInUTF16Ranges() {
        let text = NSMutableString(string: "Hello world")
        text.replaceCharacters(in: NSRange(location: 6, length: 5), with: "there")
        #expect(text.isEqual(to: "Hello there"))
        text.insert("😀 ", at: 0)
        #expect(text.length == 14 && text.hasPrefix("😀 Hello"))
        text.deleteCharacters(in: NSRange(location: 0, length: 3))
        text.append("!")
        #expect(text.isEqual(to: "Hello there!"))
        #expect(text.replaceOccurrences(of: "e", with: "E", options: [], range: NSRange(location: 0, length: text.length)) == 3)
        #expect(text.isEqual(to: "HEllo thErE!"))
        // Backwards searches from the end; anchored takes only matches at that end, adjacent ones included.
        let ends = NSMutableString(string: "aba")
        #expect(ends.replaceOccurrences(of: "a", with: "X", options: [.anchored, .backwards], range: NSRange(location: 0, length: 3)) == 1)
        #expect(ends.isEqual(to: "abX"))
        let run = NSMutableString(string: "aaba")
        #expect(run.replaceOccurrences(of: "a", with: "X", options: .anchored, range: NSRange(location: 0, length: 4)) == 2)
        #expect(run.isEqual(to: "XXba"))
        #expect(run.replaceOccurrences(of: "X", with: "-", options: .backwards, range: NSRange(location: 0, length: 4)) == 2)
        #expect(run.isEqual(to: "--ba"))
        text.setString("abc")
        #expect(text.length == 3 && NSMutableString(capacity: 8).length == 0)
    }

    @Test func composedCharacterRangesCoverWholeCharacters() {
        let text = NSString(string: "a😀e\u{301}b")
        #expect(text.rangeOfComposedCharacterSequence(at: 0) == NSRange(location: 0, length: 1))
        #expect(text.rangeOfComposedCharacterSequence(at: 2) == NSRange(location: 1, length: 2))
        #expect(text.rangeOfComposedCharacterSequence(at: 3) == NSRange(location: 3, length: 2))
        #expect(text.rangeOfComposedCharacterSequences(for: NSRange(location: 2, length: 2)) == NSRange(location: 1, length: 4))
        #expect(text.rangeOfComposedCharacterSequences(for: NSRange(location: 5, length: 1)) == NSRange(location: 5, length: 1))
    }

    @Test func getBytesCopiesWholeCharactersInAnEncoding() {
        let text = NSString(string: "hé😀")
        var buffer = [UInt8](repeating: 0, count: 16)
        var used = 0
        var rest = NSRange(location: 0, length: 0)
        let all = NSRange(location: 0, length: text.length)
        let utf8 = buffer.withUnsafeMutableBytes {
            text.getBytes($0.baseAddress, maxLength: 16, usedLength: &used, encoding: String.Encoding.utf8.rawValue,
                          options: [], range: all, remaining: &rest)
        }
        #expect(utf8 && used == 7 && Array(buffer[0..<7]) == Array("hé😀".utf8) && rest.length == 0)

        // Only whole characters fit: the emoji's four bytes don't, so it is left over.
        let partial = buffer.withUnsafeMutableBytes {
            text.getBytes($0.baseAddress, maxLength: 5, usedLength: &used, encoding: String.Encoding.utf8.rawValue,
                          options: [], range: all, remaining: &rest)
        }
        #expect(partial && used == 3 && rest == NSRange(location: 2, length: 2))

        let utf16 = buffer.withUnsafeMutableBytes {
            text.getBytes($0.baseAddress, maxLength: 16, usedLength: &used, encoding: String.Encoding.utf16LittleEndian.rawValue,
                          options: [], range: NSRange(location: 1, length: 3), remaining: &rest)
        }
        #expect(utf16 && used == 6 && Array(buffer[0..<2]) == [0xE9, 0x00] && Array(buffer[2..<6]) == [0x3D, 0xD8, 0x00, 0xDE])
    }

    @Test func characterSetsAnswerSubsetTests() {
        let vowels = CharacterSet(charactersIn: "aeiou")
        #expect(CharacterSet(charactersIn: "ae").isSubset(of: vowels))
        #expect(!CharacterSet(charactersIn: "ab").isSubset(of: vowels))
        #expect(vowels.isSubset(of: .letters) && vowels.isSuperset(of: ["a", "o"]))
        #expect(vowels.isDisjoint(with: .decimalDigits) && !vowels.isDisjoint(with: CharacterSet(charactersIn: "xyzu")))
        #expect(CharacterSet(charactersIn: ".,").isSubset(of: .punctuationCharacters))
        #expect(vowels.union(CharacterSet(charactersIn: "y")).isSuperset(of: ["y", "e"]))
        #expect(vowels.intersection(CharacterSet(charactersIn: "abc")).isSubset(of: ["a"]))
        #expect(CharacterSet().isEmpty && !vowels.isEmpty)
    }

    @Test func timersAddedToTheRunLoopAndFiredByHand() {
        let count = Count()
        let timer = Timer(timeInterval: 60, repeats: true) { _ in count.bump() }
        #expect(timer.isValid && timer.timeInterval == 60)
        timer.fire()
        #expect(count.current == 1 && timer.isValid)
        RunLoop.main.add(timer, forMode: .common)
        timer.invalidate()
        #expect(!timer.isValid)
        timer.fire()
        #expect(count.current == 1)
    }

    #if os(WASI)
    /// Invalidating a timer lets go of its block and what the block holds, as Foundation's
    /// invalidation releases a timer's target.
    @Test func invalidatedTimersLetGoOfTheirBlock() {
        final class Held: Sendable {}
        weak var probe: Held?
        let timer: Timer
        do {
            let held = Held()
            probe = held
            timer = Timer(timeInterval: 60, repeats: false) { _ in withExtendedLifetime(held) {} }
        }
        #expect(probe != nil && timer.isValid)
        timer.invalidate()
        #expect(probe == nil && !timer.isValid)
    }
    #endif

    // Linux's Foundation has no initialiser without a string; Apple's and the wasm one do.
    #if os(WASI) || canImport(Darwin)
    @Test func emptyAttributedStrings() {
        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: "a😀"))
        #expect(text.length == 3 && NSAttributedString().length == 0)
    }
    #endif
}
