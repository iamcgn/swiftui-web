// Foundation's `Calendar`, `TimeZone`, `Locale` and `DateComponents` on wasm (decision 0017).
// One calendar (Gregorian, whatever the identifier), fixed-offset time zones (the browser has
// no tz database), English symbols. `_CalendarMath` does the arithmetic.
#if os(WASI)
import FoundationEssentials

public struct TimeZone: Hashable, Sendable, Codable, CustomStringConvertible {
    public let identifier: String
    private let offset: Int

    private init(identifier: String, offset: Int) {
        self.identifier = identifier
        self.offset = offset
    }

    /// "GMT", "UTC", or a fixed offset written "GMT+5", "GMT-05:30", "UTC+0100"; named zones
    /// need a tz database the browser bundle does not carry, so they are nil.
    public init?(identifier: String) {
        let upper = identifier.uppercased()
        if upper == "GMT" || upper == "UTC" || upper == "ETC/GMT" || upper == "ETC/UTC" || upper == "Z" {
            self.init(identifier: "GMT", offset: 0)
            return
        }
        guard upper.hasPrefix("GMT") || upper.hasPrefix("UTC"), let sign = upper.dropFirst(3).first, sign == "+" || sign == "-" else { return nil }
        let digits = upper.dropFirst(4).filter { $0 != ":" }
        guard !digits.isEmpty, digits.count <= 4, digits.allSatisfy(\.isNumber), let value = Int(digits) else { return nil }
        let hours = digits.count <= 2 ? value : value / 100
        let minutes = digits.count <= 2 ? 0 : value % 100
        guard hours <= 18, minutes < 60 else { return nil }
        let seconds = (hours * 3600 + minutes * 60) * (sign == "-" ? -1 : 1)
        self.init(secondsFromGMT: seconds)
    }

    public init?(abbreviation: String) { self.init(identifier: abbreviation) }

    /// A fixed offset, named the way Foundation names it ("GMT+0530", "GMT" for zero).
    public init?(secondsFromGMT seconds: Int) {
        guard abs(seconds) <= 18 * 3600 else { return nil }
        if seconds == 0 { self.init(identifier: "GMT", offset: 0); return }
        let hours = abs(seconds) / 3600, minutes = abs(seconds) % 3600 / 60
        let name = "GMT" + (seconds < 0 ? "-" : "+") + (hours < 10 ? "0" : "") + String(hours) + (minutes < 10 ? "0" : "") + String(minutes)
        self.init(identifier: name, offset: seconds)
    }

    public static let gmt = TimeZone(identifier: "GMT", offset: 0)
    /// The browser's zone once the host reports it (`_hostSecondsFromGMT`), else GMT.
    public static var current: TimeZone { _hostSecondsFromGMT.flatMap { TimeZone(secondsFromGMT: $0) } ?? .gmt }
    public static var autoupdatingCurrent: TimeZone { current }
    /// Set by the canvas host from the browser's offset at launch.
    nonisolated(unsafe) public static var _hostSecondsFromGMT: Int?

    public func secondsFromGMT(for date: Date = Date()) -> Int { offset }
    public var secondsFromGMT: Int { offset }
    public func abbreviation(for date: Date = Date()) -> String? { identifier }
    public func isDaylightSavingTime(for date: Date = Date()) -> Bool { false }
    public func daylightSavingTimeOffset(for date: Date = Date()) -> TimeInterval { 0 }
    public func localizedName(for style: NameStyle, locale: Locale?) -> String? { identifier }
    public static var knownTimeZoneIdentifiers: [String] { ["GMT"] }
    public var description: String { identifier + " (fixed)" }

    public enum NameStyle: Sendable { case standard, shortStandard, daylightSaving, shortDaylightSaving, generic, shortGeneric }
}

