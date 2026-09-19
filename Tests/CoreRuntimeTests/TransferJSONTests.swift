// The transfer JSON coder behind `CodableRepresentation`: round trips through every container
// kind, and the same JSON Foundation's coders read and write.
import Testing
import Foundation
@testable import SwiftUIWebCore

@Suite struct TransferJSONTests {
    enum Kind: String, Codable { case draft, sent }

    struct Note: Codable, Equatable {
        var title: String
        var count: Int
        var ratio: Double
        var flag: Bool
        var kind: Kind
        var tags: [String]
        var scores: [String: Int]
        var missing: String?
        var nested: [Inner]
        var when: Date
        var bytes: Data
        var big: UInt64
        var small: Int8
        var single: Float
        struct Inner: Codable, Equatable {
            var id: Int
            var pairs: [[Double]]
            var empty: [Int]
            var none: Bool?
        }
    }

    static let sample = Note(title: "quote \" backslash \\ newline \n tab \t emoji 🙂 control \u{1}", count: -42, ratio: 0.125, flag: true, kind: .sent,
                             tags: ["a", "b, c", ""], scores: ["x": 1, "y": 2], missing: nil,
                             nested: [.init(id: 1, pairs: [[1, 2.5], []], empty: [], none: nil), .init(id: 2, pairs: [], empty: [], none: false)],
                             when: Date(timeIntervalSinceReferenceDate: 123456.789), bytes: Data([0, 1, 2, 255]), big: UInt64(Int64.max), small: -7, single: 1.5)

    @Test func roundTrip() throws {
        let data = try _TransferJSONEncoder().encode(Self.sample)
        let decoded = try _TransferJSONDecoder().decode(Note.self, from: data)
        #expect(decoded == Self.sample)
    }

    @Test func foundationReadsOurJSON() throws {
        let data = try _TransferJSONEncoder().encode(Self.sample)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        decoder.dataDecodingStrategy = .deferredToData
        #expect(try decoder.decode(Note.self, from: data) == Self.sample)
    }

    @Test func weReadFoundationJSON() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.dataEncodingStrategy = .deferredToData
        let data = try encoder.encode(Self.sample)
        #expect(try _TransferJSONDecoder().decode(Note.self, from: data) == Self.sample)
    }

    @Test func text() throws {
        struct Point: Codable { var x: Int; var y: Double; var label: String? }
        let data = try _TransferJSONEncoder().encode(Point(x: 3, y: 2.5, label: nil))
        #expect(String(decoding: data, as: UTF8.self) == #"{"x":3,"y":2.5}"#)
        #expect(String(decoding: try _TransferJSONEncoder().encode([1, 2, 3]), as: UTF8.self) == "[1,2,3]")
        #expect(String(decoding: try _TransferJSONEncoder().encode("é\u{2028}"), as: UTF8.self) == "\"é\u{2028}\"")
        let escaped = try _TransferJSONDecoder().decode(String.self, from: Data(#""é🙂\n""#.utf8))
        #expect(escaped == "é🙂\n")
    }

    @Test func superEncoders() throws {
        class Base: Codable { var id = 7 }
        final class Derived: Base {
            var name = "d"
            enum Keys: CodingKey { case name }
            override init() { super.init() }
            required init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: Keys.self)
                name = try container.decode(String.self, forKey: .name)
                try super.init(from: container.superDecoder())
            }
            override func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: Keys.self)
                try container.encode(name, forKey: .name)
                try super.encode(to: container.superEncoder())
            }
        }
        let data = try _TransferJSONEncoder().encode(Derived())
        #expect(String(decoding: data, as: UTF8.self) == #"{"name":"d","super":{"id":7}}"#)
        let decoded = try _TransferJSONDecoder().decode(Derived.self, from: data)
        #expect(decoded.id == 7 && decoded.name == "d")
    }

    @Test func errors() throws {
        struct Point: Codable { var x: Int }
        #expect(throws: DecodingError.self) { try _TransferJSONDecoder().decode(Point.self, from: Data(#"{"x":"no"}"#.utf8)) }
        #expect(throws: DecodingError.self) { try _TransferJSONDecoder().decode(Point.self, from: Data(#"{"y":1}"#.utf8)) }
        #expect(throws: DecodingError.self) { try _TransferJSONDecoder().decode(Point.self, from: Data(#"{"x":1"#.utf8)) }
        #expect(throws: DecodingError.self) { try _TransferJSONDecoder().decode(Int8.self, from: Data("300".utf8)) }
        #expect(throws: EncodingError.self) { try _TransferJSONEncoder().encode([Double.infinity]) }
    }
}
