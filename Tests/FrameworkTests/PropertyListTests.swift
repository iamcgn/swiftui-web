// Property lists: `PropertyListSerialization` in both formats and the `Codable` coders. Run
// against Foundation on macOS and Linux too, so the wasm forms read and write what Apple's do;
// the exact bytes are Python's plistlib's, which writes a binary plist the way CF does.
import Testing
import WebFoundation

@Suite struct PropertyListTests {
    let sample: [String: Any] = ["name": "Ada", "year": 1815, "ratio": 1.5, "ok": true, "tags": ["a", "é"], "blob": Data([1, 2, 3])]

    /// plistlib.dumps(sample, fmt=FMT_BINARY)
    let sampleBinary: [UInt8] = [
        0x62, 0x70, 0x6c, 0x69, 0x73, 0x74, 0x30, 0x30, 0xd6, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b,
        0x0e, 0x54, 0x62, 0x6c, 0x6f, 0x62, 0x54, 0x6e, 0x61, 0x6d, 0x65, 0x52, 0x6f, 0x6b, 0x55, 0x72, 0x61, 0x74, 0x69, 0x6f,
        0x54, 0x74, 0x61, 0x67, 0x73, 0x54, 0x79, 0x65, 0x61, 0x72, 0x43, 0x01, 0x02, 0x03, 0x53, 0x41, 0x64, 0x61, 0x09, 0x23,
        0x3f, 0xf8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xa2, 0x0c, 0x0d, 0x51, 0x61, 0x61, 0x00, 0xe9, 0x11, 0x07, 0x17, 0x08,
        0x15, 0x1a, 0x1f, 0x22, 0x28, 0x2d, 0x32, 0x36, 0x3a, 0x3b, 0x44, 0x47, 0x49, 0x4c, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0f, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x4f,
    ]

    func checkSample(_ object: Any) {
        let dictionary = object as? [String: Any]
        #expect(dictionary?["name"] as? String == "Ada")
        #expect(dictionary?["year"] as? Int == 1815)
        #expect(dictionary?["ratio"] as? Double == 1.5)
        #expect(dictionary?["ok"] as? Bool == true)
        #expect(dictionary?["tags"] as? [String] == ["a", "é"])
        #expect(dictionary?["blob"] as? Data == Data([1, 2, 3]))
    }

    @Test func readsBinary() throws {
        var format = PropertyListSerialization.PropertyListFormat.xml
        let object = try PropertyListSerialization.propertyList(from: Data(sampleBinary), options: [], format: &format)
        #expect(format == .binary)
        checkSample(object)
    }

