// Small Foundation and CoreGraphics members the sweep's packages reach for: `IndexSet`'s runs
// (swift-identified-collections), `CGRect.divided(atDistance:from:)`, the rarer `CharacterSet`
// sets and `NSString.replacingCharacters(in:with:)` (SwiftyFORM). The cases run against
// Foundation and CoreGraphics on macOS and Linux too.
import Testing
import WebGraphics
import WebFoundation
import WebFoundationFormats

@Suite struct SmallGapsTests {
    @Test func indexSetRuns() {
        let set: IndexSet = [1, 2, 3, 7, 9, 10]
        #expect(Array(set.rangeView) == [1..<4, 7..<8, 9..<11])
        #expect(set.rangeView.first == 1..<4 && set.rangeView.last == 9..<11)
        #expect(Array(set.rangeView.dropFirst()) == [7..<8, 9..<11])
        #expect(Array(set.rangeView(of: 2..<10)) == [2..<4, 7..<8, 9..<10])
        #expect(IndexSet().rangeView.isEmpty)
    }

    @Test func dividingARectangle() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 50)
        let left = rect.divided(atDistance: 30, from: .minXEdge)
        #expect(left.slice == CGRect(x: 0, y: 0, width: 30, height: 50) && left.remainder == CGRect(x: 30, y: 0, width: 70, height: 50))
        let right = rect.divided(atDistance: 30, from: .maxXEdge)
        #expect(right.slice == CGRect(x: 70, y: 0, width: 30, height: 50) && right.remainder == CGRect(x: 0, y: 0, width: 70, height: 50))
        let top = rect.divided(atDistance: 20, from: .minYEdge)
        #expect(top.slice == CGRect(x: 0, y: 0, width: 100, height: 20) && top.remainder == CGRect(x: 0, y: 20, width: 100, height: 30))
        let bottom = rect.divided(atDistance: 20, from: .maxYEdge)
        #expect(bottom.slice == CGRect(x: 0, y: 30, width: 100, height: 20) && bottom.remainder == CGRect(x: 0, y: 0, width: 100, height: 30))
        let all = rect.divided(atDistance: 200, from: .minXEdge)
        #expect(all.slice == rect && all.remainder.isEmpty)
    }

    @Test func rarerCharacterSets() {
        #expect(CharacterSet.capitalizedLetters.contains("\u{01C5}") && !CharacterSet.capitalizedLetters.contains("A"))
        #expect(CharacterSet.nonBaseCharacters.contains("\u{0301}") && !CharacterSet.nonBaseCharacters.contains("a"))
        #expect(CharacterSet.decomposables.contains("\u{E9}") && !CharacterSet.decomposables.contains("e"))
        #expect(CharacterSet.illegalCharacters.contains("\u{FFFF}") && !CharacterSet.illegalCharacters.contains("a"))
    }

    @Test func replacingAUTF16Range() {
        #expect(NSString(string: "abc").replacingCharacters(in: NSRange(location: 1, length: 1), with: "XY") == "aXYc")
        #expect(NSString(string: "h\u{E9}llo \u{1F44B}").replacingCharacters(in: NSRange(location: 6, length: 2), with: "\u{1F30D}") == "h\u{E9}llo \u{1F30D}")
        #expect(NSString(string: "abc").replacingCharacters(in: NSRange(location: 3, length: 0), with: "d") == "abcd")
    }
}
