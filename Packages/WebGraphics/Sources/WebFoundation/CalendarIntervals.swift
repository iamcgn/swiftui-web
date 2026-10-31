// `Calendar.dateInterval(of:for:)` on the wasm stand-in (Docs/coverage.md: 3 apps, charts that
// bucket samples by day, week or month): the start of the calendar unit that contains a date
// and its length, from the calendar's own fields, so a day across a daylight-saving change is
// 23 or 25 hours and a week starts on `firstWeekday`, as Foundation's do.
#if os(WASI)
import FoundationEssentials

extension Calendar {
    /// The starting time and duration of the given calendar component that contains `date`.
    /// Nil for the components with no interval of their own here (era, the week-numbering year,
    /// nanoseconds and the non-unit components).
    public func dateInterval(of component: Component, for date: Date) -> DateInterval? {
        let begin: Date?
        let next: (Component, Int)
        switch component {
        case .second:
            begin = self.date(from: dateComponents([.era, .year, .month, .day, .hour, .minute, .second], from: date)); next = (.second, 1)
        case .minute:
            begin = self.date(from: dateComponents([.era, .year, .month, .day, .hour, .minute], from: date)); next = (.minute, 1)
        case .hour:
            begin = self.date(from: dateComponents([.era, .year, .month, .day, .hour], from: date)); next = (.hour, 1)
        case .day, .weekday, .dayOfYear, .weekdayOrdinal:
            begin = startOfDay(for: date); next = (.day, 1)
        case .weekOfYear, .weekOfMonth:
            let day = startOfDay(for: date)
            let back = (self.component(.weekday, from: date) - firstWeekday + 7) % 7
            begin = self.date(byAdding: .day, value: -back, to: day); next = (.day, 7)
        case .month:
            begin = self.date(from: dateComponents([.era, .year, .month], from: date)); next = (.month, 1)
        case .quarter:
            var fields = dateComponents([.era, .year, .month], from: date)
            fields.month = ((fields.month ?? 1) - 1) / 3 * 3 + 1
            begin = self.date(from: fields); next = (.month, 3)
        case .year:
            begin = self.date(from: dateComponents([.era, .year], from: date)); next = (.year, 1)
        case .era, .yearForWeekOfYear, .nanosecond, .calendar, .timeZone, .isLeapMonth:
            return nil
        }
        guard let start = begin, let end = self.date(byAdding: next.0, value: next.1, to: start) else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// Finds the starting time and duration of the given calendar component that contains
    /// `date`, returning whether it could.
    public func dateInterval(of component: Component, start: inout Date, interval: inout TimeInterval, for date: Date) -> Bool {
        guard let found = dateInterval(of: component, for: date) else { return false }
        start = found.start
        interval = found.duration
        return true
    }
}
#endif
