// `StringProtocol.range(of:options:range:locale:)` as Thunderbird's MIME decoder, OldOS and
// Oscar° call it: a search bounded by a range, backwards, anchored, ignoring case, and on a
// substring, whose ranges index the base string. The same cases run against Foundation on macOS
// and Linux, and against the wasm stand-in.
import Testing
import WebFoundation

@Suite struct StringRangeSearchTests {
    static let text = "a=1&b=2&c=3"

    @Test func searchesWithinARange() throws {
        let text = Self.text
        let first = try #require(text.range(of: "="))
        let second = try #require(text.range(of: "=", range: first.upperBound..<text.endIndex))
        #expect(text.distance(from: text.startIndex, to: second.lowerBound) == 5)
        #expect(text.range(of: "a", range: first.upperBound..<text.endIndex) == nil)
        // A match may not run past the end of the range.
        let shortEnd = text.index(text.startIndex, offsetBy: 4)
        #expect(text.range(of: "&b", range: text.startIndex..<shortEnd) == nil)
    }

    @Test func searchesBackwardsAnchoredAndIgnoringCase() throws {
        let text = Self.text
        let last = try #require(text.range(of: "=", options: .backwards))
        #expect(text.distance(from: text.startIndex, to: last.lowerBound) == 9)
        #expect(text.range(of: "a=", options: .anchored) != nil)
        #expect(text.range(of: "b=", options: .anchored) == nil)
        #expect(text.range(of: "=3", options: [.anchored, .backwards]) != nil)
        #expect(text.range(of: "=2", options: [.anchored, .backwards]) == nil)
        let upper = try #require("Hello World".range(of: "WORLD", options: .caseInsensitive))
        #expect("Hello World"[upper] == "World")
        #expect("Hello".range(of: "") == nil)
    }

    @Test func aSubstringsRangeIndexesItsBase() throws {
        let text = Self.text
        var position = text.startIndex
        var keys: [String] = []
        while let amp = text[position...].range(of: "&") {
            keys.append(String(text[position..<amp.lowerBound]))
            position = amp.upperBound
        }
        keys.append(String(text[position...]))
        #expect(keys == ["a=1", "b=2", "c=3"])
    }
}
