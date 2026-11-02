// `JSONEncoder` and `JSONDecoder` strategies as the wasm stand-ins apply them
// (Packages/WebGraphics/Sources/WebFoundation/JSONCoding.swift over JSONCoder.swift): every
// expected string is Foundation's own output, which these tests check on macOS and Linux.
import Testing
import WebFoundation

private struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

@Suite struct JSONStrategiesTests {
    struct Event: Codable, Equatable {
        var eventName: String
        var startsAt: Date
        var payload: Data
        var link: URL
    }

    struct Stamp: Codable, Equatable { var at: Date }
    struct Blob: Codable, Equatable { var bytes: Data }
    struct Reading: Codable, Equatable { var value: Double; var notes: [String] }
    struct Pair: Codable, Equatable { var left: Int; var right: Int }

    static let moment = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14T22:13:20Z

    private func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

    @Test func snakeCaseISODatesBase64AndURLs() throws {
        let event = Event(eventName: "Launch", startsAt: Self.moment, payload: Data([0, 1, 2, 255]), link: URL(string: "https://example.com/a?b=c")!)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)
        #expect(text(data) == #"{"event_name":"Launch","link":"https:\/\/example.com\/a?b=c","payload":"AAEC\/w==","starts_at":"2023-11-14T22:13:20Z"}"#)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(Event.self, from: data) == event)
    }

    @Test func snakeCaseSplitsWordsAsFoundationDoes() throws {
        struct Keys: Encodable {
            var myURLProperty = 1
            var partCAPSLowerAGAIN = 2
            var dataPoint22Word = 3
            var _oneTwoThree = 4
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.keyEncodingStrategy = .convertToSnakeCase
        #expect(text(try encoder.encode(Keys())) == #"{"_one_two_three":4,"data_point22_word":3,"my_url_property":1,"part_caps_lower_again":2}"#)
    }

    @Test func dateStrategies() throws {
        let stamp = Stamp(at: Self.moment)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        encoder.dateEncodingStrategy = .secondsSince1970
        decoder.dateDecodingStrategy = .secondsSince1970
        #expect(text(try encoder.encode(stamp)) == #"{"at":1700000000}"#)
        #expect(try decoder.decode(Stamp.self, from: try encoder.encode(stamp)) == stamp)

        encoder.dateEncodingStrategy = .millisecondsSince1970
        decoder.dateDecodingStrategy = .millisecondsSince1970
        #expect(text(try encoder.encode(stamp)) == #"{"at":1700000000000}"#)
        #expect(try decoder.decode(Stamp.self, from: try encoder.encode(stamp)) == stamp)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        encoder.dateEncodingStrategy = .formatted(formatter)
        decoder.dateDecodingStrategy = .formatted(formatter)
        #expect(text(try encoder.encode(stamp)) == #"{"at":"2023-11-14"}"#)
        #expect(try decoder.decode(Stamp.self, from: try encoder.encode(stamp)) == Stamp(at: Date(timeIntervalSince1970: 1_699_920_000)))
        #expect(throws: DecodingError.self) { try decoder.decode(Stamp.self, from: Data(#"{"at":"14/11/2023"}"#.utf8)) }

        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode("day \(Int(date.timeIntervalSince1970) / 86400)")
        }
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            return Date(timeIntervalSince1970: Double(text.dropFirst(4))! * 86400)
        }
        #expect(text(try encoder.encode(stamp)) == #"{"at":"day 19675"}"#)
        #expect(try decoder.decode(Stamp.self, from: try encoder.encode(stamp)) == Stamp(at: Date(timeIntervalSince1970: 19675 * 86400)))

        // A custom closure that encodes nothing leaves an empty object.
        encoder.dateEncodingStrategy = .custom { _, _ in }
        #expect(text(try encoder.encode(stamp)) == #"{"at":{}}"#)

        decoder.dateDecodingStrategy = .iso8601
        #expect(throws: DecodingError.self) { try decoder.decode(Stamp.self, from: Data(#"{"at":"yesterday"}"#.utf8)) }
    }

    @Test func dataStrategies() throws {
        let blob = Blob(bytes: Data([1, 2, 3]))
        #expect(text(try JSONEncoder().encode(blob)) == #"{"bytes":"AQID"}"#)
        #expect(try JSONDecoder().decode(Blob.self, from: Data(#"{"bytes":"AQID"}"#.utf8)) == blob)
        #expect(try JSONDecoder().decode(Data.self, from: Data(#""AAEC\/w==""#.utf8)) == Data([0, 1, 2, 255]))
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Blob.self, from: Data(#"{"bytes":"not base64!"}"#.utf8)) }

        let encoder = JSONEncoder()
        encoder.dataEncodingStrategy = .deferredToData
        #expect(text(try encoder.encode(blob)) == #"{"bytes":[1,2,3]}"#)
        let decoder = JSONDecoder()
        decoder.dataDecodingStrategy = .deferredToData
        #expect(try decoder.decode(Blob.self, from: Data(#"{"bytes":[1,2,3]}"#.utf8)) == blob)

        encoder.dataEncodingStrategy = .custom { data, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(data.count)
        }
        decoder.dataDecodingStrategy = .custom { decoder in
            Data(repeating: 7, count: try decoder.singleValueContainer().decode(Int.self))
        }
        #expect(text(try encoder.encode(blob)) == #"{"bytes":3}"#)
        #expect(try decoder.decode(Blob.self, from: Data(#"{"bytes":3}"#.utf8)) == Blob(bytes: Data([7, 7, 7])))
    }

    @Test func customKeysFloatsAndPrettyPrinting() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.keyEncodingStrategy = .custom { path in AnyKey(path.last!.stringValue.uppercased()) }
        #expect(text(try encoder.encode(Pair(left: 1, right: 2))) == #"{"LEFT":1,"RIGHT":2}"#)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .custom { path in AnyKey(path.last!.stringValue.lowercased()) }
        #expect(try decoder.decode(Pair.self, from: Data(#"{"LEFT":1,"RIGHT":2}"#.utf8)) == Pair(left: 1, right: 2))

        #expect(throws: EncodingError.self) { try JSONEncoder().encode([Double.nan]) }
        #expect(text(try JSONEncoder().encode([Float(0.1), 2.5])) == "[0.1,2.5]")

        let pretty = JSONEncoder()
        pretty.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        pretty.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        let reading = Reading(value: .infinity, notes: ["a/b"])
        #expect(text(try pretty.encode(reading)) == "{\n  \"notes\" : [\n    \"a/b\"\n  ],\n  \"value\" : \"inf\"\n}")

        let lenient = JSONDecoder()
        lenient.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        #expect(try lenient.decode(Reading.self, from: Data(#"{"notes":[],"value":"-inf"}"#.utf8)) == Reading(value: -.infinity, notes: []))
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Reading.self, from: Data(#"{"notes":[],"value":"-inf"}"#.utf8)) }
    }

    @Test func userInfoReachesTheValues() throws {
        let key = CodingUserInfoKey(rawValue: "tag")!
        struct Tagged: Codable {
            var tag: String
            init(tag: String) { self.tag = tag }
            init(from decoder: any Decoder) throws { tag = decoder.userInfo[CodingUserInfoKey(rawValue: "tag")!] as? String ?? "none" }
            func encode(to encoder: any Encoder) throws {
                var container = encoder.singleValueContainer()
                try container.encode(encoder.userInfo[CodingUserInfoKey(rawValue: "tag")!] as? String ?? "none")
            }
        }
        let encoder = JSONEncoder()
        encoder.userInfo[key] = "sent"
        #expect(text(try encoder.encode([Tagged(tag: "")])) == #"["sent"]"#)
        let decoder = JSONDecoder()
        decoder.userInfo[key] = "context"
        #expect(try decoder.decode([Tagged].self, from: Data("[1]".utf8)).first?.tag == "context")
    }

    @Test func serializationFormats() throws {
        let object: [String: Any] = ["b": 1, "a": ["x/y", true] as [Any]]
        let pretty = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        #expect(text(pretty) == "{\n  \"a\" : [\n    \"x\\/y\",\n    true\n  ],\n  \"b\" : 1\n}")
        let plain = try JSONSerialization.data(withJSONObject: ["k": "x/y"], options: [.withoutEscapingSlashes])
        #expect(text(plain) == #"{"k":"x/y"}"#)
    }
}
