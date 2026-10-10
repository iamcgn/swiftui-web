// pf-web-foundation-gaps: the public wasm stand-ins over their cores: Data slices with their
// indices, string encodings, URLComponents, named time zones answered by a host, the other
// calendars, wrapping addition, the date format styles and DateFormatter.
#if os(WASI)
import Testing
import WebFoundation

@Suite(.serialized) struct WasmFoundationTests {
    @Test func dataSlicesKeepTheirIndices() {
        var data = Data([10, 20, 30, 40, 50])
        let slice = data[1..<4]
        #expect(slice.startIndex == 1 && slice.endIndex == 4 && slice.count == 3 && slice[1] == 20 && slice[3] == 40)
        #expect(Array(slice) == [20, 30, 40] && slice.first == 20 && slice.firstIndex(of: 30) == 2)
        #expect(Data(slice).startIndex == 0 && Data(slice) == Data([20, 30, 40]) && slice == Data([20, 30, 40]))
        #expect(slice.subdata(in: 2..<4) == Data([30, 40]) && slice.subdata(in: 2..<4).startIndex == 0)
        #expect(slice[2..<4].startIndex == 2 && Array(slice[2..<4]) == [30, 40])
        data[1..<3] = Data([21])
        #expect(Array(data) == [10, 21, 40, 50])
        #expect(data.range(of: Data([40, 50])) == 2..<4 && data.range(of: Data([99])) == nil)
        var mutable = slice
        mutable.append(60)
        #expect(mutable.startIndex == 1 && mutable.endIndex == 5 && mutable[4] == 60)
        mutable.replaceSubrange(1..<2, with: [1, 2])
        #expect(Array(mutable) == [1, 2, 30, 40, 60])
    }

    @Test func stringEncodings() {
        let text = "café ü 日本 🙂"
        // `data(using:)` is also FoundationEssentials' (returning its Data): the result's type picks ours.
        let utf8: Data = text.data(using: .utf8)!
        let utf16: Data = text.data(using: .utf16)!
        let utf16BE: Data = text.data(using: .utf16BigEndian)!
        let utf32: Data = text.data(using: .utf32)!
        #expect(String(data: utf8, encoding: .utf8) == text && String(data: utf16, encoding: .utf16) == text)
        #expect(String(data: utf16BE, encoding: .utf16BigEndian) == text && String(data: utf32, encoding: .utf32) == text)
        let ascii: Data? = text.data(using: .ascii), latin: Data? = text.data(using: .isoLatin1), shiftJIS: Data? = text.data(using: .shiftJIS)
        #expect(ascii == nil && latin == nil && shiftJIS == nil)
        let lossy: Data = text.data(using: .ascii, allowLossyConversion: true)!
        #expect(String(decoding: lossy, as: UTF8.self) == "caf? ? ?? ?")
        let cafe: Data? = "café".data(using: .isoLatin1), euro: Data? = "€".data(using: .windowsCP1252)
        #expect(cafe?.bytes == [0x63, 0x61, 0x66, 0xE9] && euro?.bytes == [0x80])
        #expect(String(data: Data([0xC3]), encoding: .utf8) == nil && String(data: Data([0x41, 0x42]), encoding: .ascii) == "AB")
        #expect("abc".lengthOfBytes(using: .utf16) == 8 && "abc".cString(using: .utf8) == [97, 98, 99, 0])
        #expect(String(data: Data([0xFF, 0xFE, 0x41, 0x00]), encoding: .utf16) == "A")
    }

    @Test func urlComponentsAndInternationalHosts() throws {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "bücher.example"
        components.path = "/a b/ü"
        components.port = 8080
        components.queryItems = [URLQueryItem(name: "a b", value: "c&d"), URLQueryItem(name: "ü", value: nil), URLQueryItem(name: "q", value: "x?y/z#w")]
        components.fragment = "frag ment"
        #expect(components.string == "https://xn--bcher-kva.example:8080/a%20b/%C3%BC?a%20b=c%26d&%C3%BC&q=x?y/z%23w#frag%20ment")
        #expect(components.url?.host == "xn--bcher-kva.example" && components.percentEncodedHost == "b%C3%BCcher.example" && components.encodedHost == "xn--bcher-kva.example")
        #expect(components.percentEncodedPath == "/a%20b/%C3%BC" && components.query == "a b=c&d&ü&q=x?y/z#w")
        let parsed = try #require(URLComponents(string: "https://user:p%40ss@xn--bcher-kva.example:81/p%20a?x=1&y=a%20b&z&w=#f%20g"))
        #expect(parsed.host == "bücher.example" && parsed.user == "user" && parsed.password == "p@ss" && parsed.port == 81 && parsed.path == "/p a" && parsed.fragment == "f g")
        #expect(parsed.queryItems?.map(\.name) == ["x", "y", "z", "w"] && parsed.queryItems?.map(\.value) == ["1", "a b", nil, ""])
        #expect(URLComponents(string: "not a url")?.string == "not%20a%20url")
        var changed = parsed
        changed.queryItems = nil
        #expect(changed.string == "https://user:p%40ss@xn--bcher-kva.example:81/p%20a#f%20g")
        var noSlash = try #require(URLComponents(string: "https://host"))
        noSlash.path = "noslash"
        #expect(noSlash.string == nil)
        let relative = try #require(URLComponents(string: "/relative/path?q=1"))
        #expect(relative.url(relativeTo: URL(string: "https://base.example/dir/"))?.absoluteString == "https://base.example/relative/path?q=1")
        #expect(URL(string: "https://Bücher.Example/ü")?.absoluteString == "https://xn--bcher-kva.example/%C3%BC")
        #expect(URL(string: "https://例え.テスト/")?.host == "xn--r8jz45g.xn--zckzah")
        #expect(URL(string: "https://h/p?a=1")?.appending(queryItems: [URLQueryItem(name: "b", value: "2")]).absoluteString == "https://h/p?a=1&b=2")
    }

