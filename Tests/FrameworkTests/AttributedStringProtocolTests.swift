// Swift's attributed strings as Foundation shapes them (WebFoundation's AttributedString.swift on
// wasm): an attribute read from a whole string or a slice is the value every character shares,
// slices take any range expression and append as strings do, a scope's container reads and sets
// its keys, merges keep the new or the current value, and attributes are replaced where a run
// has them. EmojiText (IceCubes) and Harbour rely on these. The cases run against Foundation
// on macOS and Linux too, so the wasm forms answer as Apple's do.
import Testing
import WebFoundation

enum NoteColorAttribute: AttributedStringKey {
    typealias Value = String
    static let name = "test.noteColor"
}

extension AttributeScopes {
    struct NoteAttributes: AttributeScope {
        let noteColor: NoteColorAttribute
    }
    var notes: NoteAttributes.Type { NoteAttributes.self }
}

extension AttributeDynamicLookup {
    subscript<T: AttributedStringKey>(dynamicMember keyPath: KeyPath<AttributeScopes.NoteAttributes, T>) -> T { self[T.self] }
}

/// The characters of any attributed string, as generic code reads them.
func plainCharacters<S: AttributedStringProtocol>(_ text: S) -> String { String(text.characters) }

@Suite struct AttributedStringProtocolTests {
    private func coloured(_ string: String, _ color: String, language: String = "en") -> AttributedString {
        var text = AttributedString(string)
        text.noteColor = color
        text.languageIdentifier = language
        return text
    }

