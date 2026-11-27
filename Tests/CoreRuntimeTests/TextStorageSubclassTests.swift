// A text storage that keeps its text in a store of its own, as a syntax highlighter's does
// (GistHub's Highlightr, `CodeAttributedString`): it overrides the four primitives (`string`,
// `attributes(at:effectiveRange:)`, `replaceCharacters(in:with:)` and `setAttributes(_:range:)`)
// and `processEditing()`, and every other member reads and writes through those. On wasm the
// attributed strings under it are WebFoundation's, whose other members go through the same
// primitives; `Scanner`'s older string scans read the highlighter's HTML.
import Testing
import UIKitWebCore
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

@Suite @MainActor struct TextStorageSubclassTests {
    @Test func aStorageWithItsOwnStoreIsReadAndWrittenThroughItsPrimitives() {
        let storage = DigitHighlighter()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "let x = 1")
        #expect(storage.string == "let x = 1" && storage.length == 9)
        // The override ran after `super.processEditing()` with the edit still described, and
        // marked the digit, which the edit it made in turn was processed for.
        #expect(storage.processed.first?.mask == .editedCharacters)
        #expect(storage.processed.first?.range == NSRange(location: 0, length: 9))
        #expect(storage.processed.first?.delta == 9)
        #expect(storage.processed.count == 2 && storage.processed.last?.mask == .editedAttributes)
        #expect(storage.attribute(.digit, at: 8, effectiveRange: nil) as? Bool == true)
        #expect(storage.attribute(.digit, at: 0, effectiveRange: nil) == nil)

        // Members it doesn't override reach its store through the primitives.
        storage.addAttribute(.spacing, value: 2, range: NSRange(location: 0, length: 3))
        #expect(storage.backing.attribute(.spacing, at: 1, effectiveRange: nil) as? Int == 2)
        storage.append(NSAttributedString(string: "2", attributes: [.spacing: 1]))
        #expect(storage.backing.string == "let x = 12")
        #expect(storage.backing.attribute(.spacing, at: 9, effectiveRange: nil) as? Int == 1)
        storage.deleteCharacters(in: NSRange(location: 0, length: 4))
        #expect(storage.string == "x = 12")
        #expect(storage.attributedSubstring(from: NSRange(location: 4, length: 2)).string == "12")
        var runs: [NSRange] = []
        storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { _, range, _ in runs.append(range) }
        #expect(runs.first?.location == 0 && runs.last.map { $0.location + $0.length } == 6)
    }

    @Test func aLayoutManagerLaysOutTheStoresText() {
        let storage = DigitHighlighter()
        let manager = NSLayoutManager()
        storage.addLayoutManager(manager)
        manager.addTextContainer(NSTextContainer(size: CGSize(width: 300, height: 100)))
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "abc 42")
        #expect(manager.numberOfGlyphs == 6)
        storage.replaceCharacters(in: NSRange(location: 4, length: 2), with: "7")
        #expect(manager.numberOfGlyphs == 5)
        // The edit's range is the one before it, as TextKit's `edited` takes it.
        #expect(storage.processed.contains { $0.mask == .editedCharacters && $0.range == NSRange(location: 4, length: 1) && $0.delta == -1 })
    }

    #if os(WASI)
    @Test func aMutableAttributedStringSubclassOverridesThePrimitivesOnly() {
        let string = BackedAttributedString()
        string.append(NSAttributedString(string: "hello", attributes: [.tag: "a"]))
        string.insert(NSAttributedString(string: ">"), at: 0)
        string.addAttribute(.spacing, value: 1, range: NSRange(location: 1, length: 2))
        #expect(string.string == ">hello" && string.backing.string == ">hello")
        #expect(string.attribute(.tag, at: 2, effectiveRange: nil) as? String == "a")
        #expect(string.attribute(.spacing, at: 2, effectiveRange: nil) as? Int == 1)
        #expect(string.attribute(.spacing, at: 3, effectiveRange: nil) == nil)
        let copy = NSAttributedString(attributedString: string)
        #expect(copy.string == ">hello" && copy.isEqual(to: string))
        #expect(string.primitiveCalls > 0)
    }

    @Test func scannersOlderStringScansWriteAnNSString() {
        let scanner = Scanner(string: "<span class=\"hljs-keyword\">let</span>")
        scanner.charactersToBeSkipped = nil
        var text: NSString?
        #expect(scanner.scanString("<span class=\"", into: nil))
        #expect(scanner.scanUpTo("\"", into: &text) && text?.string == "hljs-keyword")
        #expect(scanner.scanString("\">", into: nil))
        #expect(scanner.scanUpToCharacters(from: CharacterSet(charactersIn: "<"), into: &text) && text?.string == "let")
        #expect(!scanner.scanUpTo("<", into: &text))
    }
    #endif
}

extension NSAttributedString.Key {
    fileprivate static let digit = NSAttributedString.Key("TestDigit")
    fileprivate static let spacing = NSAttributedString.Key("TestSpacing")
    fileprivate static let tag = NSAttributedString.Key("TestTag")
}

/// Keeps its text in a mutable attributed string of its own and marks digits as each
/// edit is processed, as Highlightr's `CodeAttributedString` colours code.
private final class DigitHighlighter: NSTextStorage, @unchecked Sendable {
    let backing = NSMutableAttributedString(string: "")
    var processed: [(mask: NSTextStorage.EditActions, range: NSRange, delta: Int)] = []

    override init() { super.init() }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    override var string: String { backing.string }
    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        backing.attributes(at: location, effectiveRange: range)
    }
    override func replaceCharacters(in range: NSRange, with str: String) {
        backing.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range, changeInLength: str.utf16.count - range.length)
    }
    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        backing.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
    }
    override func processEditing() {
        super.processEditing()
        processed.append((editedMask, editedRange, changeInLength))
        guard editedMask.contains(.editedCharacters) else { return }
        beginEditing()
        for (offset, unit) in string.utf16.enumerated() where (0x30...0x39).contains(unit) {
            addAttribute(.digit, value: true, range: NSRange(location: offset, length: 1))
        }
        endEditing()
    }
}

#if os(WASI)
/// A mutable attributed string over another, counting the calls to its primitives.
private final class BackedAttributedString: NSMutableAttributedString, @unchecked Sendable {
    let backing = NSMutableAttributedString(string: "")
    var primitiveCalls = 0

    init() { super.init(string: "") }

    override var string: String { backing.string }
    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        backing.attributes(at: location, effectiveRange: range)
    }
    override func replaceCharacters(in range: NSRange, with str: String) {
        primitiveCalls += 1
        backing.replaceCharacters(in: range, with: str)
    }
    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        primitiveCalls += 1
        backing.setAttributes(attrs, range: range)
    }
}
#endif
