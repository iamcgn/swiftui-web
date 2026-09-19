// The platform-neutral cores of the wasm stand-ins (decision 0017), held to Foundation on
// macOS: the Gregorian arithmetic, the URL parser and base64.
import Testing
import Foundation
@testable import WebFoundation

@Suite struct CalendarMathTests {
    static func foundation(offset: Int, firstWeekday: Int = 1, minimumDays: Int = 1) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: offset)!
        calendar.locale = Locale(identifier: "en_US")
        calendar.firstWeekday = firstWeekday
        calendar.minimumDaysInFirstWeek = minimumDays
        return calendar
    }

    /// Deterministic instants between 1900 and 2100 at odd offsets, plus the edges.
    static var samples: [Double] {
        var generator = SplitMix(seed: 42)
        var times = (0..<400).map { _ in Double(Int(generator.next() % (200 * 366 * 86400)) - 70 * 365 * 86400) }
        times += [0, -1, 86399, 86400, 951782400 /* 2000-02-29 */, 951868799, 1709164800 /* 2024-02-29 */, 4102444800 /* 2100-01-01 */,
                  1704067200 /* 2024-01-01 */, 1735603200 /* 2024-12-31 */, 1767225599, 1767225600 /* 2026-01-01 */]
        return times
    }
    static let offsets = [0, 3600, -18000, 19800, -34200, 46800]

    @Test func fieldsMatchFoundation() {
        for offset in Self.offsets {
            let math = _CalendarMath(offset: offset)
            let calendar = Self.foundation(offset: offset)
            for time in Self.samples {
                let date = Date(timeIntervalSince1970: time)
                let f = math.fields(time)
                let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: date)
                let ours = [f.year, f.month, f.day, f.hour, f.minute, f.second, f.weekday]
                let theirs = [c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!, c.weekday!]
                #expect(ours == theirs, "\(time) at \(offset)")
                #expect(f.dayOfYear == calendar.ordinality(of: .day, in: .year, for: date), "dayOfYear \(time)")
                #expect(math.startOfDay(time) == calendar.startOfDay(for: date).timeIntervalSince1970)
                #expect(math.range(of: .day, in: .month, for: time) == calendar.range(of: .day, in: .month, for: date))
                #expect(math.range(of: .weekOfMonth, in: .month, for: time) == calendar.range(of: .weekOfMonth, in: .month, for: date), "weeks in month \(time) at \(offset)")
            }
        }
    }

    @Test func compositionMatchesFoundation() {
        for offset in Self.offsets {
            let math = _CalendarMath(offset: offset)
            let calendar = Self.foundation(offset: offset)
            for time in Self.samples {
                let f = math.fields(time)
                let rebuilt = math.time(year: f.year, month: f.month, day: f.day, hour: f.hour, minute: f.minute, second: f.second)
                #expect(rebuilt == time.rounded(.down), "\(time) at \(offset)")
                // Overflowing fields carry over as Foundation's do.
                for (month, day) in [(13, 1), (14, 40), (0, 1), (-1, 31), (2, 30), (12, 32)] {
                    var components = DateComponents()
                    components.year = f.year; components.month = month; components.day = day; components.hour = f.hour
                    #expect(math.time(year: f.year, month: month, day: day, hour: f.hour) == calendar.date(from: components)!.timeIntervalSince1970, "\(f.year)-\(month)-\(day)")
                }
            }
        }
    }

    @Test func addingMatchesFoundation() {
        // Not `.quarter`: Foundation's `date(byAdding: .quarter, …)` returns the date unchanged.
        let pairs: [(_CalendarUnit, Calendar.Component)] = [(.year, .year), (.month, .month), (.day, .day), (.hour, .hour), (.minute, .minute), (.second, .second), (.weekOfYear, .weekOfYear)]
        for offset in [0, -18000, 19800] {
            let math = _CalendarMath(offset: offset)
            let calendar = Self.foundation(offset: offset)
            for time in Self.samples {
                let date = Date(timeIntervalSince1970: time.rounded(.down))
                for (unit, component) in pairs {
                    for value in [1, -1, 7, -13, 25, 100] {
                        let ours = math.adding(unit, value, to: date.timeIntervalSince1970)
                        let theirs = calendar.date(byAdding: component, value: value, to: date)!.timeIntervalSince1970
                        #expect(ours == theirs, "\(time) + \(value) \(unit) at \(offset)")
                    }
                }
            }
        }
    }

    @Test func weeksMatchFoundation() {
        for (firstWeekday, minimumDays) in [(1, 1), (2, 4), (1, 4), (7, 1)] {
            let math = _CalendarMath(offset: 0, firstWeekday: firstWeekday, minimumDaysInFirstWeek: minimumDays)
            let calendar = Self.foundation(offset: 0, firstWeekday: firstWeekday, minimumDays: minimumDays)
            for time in Self.samples {
                let date = Date(timeIntervalSince1970: time)
                let week = math.weekOfYear(time)
                #expect(week.week == calendar.component(.weekOfYear, from: date), "weekOfYear \(time) fw \(firstWeekday) min \(minimumDays)")
                #expect(week.year == calendar.component(.yearForWeekOfYear, from: date), "yearForWeekOfYear \(time) fw \(firstWeekday) min \(minimumDays)")
                #expect(math.weekOfMonth(time) == calendar.component(.weekOfMonth, from: date), "weekOfMonth \(time) fw \(firstWeekday) min \(minimumDays)")
            }
        }
    }

    @Test func differencesMatchFoundation() {
        let math = _CalendarMath(offset: 0)
        let calendar = Self.foundation(offset: 0)
        let samples = Self.samples.map { $0.rounded(.down) }
        for (i, a) in samples.enumerated() where i % 7 == 0 {
            for b in samples.prefix(60) {
                let ours = math.difference(from: a, to: b, units: [.year, .month, .day, .hour, .minute, .second])
                let theirs = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date(timeIntervalSince1970: a), to: Date(timeIntervalSince1970: b))
                let mine: [Int?] = [ours[.year], ours[.month], ours[.day], ours[.hour], ours[.minute], ours[.second]]
                let foundation: [Int?] = [theirs.year, theirs.month, theirs.day, theirs.hour, theirs.minute, theirs.second]
                #expect(mine == foundation, "\(a) to \(b)")
                let days = math.difference(from: a, to: b, units: [.day])
                #expect(days[.day] == calendar.dateComponents([.day], from: Date(timeIntervalSince1970: a), to: Date(timeIntervalSince1970: b)).day)
            }
        }
    }

    struct SplitMix {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }
}