    /// A pretend host: Europe/Berlin with its 2026 transitions, answered like `Intl` would.
    private func withBerlin<R>(_ body: () throws -> R) rethrows -> R {
        let saved = (TimeZone._hostOffset, TimeZone._hostName, TimeZone._hostIdentifier)
        TimeZone._hostOffset = { identifier, time in
            guard identifier == "Europe/Berlin" else { return nil }
            // Summer time between the last Sundays of March and October (the year taken from the
            // mean year length: the transitions are far from January 1).
            let year = 1970 + Int((time / 31_556_952).rounded(.down))
            let (start, end) = _CalendarMathProbe.transitions(year)
            return time >= start && time < end ? 7200 : 3600
        }
        TimeZone._hostName = { identifier, time, style in
            guard identifier == "Europe/Berlin" else { return nil }
            let summer = TimeZone._hostOffset?(identifier, time) == 7200
            switch style {
            case "short": return summer ? "GMT+2" : "GMT+1"
            case "long": return summer ? "Central European Summer Time" : "Central European Standard Time"
            case "shortGeneric": return "Germany Time"
            default: return "Central European Time"
            }
        }
        TimeZone._hostIdentifier = "Europe/Berlin"
        defer { (TimeZone._hostOffset, TimeZone._hostName, TimeZone._hostIdentifier) = saved }
        return try body()
    }

