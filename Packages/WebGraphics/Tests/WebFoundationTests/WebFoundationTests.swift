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

    @Test func partsMatchFoundation() throws {
        for text in Self.urls {
            guard let theirs = URL(string: text) else { Issue.record("Foundation rejects \(text)"); continue }
            guard let ours = _URLParts.parse(text) else { Issue.record("we reject \(text)"); continue }
            let components = try #require(URLComponents(string: text))
            #expect(ours.string == theirs.absoluteString, Comment(rawValue: text))
            #expect(ours.scheme == theirs.scheme, Comment(rawValue: text))
            #expect(ours.host == theirs.host, Comment(rawValue: text))
            #expect(ours.port == theirs.port, Comment(rawValue: text))
            #expect(ours.user == theirs.user, Comment(rawValue: text))
            #expect(ours.password == theirs.password, Comment(rawValue: text))
            #expect(ours.query == theirs.query, Comment(rawValue: text))
            #expect(ours.fragment == theirs.fragment, Comment(rawValue: text))
            #expect(ours.path == components.percentEncodedPath, Comment(rawValue: text))
            let reference = try pathReference(for: components, url: theirs)
            #expect(ours.lastPathComponent == reference.last, Comment(rawValue: text))
            #expect(ours.pathExtension == reference.pathExtension, Comment(rawValue: text))
            #expect(ours.pathComponents == reference.components, Comment(rawValue: text))
        }
        for bad in ["", "a b", "http://host:port/", "1abc://x", "http://\u{1}"] {
            #expect(_URLParts.parse(bad) == nil, Comment(rawValue: bad))
        }
    }

    /// macOS 15's URL accessors hide opaque paths (mailto:, about:), whereas URLComponents
    /// and current Swift Foundation follow RFC 3986's path-rootless production. Use Foundation's
    /// NSString path utilities on the encoded path, then Foundation's percent decoder on each
    /// component. Older URL accessors also split escaped slashes after decoding (%2F), so even
    /// moving an opaque path under a synthetic authority would not be a portable oracle.
    private func pathReference(for components: URLComponents, url: URL) throws -> (last: String, pathExtension: String, components: [String]) {
        let path = components.percentEncodedPath
        guard components.scheme != nil, components.host == nil, !path.hasPrefix("/") else {
            return (url.lastPathComponent, url.pathExtension, url.pathComponents)
        }
        let encoded = path as NSString
        let last = try #require(encoded.lastPathComponent.removingPercentEncoding)
        var segments = encoded.pathComponents
        if segments.count > 1, segments.last == "/" { segments.removeLast() }
        let decoded = try segments.map { try #require($0.removingPercentEncoding) }
        return (last, (last as NSString).pathExtension, decoded)
    }

    struct RootlessPathCase: Sendable {
        let url: String
        let path: String
        let last: String
        let pathExtension: String
        let components: [String]
    }

    static let rootlessPaths: [RootlessPathCase] = [
        .init(url: "mailto:someone@example.com", path: "someone@example.com", last: "someone@example.com", pathExtension: "com", components: ["someone@example.com"]),
        .init(url: "about:blank", path: "blank", last: "blank", pathExtension: "", components: ["blank"]),
        .init(url: "custom:dir/file.txt", path: "dir/file.txt", last: "file.txt", pathExtension: "txt", components: ["dir", "file.txt"]),
        .init(url: "custom:dir/", path: "dir/", last: "dir", pathExtension: "", components: ["dir"]),
        .init(url: "custom:dir/a%2Fb.txt", path: "dir/a%2Fb.txt", last: "a/b.txt", pathExtension: "txt", components: ["dir", "a/b.txt"]),
        .init(url: "mailto:someone%40example.com?subject=Hello#top", path: "someone%40example.com", last: "someone@example.com", pathExtension: "com", components: ["someone@example.com"]),
        .init(url: "urn:isbn:978-0-00", path: "isbn:978-0-00", last: "isbn:978-0-00", pathExtension: "", components: ["isbn:978-0-00"]),
        .init(url: "custom:?query#fragment", path: "", last: "", pathExtension: "", components: []),
    ]

    @Test(arguments: rootlessPaths)
    func rootlessPathsHaveExplicitRFC3986Components(_ expected: RootlessPathCase) throws {
        let ours = try #require(_URLParts.parse(expected.url))
        let components = try #require(URLComponents(string: expected.url))
        #expect(ours.string == expected.url)
        #expect(ours.path == expected.path)
        #expect(components.percentEncodedPath == expected.path)
        #expect(ours.lastPathComponent == expected.last)
        #expect(ours.pathExtension == expected.pathExtension)
        #expect(ours.pathComponents == expected.components)
        // Check the native reference against the same explicit answers, independently of ours.
        let reference = try pathReference(for: components, url: #require(components.url))
        #expect(reference.last == expected.last)
        #expect(reference.pathExtension == expected.pathExtension)
        #expect(reference.components == expected.components)
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

@Suite struct NumberFormattingTests {
    static let doubles: [Double] = [3.14159, 1.0 / 3.0, 1234.5678, 12345.6789, 0.1, 100, 2.5, 1e7, 0.000123, 123456789.123456789, -0.5, 0, 0.5, 1.5, 2.675, 1e-7]
    static let integers = [0, 7, 1234, -1234567, 1_000_000]

    @Test func decimalPercentAndCurrencyMatchFoundation() {
        // The stand-in implements en_US, independently of the machine's current locale.
        let locale = Locale(identifier: "en_US")
        for value in Self.doubles {
            #expect(_NumberFormatting().format(value) == value.formatted(.number.locale(locale)), "\(value)")
            #expect(_NumberFormatting(style: .percent).format(value) == value.formatted(.percent.locale(locale)), "\(value) percent \(_NumberFormatting(style: .percent).format(value)) vs \(value.formatted(.percent.locale(locale)))")
            #expect(_NumberFormatting(style: .currency("USD")).format(value) == value.formatted(.currency(code: "USD").locale(locale)), "\(value) usd")
            #expect(_NumberFormatting(style: .currency("EUR")).format(value) == value.formatted(.currency(code: "EUR").locale(locale)), "\(value) eur")
            var two = _NumberFormatting(); two.minimumFractionDigits = 2; two.maximumFractionDigits = 2
            #expect(two.format(value) == value.formatted(.number.precision(.fractionLength(2)).locale(locale)), "\(value) frac2")
            var plain = _NumberFormatting(); plain.usesGrouping = false
            #expect(plain.format(value) == value.formatted(.number.grouping(.never).locale(locale)), "\(value) nogroup")
        }
        for value in Self.integers {
            #expect(_NumberFormatting().format(value) == value.formatted(.number.locale(locale)), "\(value)")
            #expect(_NumberFormatting(style: .percent).format(value) == value.formatted(.percent.locale(locale)), "\(value) percent")
            #expect(_NumberFormatting(style: .currency("USD")).format(value) == value.formatted(.currency(code: "USD").locale(locale)), "\(value) usd")
        }
    }

    @Test func parsesLikeFoundation() {
        let core = _NumberFormatting()
        #expect(core.parse("1,234") == 1234)
        #expect(core.parse("3.5") == 3.5)
        #expect(core.parse(" 12 ") == 12)
        #expect(core.parse("abc") == nil)
        #expect(_NumberFormatting(style: .percent).parse("25%") == 0.25)
        #expect(_NumberFormatting(style: .currency("USD")).parse("$12.50") == 12.5)
    }

    @Test func numberFormatterStyles() {
        var none = _NumberFormatting(); none.usesGrouping = false; none.maximumFractionDigits = 0
        #expect(none.format(42) == "42" && none.format(3.14159) == "3" && none.format(1234.5) == "1234")
        var decimal = _NumberFormatting(); decimal.maximumFractionDigits = 3
        #expect(decimal.format(1234.5678) == "1,234.568" && decimal.format(1234567) == "1,234,567")
        var percent = _NumberFormatting(style: .percent); percent.maximumFractionDigits = 0
        #expect(percent.format(0.256) == "26%")
    }
}

@Suite struct InlineMarkdownTests {
    private func runs(_ string: String) -> [_InlineMarkdownRun] { _InlineMarkdown.parse(string) }

    @Test func plainTextIsOneRun() {
        #expect(runs("Hello world") == [_InlineMarkdownRun(text: "Hello world")])
        #expect(runs("") == [_InlineMarkdownRun(text: "")])
    }

    @Test func emphasisStrongCodeAndStrikethrough() {
        #expect(runs("Plain **bold** and _italic_ and ***both*** done") == [
            _InlineMarkdownRun(text: "Plain "), _InlineMarkdownRun(text: "bold", bold: true), _InlineMarkdownRun(text: " and "),
            _InlineMarkdownRun(text: "italic", italic: true), _InlineMarkdownRun(text: " and "), _InlineMarkdownRun(text: "both", bold: true, italic: true),
            _InlineMarkdownRun(text: " done")])
        #expect(runs("`code`") == [_InlineMarkdownRun(text: "code", code: true)])
        #expect(runs("~~struck~~ on") == [_InlineMarkdownRun(text: "struck", strikethrough: true), _InlineMarkdownRun(text: " on")])
        #expect(runs("__strong__ *em* nested **a _b_ c**") == [
            _InlineMarkdownRun(text: "strong", bold: true), _InlineMarkdownRun(text: " "), _InlineMarkdownRun(text: "em", italic: true), _InlineMarkdownRun(text: " nested "),
            _InlineMarkdownRun(text: "a ", bold: true), _InlineMarkdownRun(text: "b", bold: true, italic: true), _InlineMarkdownRun(text: " c", bold: true)])
    }

    @Test func linksEscapesAndLooseDelimiters() {
        #expect(runs("[a link](https://example.com) rest") == [_InlineMarkdownRun(text: "a link", link: "https://example.com"), _InlineMarkdownRun(text: " rest")])
        #expect(runs("Escaped \\*stars\\*") == [_InlineMarkdownRun(text: "Escaped *stars*")])
        // Unclosed or space-flanked delimiters stay literal.
        #expect(runs("a * b * c") == [_InlineMarkdownRun(text: "a * b * c")])
        #expect(runs("open **never") == [_InlineMarkdownRun(text: "open **never")])
        #expect(runs("snake_case_name") == [_InlineMarkdownRun(text: "snake_case_name")])
    }
}
