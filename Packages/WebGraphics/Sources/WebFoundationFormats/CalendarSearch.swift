// `Calendar.nextDate(after:matching:matchingPolicy:)` and its family on the wasm stand-in
// (Docs/coverage.md: SwiftDate, which Clendar builds from source, finds recurring dates with
// it). The search walks the calendar's own days, jumping over years, months and days that
// cannot match, and tries the times the components allow within each day. Units smaller than
// the smallest one given take their lowest value, as Foundation's do: matching `day: 15` is
// midnight on the 15th, matching `month: 3` is the 1st of March.
//
// Differences from Foundation: the repeated hour after a daylight-saving change is always the
// first of the two (`RepeatedTimePolicy` is accepted), and a time skipped by a change is the
// time the zone gives for it, except under `.strict`, which looks for the next day that has it.
#if os(WASI)
import WebFoundation

extension Calendar {
    /// The date on the same day at the time; the policies are accepted, and the time is the one
    /// the zone gives for it.
    public func date(bySettingHour hour: Int, minute: Int, second: Int, of date: Date, matchingPolicy: MatchingPolicy,
                     repeatedTimePolicy: RepeatedTimePolicy = .first, direction: SearchDirection = .forward) -> Date? {
        self.date(bySettingHour: hour, minute: minute, second: second, of: date)
    }

    /// What a search does when the components name a date that doesn't exist, such as
    /// February 30.
    public enum MatchingPolicy: Hashable, Sendable {
        /// The next date that exists, at its start.
        case nextTime
        /// The next date that exists, with the time the components give.
        case nextTimePreservingSmallerComponents
        /// The last date before it that exists, with the time the components give.
        case previousTimePreservingSmallerComponents
        /// Only dates that match every component.
        case strict
    }

    /// Which of a time that occurs twice (the hour repeated when daylight saving ends) to find.
    public enum RepeatedTimePolicy: Hashable, Sendable {
        case first, last
    }

    /// Which way a search goes from its starting date.
    public enum SearchDirection: Hashable, Sendable {
        case forward, backward
    }

    /// Whether the date has the value of every component the components set.
    public func date(_ date: Date, matchesComponents components: DateComponents) -> Bool {
        for component in Component.allCases {
            if let value = components.value(for: component), self.component(component, from: date) != value { return false }
        }
        return true
    }