public struct Locale: Hashable, Sendable, Codable, CustomStringConvertible {
    public let identifier: String
    public init(identifier: String) { self.identifier = identifier }
    public static var current: Locale { Locale(identifier: "en_US") }
    public static var autoupdatingCurrent: Locale { current }
    public var languageCode: String? { identifier.split { $0 == "_" || $0 == "-" }.first.map(String.init) }
    public var regionCode: String? { identifier.split { $0 == "_" || $0 == "-" }.dropFirst().first.map(String.init) }
    public var calendar: Calendar { Calendar(identifier: .gregorian) }
    public var description: String { identifier + " (fixed)" }
}

public struct DateComponents: Hashable, Sendable, Codable, CustomStringConvertible {
    public var calendar: Calendar?
    public var timeZone: TimeZone?
    public var era: Int?
    public var year: Int?
    public var month: Int?
    public var day: Int?
    public var hour: Int?
    public var minute: Int?
    public var second: Int?
    public var nanosecond: Int?
    public var weekday: Int?
    public var weekdayOrdinal: Int?
    public var quarter: Int?
    public var weekOfMonth: Int?
    public var weekOfYear: Int?
    public var yearForWeekOfYear: Int?
    public var dayOfYear: Int?
    public var isLeapMonth: Bool?

    public init(calendar: Calendar? = nil, timeZone: TimeZone? = nil, era: Int? = nil, year: Int? = nil, month: Int? = nil, day: Int? = nil,
                hour: Int? = nil, minute: Int? = nil, second: Int? = nil, nanosecond: Int? = nil, weekday: Int? = nil, weekdayOrdinal: Int? = nil,
                quarter: Int? = nil, weekOfMonth: Int? = nil, weekOfYear: Int? = nil, yearForWeekOfYear: Int? = nil) {
        self.calendar = calendar; self.timeZone = timeZone; self.era = era; self.year = year; self.month = month; self.day = day
        self.hour = hour; self.minute = minute; self.second = second; self.nanosecond = nanosecond; self.weekday = weekday
        self.weekdayOrdinal = weekdayOrdinal; self.quarter = quarter; self.weekOfMonth = weekOfMonth; self.weekOfYear = weekOfYear
        self.yearForWeekOfYear = yearForWeekOfYear
    }

    /// The date, when a calendar is set (Foundation's rule).
    public var date: Date? { calendar?.date(from: self) }
    public var isValidDate: Bool { calendar.map { isValidDate(in: $0) } ?? false }
    public func isValidDate(in calendar: Calendar) -> Bool {
        guard let date = calendar.date(from: self) else { return false }
        let back = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return (year ?? back.year) == back.year && (month ?? back.month) == back.month && (day ?? back.day) == back.day
            && (hour ?? back.hour) == back.hour && (minute ?? back.minute) == back.minute && (second ?? back.second) == back.second
    }

    public func value(for component: Calendar.Component) -> Int? {
        switch component {
        case .era: return era
        case .year: return year
        case .month: return month
        case .day: return day
        case .hour: return hour
        case .minute: return minute
        case .second: return second
        case .nanosecond: return nanosecond
        case .weekday: return weekday
        case .weekdayOrdinal: return weekdayOrdinal
        case .quarter: return quarter
        case .weekOfMonth: return weekOfMonth
        case .weekOfYear: return weekOfYear
        case .yearForWeekOfYear: return yearForWeekOfYear
        case .dayOfYear: return dayOfYear
        case .calendar, .timeZone, .isLeapMonth: return nil
        }
    }

    public mutating func setValue(_ value: Int?, for component: Calendar.Component) {
        switch component {
        case .era: era = value
        case .year: year = value
        case .month: month = value
        case .day: day = value
        case .hour: hour = value
        case .minute: minute = value
        case .second: second = value
        case .nanosecond: nanosecond = value
        case .weekday: weekday = value
        case .weekdayOrdinal: weekdayOrdinal = value
        case .quarter: quarter = value
        case .weekOfMonth: weekOfMonth = value
        case .weekOfYear: weekOfYear = value
        case .yearForWeekOfYear: yearForWeekOfYear = value
        case .dayOfYear: dayOfYear = value
        case .calendar, .timeZone, .isLeapMonth: break
        }
    }

