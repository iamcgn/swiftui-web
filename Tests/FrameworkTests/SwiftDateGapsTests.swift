// What SwiftDate (which Clendar builds from source) asks of Foundation beyond the common API:
// a calendar's unit ranges, the standalone symbols of a date formatter, ordinal numbers, the
// undefined component value, `NSString.substring(to:)`, a locale's collator identifier, and a
// struct holding a formatter staying `Hashable`. The cases run against Foundation on macOS and
// Linux too, which holds WebFoundation's answers to it.
import Testing
import WebFoundation
import WebFoundationFormats

private struct Holder: Hashable {
    var formatter: DateFormatter?
}

@Suite struct SwiftDateGapsTests {
    @Test func unitRangesAreTheGregorianOnes() {
        let calendar = Calendar(identifier: .gregorian)
        #expect(calendar.maximumRange(of: .weekday) == 1..<8)
        #expect(calendar.minimumRange(of: .weekday) == 1..<8)
        #expect(calendar.maximumRange(of: .month) == 1..<13)
        #expect(calendar.minimumRange(of: .day) == 1..<29)
        #expect(calendar.maximumRange(of: .day) == 1..<32)
        #expect(calendar.maximumRange(of: .hour) == 0..<24)
        #expect(calendar.maximumRange(of: .minute) == 0..<60)
        #expect(calendar.maximumRange(of: .quarter) == 1..<5)
    }

    @Test func standaloneSymbolsMatchTheirFormattingOnes() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        #expect(formatter.veryShortStandaloneMonthSymbols.first == "J")
        #expect(formatter.veryShortStandaloneMonthSymbols.count == 12)
        #expect(formatter.veryShortStandaloneWeekdaySymbols == ["S", "M", "T", "W", "T", "F", "S"])
        #expect(formatter.standaloneQuarterSymbols == ["1st quarter", "2nd quarter", "3rd quarter", "4th quarter"])
        #expect(formatter.shortStandaloneQuarterSymbols == ["Q1", "Q2", "Q3", "Q4"])
    }

    @Test func ordinalsTakeEnglishSuffixes() {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .ordinal
        let cases: [(Int, String)] = [(1, "1st"), (2, "2nd"), (3, "3rd"), (4, "4th"), (11, "11th"), (12, "12th"), (13, "13th"),
                                      (21, "21st"), (22, "22nd"), (101, "101st"), (111, "111th"), (1000, "1,000th")]
        for (number, text) in cases {
            #expect(formatter.string(from: NSNumber(value: number)) == text)
        }
        #expect(formatter.string(for: 23) == "23rd")
    }

    @Test func smallFoundationNames() {
        #expect(NSDateComponentUndefined == Int.max)
        #expect(NSString(string: "+0100").substring(to: 1) == "+")
        #expect(Locale(identifier: "en_US").collatorIdentifier != nil)
        #expect(Holder(formatter: nil) == Holder(formatter: nil))
        let formatter = DateFormatter()
        #expect(Holder(formatter: formatter) == Holder(formatter: formatter))
        #expect(Holder(formatter: formatter) != Holder(formatter: DateFormatter()))
    }
}
