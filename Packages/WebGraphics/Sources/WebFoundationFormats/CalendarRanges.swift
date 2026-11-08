// The ranges a calendar's units can take on the wasm stand-in, the undefined component value,
// and a locale's collator identifier (Docs/coverage.md: SwiftDate, which Clendar builds from
// source, asks for the weekday range to tell weekends and for `NSDateComponentUndefined` to
// clear components). The ranges are the Gregorian calendar's, as Foundation gives them; the
// stand-in's other calendars count their units the same way.
#if os(WASI)
import WebFoundation

/// The value of a date component that isn't set (Foundation's `NSDateComponentUndefined`).
public let NSDateComponentUndefined = Int.max

extension Calendar {
    /// The values `component` takes in every one of its larger units: days 1 to 28, as every
    /// month has them. Nil for the calendar and time zone, which have no values.
    public func minimumRange(of component: Component) -> Range<Int>? {
        switch component {
        case .year, .yearForWeekOfYear: return 1..<140743
        case .day: return 1..<29
        case .weekdayOrdinal: return 1..<5
        case .weekOfMonth: return 1..<5
        case .weekOfYear: return 1..<53
        case .dayOfYear: return 1..<366
        default: return maximumRange(of: component)
        }
    }

    /// The values `component` can take in any of its larger units: days 1 to 31. Nil for the
    /// calendar and time zone, which have no values.
    public func maximumRange(of component: Component) -> Range<Int>? {
        switch component {
        case .era, .isLeapMonth: return 0..<2
        case .year, .yearForWeekOfYear: return 1..<144684
        case .month: return 1..<13
        case .day: return 1..<32
        case .hour: return 0..<24
        case .minute, .second: return 0..<60
        case .weekday: return 1..<8
        case .weekdayOrdinal: return 1..<6
        case .quarter: return 1..<5
        case .weekOfMonth: return 1..<7
        case .weekOfYear: return 1..<54
        case .nanosecond: return 0..<1_000_000_000
        case .dayOfYear: return 1..<367
        case .calendar, .timeZone: return nil
        }
    }
}

extension Locale {
    /// The identifier of the locale's string collation: the locale's own, as the stand-in
    /// compares strings the same way in every locale.
    public var collatorIdentifier: String? { identifier }
}
#endif