    /// The first date after (or, searching backward, before) `date` that matches the
    /// components, or nil when none does within about five centuries.
    public func nextDate(after date: Date, matching components: DateComponents, matchingPolicy: MatchingPolicy,
                         repeatedTimePolicy: RepeatedTimePolicy = .first, direction: SearchDirection = .forward) -> Date? {
        let forward = direction == .forward
        func beyond(_ candidate: Date) -> Bool { forward ? candidate > date : candidate < date }

        // The times of day to try, in the order of the search.
        let timeGiven = components.hour != nil || components.minute != nil || components.second != nil || components.nanosecond != nil
        func values(_ given: Int?, smallerGiven: Bool, in range: Range<Int>) -> [Int] {
            let all = given.map { [$0] } ?? (smallerGiven ? Array(range) : [range.lowerBound])
            return forward ? all : all.reversed()
        }
        let nanosecond = components.nanosecond ?? 0
        let seconds = values(components.second, smallerGiven: components.nanosecond != nil, in: 0..<60)
        let minutes = values(components.minute, smallerGiven: components.second != nil || components.nanosecond != nil, in: 0..<60)
        let hours = values(components.hour, smallerGiven: components.minute != nil || components.second != nil || components.nanosecond != nil, in: 0..<24)

        // The fields a day must have; the unit below the smallest one given takes its first value.
        var day = components
        day.hour = nil; day.minute = nil; day.second = nil; day.nanosecond = nil
        day.calendar = nil; day.timeZone = nil; day.isLeapMonth = nil
        let weekGiven = day.weekOfYear != nil || day.weekOfMonth != nil || day.yearForWeekOfYear != nil
        let dayGiven = day.day != nil || day.weekday != nil || day.weekdayOrdinal != nil || day.dayOfYear != nil || weekGiven
        if !timeGiven, !dayGiven, day.year != nil || day.month != nil || day.quarter != nil || day.era != nil {
            day.day = 1
            if day.month == nil { day.month = day.quarter.map { ($0 - 1) * 3 + 1 } ?? 1 }
        }
        if !timeGiven, weekGiven, day.weekday == nil, day.day == nil { day.weekday = firstWeekday }

        func firstOfMonth(_ year: Int, _ month: Int) -> Date? { self.date(from: DateComponents(year: year, month: month, day: 1)) }
        func atTimes(_ fields: DateComponents, preservingTime: Bool) -> Date? {
            var fields = fields
            fields.nanosecond = nanosecond
            for hour in preservingTime ? hours : [0] {
                for minute in preservingTime ? minutes : [0] {
                    for second in preservingTime ? seconds : [0] {
                        fields.hour = hour; fields.minute = minute; fields.second = second
                        guard let candidate = self.date(from: fields), beyond(candidate) else { continue }
                        if matchingPolicy == .strict, !self.date(candidate, matchesComponents: components) { continue }
                        return candidate
                    }
                }
            }
            return nil
        }

        var cursor = startOfDay(for: date)
        for _ in 0..<200_000 {
            let here = dateComponents([.year, .month, .day], from: cursor)
            guard let year = here.year, let month = here.month, let dayOfMonth = here.day else { return nil }
            let nextMonth = firstOfMonth(year, month + 1)
            let previousMonth = firstOfMonth(year, month).flatMap { self.date(byAdding: .day, value: -1, to: $0) }
            let otherMonth = forward ? nextMonth : previousMonth

            if let wanted = day.year, wanted != year {
                if forward ? year > wanted : year < wanted { return nil }
                guard let jump = forward ? firstOfMonth(wanted, 1) : firstOfMonth(wanted + 1, 1).flatMap({ self.date(byAdding: .day, value: -1, to: $0) })
                else { return nil }
                cursor = jump
                continue
            }
            if let wanted = day.month, wanted != month {
                guard let otherMonth else { return nil }
                cursor = otherMonth
                continue
            }
            if let wanted = day.day, wanted != dayOfMonth {
                let length = range(of: .day, in: .month, for: cursor)?.count ?? 31
                if wanted > length, wanted <= 31, matchingPolicy != .strict {
                    // The day doesn't exist in this month: the policy's stand-in for it.
                    var stand = DateComponents(year: year, month: month)
                    switch matchingPolicy {
                    case .previousTimePreservingSmallerComponents:
                        stand.day = length
                        if let found = atTimes(stand, preservingTime: true) { return found }
                    case .nextTime, .nextTimePreservingSmallerComponents:
                        stand.month = month + 1
                        stand.day = 1
                        if let found = atTimes(stand, preservingTime: matchingPolicy != .nextTime) { return found }
                    case .strict:
                        break
                    }
                } else if wanted <= length, forward ? dayOfMonth < wanted : dayOfMonth > wanted {
                    guard let jump = self.date(from: DateComponents(year: year, month: month, day: wanted)) else { return nil }
                    cursor = jump
                    continue
                }
                guard let otherMonth else { return nil }
                cursor = otherMonth
                continue
            }
            if self.date(cursor, matchesComponents: day), let found = atTimes(here, preservingTime: true) { return found }
            guard let step = self.date(byAdding: .day, value: forward ? 1 : -1, to: cursor) else { return nil }
            cursor = step
        }
        return nil
    }

    /// Calls `block` with each date after (or before) `start` that matches the components,
    /// until it sets its last argument to true; a nil date ends the search.
    public func enumerateDates(startingAfter start: Date, matching components: DateComponents, matchingPolicy: MatchingPolicy,
                               repeatedTimePolicy: RepeatedTimePolicy = .first, direction: SearchDirection = .forward,
                               using block: (_ result: Date?, _ exactMatch: Bool, _ stop: inout Bool) -> Void) {
        var from = start
        var stop = false
        while !stop {
            let found = nextDate(after: from, matching: components, matchingPolicy: matchingPolicy,
                                 repeatedTimePolicy: repeatedTimePolicy, direction: direction)
            block(found, found.map { self.date($0, matchesComponents: components) } ?? false, &stop)
            guard let found else { return }
            from = found
        }
    }

    /// The start and length of the next weekend after `date` (or before, searching backward):
    /// Saturday and Sunday.
    public func nextWeekend(startingAfter date: Date, start: inout Date, interval: inout TimeInterval, direction: SearchDirection = .forward) -> Bool {
        guard let weekend = nextWeekend(startingAfter: date, direction: direction) else { return false }
        start = weekend.start
        interval = weekend.duration
        return true
    }

    /// The next weekend after `date` (or before, searching backward): Saturday and Sunday.
    public func nextWeekend(startingAfter date: Date, direction: SearchDirection = .forward) -> DateInterval? {
        guard let saturday = nextDate(after: date, matching: DateComponents(weekday: 7), matchingPolicy: .nextTime, direction: direction),
              let end = self.date(byAdding: .day, value: 2, to: saturday) else { return nil }
        return DateInterval(start: saturday, end: end)
    }
}
#endif
