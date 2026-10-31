// The everyday API batch's Foundation fills on wasm (Docs/coverage.md): `Scanner`, `NSNumber`,
// `Calendar.dateInterval(of:for:)`, `String(localized:)` with `LocalizedStringResource`, and
// `NSUbiquitousKeyValueStore` over its own defaults suite.
#if os(WASI)
import Testing
import WebFoundation

@Suite(.serialized) struct WasmEverydayFoundationTests {
    @Test func scannerReadsNumbersAndStrings() {
        let hex = Scanner(string: "#FF8000")
        _ = hex.scanString("#")
        var rgb: UInt64 = 0
        #expect(hex.scanHexInt64(&rgb) && rgb == 0xFF8000 && hex.isAtEnd)

        let mixed = Scanner(string: "  width = 12.5px, count -3")
        #expect(mixed.scanUpToString("=") == "width " && mixed.scanString("=") == "=")
        #expect(mixed.scanDouble() == 12.5 && mixed.scanString("PX") == "px")
        #expect(mixed.scanCharacters(from: CharacterSet(charactersIn: ",")) == ",")
        #expect(mixed.scanUpToCharacters(from: .whitespaces) == "count" && mixed.scanInt() == -3 && mixed.isAtEnd)

        let failing = Scanner(string: "abc")
        #expect(failing.scanInt() == nil && failing.currentIndex == failing.string.startIndex)
        #expect(Scanner(string: "0x1f").scanUInt64(representation: .hexadecimal) == 31)
    }

    @Test func numbersConvertAndCompare() {
        let integer = NSNumber(value: 42)
        let real = NSNumber(value: 2.75)
        let truth: NSNumber = true
        #expect(integer.doubleValue == 42 && real.intValue == 2 && truth.boolValue && truth.intValue == 1)
        #expect(integer.stringValue == "42" && real.stringValue == "2.75" && NSNumber(value: 3.0).stringValue == "3")
        #expect(NSNumber(value: 42) == NSNumber(value: 42.0) && real < integer && real.compare(integer) == .orderedAscending)
        #expect(Int(truncating: real) == 2 && Double(truncating: integer) == 42)
    }

    @Test func calendarIntervalsCoverTheirUnit() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        calendar.firstWeekday = 1
        let date = Date(timeIntervalSince1970: 1_793_448_000)   // Saturday 2026-10-31 12:00 UTC
        let day = try #require(calendar.dateInterval(of: .day, for: date))
        #expect(day.start == Date(timeIntervalSince1970: 1_793_404_800) && day.duration == 86_400)
        let week = try #require(calendar.dateInterval(of: .weekOfYear, for: date))
        #expect(week.start == Date(timeIntervalSince1970: 1_792_886_400) && week.duration == 7 * 86_400)
        let month = try #require(calendar.dateInterval(of: .month, for: date))
        #expect(month.start == Date(timeIntervalSince1970: 1_790_812_800) && month.duration == 31 * 86_400)
        let quarter = try #require(calendar.dateInterval(of: .quarter, for: date))
        #expect(quarter.start == month.start && quarter.duration == 92 * 86_400)
        var start = Date.distantPast
        var length: TimeInterval = 0
        #expect(calendar.dateInterval(of: .hour, start: &start, interval: &length, for: date) && start == date && length == 3600)
        #expect(calendar.dateInterval(of: .era, for: date) == nil)
    }

    @Test func localizedStringsFallBackToTheirText() {
        #expect(String(localized: "Hello") == "Hello")
        #expect(String(localized: "greeting.key", defaultValue: "Hi there") == "Hi there")
        let resource: LocalizedStringResource = "Settings"
        #expect(String(localized: resource) == "Settings" && resource.key == "Settings")
    }

    @Test func ubiquitousStoreKeepsValues() {
        let store = NSUbiquitousKeyValueStore.default
        store.set("dark", forKey: "theme")
        store.set(true, forKey: "synced")
        store.set(Int64(7), forKey: "launches")
        #expect(store.string(forKey: "theme") == "dark" && store.bool(forKey: "synced") && store.longLong(forKey: "launches") == 7)
        store.removeObject(forKey: "theme")
        #expect(store.string(forKey: "theme") == nil && store.synchronize())
    }
}
#endif
