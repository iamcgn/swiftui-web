// Calendar searches (`nextDate(after:matching:matchingPolicy:)`, `enumerateDates`,
// `date(_:matchesComponents:)`, `nextWeekend`) and URLError's codes named on the type. The
// cases run against Foundation on macOS and Linux too, which holds WebFoundation's answers to it.
import Testing
import WebFoundation

@Suite struct CalendarSearchTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func aTimeOfDayIsTodayOrTomorrow() {
        let morning = DateComponents(hour: 9)
        #expect(calendar.nextDate(after: date(2027, 1, 10, 8), matching: morning, matchingPolicy: .nextTime) == date(2027, 1, 10, 9))
        #expect(calendar.nextDate(after: date(2027, 1, 10, 9), matching: morning, matchingPolicy: .nextTime) == date(2027, 1, 11, 9))
        let halfPast = DateComponents(minute: 30)
        #expect(calendar.nextDate(after: date(2027, 1, 10, 23, 45), matching: halfPast, matchingPolicy: .nextTime) == date(2027, 1, 11, 0, 30))
    }

    @Test func unitsBelowTheSmallestGivenStartAtTheirFirstValue() {
        #expect(calendar.nextDate(after: date(2027, 1, 10, 14), matching: DateComponents(day: 15), matchingPolicy: .nextTime) == date(2027, 1, 15))
        #expect(calendar.nextDate(after: date(2027, 1, 15, 14), matching: DateComponents(day: 15), matchingPolicy: .nextTime) == date(2027, 2, 15))
        #expect(calendar.nextDate(after: date(2027, 3, 10), matching: DateComponents(month: 3), matchingPolicy: .nextTime) == date(2028, 3, 1))
        #expect(calendar.nextDate(after: date(2027, 3, 10), matching: DateComponents(year: 2030), matchingPolicy: .nextTime) == date(2030, 1, 1))
        #expect(calendar.nextDate(after: date(2027, 3, 10), matching: DateComponents(year: 2020), matchingPolicy: .nextTime) == nil)
    }

    @Test func weekdaysAndBackwardSearches() {
        // 2027-01-10 is a Sunday.
        let friday = DateComponents(hour: 18, weekday: 6)
        #expect(calendar.nextDate(after: date(2027, 1, 10), matching: friday, matchingPolicy: .nextTime) == date(2027, 1, 15, 18))
        #expect(calendar.nextDate(after: date(2027, 1, 10), matching: friday, matchingPolicy: .nextTime, direction: .backward) == date(2027, 1, 8, 18))
        #expect(calendar.nextDate(after: date(2027, 1, 10, 12), matching: DateComponents(hour: 9), matchingPolicy: .nextTime, direction: .backward) == date(2027, 1, 10, 9))
        #expect(calendar.nextDate(after: date(2027, 1, 10), matching: DateComponents(day: 20), matchingPolicy: .nextTime, direction: .backward) == date(2026, 12, 20))
    }

    @Test func aDayAMonthLacksFollowsThePolicy() {
        let thirtyFirst = DateComponents(day: 31, hour: 10)
        let april = date(2027, 4, 5)
        #expect(calendar.nextDate(after: april, matching: thirtyFirst, matchingPolicy: .strict) == date(2027, 5, 31, 10))
        #expect(calendar.nextDate(after: april, matching: thirtyFirst, matchingPolicy: .nextTime) == date(2027, 5, 1))
        #expect(calendar.nextDate(after: april, matching: thirtyFirst, matchingPolicy: .nextTimePreservingSmallerComponents) == date(2027, 5, 1, 10))
        #expect(calendar.nextDate(after: april, matching: thirtyFirst, matchingPolicy: .previousTimePreservingSmallerComponents) == date(2027, 4, 30, 10))
        let leapDay = DateComponents(month: 2, day: 29)
        #expect(calendar.nextDate(after: date(2027, 1, 1), matching: leapDay, matchingPolicy: .strict) == date(2028, 2, 29))
    }

    @Test func matchingAndEnumerating() {
        let tuesday = date(2027, 1, 12, 9, 30)
        #expect(calendar.date(tuesday, matchesComponents: DateComponents(month: 1, hour: 9, weekday: 3)))
        #expect(!calendar.date(tuesday, matchesComponents: DateComponents(minute: 0)))

        var firsts: [Date] = []
        calendar.enumerateDates(startingAfter: date(2027, 1, 15), matching: DateComponents(day: 1), matchingPolicy: .nextTime) { found, exact, stop in
            if let found, exact { firsts.append(found) }
            stop = firsts.count == 3
        }
        #expect(firsts == [date(2027, 2, 1), date(2027, 3, 1), date(2027, 4, 1)])
    }

    @Test func settingATimeKeepsTheDay() {
        #expect(calendar.date(bySettingHour: 7, minute: 15, second: 0, of: date(2027, 1, 12, 20), matchingPolicy: .nextTime,
                              repeatedTimePolicy: .first, direction: .forward) == date(2027, 1, 12, 7, 15))
    }

    @Test func urlErrorNamesItsCodes() {
        let error = URLError(.cancelled)
        #expect(error.code == URLError.cancelled)
        #expect(URLError.timedOut == URLError.Code.timedOut)
        #expect(URLError.notConnectedToInternet.rawValue == -1009)
    }
}
