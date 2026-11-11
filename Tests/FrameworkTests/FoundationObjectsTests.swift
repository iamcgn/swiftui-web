// Foundation's object forms of its values, which swift-custom-dump and ApolloAPI name with only
// Foundation imported: `NSDictionary` and `NSMutableDictionary`, the classes `as` bridges a
// locale, index path, index set, URL, UUID, URL components, query item, measurement and calendar
// to and back, `NSValue`, `NSExceptionName` and the unfair lock. Run against Foundation on
// macOS and Linux too, so the wasm forms behave as Apple's.
import Testing
import WebFoundation
import WebFoundationFormats
#if os(WASI)
import WebGraphics
#endif

/// swift-custom-dump conforms both `NSSet` and `Set` to one protocol: that compiles only while
/// `NSSet` is a class of its own.
protocol _BothSetForms {}
extension NSSet: _BothSetForms {}
extension Set: _BothSetForms {}

@Suite struct FoundationObjectsTests {
    struct Tag { var name: String }

    @Test func sets() {
        let set = NSSet(array: [1, 2, 2, 3])
        #expect(set.count == 3)
        #expect(set.contains(2) && !set.contains(4))
        #expect(set.member(3) as? Int == 3)
        #expect(Set(set.allObjects.compactMap { $0 as? Int }) == [1, 2, 3])
        #expect(set as? Set<Int> == [1, 2, 3])
        #expect(set as? Set<String> == nil)
        #expect(Set(["a", "b"]) as NSSet == NSSet(array: ["b", "a"]))
        #if os(WASI) || canImport(Darwin)
        // Linux's Foundation has no array literal for NSSet.
        let literal: NSSet = [1, 2]
        #expect(literal.count == 2)
        // A member that isn't Hashable is kept, as Foundation keeps one in its box.
        let tagged: NSSet = [Tag(name: "a"), 1]
        #expect(tagged.count == 2)
        #expect(tagged.allObjects.contains { ($0 as? Tag)?.name == "a" })
        #expect(NSSet(array: [Tag(name: "b")]).count == 1)
        #expect((NSSet(objects: Tag(name: "c")).anyObject() as? Tag)?.name == "c")
        #endif
        var seen = 0
        for case let member as Int in set { seen += member }
        #expect(seen == 6)
    }


    @Test func dictionaries() {
        let dictionary = NSDictionary(dictionary: ["a": 1, "b": "two"])
        #expect(dictionary.count == 2)
        #expect(dictionary.object(forKey: "a") as? Int == 1)
        #expect(dictionary.object(forKey: "missing") == nil)
        #expect(Set(dictionary.allKeys.compactMap { $0 as? String }) == ["a", "b"])
        var seen: [String] = []
        for (key, _) in dictionary { seen.append(key as! String) }
        #expect(seen.sorted() == ["a", "b"])
        // Equal by their entries, so a dictionary is a JSON value ApolloAPI can hash and compare.
        #expect(dictionary == NSDictionary(dictionary: ["a": 1, "b": "two"]))
        #expect(dictionary != NSDictionary(dictionary: ["a": 2, "b": "two"]))
        #expect(AnyHashable(dictionary) == AnyHashable(NSDictionary(dictionary: ["b": "two", "a": 1])))
        #if os(WASI) || canImport(Darwin)
        // Linux's Foundation reports these entries unequal (CI, Nov 10), though Apple's and the wasm forms match.
        let sameEntries = dictionary.isEqual(to: ["a": 1, "b": "two"])
        #expect(sameEntries)
        #endif
    }

    @Test func mutableDictionaries() {
        let dictionary = NSMutableDictionary()
        dictionary["name"] = "Ada"
        dictionary["year"] = 1815
        #expect(dictionary.count == 2)
        #expect(dictionary["name"] as? String == "Ada")
        dictionary.removeObject(forKey: "year")
        #expect(dictionary.count == 1)
        dictionary.addEntries(from: ["field": "maths"])
        #expect(dictionary.object(forKey: "field") as? String == "maths")
        dictionary.removeAllObjects()
        #expect(dictionary.count == 0)
    }

    @Test func valuesBridgeToTheirObjects() {
        let locale = Locale(identifier: "fr_FR") as NSLocale
        #if os(WASI) || canImport(Darwin)
        // Linux's Foundation has no instance `localeIdentifier`.
        #expect(locale.localeIdentifier == "fr_FR")
        #endif
        #expect((locale as Locale).identifier == "fr_FR")

        let path = IndexPath(indexes: [1, 2]) as NSIndexPath
        #expect(path.length == 2)
        #expect(path as IndexPath == IndexPath(indexes: [1, 2]))

        let indexes = IndexSet(integersIn: 1..<4) as NSIndexSet
        #expect(indexes.count == 3)
        #expect(indexes as IndexSet == IndexSet(integersIn: 1..<4))

        let url = NSURL(string: "https://example.com/a/b")!
        #expect((url as URL).host == "example.com")
        #expect(url.absoluteString == "https://example.com/a/b")

        #expect((URL(string: "https://example.com/c")! as NSURL).host == "example.com")

        let text = "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
        #expect((NSUUID(uuidString: text)! as UUID).uuidString == text)
        #expect((UUID(uuidString: text)! as NSUUID).uuidString == text)

        let bytes = Data([1, 2, 3]) as NSData
        #expect(bytes.length == 3)
        #expect(bytes as Data == Data([1, 2, 3]))

        let components = URLComponents(string: "https://example.com/search?q=1")! as NSURLComponents
        #expect((components as URLComponents).queryItems?.first?.value == "1")
        let item = URLQueryItem(name: "q", value: "1") as NSURLQueryItem
        #expect(item.name == "q")
        #expect(item as URLQueryItem == URLQueryItem(name: "q", value: "1"))

        let length = Measurement(value: 3, unit: UnitLength.meters) as NSMeasurement
        #expect(length.doubleValue == 3)
        #expect((length as Measurement<UnitLength>).value == 3)

        let calendar = Calendar(identifier: .gregorian) as NSCalendar
        #expect((calendar as Calendar).identifier == .gregorian)
    }

    @Test func valuesAndExceptionNames() {
        let range = NSValue(range: NSRange(location: 1, length: 2))
        #expect(range.rangeValue.length == 2)
        #expect(!range.debugDescription.isEmpty)
        #if os(WASI) || canImport(Darwin)
        // Linux's Foundation declares the type but none of the standard names.
        #expect(NSExceptionName.invalidArgumentException.rawValue == "NSInvalidArgumentException")
        #endif
        #expect(NSExceptionName("Custom").rawValue == "Custom")
    }

    #if os(WASI) || canImport(Darwin)
    @Test func unfairLock() {
        let lock = os_unfair_lock_t.allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
        defer {
            lock.deinitialize(count: 1)
            lock.deallocate()
        }
        os_unfair_lock_lock(lock)
        #expect(!os_unfair_lock_trylock(lock))
        os_unfair_lock_unlock(lock)
        #expect(os_unfair_lock_trylock(lock))
        os_unfair_lock_unlock(lock)
    }
    #endif
}
