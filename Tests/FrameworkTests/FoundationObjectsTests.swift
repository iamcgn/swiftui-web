// Foundation's object forms of its values, which swift-custom-dump and ApolloAPI name with only
// Foundation imported: `NSDictionary` and `NSMutableDictionary`, the classes `as` bridges a
// locale, index path, index set, URL, UUID, URL components, query item, measurement and calendar
// to and back, `NSValue`, `NSExceptionName` and the unfair lock. Run against Foundation on
// macOS and Linux too, so the wasm forms behave as Apple's.
import Testing
import WebFoundation
import WebFoundationFormats
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
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

    /// CVCalendar's weekday symbols (`symbols as NSArray`, then a Monday-first copy) and
    /// SwiftyFORM's counts of any array it is handed.
    @Test func arrays() {
        let symbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        var weekdays = symbols as NSArray
        #expect(weekdays.count == 7 && weekdays.object(at: 1) as? String == "Mon")
        #expect(weekdays.firstObject as? String == "Sun" && weekdays.lastObject as? String == "Sat")
        #expect(weekdays.contains("Wed") && !weekdays.contains("Caturday"))
        #expect(weekdays.index(of: "Tue") == 2 && weekdays.index(of: "Caturday") == NSNotFound)
        let copy = weekdays
        weekdays = weekdays.subarray(with: NSRange(location: 1, length: 6)) as NSArray
        weekdays = weekdays.addingObjects(from: copy.subarray(with: NSRange(location: 0, length: 1))) as NSArray
        #expect(weekdays as! [String] == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        #expect(weekdays as? [Int] == nil)
        #expect(weekdays.componentsJoined(by: ",") == "Mon,Tue,Wed,Thu,Fri,Sat,Sun")
        var startingWithT = 0
        for case let symbol as String in weekdays where symbol.hasPrefix("T") { startingWithT += 1 }
        #expect(startingWithT == 2)
        #expect(NSArray(array: [1, 2]).adding(3).count == 3)
        // Linux's corelibs takes only class instances here, so this is the browser's and Apple's form.
        #if os(WASI) || canImport(Darwin)
        let handed: Any = NSArray(objects: "a", "b")
        #expect((handed as? NSArray)?.count == 2)
        // Separate arrays with equal nested arrays are equal, by value.
        let nested = NSArray(array: [NSArray(array: [1, "x"]), 2])
        let same = NSArray(array: [NSArray(array: [1, "x"]), 2])
        #expect(nested.isEqual(same))
        #expect(nested.isEqual(to: [NSArray(array: [1, "x"]), 2]))
        #expect(NSArray(array: [nested]).contains(same))
        #expect(NSArray(array: [nested]).index(of: same) == 0)
        #expect(!nested.isEqual(NSArray(array: [NSArray(array: [1, "y"]), 2])))
        #endif
    }

    /// `(calendar as NSCalendar)` date math as CVCalendar reads its months and weeks.
    @Test func calendarMath() throws {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        gregorian.firstWeekday = 1
        let calendar = gregorian as NSCalendar
        // Sunday 15 November 2026, midnight UTC: the month starts on a Sunday and has five weeks.
        let date = Date(timeIntervalSince1970: 1_794_700_800)
        let parts = calendar.components([.year, .month, .day, .weekday], from: date)
        #expect(parts.year == 2026 && parts.month == 11 && parts.day == 15 && parts.weekday == 1)
        #expect(calendar.component(.weekday, from: date) == 1 && calendar.firstWeekday == 1)
        let weeks = calendar.range(of: .weekOfMonth, in: .month, for: date)
        #expect(weeks.location == 1 && weeks.length == 5)
        let days = calendar.range(of: .day, in: .month, for: date)
        #expect(days.location == 1 && days.length == 30)
        let later = try #require(calendar.date(byAdding: .day, value: 20, to: date, options: []))
        #expect(calendar.components(.day, from: later).day == 5)
        #expect(calendar.components(.day, from: date, to: later, options: []).day == 20)
        let nextMonth = try #require(calendar.date(byAdding: DateComponents(month: 1), to: date, options: []))
        #expect(calendar.component(.month, from: nextMonth) == 12)
        #expect(calendar.date(from: DateComponents(year: 2026, month: 11, day: 15)) == date)
        #expect(calendar.isDate(date, inSameDayAs: date.addingTimeInterval(3600)))
        #expect(calendar.startOfDay(for: date.addingTimeInterval(3600)) == date)
        #expect(calendar.ordinality(of: .day, in: .year, for: date) == 319)
        #expect(calendar.isDateInWeekend(date))
    }

    /// SwiftyStoreKit's receipt request: a mutable request with a JSON body from a mutable
    /// dictionary, handed to URLSession `as URLRequest`.
    @Test func mutableRequestsAndJSONBodies() throws {
        let request = NSMutableURLRequest(url: try #require(URL(string: "https://buy.itunes.apple.com/verifyReceipt")))
        #expect(request.httpMethod == "GET")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        #if os(WASI) || canImport(Darwin)
        // Linux's Foundation has neither the literal nor key-value coding for dictionaries.
        let contents: NSMutableDictionary = ["receipt-data": "MIIT"]
        contents.setValue("secret", forKey: "password")
        contents.setValue(nil, forKey: "missing")
        #expect(contents.count == 2 && contents.value(forKey: "password") as? String == "secret")
        request.httpBody = try JSONSerialization.data(withJSONObject: contents, options: [.sortedKeys])
        #expect(request.httpBody.map { String(decoding: $0, as: UTF8.self) } == #"{"password":"secret","receipt-data":"MIIT"}"#)
        #endif
        let plain = request as URLRequest
        #expect(plain.httpMethod == "POST" && plain.value(forHTTPHeaderField: "content-type") == "application/json")
        #expect(plain.timeoutInterval == 30 && plain.httpBody == request.httpBody)
        #expect((plain as NSURLRequest).url?.host == "buy.itunes.apple.com")
        // The value is a copy: changing the object afterwards leaves it as it was.
        request.httpMethod = "PUT"
        #expect(plain.httpMethod == "POST")

        let list = try JSONSerialization.data(withJSONObject: NSArray(array: ["a", 1]))
        #expect(String(decoding: list, as: UTF8.self) == #"["a",1]"#)
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
        // From and to its 16 bytes (RevenueCat reads a UUID out of `Data` this way).
        let uuidBytes: [UInt8] = Array(0..<16)
        let fromBytes = uuidBytes.withUnsafeBufferPointer { NSUUID(uuidBytes: $0.baseAddress!) }
        #expect(fromBytes.uuidString == "00010203-0405-0607-0809-0A0B0C0D0E0F")
        var copied = [UInt8](repeating: 0, count: 16)
        copied.withUnsafeMutableBufferPointer { fromBytes.getBytes($0.baseAddress!) }
        #expect(copied == uuidBytes)

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