@Suite struct URLPartsTests {
    static let urls = [
        "https://example.com", "https://example.com/", "http://user:pw@host.example:8080/a/b/c.txt?x=1&y=2#frag",
        "https://example.com/path/to/file.tar.gz", "file:///Users/me/doc.txt", "file:///tmp/dir/", "mailto:someone@example.com",
        "about:blank", "https://[::1]:443/x", "https://example.com/a%20b", "ftp://example.com:21/", "https://example.com/a/b/../c/./d",
        "https://example.com?q=1", "https://example.com#top", "https://example.com/.hidden", "https://example.com/dir.d/file",
        "custom-scheme+x://host/", "https://example.com/a/b/", "/relative/path", "relative/path?x#y",     ]

    @Test func partsMatchFoundation() {
        for text in Self.urls {
            guard let theirs = URL(string: text) else { Issue.record("Foundation rejects \(text)"); continue }
            guard let ours = _URLParts.parse(text) else { Issue.record("we reject \(text)"); continue }
            #expect(ours.string == theirs.absoluteString, Comment(rawValue: text))
            #expect(ours.scheme == theirs.scheme, Comment(rawValue: text))
            #expect(ours.host == theirs.host, Comment(rawValue: text))
            #expect(ours.port == theirs.port, Comment(rawValue: text))
            #expect(ours.user == theirs.user, Comment(rawValue: text))
            #expect(ours.password == theirs.password, Comment(rawValue: text))
            #expect(ours.query == theirs.query, Comment(rawValue: text))
            #expect(ours.fragment == theirs.fragment, Comment(rawValue: text))
            #expect(ours.lastPathComponent == theirs.lastPathComponent, Comment(rawValue: text))
            #expect(ours.pathExtension == theirs.pathExtension, Comment(rawValue: text))
            #expect(ours.pathComponents == theirs.pathComponents, Comment(rawValue: text))
        }
        for bad in ["", "a b", "http://host:port/", "1abc://x", "http://\u{1}"] {
            #expect(_URLParts.parse(bad) == nil, Comment(rawValue: bad))
        }
    }

    @Test func resolutionMatchesFoundation() {
        let base = "http://a/b/c/d;p?q"
        // RFC 3986 section 5.4.1's normal examples.
        let cases = ["g:h", "g", "./g", "g/", "/g", "//g", "?y", "g?y", "#s", "g#s", "g?y#s", ";x", "g;x", "g;x?y#s", "", ".", "./", "..", "../", "../g", "../..", "../../", "../../g"]
        let expected = ["g:h", "http://a/b/c/g", "http://a/b/c/g", "http://a/b/c/g/", "http://a/g", "http://g", "http://a/b/c/d;p?y", "http://a/b/c/g?y", "http://a/b/c/d;p?q#s",
                        "http://a/b/c/g#s", "http://a/b/c/g?y#s", "http://a/b/c/;x", "http://a/b/c/g;x", "http://a/b/c/g;x?y#s", "http://a/b/c/d;p?q", "http://a/b/c/", "http://a/b/c/",
                        "http://a/b/", "http://a/b/", "http://a/b/g", "http://a/", "http://a/", "http://a/g"]
        let baseParts = _URLParts.parse(base)!
        for (reference, result) in zip(cases, expected) where !reference.isEmpty {
            let ours = _URLParts.parse(reference)!.resolved(against: baseParts).string
            #expect(ours == result, Comment(rawValue: reference))
            let theirs = URL(string: reference, relativeTo: URL(string: base)!)?.absoluteString
            #expect(ours == theirs, "Foundation: \(reference)")
        }
    }
}

@Suite struct Base64Tests {
    @Test func matchesFoundation() {
        var bytes: [UInt8] = []
        for length in 0..<40 {
            bytes = (0..<length).map { UInt8(($0 * 37 + length) % 256) }
            let ours = _Base64.encode(bytes)
            #expect(ours == Data(bytes).base64EncodedString(), "\(length)")
            #expect(_Base64.decode(ours.utf8) == bytes, "\(length)")
            #expect(_Base64.encode(bytes, lineLength: 64) == Data(bytes).base64EncodedString(options: .lineLength64Characters))
        }
        #expect(_Base64.decode("****".utf8) == nil)
        #expect(_Base64.decode("QQ".utf8) == [65])
        #expect(_Base64.decode("Q".utf8) == nil)
        #expect(_Base64.decode("QU JD".utf8) == nil && _Base64.decode("QU JD".utf8, ignoreUnknown: true) == [65, 66, 67])
    }
}
