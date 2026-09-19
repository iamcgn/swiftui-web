// The Gregorian arithmetic behind `Calendar` on wasm (decision 0017), platform-neutral so the
// tests can hold it to Foundation's calendar. Time values are seconds since 1970 (UTC); the
// calendar is proleptic Gregorian (Foundation switches to Julian before 1582; nothing here
// asks about those years) and the offset is a fixed number of seconds from GMT.

/// The fields of an instant in a fixed-offset zone.
package struct _DateFields: Hashable, Sendable {
    package var year: Int, month: Int, day: Int
    package var hour: Int, minute: Int, second: Int, nanosecond: Int
    /// 1 = Sunday … 7 = Saturday.
    package var weekday: Int
    package var dayOfYear: Int
}

/// The units the arithmetic knows.
package enum _CalendarUnit: Hashable, Sendable {
    case era, year, quarter, month, weekOfYear, weekOfMonth, day, weekday, weekdayOrdinal, hour, minute, second, nanosecond, dayOfYear, yearForWeekOfYear
}

package enum _Gregorian {
    package static func isLeap(_ year: Int) -> Bool { year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) }

    package static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        default: return isLeap(year) ? 29 : 28
        }
    }

    /// Days since 1970-01-01 of a civil date (Howard Hinnant's `days_from_civil`).
    package static func days(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    /// The civil date of a day count since 1970-01-01 (`civil_from_days`).
    package static func civil(days z: Int) -> (year: Int, month: Int, day: Int) {
        let z = z + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }

    /// 1 = Sunday … 7 = Saturday; 1970-01-01 was a Thursday.
    package static func weekday(days z: Int) -> Int { (((z + 4) % 7) + 7) % 7 + 1 }

    package static func floorDiv(_ a: Int, _ b: Int) -> Int { a >= 0 ? a / b : -((-a + b - 1) / b) }
    package static func floorMod(_ a: Int, _ b: Int) -> Int { a - floorDiv(a, b) * b }
}