    public var description: String {
        var parts: [String] = []
        if let calendar { parts.append("calendar: \(calendar)") }
        if let timeZone { parts.append("timeZone: \(timeZone)") }
        for (name, value) in [("era", era), ("year", year), ("month", month), ("day", day), ("hour", hour), ("minute", minute), ("second", second),
                              ("nanosecond", nanosecond), ("weekday", weekday), ("weekdayOrdinal", weekdayOrdinal), ("quarter", quarter),
                              ("weekOfMonth", weekOfMonth), ("weekOfYear", weekOfYear), ("yearForWeekOfYear", yearForWeekOfYear)] {
            if let value { parts.append("\(name): \(value)") }
        }
        return parts.joined(separator: " ")
    }
}

public struct Calendar: Hashable, Sendable, Codable, CustomStringConvertible {
    public enum Identifier: String, Sendable, Codable, CaseIterable {
        case gregorian, buddhist, chinese, coptic, ethiopicAmeteMihret, ethiopicAmeteAlem, hebrew, iso8601, indian,
             islamic, islamicCivil, islamicTabular, islamicUmmAlQura, japanese, persian, republicOfChina
    }

    public enum Component: Hashable, Sendable, Codable, CaseIterable {
        case era, year, month, day, hour, minute, second, weekday, weekdayOrdinal, quarter, weekOfMonth, weekOfYear,
             yearForWeekOfYear, nanosecond, calendar, timeZone, isLeapMonth, dayOfYear
    }

    public let identifier: Identifier
    public var timeZone: TimeZone
    public var locale: Locale?
    /// 1 = Sunday.
    public var firstWeekday: Int = 1
    public var minimumDaysInFirstWeek: Int = 1

    public init(identifier: Identifier) {
        self.identifier = identifier
        timeZone = .current
        locale = .current
    }
    public static var current: Calendar { Calendar(identifier: .gregorian) }
    public static var autoupdatingCurrent: Calendar { current }

    private var math: _CalendarMath { _CalendarMath(offset: timeZone.secondsFromGMT, firstWeekday: firstWeekday, minimumDaysInFirstWeek: minimumDaysInFirstWeek) }
    private func math(in zone: TimeZone?) -> _CalendarMath {
        _CalendarMath(offset: (zone ?? timeZone).secondsFromGMT, firstWeekday: firstWeekday, minimumDaysInFirstWeek: minimumDaysInFirstWeek)
    }

    private static func unit(_ component: Component) -> _CalendarUnit? {
        switch component {
        case .era: return .era
        case .year: return .year
        case .month: return .month
        case .day: return .day
        case .hour: return .hour
        case .minute: return .minute
        case .second: return .second
        case .weekday: return .weekday
        case .weekdayOrdinal: return .weekdayOrdinal
        case .quarter: return .quarter
        case .weekOfMonth: return .weekOfMonth
        case .weekOfYear: return .weekOfYear
        case .yearForWeekOfYear: return .yearForWeekOfYear
        case .nanosecond: return .nanosecond
        case .dayOfYear: return .dayOfYear
        case .calendar, .timeZone, .isLeapMonth: return nil
        }
    }

    public func component(_ component: Component, from date: Date) -> Int {
        let math = math
        let time = date.timeIntervalSince1970
        let f = math.fields(time)
        switch component {
        case .era: return f.year > 0 ? 1 : 0
        case .year: return f.year
        case .month: return f.month
        case .day: return f.day
        case .hour: return f.hour
        case .minute: return f.minute
        case .second: return f.second
        case .nanosecond: return f.nanosecond
        case .weekday: return f.weekday
        case .weekdayOrdinal: return (f.day - 1) / 7 + 1
        case .quarter: return (f.month - 1) / 3 + 1
        case .weekOfMonth: return math.weekOfMonth(time)
        case .weekOfYear: return math.weekOfYear(time).week
        case .yearForWeekOfYear: return math.weekOfYear(time).year
        case .dayOfYear: return f.dayOfYear
        case .calendar, .timeZone, .isLeapMonth: return 0
        }
    }

