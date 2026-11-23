// Small wasm stand-ins the corpus reaches for: `Date.compare(_:)` answering this Foundation's
// `ComparisonResult` (SwiftDate), NSCalendar's `range(of:start:interval:for:)` (SwiftDate's
// `dateAtStartOf`), responses equal by identity (Networkable's `Equatable` error), empty responses (OAuth2) and
// `CGColor.converted(to:intent:options:)` (GistHub's `hexString`).
#if os(WASI)
import Testing
import WebFoundation
import WebFoundationFormats
import WebGraphics

@Suite struct EverydayWasmAPITests {
    /// What SwiftDate's `compare(toDate:granularity:)` does: hand a date comparison back as the
    /// function's own result type.
    private func order(_ a: Date, _ b: Date) -> ComparisonResult { a.compare(b) }
    private func order(_ a: DateInterval, _ b: DateInterval) -> ComparisonResult { a.compare(b) }

    @Test func datesCompareIntoThisFoundationsResult() {
        let early = Date(timeIntervalSince1970: 100), late = Date(timeIntervalSince1970: 200)
        #expect(order(early, late) == .orderedAscending)
        #expect(order(late, early) == .orderedDescending)
        #expect(order(early, early) == .orderedSame)
        // With no result type to match, the call still compiles and answers alike.
        #expect(early.compare(late) == .orderedAscending)
        let a = DateInterval(start: early, duration: 10), b = DateInterval(start: early, duration: 20)
        #expect(order(a, b) == .orderedAscending && order(b, a) == .orderedDescending && order(a, a) == .orderedSame)
        #expect(order(DateInterval(start: late, duration: 1), b) == .orderedDescending)
    }

    @Test func calendarRangeGivesTheUnitsStartAndLength() throws {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let calendar = gregorian as NSCalendar
        // Sunday 15 November 2026, 13:20 UTC.
        let date = Date(timeIntervalSince1970: 1_794_700_800 + 48_000)
        var start: Date?
        var interval: TimeInterval = 0
        #expect(calendar.range(of: .day, start: &start, interval: &interval, for: date))
        #expect(start == Date(timeIntervalSince1970: 1_794_700_800) && interval == 86_400)
        #expect(calendar.range(of: .month, start: &start, interval: &interval, for: date))
        #expect(start == Date(timeIntervalSince1970: 1_793_491_200) && interval == 30 * 86_400)
        #expect(calendar.range(of: .hour, start: nil, interval: &interval, for: date) && interval == 3600)
    }

    @Test func responsesAreEqualOnlyToThemselves() throws {
        enum Failure: Error, Equatable { case unexpected(URLResponse, Data) }
        let url = try #require(URL(string: "https://example.com/a"))
        let one = URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        let other = URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        #expect(one == one && one != other)
        #expect(Failure.unexpected(one, Data()) == .unexpected(one, Data()))
        #expect(Failure.unexpected(one, Data()) != .unexpected(other, Data()))
        #expect(Set([one, one, other]).count == 2)
        let http = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
        #expect(http == http && (http as URLResponse) != one)
        // OAuth2 reports a failed load with an empty response.
        let empty = HTTPURLResponse()
        #expect(empty.url == nil && empty.statusCode == 0 && empty.allHeaderFields.isEmpty && empty.mimeType == nil)
        #expect(empty.value(forHTTPHeaderField: "Content-Type") == nil && URLResponse().expectedContentLength == -1)
    }

    @Test func colorsConvertBetweenSpaces() throws {
        let color = CGColor(red: 1, green: 0.5, blue: 0, alpha: 0.25)
        let srgb = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let same = try #require(color.converted(to: srgb, intent: .defaultIntent, options: nil))
        #expect(same.components == [1, 0.5, 0, 0.25] && same.alpha == 0.25)
        #expect(color.colorSpace?.model == .rgb)
        let gray = try #require(color.converted(to: CGColorSpaceCreateDeviceGray(), intent: .defaultIntent, options: nil))
        let luminance = 0.2126 + 0.7152 * 0.5
        #expect(abs((gray.components?[0] ?? 0) - luminance) < 1e-9 && gray.alpha == 0.25)
    }
}
#endif