    @Test func attributesAreTheOnesEveryCharacterShares() throws {
        let text = coloured("Hello", "red") + coloured(" world", "blue")
        #expect(text.languageIdentifier == "en")
        #expect(text.noteColor == nil)
        #expect(text.runs.count == 2)
        let world = try #require(text.range(of: "world"))
        #expect(text[world].noteColor == "blue" && String(text[world].characters) == "world")
        #expect(text[text.startIndex..<world.lowerBound].noteColor == nil)

        // Neighbours whose attributes match are one run, however the string was put together.
        var joined = AttributedString("a") + AttributedString("b")
        #expect(joined.runs.count == 1)
        joined.noteColor = "green"
        #expect(joined.runs.count == 1 && joined.noteColor == "green")
        var split = coloured("ab", "red")
        split[try #require(split.range(of: "b"))].noteColor = "blue"
        #expect(split.runs.count == 2)
        split[try #require(split.range(of: "b"))].noteColor = "red"
        #expect(split.runs.count == 1 && split.noteColor == "red")
        #expect(AttributedString().noteColor == nil && AttributedString().runs.isEmpty)
    }

    @Test func slicesTakeAnyRangeAndAppendAsStrings() throws {
        let text = coloured("Hello", "red") + coloured(" world", "blue")
        let start = text.index(text.startIndex, offsetByCharacters: 6)
        let tail = text[start...]
        #expect(plainCharacters(tail) == "world" && plainCharacters(text[..<start]) == "Hello ")
        #expect(plainCharacters(text) == "Hello world")
        #expect(tail.startIndex == start && tail.endIndex == text.endIndex)

        let said = AttributedString("Say ") + tail
        #expect(plainCharacters(said) == "Say world")
        #expect(said[try #require(said.range(of: "world"))].noteColor == "blue")
        var built = AttributedString("x")
        built.append(tail)
        built += text[..<start]
        #expect(plainCharacters(built) == "xworldHello ")
        #expect(AttributedString(tail) == coloured("world", "blue"))
        #expect(tail.runs.count == 1 && tail.runs.first?.noteColor == "blue")
        #expect(tail.runs.first?.range == start..<text.endIndex)

        var edited = text
        edited.removeSubrange(..<start)
        #expect(edited == coloured("world", "blue"))
        edited.insert(AttributedString("big "), at: edited.startIndex)
        #expect(plainCharacters(edited) == "big world" && edited.runs.count == 2)
        edited.replaceSubrange(edited.startIndex..<edited.index(edited.startIndex, offsetByCharacters: 3), with: text[..<start])
        #expect(plainCharacters(edited) == "Hello  world")
    }

    @Test func aScopesContainerReadsAndSetsItsKeys() {
        var container = AttributeContainer()
        container.notes.noteColor = "red"
        #expect(container.noteColor == "red" && container.notes.noteColor == "red")

        var text = AttributedString("note", attributes: container)
        #expect(text.notes.noteColor == "red")
        text.notes.noteColor = "blue"
        #expect(text.noteColor == "blue" && text.runs.first?.notes.noteColor == "blue")
        text.notes.noteColor = nil
        #expect(text.noteColor == nil && text.runs.first?.notes.noteColor == nil)

        // A slice's container is the values the slice shares; setting one sets it there only.
        var mixed = coloured("ab", "red") + coloured("cd", "blue")
        #expect(mixed.notes.noteColor == nil)
        let cd = mixed.index(mixed.startIndex, offsetByCharacters: 2)..<mixed.endIndex
        #expect(mixed[cd].notes.noteColor == "blue")
        mixed[cd].notes.noteColor = "red"
        #expect(mixed.notes.noteColor == "red" && mixed.runs.count == 1)
    }

    @Test func clearingThroughAScopeClearsRunsThatDiffer() {
        // The runs differ, so the scope holds no colour, and clearing it still clears them all.
        var mixed = coloured("ab", "red") + coloured("cd", "blue")
        mixed.notes.noteColor = nil
        #expect(mixed.runs.count == 1)
        #expect(mixed.runs.allSatisfy { $0.noteColor == nil } && mixed.languageIdentifier == "en")

        // Through a slice, only the slice's characters lose it.
        var three = coloured("ab", "red") + coloured("cd", "blue") + coloured("ef", "green")
        let middle = three.index(three.startIndex, offsetByCharacters: 1)..<three.index(three.startIndex, offsetByCharacters: 4)
        three[middle].notes.noteColor = nil
        #expect(three.runs.map { String(three[$0.range].characters) } == ["a", "bcd", "ef"])
        #expect(three.runs.map(\.noteColor) == ["red", nil, "green"])
    }

    @Test func mergesKeepTheNewOrTheCurrentValue() {
        var added = AttributeContainer()
        added.noteColor = "blue"
        added.languageIdentifier = "fr"
        var current = AttributeContainer()
        current.noteColor = "red"
        #expect(current.merging(added, mergePolicy: .keepCurrent).noteColor == "red")
        #expect(current.merging(added).noteColor == "blue" && current.merging(added).languageIdentifier == "fr")
        current.merge(added, mergePolicy: .keepCurrent)
        #expect(current.noteColor == "red" && current.languageIdentifier == "fr")

        var text = AttributedString("ab")
        text.noteColor = "red"
        text.mergeAttributes(added, mergePolicy: .keepCurrent)
        #expect(text.noteColor == "red" && text.languageIdentifier == "fr")
        text.mergeAttributes(added)
        #expect(text.noteColor == "blue")
        #expect(text.mergingAttributes(current, mergePolicy: .keepCurrent).noteColor == "blue")
        #expect(text.settingAttributes(AttributeContainer()).languageIdentifier == nil)
        #expect(text.languageIdentifier == "fr")
    }

    @Test func attributesAreReplacedWhereARunHasThemAll() throws {
        var blue = AttributeContainer()
        blue.noteColor = "blue"
        var green = AttributeContainer()
        green.noteColor = "green"
        var text = coloured("ab", "blue", language: "fr") + coloured("cd", "red", language: "fr")
        text.replaceAttributes(blue, with: green)
        let ab = text.startIndex..<text.index(text.startIndex, offsetByCharacters: 2)
        #expect(text[ab].noteColor == "green" && text[ab].languageIdentifier == "fr")
        #expect(text[ab.upperBound...].noteColor == "red")

        // On a slice: only the slice's runs change, and the non-mutating forms leave it alone.
        var slice = text[ab.upperBound...]
        var red = AttributeContainer()
        red.noteColor = "red"
        #expect(slice.replacingAttributes(red, with: blue).noteColor == "blue")
        #expect(slice.noteColor == "red")
        slice.setAttributes(blue)
        #expect(slice.noteColor == "blue" && slice.languageIdentifier == nil)
        var whole = text
        whole[ab.upperBound...].setAttributes(blue)
        #expect(whole[ab.upperBound...].languageIdentifier == nil && whole[ab].languageIdentifier == "fr")
        whole[ab.upperBound...].mergeAttributes(red, mergePolicy: .keepCurrent)
        #expect(whole[ab.upperBound...].noteColor == "blue")
        whole[ab].replaceAttributes(green, with: red)
        #expect(whole[ab].noteColor == "red" && whole.runs.count == 2)
    }

    @Test func slicesEqualByContent() {
        let one = coloured("ab", "red") + coloured("ab", "red", language: "fr")
        let first = one[..<one.index(one.startIndex, offsetByCharacters: 2)]
        let red = coloured("ab", "red")
        let again = red[red.startIndex...]
        #expect(first == again && first.hashValue == again.hashValue)
        #expect(first != one[one.index(one.startIndex, offsetByCharacters: 2)...])
    }
}

#if os(WASI)
/// A type of an app's own that conforms, shaped as EmojiText's partial string is: slices kept
/// in a list, read as the string they make and changed slice by slice.
struct PartialAttributedString: AttributedStringProtocol, Sendable {
    @available(iOS 26.0, *)
    var utf8: AttributedString.UTF8View { AttributedString(self).utf8 }
    @available(iOS 26.0, *)
    var utf16: AttributedString.UTF16View { AttributedString(self).utf16 }
    fileprivate var substrings: [AttributedSubstring] = []

    mutating func append(_ substring: AttributedSubstring) { substrings.append(substring) }

    var startIndex: AttributedString.Index { whole.startIndex }
    var endIndex: AttributedString.Index { whole.endIndex }
    var runs: AttributedString.Runs { whole.runs }
    var characters: AttributedString.CharacterView { whole.characters }
    var unicodeScalars: AttributedString.UnicodeScalarView { whole.unicodeScalars }
    var description: String { whole.description }
    private var whole: AttributedString { AttributedString(self) }

    subscript<K>(_ value: K.Type) -> K.Value? where K: AttributedStringKey, K.Value: Sendable {
        get { whole[value] }
        set { substrings = substrings.map { var substring = $0; substring[value] = newValue; return substring } }
    }
    subscript<K>(dynamicMember keyPath: KeyPath<AttributeDynamicLookup, K>) -> K.Value? where K: AttributedStringKey, K.Value: Sendable {
        get { whole[dynamicMember: keyPath] }
        set { substrings = substrings.map { var substring = $0; substring[dynamicMember: keyPath] = newValue; return substring } }
    }
    subscript<S>(dynamicMember keyPath: KeyPath<AttributeScopes, S.Type>) -> ScopedAttributeContainer<S> where S: AttributeScope {
        get { whole[dynamicMember: keyPath] }
        set { substrings = substrings.map { var substring = $0; substring[dynamicMember: keyPath] = newValue; return substring } }
    }
    subscript<R>(bounds: R) -> AttributedSubstring where R: RangeExpression, R.Bound == AttributedString.Index {
        whole[bounds]
    }
    mutating func setAttributes(_ attributes: AttributeContainer) {
        substrings = substrings.map { var substring = $0; substring.setAttributes(attributes); return substring }
    }
    mutating func mergeAttributes(_ attributes: AttributeContainer, mergePolicy: AttributedString.AttributeMergePolicy) {
        substrings = substrings.map { var substring = $0; substring.mergeAttributes(attributes, mergePolicy: mergePolicy); return substring }
    }
    mutating func replaceAttributes(_ attributes: AttributeContainer, with others: AttributeContainer) {
        substrings = substrings.map { var substring = $0; substring.replaceAttributes(attributes, with: others); return substring }
    }
}

private extension AttributedString {
    init(_ value: PartialAttributedString) {
        self = value.substrings.reduce(AttributedString()) { partialResult, substring in partialResult + substring }
    }
}

@Suite struct WasmAttributedStringConformanceTests {
    @Test func aTypeOfAnAppsOwnConforms() {
        var red = AttributedString("Hi ")
        red.noteColor = "red"
        let emoji = AttributedString(":wave:")
        var partial = PartialAttributedString()
        partial.append(red[red.startIndex...])
        partial.append(emoji[emoji.startIndex...])
        #expect(plainCharacters(partial) == "Hi :wave:" && partial.runs.count == 2)
        #expect(partial.noteColor == nil)
        partial.noteColor = "blue"
        #expect(partial.noteColor == "blue" && AttributedString(partial).runs.count == 1)
        #expect(partial.utf8.count == 9 && partial.utf16.count == 9 && partial.settingAttributes(AttributeContainer()).noteColor == nil)
        var languages = AttributeContainer()
        languages.languageIdentifier = "en"
        partial.mergeAttributes(languages, mergePolicy: .keepNew)
        #expect(AttributedString("Say ") + partial == AttributedString("Say ") + AttributedString(partial))
        #expect((AttributedString("Say ") + partial).languageIdentifier == nil)
        #expect(partial.languageIdentifier == "en" && partial.notes.noteColor == "blue")
    }

    @Test func aDictionarysFoundationAttributes() {
        let container = AttributeContainer([NSAttributedString.Key("NSLanguage"): "fr", NSAttributedString.Key("test.noteColor"): "red"])
        #expect(container.languageIdentifier == "fr" && container.noteColor == nil)
    }
}
#endif