    @Test func namedZonesFollowTheHost() {
        withBerlin {
            let berlin = TimeZone(identifier: "Europe/Berlin")!
            #expect(TimeZone(identifier: "Mars/Olympus") == nil && TimeZone.current.identifier == "Europe/Berlin")
            let winter = Date(timeIntervalSince1970: 1_767_225_600)   // 2026-01-01
            let summer = Date(timeIntervalSince1970: 1_782_000_000)   // 2026-06-21
            #expect(berlin.secondsFromGMT(for: winter) == 3600 && berlin.secondsFromGMT(for: summer) == 7200)
            #expect(!berlin.isDaylightSavingTime(for: winter) && berlin.isDaylightSavingTime(for: summer) && berlin.daylightSavingTimeOffset(for: summer) == 3600)
            #expect(berlin.abbreviation(for: summer) == "GMT+2" && berlin.localizedName(for: .standard, locale: nil) != nil)
            let transition = berlin.nextDaylightSavingTimeTransition(after: winter)
            #expect(transition == Date(timeIntervalSince1970: 1_774_746_000))   // 2026-03-29 01:00Z
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = berlin
            // 2026-03-29 02:30 does not exist: it moves to 03:30 summer time.
            let gap = calendar.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 2, minute: 30))!
            #expect(calendar.component(.hour, from: gap) == 3 && gap.timeIntervalSince1970 == 1_774_746_000 + 1800)
            // Adding a day keeps the wall clock across the change.
            let before = calendar.date(from: DateComponents(year: 2026, month: 3, day: 28, hour: 12))!
            let after = calendar.date(byAdding: .day, value: 1, to: before)!
            #expect(calendar.component(.hour, from: after) == 12 && after.timeIntervalSince(before) == 23 * 3600)
            #expect(TimeZone(identifier: "GMT+2")?.secondsFromGMT == 7200 && TimeZone(identifier: "UTC")?.identifier == "GMT")
        }
    }

    @Test func calendarsAndWrapping() {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = .gmt
        let date = gregorian.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 23))!
        #expect(gregorian.date(byAdding: .hour, value: 2, to: date, wrappingComponents: true) == gregorian.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 1)))
        #expect(gregorian.date(byAdding: .day, value: 1, to: date, wrappingComponents: true) == gregorian.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 23)))
        #expect(gregorian.date(byAdding: .month, value: 12, to: date, wrappingComponents: true) == date)
        var hebrew = Calendar(identifier: .hebrew)
        hebrew.timeZone = .gmt
        let components = hebrew.dateComponents([.era, .year, .month, .day], from: date)
        #expect(components.year == 5786 && components.month == 5 && components.day == 13 && components.era == 0)   // 13 Shevat 5786
        var japanese = Calendar(identifier: .japanese)
        japanese.timeZone = .gmt
        #expect(japanese.component(.year, from: date) == 8 && japanese.component(.era, from: date) == 236)
        var islamic = Calendar(identifier: .islamicCivil)
        islamic.timeZone = .gmt
        #expect(islamic.component(.year, from: date) == 1447 && islamic.range(of: .day, in: .month, for: date)!.count <= 30)
        var persian = Calendar(identifier: .persian)
        persian.timeZone = .gmt
        #expect(persian.dateComponents([.year, .month, .day], from: date).year == 1404)
        #expect(Calendar(identifier: .iso8601).firstWeekday == 2)
    }

    @Test func dateStylesAndFormatter() {
        let gmt = TimeZone.gmt
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = gmt
        let date = Date(timeIntervalSince1970: 1_775_000_000)   // 2026-03-31 23:33:20Z
        let style = Date.FormatStyle(locale: Locale(identifier: "en_US"), calendar: calendar, timeZone: gmt)
        #expect(style.format(date) == "3/31/2026, 11:33\u{202F}PM")
        #expect(date.formatted(style.year().month().day()) == "Mar 31, 2026" && style.month(.wide).day().format(date) == "March 31")
        #expect(style.hour().minute().format(date) == "11:33\u{202F}PM" && style.hour(.defaultDigits(amPM: .omitted)).minute().format(date) == "11:33")
        #expect(Date.FormatStyle(date: .complete, time: .standard, calendar: calendar, timeZone: gmt).format(date) == "Tuesday, March 31, 2026 at 11:33:20\u{202F}PM")
        #expect(Date.FormatStyle(date: .abbreviated, time: .omitted, calendar: calendar, timeZone: gmt).format(date) == "Mar 31, 2026")
        #expect(date.formatted(.iso8601) == "2026-03-31T23:33:20Z" && Date.ISO8601Style().format(date) == "2026-03-31T23:33:20Z")
        #expect(date.formatted(.iso8601.year().month().day()) == "2026-03-31")
        #expect((try? Date("2026-03-31T23:33:20Z", strategy: .iso8601)) == date)
        #expect((try? Date("2026-03-31T23:33:20.500+02:00", strategy: .iso8601)) == Date(timeIntervalSince1970: 1_775_000_000 - 7200 + 0.5))
        #expect((try? style.year().month().day().parseStrategy.parse("Mar 31, 2026")) == Date(timeIntervalSince1970: 1_774_915_200))
        let verbatim = Date.VerbatimFormatStyle(format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) at \(hour: .twoDigits(amPM: .omitted)):\(minute: .twoDigits)", timeZone: gmt, calendar: calendar)
        #expect(verbatim.format(date) == "2026-03-31 at 11:33")
        var relative = Date.RelativeFormatStyle(presentation: .named, unitsStyle: .wide, calendar: calendar)
        relative._reference = date
        #expect(relative.format(date.addingTimeInterval(-86400)) == "yesterday" && relative.format(date.addingTimeInterval(7200)) == "in 2 hours")
        let formatter = DateFormatter()
        formatter.timeZone = gmt
        formatter.calendar = calendar
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        #expect(formatter.string(from: date) == "Mar 31, 2026 at 11:33\u{202F}PM")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        #expect(formatter.string(from: date) == "2026-03-31T23:33:20+0000" && formatter.date(from: "2026-03-31T23:33:20+0200") == date.addingTimeInterval(-7200))
        formatter.setLocalizedDateFormatFromTemplate("yMMMMd")
        #expect(formatter.dateFormat == "MMMM d, y" && formatter.string(from: date) == "March 31, 2026")
        let relativeFormatter = RelativeDateTimeFormatter()
        relativeFormatter.calendar = calendar
        #expect(relativeFormatter.localizedString(for: date.addingTimeInterval(-3599), relativeTo: date) == "59 minutes ago")
    }
}

/// The GMT instants of a year's last-Sunday-of-March and last-Sunday-of-October 01:00, as a
/// browser would answer for Europe/Berlin (plain arithmetic: a `Calendar` here would ask the
/// host for the current zone and recurse).
private enum _CalendarMathProbe {
    static func days(_ year: Int, _ month: Int, _ day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * ((month + 9) % 12) + 2) / 5 + day - 1
        return era * 146097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719468
    }
    static func transitions(_ year: Int) -> (Double, Double) {
        func lastSunday(month: Int, length: Int) -> Double {
            var day = length
            while (days(year, month, day) + 4) % 7 != 0 { day -= 1 }   // 1970-01-01 was a Thursday
            return Double(days(year, month, day) * 86400 + 3600)
        }
        return (lastSunday(month: 3, length: 31), lastSunday(month: 10, length: 31))
    }
}
#endif