    public func dateComponents(_ components: Set<Component>, from date: Date) -> DateComponents {
        var result = DateComponents()
        for component in components {
            switch component {
            case .calendar: result.calendar = self
            case .timeZone: result.timeZone = timeZone
            case .isLeapMonth: result.isLeapMonth = false
            default: result.setValue(self.component(component, from: date), for: component)
            }
        }
        return result
    }

    public func dateComponents(in zone: TimeZone, from date: Date) -> DateComponents {
        var calendar = self
        calendar.timeZone = zone
        var result = calendar.dateComponents(Set(Component.allCases), from: date)
        result.calendar = self
        result.timeZone = zone
        return result
    }

    public func dateComponents(_ components: Set<Component>, from start: Date, to end: Date) -> DateComponents {
        let units = Set(components.compactMap(Self.unit))
        let difference = math.difference(from: start.timeIntervalSince1970, to: end.timeIntervalSince1970, units: units)
        var result = DateComponents()
        for component in components {
            if let unit = Self.unit(component), let value = difference[unit] { result.setValue(value, for: component) }
        }
        return result
    }

    public func dateComponents(_ components: Set<Component>, from start: DateComponents, to end: DateComponents) -> DateComponents {
        guard let a = date(from: start), let b = date(from: end) else { return DateComponents() }
        return dateComponents(components, from: a, to: b)
    }

    /// The date of the components: year, month and day default to 1, the time to midnight;
    /// values past their range carry over. Week and weekday fields are not used.
    public func date(from components: DateComponents) -> Date? {
        let math = math(in: components.timeZone)
        let time = math.time(year: components.year ?? 1, month: components.month ?? 1, day: components.day ?? 1,
                             hour: components.hour ?? 0, minute: components.minute ?? 0, second: components.second ?? 0,
                             nanosecond: components.nanosecond ?? 0)
        return Date(timeIntervalSince1970: time)
    }

    public func date(byAdding component: Component, value: Int, to date: Date, wrappingComponents: Bool = false) -> Date? {
        guard let unit = Self.unit(component) else { return nil }
        return Date(timeIntervalSince1970: math.adding(unit, value, to: date.timeIntervalSince1970))
    }

    public func date(byAdding components: DateComponents, to date: Date, wrappingComponents: Bool = false) -> Date? {
        var time = date.timeIntervalSince1970
        let math = math
        for component in [Component.era, .year, .quarter, .month, .weekOfYear, .weekOfMonth, .day, .hour, .minute, .second, .nanosecond] {
            if let value = components.value(for: component), let unit = Self.unit(component) { time = math.adding(unit, value, to: time) }
        }
        return Date(timeIntervalSince1970: time)
    }

    public func date(bySettingHour hour: Int, minute: Int, second: Int, of date: Date) -> Date? {
        let f = math.fields(date.timeIntervalSince1970)
        return Date(timeIntervalSince1970: math.time(year: f.year, month: f.month, day: f.day, hour: hour, minute: minute, second: second))
    }

