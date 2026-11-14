// The Foundation members IceCubes' packages (SwiftSoup, swift-markdown, keychain-swift) reach
// for on wasm: string comparison and normalization, `Data`'s settable count, JSON5, and, on
// wasm, `NSMutableData` bridged to `Data`, the locale's code lists and `NSCopying`. The shared
// cases run against Foundation on macOS and Linux too.
import Testing
import WebFoundation
import WebFoundationFormats

@Suite struct FoundationGapsTests {
    @Test func comparisons() {
        #expect("abc".caseInsensitiveCompare("ABD") == .orderedAscending)
        #expect("Hello".caseInsensitiveCompare("hELLO") == .orderedSame)
        #expect("B".compare("a") == .orderedAscending)
        #expect("x9".compare("x10", options: .numeric) == .orderedAscending)
        #expect("x9".compare("x10") == .orderedDescending)
        #expect("café".compare("cafe", options: .diacriticInsensitive) == .orderedSame)
        #expect("e\u{301}".compare("é") == .orderedSame)
        #expect("e\u{301}".compare("é", options: .literal) != .orderedSame)
    }

    @Test func normalizationAndReplacing() {
        #expect("e\u{301}".precomposedStringWithCanonicalMapping.unicodeScalars.count == 1)
        #expect("é".decomposedStringWithCanonicalMapping.unicodeScalars.count == 2)
        let text = "hello world"
        let range = text.range(of: "world")!
        #expect(text.replacingCharacters(in: range, with: "there") == "hello there")
        #expect("a,b;;c".components(separatedBy: CharacterSet(charactersIn: ",;")) == ["a", "b", "", "c"])
    }

    @Test func settableDataCount() {
        var data = Data([1, 2, 3])
        data.count = 1
        #expect(Array(data) == [1])
        data.count = 3
        #expect(Array(data) == [1, 0, 0])
        #expect(Data(count: 2).count == 2)
    }

    @Test func json5() throws {
        struct Settings: Decodable, Equatable { var name: String; var size: Int; var ratio: Double; var tags: [String] }
        let text = """
        // settings
        { name: 'Ice Cubes', size: 0x10, /* inline */ ratio: .5, tags: ["a", 'b',], }
        """
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        let settings = try decoder.decode(Settings.self, from: Data(text.utf8))
        #expect(settings == Settings(name: "Ice Cubes", size: 16, ratio: 0.5, tags: ["a", "b"]))
        #expect(throws: (any Error).self) { try JSONDecoder().decode(Settings.self, from: Data(text.utf8)) }
    }

    #if os(WASI)
    @Test func localizedOrder() {
        #expect("a".localizedCompare("B") == .orderedAscending)
        #expect("a".localizedCompare("A") == .orderedAscending)
        #expect("é".localizedCompare("f") == .orderedAscending)
        #expect("File 2".localizedStandardCompare("File 10") == .orderedAscending)
        #expect("ß".caseInsensitiveCompare("SS") == .orderedSame)
    }

    @Test func mutableDataBridgesToData() {
        let body = NSMutableData()
        body.append(Data("--b\r\n".utf8))
        body.append(Data([0x41]))
        #expect(body.length == 6)
        let data = body as Data
        #expect(String(data: data, encoding: .utf8) == "--b\r\nA")
        #expect((data as NSData).isEqual(to: data))
        #expect((body.copy() as? NSData)?.length == 6)
    }

    @Test func stringsFromBytes() {
        let bytes: ArraySlice<UInt8> = [0x68, 0x69][...]
        #expect(String(bytes: bytes, encoding: .utf8) != nil)
        #expect(String(bytes: [0xFF, 0xFE], encoding: .ascii) == nil)
        let data: Data? = "hi".data(using: .utf8)
        #expect(data.map(Array.init) == [0x68, 0x69])
    }

    @Test func localeCodes() {
        #expect(Locale.LanguageCode.isoLanguageCodes.contains(Locale.LanguageCode("fr")))
        #expect(Locale.isoRegionCodes.contains("US"))
        #expect(Locale(languageComponents: Locale.Language.Components(languageCode: "zh", script: "Hans", region: "CN")).identifier == "zh-Hans_CN")
        let saved = Locale._hostDisplayName
        defer { Locale._hostDisplayName = saved }
        Locale._hostDisplayName = { locale, type, code in locale == "fr" && type == "language" && code == "fr" ? "français" : nil }
        #expect(Locale(identifier: "fr").localizedString(forLanguageCode: "fr") == "français")
        #expect(Locale(identifier: "fr").localizedString(forRegionCode: "FR") == nil)
    }

    @Test func copying() {
        final class Box: NSCopying {
            let value: Int
            init(_ value: Int) { self.value = value }
            func copy(with zone: NSZone? = nil) -> Any { Box(value) }
        }
        #expect((Box(3).copy(with: nil) as? Box)?.value == 3)
    }
    #endif
}

extension FoundationGapsTests {
    @Test func localizedCase() {
        #expect("hello wORLD, it's here".localizedCapitalized == "Hello World, It's Here")
        #expect("Ab".localizedLowercase == "ab")
        #expect("Ab".localizedUppercase == "AB")
    }

    #if os(WASI) || canImport(Darwin)
    /// `NotificationCenter.notifications(named:)`: the posts after the sequence is made, in order
    /// (CloudKitSyncMonitor reads the container's sync events this way).
    @Test func notificationsAsAnAsyncSequence() async {
        let center = NotificationCenter()
        let name = Notification.Name("FoundationGapsTests.ping")
        let iterator = center.notifications(named: name).makeAsyncIterator()
        center.post(name: name, object: nil, userInfo: ["n": 1])
        center.post(name: Notification.Name("FoundationGapsTests.other"), object: nil)
        center.post(name: name, object: nil, userInfo: ["n": 2])
        let first = await iterator.next()
        let second = await iterator.next()
        #expect(first?.userInfo?["n"] as? Int == 1)
        #expect(second?.userInfo?["n"] as? Int == 2)
        #expect(second?.name == name)
    }
    #endif
}