package struct _CalendarMath: Hashable, Sendable {
    /// Seconds east of GMT.
    package var offset: Int
    /// 1 = Sunday.
    package var firstWeekday: Int
    package var minimumDaysInFirstWeek: Int

    package init(offset: Int, firstWeekday: Int = 1, minimumDaysInFirstWeek: Int = 1) {
        self.offset = offset
        self.firstWeekday = firstWeekday
        self.minimumDaysInFirstWeek = minimumDaysInFirstWeek
    }

    /// The local day count and second of day of an instant.
    package func split(_ time: Double) -> (days: Int, secondOfDay: Int, nanosecond: Int) {
        let whole = time.rounded(.down)
        let nanosecond = Int(((time - whole) * 1e9).rounded())
        let local = Int(whole) + offset
        let days = _Gregorian.floorDiv(local, 86400)
        return (days, local - days * 86400, nanosecond)
    }

    package func fields(_ time: Double) -> _DateFields {
        let (days, secondOfDay, nanosecond) = split(time)
        let civil = _Gregorian.civil(days: days)
        return _DateFields(year: civil.year, month: civil.month, day: civil.day,
                           hour: secondOfDay / 3600, minute: secondOfDay % 3600 / 60, second: secondOfDay % 60, nanosecond: nanosecond,
                           weekday: _Gregorian.weekday(days: days),
                           dayOfYear: days - _Gregorian.days(year: civil.year, month: 1, day: 1) + 1)
    }

    /// The instant of civil fields; months, days and times past their range carry over.
    package func time(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0, second: Int = 0, nanosecond: Int = 0) -> Double {
        let monthIndex = month - 1
        let normalizedYear = year + _Gregorian.floorDiv(monthIndex, 12)
        let normalizedMonth = _Gregorian.floorMod(monthIndex, 12) + 1
        let days = _Gregorian.days(year: normalizedYear, month: normalizedMonth, day: 1) + day - 1
        let seconds = days * 86400 + hour * 3600 + minute * 60 + second - offset
        return Double(seconds) + Double(nanosecond) / 1e9
    }

    /// The instant at the start of the day holding `time`.
    package func startOfDay(_ time: Double) -> Double { Double(split(time).days * 86400 - offset) }

    /// `time` plus `value` units; months and years clamp the day to the target month's length.
    package func adding(_ unit: _CalendarUnit, _ value: Int, to time: Double) -> Double {
        let f = fields(time)
        let fraction = time - time.rounded(.down)
        switch unit {
        case .era: return time
        case .year, .month, .quarter:
            let months = unit == .year ? value * 12 : unit == .quarter ? value * 3 : value
            let index = f.month - 1 + months
            let year = f.year + _Gregorian.floorDiv(index, 12)
            let month = _Gregorian.floorMod(index, 12) + 1
            let day = min(f.day, _Gregorian.daysInMonth(year: year, month: month))
            return self.time(year: year, month: month, day: day, hour: f.hour, minute: f.minute, second: f.second) + fraction
        case .day, .weekday, .dayOfYear: return time + Double(value * 86400)
        case .weekOfYear, .weekOfMonth, .weekdayOrdinal, .yearForWeekOfYear: return time + Double(value * 7 * 86400)
        case .hour: return time + Double(value * 3600)
        case .minute: return time + Double(value * 60)
        case .second: return time + Double(value)
        case .nanosecond: return time + Double(value) / 1e9
        }
    }

    /// The day count that starts the week holding `days`.
    private func weekStart(_ days: Int) -> Int { days - _Gregorian.floorMod(_Gregorian.weekday(days: days) - firstWeekday, 7) }

    /// The first day of week 1 of the period starting at `first` (a year's or month's first day).
    private func firstWeekStart(period first: Int) -> Int {
        let start = weekStart(first)
        return 7 - (first - start) >= minimumDaysInFirstWeek ? start : start + 7
    }

    /// The week of the year and the year it belongs to, Foundation's `weekOfYear` and
    /// `yearForWeekOfYear` under `firstWeekday` and `minimumDaysInFirstWeek`.
    package func weekOfYear(_ time: Double) -> (week: Int, year: Int) {
        let days = split(time).days
        let civil = _Gregorian.civil(days: days)
        var year = civil.year
        var start = firstWeekStart(period: _Gregorian.days(year: year, month: 1, day: 1))
        if days < start {
            year -= 1
            start = firstWeekStart(period: _Gregorian.days(year: year, month: 1, day: 1))
        } else {
            let next = firstWeekStart(period: _Gregorian.days(year: year + 1, month: 1, day: 1))
            if days >= next { year += 1; start = next }
        }
        return ((days - start) / 7 + 1, year)
    }

    package func weekOfMonth(_ time: Double) -> Int {
        let days = split(time).days
        let civil = _Gregorian.civil(days: days)
        let start = firstWeekStart(period: _Gregorian.days(year: civil.year, month: civil.month, day: 1))
        return _Gregorian.floorDiv(days - start, 7) + 1
    }

    /// How many weeks the month holding `time` spans (its `weekOfMonth` range).
    package func weeksInMonth(_ time: Double) -> Range<Int> {
        let civil = _Gregorian.civil(days: split(time).days)
        let first = _Gregorian.days(year: civil.year, month: civil.month, day: 1)
        let last = first + _Gregorian.daysInMonth(year: civil.year, month: civil.month) - 1
        let start = firstWeekStart(period: first)
        let low = first < start ? 0 : 1
        return low..<(_Gregorian.floorDiv(last - start, 7) + 2)
    }

    package func weeksInYear(_ time: Double) -> Range<Int> {
        let year = _Gregorian.civil(days: split(time).days).year
        let start = firstWeekStart(period: _Gregorian.days(year: year, month: 1, day: 1))
        let next = firstWeekStart(period: _Gregorian.days(year: year + 1, month: 1, day: 1))
        return 1..<((next - start) / 7 + 1)
    }

    package func range(of smaller: _CalendarUnit, in larger: _CalendarUnit, for time: Double) -> Range<Int>? {
        let f = fields(time)
        switch (smaller, larger) {
        case (.day, .month): return 1..<(_Gregorian.daysInMonth(year: f.year, month: f.month) + 1)
        case (.day, .year), (.dayOfYear, .year): return 1..<((_Gregorian.isLeap(f.year) ? 366 : 365) + 1)
        case (.day, .weekOfYear), (.day, .weekOfMonth), (.weekday, .weekOfYear), (.weekday, .weekOfMonth), (.weekday, .month), (.weekday, .year): return 1..<8
        case (.month, .year): return 1..<13
        case (.month, .quarter): return 1..<4
        case (.quarter, .year): return 1..<5
        case (.hour, .day): return 0..<24
        case (.minute, .hour): return 0..<60
        case (.minute, .day): return 0..<1440
        case (.second, .minute): return 0..<60
        case (.second, .hour): return 0..<3600
        case (.second, .day): return 0..<86400
        case (.nanosecond, .second): return 0..<1_000_000_000
        case (.weekOfMonth, .month): return weeksInMonth(time)
        case (.weekOfYear, .year), (.weekOfYear, .yearForWeekOfYear): return weeksInYear(time)
        case (.weekdayOrdinal, .month): return 1..<((_Gregorian.daysInMonth(year: f.year, month: f.month) + 6) / 7 + 1)
        case (.year, .era): return 1..<144684
        default: return nil
        }
    }

    /// The whole units between two instants, largest first: years and months as calendar
    /// steps from the instant the larger units reached (each step clamped like `adding`, so
    /// Jan 31 + 2 months is Mar 31, as Foundation counts), the rest from the remaining seconds.
    package func difference(from start: Double, to end: Double, units: Set<_CalendarUnit>) -> [_CalendarUnit: Int] {
        var result: [_CalendarUnit: Int] = [:]
        var cursor = start
        let sign = end >= start ? 1 : -1
        for unit in [_CalendarUnit.year, .quarter, .month] where units.contains(unit) {
            var count = 0
            while true {
                let next = adding(unit, count + sign, to: cursor)
                if sign > 0 ? next > end : next < end { break }
                count += sign
            }
            cursor = adding(unit, count, to: cursor)
            result[unit] = count
        }
        var remaining = end - cursor
        for (unit, length) in [(_CalendarUnit.weekOfYear, 604800.0), (.weekOfMonth, 604800.0), (.day, 86400.0), (.hour, 3600.0), (.minute, 60.0), (.second, 1.0)] where units.contains(unit) {
            let count = (remaining / length).rounded(.towardZero)
            result[unit] = Int(count)
            remaining -= count * length
        }
        if units.contains(.nanosecond) { result[.nanosecond] = Int((remaining * 1e9).rounded()) }
        return result
    }
}