    public func date(bySetting component: Component, value: Int, of date: Date) -> Date? {
        var components = dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: date)
        switch component {
        case .year, .month, .day, .hour, .minute, .second, .nanosecond: components.setValue(value, for: component)
        default: return nil
        }
        return self.date(from: components)
    }

    public func range(of smaller: Component, in larger: Component, for date: Date) -> Range<Int>? {
        guard let s = Self.unit(smaller), let l = Self.unit(larger) else { return nil }
        return math.range(of: s, in: l, for: date.timeIntervalSince1970)
    }

    public func startOfDay(for date: Date) -> Date { Date(timeIntervalSince1970: math.startOfDay(date.timeIntervalSince1970)) }

    public func isDate(_ date1: Date, inSameDayAs date2: Date) -> Bool {
        math.split(date1.timeIntervalSince1970).days == math.split(date2.timeIntervalSince1970).days
    }
    public func isDateInToday(_ date: Date) -> Bool { isDate(date, inSameDayAs: Date()) }
    public func isDateInYesterday(_ date: Date) -> Bool { isDate(date, inSameDayAs: Date(timeIntervalSinceNow: -86400)) }
    public func isDateInTomorrow(_ date: Date) -> Bool { isDate(date, inSameDayAs: Date(timeIntervalSinceNow: 86400)) }
    public func isDateInWeekend(_ date: Date) -> Bool {
        let weekday = component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }

    public func compare(_ date1: Date, to date2: Date, toGranularity component: Component) -> ComparisonResult {
        let a = date1.timeIntervalSince1970, b = date2.timeIntervalSince1970
        let math = math
        func key(_ t: Double) -> [Int] {
            let f = math.fields(t)
            switch component {
            case .era: return [f.year > 0 ? 1 : 0]
            case .year: return [f.year]
            case .quarter: return [f.year, (f.month - 1) / 3]
            case .month: return [f.year, f.month]
            case .weekOfYear, .yearForWeekOfYear: let w = math.weekOfYear(t); return [w.year, w.week]
            case .weekOfMonth: return [f.year, f.month, math.weekOfMonth(t)]
            case .day, .weekday, .weekdayOrdinal, .dayOfYear: return [f.year, f.month, f.day]
            case .hour: return [f.year, f.month, f.day, f.hour]
            case .minute: return [f.year, f.month, f.day, f.hour, f.minute]
            case .second: return [f.year, f.month, f.day, f.hour, f.minute, f.second]
            case .nanosecond: return [f.year, f.month, f.day, f.hour, f.minute, f.second, f.nanosecond]
            case .calendar, .timeZone, .isLeapMonth: return []
            }
        }
        let ka = key(a), kb = key(b)
        return ka.lexicographicallyPrecedes(kb) ? .orderedAscending : ka == kb ? .orderedSame : .orderedDescending
    }
    public func isDate(_ date1: Date, equalTo date2: Date, toGranularity component: Component) -> Bool {
        compare(date1, to: date2, toGranularity: component) == .orderedSame
    }

    /// Days and weekdays counted from the start of the larger unit, one-based.
    public func ordinality(of smaller: Component, in larger: Component, for date: Date) -> Int? {
        let f = math.fields(date.timeIntervalSince1970)
        switch (smaller, larger) {
        case (.day, .year): return f.dayOfYear
        case (.day, .month): return f.day
        case (.month, .year): return f.month
        case (.day, .weekOfYear), (.day, .weekOfMonth): return _Gregorian.floorMod(f.weekday - firstWeekday, 7) + 1
        case (.weekday, .month): return (f.day - 1) / 7 + 1
        case (.hour, .day): return f.hour + 1
        case (.minute, .hour): return f.minute + 1
        case (.second, .minute): return f.second + 1
        case (.quarter, .year): return (f.month - 1) / 3 + 1
        default: return nil
        }
    }

    public var monthSymbols: [String] { ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"] }
    public var shortMonthSymbols: [String] { ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"] }
    public var veryShortMonthSymbols: [String] { ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"] }
    public var standaloneMonthSymbols: [String] { monthSymbols }
    public var shortStandaloneMonthSymbols: [String] { shortMonthSymbols }
    public var veryShortStandaloneMonthSymbols: [String] { veryShortMonthSymbols }
    public var weekdaySymbols: [String] { ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"] }
    public var shortWeekdaySymbols: [String] { ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"] }
    public var veryShortWeekdaySymbols: [String] { ["S", "M", "T", "W", "T", "F", "S"] }
    public var standaloneWeekdaySymbols: [String] { weekdaySymbols }
    public var shortStandaloneWeekdaySymbols: [String] { shortWeekdaySymbols }
    public var veryShortStandaloneWeekdaySymbols: [String] { veryShortWeekdaySymbols }
    public var quarterSymbols: [String] { ["1st quarter", "2nd quarter", "3rd quarter", "4th quarter"] }
    public var shortQuarterSymbols: [String] { ["Q1", "Q2", "Q3", "Q4"] }
    public var eraSymbols: [String] { ["BC", "AD"] }
    public var longEraSymbols: [String] { ["Before Christ", "Anno Domini"] }
    public var amSymbol: String { "AM" }
    public var pmSymbol: String { "PM" }

    public var description: String { "gregorian (fixed)" }
}
#endif
