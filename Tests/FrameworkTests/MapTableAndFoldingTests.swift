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
}