    @Test func writesBinary() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: sample, format: .binary, options: 0)
        #expect(data.starts(with: Array("bplist00".utf8)))
        checkSample(try PropertyListSerialization.propertyList(from: data, options: [], format: nil))
        #if os(WASI)
        #expect(Array(data) == sampleBinary)
        #endif
    }

    @Test func xml() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: ["name": "Ada & Co", "n": [1, 2]], format: .xml, options: 0)
        let expected = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>n</key>
        \t<array>
        \t\t<integer>1</integer>
        \t\t<integer>2</integer>
        \t</array>
        \t<key>name</key>
        \t<string>Ada &amp; Co</string>
        </dict>
        </plist>

        """
        #if os(WASI) || canImport(Darwin)
        #expect(String(decoding: data, as: UTF8.self) == expected)
        #endif
        var format = PropertyListSerialization.PropertyListFormat.binary
        let object = try PropertyListSerialization.propertyList(from: Data(expected.utf8), options: [], format: &format)
        #expect(format == .xml)
        let dictionary = object as? [String: Any]
        #expect(dictionary?["name"] as? String == "Ada & Co")
        #expect(dictionary?["n"] as? [Int] == [1, 2])
        _ = data
    }

    @Test func readsHandWrittenXML() throws {
        let text = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!-- A pod's acknowledgements -->
        <plist version="1.0">
        <dict>
            <key>PreferenceSpecifiers</key>
            <array>
                <dict>
                    <key>Title</key><string>Kingfisher</string>
                    <key>FooterText</key><string>&lt;MIT&gt; &#169; 2019</string>
                    <key>Empty</key><string/>
                    <key>Flag</key><false/>
                    <key>When</key><date>2001-01-01T00:00:00Z</date>
                    <key>Bytes</key><data>
                    AQID
                    </data>
                    <key>Ratio</key><real>-2.5</real>
                </dict>
            </array>
        </dict>
        </plist>
        """
        let object = try PropertyListSerialization.propertyList(from: Data(text.utf8), options: [], format: nil)
        let specifiers = (object as? [String: Any])?["PreferenceSpecifiers"] as? [[String: Any]]
        let first = specifiers?.first
        #expect(first?["Title"] as? String == "Kingfisher")
        #expect(first?["FooterText"] as? String == "<MIT> © 2019")
        #expect(first?["Empty"] as? String == "")
        #expect(first?["Flag"] as? Bool == false)
        #expect(first?["When"] as? Date == Date(timeIntervalSinceReferenceDate: 0))
        #expect(first?["Bytes"] as? Data == Data([1, 2, 3]))
        #expect(first?["Ratio"] as? Double == -2.5)
    }

    @Test func refusesWhatIsNotAPropertyList() {
        #expect(throws: (any Error).self) { _ = try PropertyListSerialization.propertyList(from: Data("<plist><dict><key>a</key></plist>".utf8), options: [], format: nil) }
        #expect(throws: (any Error).self) { _ = try PropertyListSerialization.propertyList(from: Data("<plist><array><string>x".utf8), options: [], format: nil) }
        #if os(WASI)
        // Apple's reads a bare `bplist00` as an OpenStep string; the wasm form reads no OpenStep.
        #expect(throws: (any Error).self) { _ = try PropertyListSerialization.propertyList(from: Data(Array("bplist00".utf8)), options: [], format: nil) }
        #endif
        #expect(PropertyListSerialization.propertyList(["a": 1], isValidFor: .xml))
    }

    struct Settings: Codable, Equatable {
        struct Window: Codable, Equatable { var width: Double; var height: Int }
        var name: String
        var launched: Date
        var token: Data
        var nickname: String?
        var windows: [Window]
        var enabled: Bool
    }

    @Test func codableRoundTrips() throws {
        let settings = Settings(name: "Ada", launched: Date(timeIntervalSinceReferenceDate: 86_400), token: Data([9, 8]),
                                nickname: nil, windows: [Window(width: 320.5, height: 480)], enabled: true)
        for format in [PropertyListSerialization.PropertyListFormat.binary, .xml] {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = format
            let data = try encoder.encode(settings)
            var found = PropertyListSerialization.PropertyListFormat.openStep
            #expect(try PropertyListDecoder().decode(Settings.self, from: data, format: &found) == settings)
            #expect(found == format)
            // The date and data are the plist's own, as any reader sees them.
            let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
            #expect(object?["launched"] as? Date == settings.launched)
            #expect(object?["token"] as? Data == settings.token)
            #expect(object?["nickname"] == nil)
        }
        #expect(PropertyListEncoder().outputFormat == .binary)
    }

    @Test func emptyCollectionsRoundTrip() throws {
        struct Scores: Codable, Equatable { var points: [Int]; var names: [String: String] }
        let empty = Scores(points: [], names: [:])
        for format in [PropertyListSerialization.PropertyListFormat.binary, .xml] {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = format
            #expect(try PropertyListDecoder().decode([Int].self, from: encoder.encode([Int]())) == [])
            #expect(try PropertyListDecoder().decode(Scores.self, from: encoder.encode(empty)) == empty)
            let object = try PropertyListSerialization.propertyList(from: encoder.encode(empty), options: [], format: nil) as? [String: Any]
            #expect((object?["points"] as? [Any])?.isEmpty == true)
        }
    }

    #if os(WASI)
    /// A binary list of one object, with the trailer's values as given.
    func binary(_ object: [UInt8], count: UInt64 = 1, top: UInt64 = 0, table: UInt64? = nil) -> Data {
        var bytes = Array("bplist00".utf8) + object
        let tableOffset = UInt64(bytes.count)
        bytes.append(8)
        bytes += [0, 0, 0, 0, 0, 0, 1, 1]
        for value in [count, top, table ?? tableOffset] {
            for shift in stride(from: 56, through: 0, by: -8) { bytes.append(UInt8(truncatingIfNeeded: value >> UInt64(shift))) }
        }
        return Data(bytes)
    }

    @Test func refusesMalformedBinaryWithoutTrapping() throws {
        #expect(try PropertyListSerialization.propertyList(from: binary([0x08]), options: [], format: nil) as? Bool == false)
        let huge = [UInt8](repeating: 0xFF, count: 8)
        for data in [binary([0x08], count: .max), binary([0x08], top: .max), binary([0x08], table: .max),
                     binary([0xAF, 0x13] + huge), binary([0x5F, 0x13] + huge), binary([0x4F, 0x13] + huge), binary([0xDF, 0x13] + huge)] {
            #expect(throws: (any Error).self) { _ = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) }
        }
    }
    #endif

    typealias Window = Settings.Window
}
