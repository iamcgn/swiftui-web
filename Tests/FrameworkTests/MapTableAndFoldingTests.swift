// `NSMapTable` and `String.folding(options:locale:)` as the wasm stand-ins give them
// (Packages/WebGraphics/Sources/WebFoundation/MapTable.swift and StringCompare.swift): the same
// answers as Foundation's own on macOS, and folding's on Linux too. Mlem keeps sibling value
// synthesizers in a weak-to-weak table and files communities under their unaccented first letter.
import Testing
import WebFoundation

private final class Token: NSObject {
    let id: Int
    init(_ id: Int) { self.id = id }
    override func isEqual(_ object: Any?) -> Bool { (object as? Token)?.id == id }
    override var hash: Int { id }
}

#if canImport(Darwin)
// Foundation's `dictionaryRepresentation()` copies each key into an `NSDictionary`, so keys
// must be copyable there, as `NSUUID` and `NSString` keys are.
extension Token: NSCopying {
    func copy(with zone: NSZone? = nil) -> Any { self }
}
#endif

private final class Box: NSObject {
    let value: String
    init(_ value: String) { self.value = value }
}

@Suite struct MapTableAndFoldingTests {
    @Test func folding() {
        #expect("Élan".folding(options: .diacriticInsensitive, locale: .current) == "Elan")
        #expect("Ångström".folding(options: .diacriticInsensitive, locale: nil) == "Angstrom")
        #expect("ÀBc".folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) == "abc")
        #expect("Café".folding(options: .caseInsensitive, locale: nil) == "café")
        #expect("Café".folding(locale: nil) == "Café")
    }

    #if os(WASI) || canImport(Darwin)
    @Test func foldingWidthAndTurkish() {
        #expect("ａ".folding(options: .widthInsensitive, locale: nil) == "a")
        #expect("ＡＢＣ１".folding(options: .widthInsensitive, locale: nil) == "ABC1")
        #expect("Ａ".folding(options: [.widthInsensitive, .caseInsensitive], locale: nil) == "a")
        #expect("I".folding(options: .caseInsensitive, locale: Locale(identifier: "tr_TR")) == "\u{131}")
        #expect("\u{130}".folding(options: .caseInsensitive, locale: Locale(identifier: "tr")) == "i")
        #expect("I".folding(options: .caseInsensitive, locale: Locale(identifier: "en_US")) == "i")
        #expect("I".folding(options: .diacriticInsensitive, locale: Locale(identifier: "tr_TR")) == "I")
    }
    #endif

    #if os(WASI)
    @Test func foldingHalfwidthKana() {
        #expect("ｶﾞｷﾞ".folding(options: .widthInsensitive, locale: nil) == "ガギ")
        #expect("ｱｲｳ".folding(options: .widthInsensitive, locale: nil) == "アイウ")
        #expect("ｶﾞ".compare("ガ", options: .widthInsensitive) == .orderedSame)
    }
    #endif

    #if os(WASI) || canImport(Darwin)
    @Test func strongTable() {
        let table = NSMapTable<Token, Box>.strongToStrongObjects()
        table.setObject(Box("one"), forKey: Token(1))
        table.setObject(Box("two"), forKey: Token(2))
        // Keys compare by `isEqual`, so an equal key finds and replaces the entry.
        #expect(table.object(forKey: Token(1))?.value == "one")
        table.setObject(Box("uno"), forKey: Token(1))
        #expect(table.object(forKey: Token(1))?.value == "uno")
        #expect(table.count == 2)
        #expect(Set(table.dictionaryRepresentation().values.map(\.value)) == ["uno", "two"])
        table.removeObject(forKey: Token(2))
        #expect(table.object(forKey: Token(2)) == nil)
        #expect(table.count == 1)
        table.setObject(Box("three"), forKey: Token(3))
        table.removeAllObjects()
        #expect(table.object(forKey: Token(3)) == nil)
        #expect(table.object(forKey: nil) == nil)
    }

    @Test func pointerPersonality() {
        let table = NSMapTable<Token, Box>(keyOptions: [.strongMemory, .objectPointerPersonality], valueOptions: .strongMemory)
        let key = Token(7)
        table.setObject(Box("seven"), forKey: key)
        #expect(table.object(forKey: key)?.value == "seven")
        // An equal but distinct key is another key under the pointer personality.
        #expect(table.object(forKey: Token(7)) == nil)
    }
    #endif

    #if os(WASI)
    @Test func weakEntriesGo() {
        let table = NSMapTable<Token, Box>.weakToWeakObjects()
        let key = Token(1)
        do {
            let value = Box("short-lived")
            table.setObject(value, forKey: key)
            #expect(table.object(forKey: key)?.value == "short-lived")
        }
        // The value is freed with its last strong reference, and its entry with it.
        #expect(table.object(forKey: key) == nil)
        #expect(table.count == 0)

        let value = Box("kept")
        do {
            table.setObject(value, forKey: Token(2))
        }
        #expect(table.count == 0)
        #expect(table.dictionaryRepresentation().isEmpty)

        let strongValues = NSMapTable<Token, Box>.weakToStrongObjects()
        strongValues.setObject(Box("held"), forKey: key)
        #expect(strongValues.object(forKey: key)?.value == "held")
        #expect(strongValues.count == 1)
    }
    #endif

    // OscarWeather keeps each live layer state in `NSHashTable.weakObjects()`.
    #if os(WASI) || canImport(Darwin)
    @Test func hashTablesHoldMembersOnceAndWeakOnesGo() {
        let table = NSHashTable<Token>()
        let one = Token(1)
        table.add(one)
        table.add(Token(1))   // equal to a member: the member stays
        table.add(Token(2))
        #expect(table.count == 2)
        #expect(table.member(Token(1)) === one)
        #expect(table.contains(Token(2)))
        table.remove(Token(2))
        #expect(table.allObjects.map(\.id) == [1])

        let weak = NSHashTable<Box>.weakObjects()
        let kept = Box("kept")
        weak.add(kept)
        #if os(WASI)
        do {
            weak.add(Box("short-lived"))
        }
        // Freed with its last strong reference (Foundation's may keep it until its pool drains).
        #expect(weak.count == 1)
        #endif
        #expect(weak.allObjects.map(\.value) == ["kept"])
        weak.removeAllObjects()
        #expect(weak.anyObject == nil)
    }
    #endif
}
