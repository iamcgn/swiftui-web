// More of Foundation's formatting on wasm (decision 0017): list formatting
// (`["a", "b"].formatted()`), `Duration`'s time and units styles, `DateComponentsFormatter`
// with `NSCalendar.Unit`, `Locale.Language` and its parts, and the app group container. English
// output, as the other stand-ins; held to Foundation's output on macOS and Linux by the root
// package's FrameworkTests.
//
// A module of its own, which `import Foundation` (Packages/Shadows) re-exports and `import
// SwiftUI` does not: on wasm a type's protocol conformances keep its code in every bundle that
// links its module, used or not, and these are ~100 KB that an app with no `import Foundation`
// (Counter) would ship (decision 0006's budget). `Decimal.FormatStyle` is in WebDecimalFormats:
// naming `Decimal` links Foundation's Decimal and what it reaches (3.4 MB, AttributedString and
// the collections among them) into every app that links the module that names it.
#if os(WASI)
import WebFoundation

// MARK: - Lists

/// The style that formats each string of a list as itself.
public struct StringStyle: FormatStyle, Hashable, Sendable {
    public init() {}
    public func format(_ value: String) -> String { value }
}

/// A type that formats lists of items with a separator and conjunction ("a, b, and c").
public struct ListFormatStyle<Style: FormatStyle, Base: Sequence>: FormatStyle where Style.FormatInput == Base.Element, Style.FormatOutput == String {
    /// Whether the list joins its items with "and" or "or".
    public enum ListType: Int, Codable, Hashable, Sendable { case and, or }
    /// How much the separators are shortened.
    public enum Width: Int, Codable, Hashable, Sendable { case standard, short, narrow }

    public var width: Width = .standard
    public var listType: ListType = .and
    public var locale: Locale = .current
    private let memberStyle: Style

    public init(memberStyle: Style) { self.memberStyle = memberStyle }

    public func format(_ value: Base) -> String {
        let items = value.map { memberStyle.format($0) }
        let word: String
        switch (listType, width) {
        case (.or, _): word = "or"
        case (.and, .standard): word = "and"
        case (.and, .short): word = "&"
        case (.and, .narrow): word = ""
        }
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return word.isEmpty ? "\(items[0]), \(items[1])" : "\(items[0]) \(word) \(items[1])"
        default:
            let head = items.dropLast().joined(separator: ", ")
            return word.isEmpty ? "\(head), \(items[items.count - 1])" : "\(head), \(word) \(items[items.count - 1])"
        }
    }

    public func locale(_ locale: Locale) -> Self { var copy = self; copy.locale = locale; return copy }
}

extension FormatStyle {
    /// A list whose items are formatted with `memberStyle`.
    public static func list<MemberStyle, Base>(memberStyle: MemberStyle, type: ListFormatStyle<MemberStyle, Base>.ListType,
                                               width: ListFormatStyle<MemberStyle, Base>.Width = .standard) -> Self where Self == ListFormatStyle<MemberStyle, Base> {
        var style = ListFormatStyle<MemberStyle, Base>(memberStyle: memberStyle)
        style.listType = type
        style.width = width
        return style
    }

    /// A list of strings.
    public static func list<Base>(type: ListFormatStyle<StringStyle, Base>.ListType,
                                  width: ListFormatStyle<StringStyle, Base>.Width = .standard) -> Self where Self == ListFormatStyle<StringStyle, Base>, Base: Sequence, Base.Element == String {
        var style = ListFormatStyle<StringStyle, Base>(memberStyle: StringStyle())
        style.listType = type
        style.width = width
        return style
    }
}

extension Sequence {
    /// The sequence formatted by `style`.
    public func formatted<S: FormatStyle>(_ style: S) -> S.FormatOutput where S.FormatInput == Self { style.format(self) }
}

extension Sequence where Element == String {
    /// The strings as a list joined with "and" ("a, b, and c").
    public func formatted() -> String { ListFormatStyle<StringStyle, Self>(memberStyle: StringStyle()).format(self) }
}

// MARK: - Duration

extension Duration {
    /// The duration in seconds, as a `Double`.
    fileprivate var _seconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1e18
    }

    /// A clock-style format: "1:05:05", "1:05", "65:05".
    public struct TimeFormatStyle: FormatStyle, Hashable, Sendable {
        /// Which fields the duration shows.
        public struct Pattern: Hashable, Sendable {
            enum Fields: Int, Hashable, Sendable { case hourMinute, hourMinuteSecond, minuteSecond }
            let fields: Fields
            let padFirstToLength: Int
            let fractionalSecondsLength: Int

            public static var hourMinute: Pattern { Pattern(fields: .hourMinute, padFirstToLength: 1, fractionalSecondsLength: 0) }
            public static var hourMinuteSecond: Pattern { Pattern(fields: .hourMinuteSecond, padFirstToLength: 1, fractionalSecondsLength: 0) }
            public static var minuteSecond: Pattern { Pattern(fields: .minuteSecond, padFirstToLength: 1, fractionalSecondsLength: 0) }

            public static func hourMinute(padHourToLength: Int, roundSeconds: FloatingPointRoundingRule = .toNearestOrEven) -> Pattern {
                Pattern(fields: .hourMinute, padFirstToLength: padHourToLength, fractionalSecondsLength: 0)
            }
            public static func hourMinuteSecond(padHourToLength: Int, fractionalSecondsLength: Int = 0,
                                                roundFractionalSeconds: FloatingPointRoundingRule = .toNearestOrEven) -> Pattern {
                Pattern(fields: .hourMinuteSecond, padFirstToLength: padHourToLength, fractionalSecondsLength: fractionalSecondsLength)
            }
            public static func minuteSecond(padMinuteToLength: Int, fractionalSecondsLength: Int = 0,
                                            roundFractionalSeconds: FloatingPointRoundingRule = .toNearestOrEven) -> Pattern {
                Pattern(fields: .minuteSecond, padFirstToLength: padMinuteToLength, fractionalSecondsLength: fractionalSecondsLength)
            }
        }

        public var pattern: Pattern
        public var locale: Locale = .current

        public init(pattern: Pattern, locale: Locale = .current) {
            self.pattern = pattern
            self.locale = locale
        }

        public func locale(_ locale: Locale) -> Self { var copy = self; copy.locale = locale; return copy }

        public func format(_ value: Duration) -> String {
            let total = value._seconds
            let sign = total < 0 ? "-" : ""
            let magnitude = abs(total)
            func padded(_ n: Int, _ length: Int) -> String {
                let text = String(n)
                return String(repeating: "0", count: max(0, length - text.count)) + text
            }
            func seconds(_ s: Double) -> String {
                let digits = pattern.fractionalSecondsLength
                guard digits > 0 else { return padded(Int(s), 2) }
                let scale = (0..<digits).reduce(1.0) { value, _ in value * 10 }
                let units = Int((s * scale).rounded(.toNearestOrEven))
                return padded(units / Int(scale), 2) + "." + padded(units % Int(scale), digits)
            }
            switch pattern.fields {
            case .hourMinute:
                let minutes = Int((magnitude / 60).rounded(.toNearestOrEven))
                return sign + padded(minutes / 60, pattern.padFirstToLength) + ":" + padded(minutes % 60, 2)
            case .hourMinuteSecond:
                let rounded = pattern.fractionalSecondsLength > 0 ? magnitude : magnitude.rounded(.toNearestOrEven)
                let whole = Int(rounded)
                let s = rounded - Double(whole / 60 * 60)
                return sign + padded(whole / 3600, pattern.padFirstToLength) + ":" + padded(whole / 60 % 60, 2) + ":" + seconds(s)
            case .minuteSecond:
                let rounded = pattern.fractionalSecondsLength > 0 ? magnitude : magnitude.rounded(.toNearestOrEven)
                let whole = Int(rounded)
                let s = rounded - Double(whole / 60 * 60)
                return sign + padded(whole / 60, pattern.padFirstToLength) + ":" + seconds(s)
            }
        }
    }

    /// A units format: "3 hr, 5 min", "3h 5m", "3 hours, 5 minutes".
    public struct UnitsFormatStyle: FormatStyle, Hashable, Sendable {
        /// A unit a duration can be shown in.
        public struct Unit: Hashable, Sendable {
            let seconds: Double
            let narrow: String
            let abbreviated: (String, String)
            let wide: (String, String)

            public static var weeks: Unit { Unit(seconds: 604_800, narrow: "w", abbreviated: ("wk", "wks"), wide: ("week", "weeks")) }
            public static var days: Unit { Unit(seconds: 86_400, narrow: "d", abbreviated: ("day", "days"), wide: ("day", "days")) }
            public static var hours: Unit { Unit(seconds: 3_600, narrow: "h", abbreviated: ("hr", "hr"), wide: ("hour", "hours")) }
            public static var minutes: Unit { Unit(seconds: 60, narrow: "m", abbreviated: ("min", "min"), wide: ("minute", "minutes")) }
            public static var seconds: Unit { Unit(seconds: 1, narrow: "s", abbreviated: ("sec", "sec"), wide: ("second", "seconds")) }
            public static var milliseconds: Unit { Unit(seconds: 0.001, narrow: "ms", abbreviated: ("ms", "ms"), wide: ("millisecond", "milliseconds")) }

            public static func == (lhs: Unit, rhs: Unit) -> Bool { lhs.seconds == rhs.seconds }
            public func hash(into hasher: inout Hasher) { hasher.combine(seconds) }

            private init(seconds: Double, narrow: String, abbreviated: (String, String), wide: (String, String)) {
                self.seconds = seconds
                self.narrow = narrow
                self.abbreviated = abbreviated
                self.wide = wide
            }
        }

        /// How long the unit names are.
        public struct UnitWidth: Hashable, Sendable {
            enum Kind: Int, Hashable, Sendable { case wide, abbreviated, condensedAbbreviated, narrow }
            let kind: Kind
            public static var wide: UnitWidth { UnitWidth(kind: .wide) }
            public static var abbreviated: UnitWidth { UnitWidth(kind: .abbreviated) }
            public static var condensedAbbreviated: UnitWidth { UnitWidth(kind: .condensedAbbreviated) }
            public static var narrow: UnitWidth { UnitWidth(kind: .narrow) }
        }

        /// Whether units whose value is zero are shown.
        public struct ZeroValueUnitsDisplayStrategy: Hashable, Sendable {
            let length: Int?
            public static var hide: ZeroValueUnitsDisplayStrategy { ZeroValueUnitsDisplayStrategy(length: nil) }
            public static func show(length: Int) -> ZeroValueUnitsDisplayStrategy { ZeroValueUnitsDisplayStrategy(length: length) }
        }

        /// Whether the smallest unit shows a fraction (hidden: the value is rounded).
        public struct FractionalPartDisplayStrategy: Hashable, Sendable {
            let length: Int
            public static var hide: FractionalPartDisplayStrategy { FractionalPartDisplayStrategy(length: 0) }
            public static func show(length: Int, rounded rule: FloatingPointRoundingRule = .toNearestOrEven, increment: Double? = nil) -> FractionalPartDisplayStrategy {
                FractionalPartDisplayStrategy(length: length)
            }
        }

        public var allowedUnits: Set<Unit>
        public var unitWidth: UnitWidth
        public var maximumUnitCount: Int?
        public var zeroValueUnitsDisplay: ZeroValueUnitsDisplayStrategy
        public var valueLengthLimits: Range<Int>?
        public var fractionalPartDisplay: FractionalPartDisplayStrategy
        public var locale: Locale = .current

        public init(allowedUnits: Set<Unit>, width: UnitWidth, maximumUnitCount: Int? = nil, zeroValueUnits: ZeroValueUnitsDisplayStrategy = .hide,
                    valueLength: Int? = nil, fractionalPart: FractionalPartDisplayStrategy = .hide) {
            self.allowedUnits = allowedUnits
            self.unitWidth = width
            self.maximumUnitCount = maximumUnitCount
            self.zeroValueUnitsDisplay = zeroValueUnits
            self.valueLengthLimits = valueLength.map { $0..<Int.max }
            self.fractionalPartDisplay = fractionalPart
        }

        public func locale(_ locale: Locale) -> Self { var copy = self; copy.locale = locale; return copy }

        public func format(_ value: Duration) -> String {
            let units = allowedUnits.sorted { $0.seconds > $1.seconds }
            guard let smallest = units.last else { return "" }
            let total = value._seconds
            // Whole units from the largest down; the smallest takes the rounded rest.
            var rest = abs(total)
            var values: [(Unit, Double)] = []
            for unit in units {
                if unit == smallest {
                    let count = rest / unit.seconds
                    let scale = (0..<fractionalPartDisplay.length).reduce(1.0) { value, _ in value * 10 }
                    values.append((unit, (count * scale).rounded(.toNearestOrEven) / scale))
                } else {
                    let count = (rest / unit.seconds).rounded(.towardZero)
                    values.append((unit, count))
                    rest -= count * unit.seconds
                }
            }
            var shown = zeroValueUnitsDisplay.length == nil ? values.filter { $0.1 != 0 } : values
            if shown.isEmpty { shown = [(smallest, 0)] }
            if let maximum = maximumUnitCount, shown.count > maximum { shown = Array(shown.prefix(maximum)) }
            let parts = shown.map { unit, count -> String in
                let number = fractionalPartDisplay.length > 0 ? _fixed(count, fraction: fractionalPartDisplay.length) : String(Int(count))
                let padded = zeroValueUnitsDisplay.length.map { String(repeating: "0", count: max(0, $0 - number.count)) + number } ?? number
                switch unitWidth.kind {
                case .narrow: return padded + unit.narrow
                case .abbreviated, .condensedAbbreviated: return padded + " " + (count == 1 ? unit.abbreviated.0 : unit.abbreviated.1)
                case .wide: return padded + " " + (count == 1 ? unit.wide.0 : unit.wide.1)
                }
            }
            let sign = total < 0 ? "-" : ""
            switch unitWidth.kind {
            case .narrow, .condensedAbbreviated: return sign + parts.joined(separator: " ")
            case .abbreviated, .wide: return sign + parts.joined(separator: ", ")
            }
        }
    }

    /// The duration formatted by `style`.
    public func formatted<S: FormatStyle>(_ style: S) -> S.FormatOutput where S.FormatInput == Duration { style.format(self) }
    /// The duration as hours, minutes and seconds ("1:05:05").
    public func formatted() -> String { TimeFormatStyle(pattern: .hourMinuteSecond).format(self) }
}

/// `value` with exactly `fraction` digits after the point.
private func _fixed(_ value: Double, fraction: Int) -> String {
    let scale = (0..<fraction).reduce(1.0) { value, _ in value * 10 }
    let units = Int((abs(value) * scale).rounded(.toNearestOrEven))
    let digits = String(units % Int(scale))
    return (value < 0 ? "-" : "") + String(units / Int(scale)) + "." + String(repeating: "0", count: max(0, fraction - digits.count)) + digits
}

extension FormatStyle where Self == Duration.TimeFormatStyle {
    public static func time(pattern: Duration.TimeFormatStyle.Pattern) -> Duration.TimeFormatStyle { Duration.TimeFormatStyle(pattern: pattern) }
}

extension FormatStyle where Self == Duration.UnitsFormatStyle {
    public static func units(allowed units: Set<Duration.UnitsFormatStyle.Unit> = [.hours, .minutes, .seconds],
                             width: Duration.UnitsFormatStyle.UnitWidth = .abbreviated, maximumUnitCount: Int? = nil,
                             zeroValueUnits: Duration.UnitsFormatStyle.ZeroValueUnitsDisplayStrategy = .hide, valueLength: Int? = nil,
                             fractionalPart: Duration.UnitsFormatStyle.FractionalPartDisplayStrategy = .hide) -> Duration.UnitsFormatStyle {
        Duration.UnitsFormatStyle(allowedUnits: units, width: width, maximumUnitCount: maximumUnitCount, zeroValueUnits: zeroValueUnits,
                                  valueLength: valueLength, fractionalPart: fractionalPart)
    }
}

// MARK: - DateComponentsFormatter

/// Foundation's `NSCalendar`, for its unit set (`DateComponentsFormatter.allowedUnits`).
open class NSCalendar {
    public struct Unit: OptionSet, Hashable, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let era = Unit(rawValue: 1 << 1)
        public static let year = Unit(rawValue: 1 << 2)
        public static let month = Unit(rawValue: 1 << 3)
        public static let day = Unit(rawValue: 1 << 4)
        public static let hour = Unit(rawValue: 1 << 5)
        public static let minute = Unit(rawValue: 1 << 6)
        public static let second = Unit(rawValue: 1 << 7)
        public static let weekday = Unit(rawValue: 1 << 9)
        public static let weekdayOrdinal = Unit(rawValue: 1 << 10)
        public static let quarter = Unit(rawValue: 1 << 11)
        public static let weekOfMonth = Unit(rawValue: 1 << 12)
        public static let weekOfYear = Unit(rawValue: 1 << 13)
        public static let yearForWeekOfYear = Unit(rawValue: 1 << 14)
        public static let nanosecond = Unit(rawValue: 1 << 15)
        public static let calendar = Unit(rawValue: 1 << 20)
        public static let timeZone = Unit(rawValue: 1 << 21)
    }

    public init() {}
}

/// Formats an amount of time ("1h 5m", "1:05:03", "1 hour, 5 minutes").
open class DateComponentsFormatter: Formatter {
    public enum UnitsStyle: Int, Sendable { case positional = 0, abbreviated, short, full, spellOut, brief }

    public struct ZeroFormattingBehavior: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let none = ZeroFormattingBehavior([])
        public static let `default` = ZeroFormattingBehavior(rawValue: 1 << 0)
        public static let dropLeading = ZeroFormattingBehavior(rawValue: 1 << 1)
        public static let dropMiddle = ZeroFormattingBehavior(rawValue: 1 << 2)
        public static let dropTrailing = ZeroFormattingBehavior(rawValue: 1 << 3)
        public static let dropAll: ZeroFormattingBehavior = [.dropLeading, .dropMiddle, .dropTrailing]
        public static let pad = ZeroFormattingBehavior(rawValue: 1 << 16)
    }

    open var unitsStyle: UnitsStyle = .positional
    open var allowedUnits: NSCalendar.Unit = [.year, .month, .weekOfMonth, .day, .hour, .minute, .second]
    open var zeroFormattingBehavior: ZeroFormattingBehavior = .default
    open var maximumUnitCount = 0
    open var calendar: Calendar? = Calendar(identifier: .gregorian)
    open var referenceDate: Date?
    open var allowsFractionalUnits = false
    open var collapsesLargestUnit = false
    open var includesApproximationPhrase = false
    open var includesTimeRemainingPhrase = false

    public override init() { super.init() }

    /// The interval in the allowed units.
    open func string(from ti: TimeInterval) -> String? {
        guard ti.isFinite else { return nil }
        var rest = abs(ti).rounded(.toNearestOrEven)
        var values: [(NSCalendar.Unit, Int)] = []
        for (unit, seconds) in Self.lengths where allowedUnits.contains(unit) {
            let count = Int(rest / seconds)
            values.append((unit, count))
            rest -= Double(count) * seconds
        }
        return render(values, negative: ti < 0)
    }

    /// The components in the allowed units, as given (no carrying between units).
    open func string(from components: DateComponents) -> String? {
        var values: [(NSCalendar.Unit, Int)] = []
        let given: [NSCalendar.Unit: Int?] = [.year: components.year, .month: components.month, .weekOfMonth: components.weekOfMonth,
                                              .day: components.day, .hour: components.hour, .minute: components.minute, .second: components.second]
        for (unit, _) in Self.lengths where allowedUnits.contains(unit) {
            values.append((unit, (given[unit] ?? nil) ?? 0))
        }
        let negative = values.contains { $0.1 < 0 }
        return render(values.map { ($0.0, abs($0.1)) }, negative: negative)
    }

    /// The time between two dates.
    open func string(from startDate: Date, to endDate: Date) -> String? { string(from: endDate.timeIntervalSince(startDate)) }

    open override func string(for obj: Any?) -> String? {
        switch obj {
        case let interval as TimeInterval: return string(from: interval)
        case let components as DateComponents: return string(from: components)
        default: return nil
        }
    }

    /// The components formatted in `unitsStyle`.
    open class func localizedString(from components: DateComponents, unitsStyle: UnitsStyle) -> String? {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = unitsStyle
        return formatter.string(from: components)
    }

    /// Each unit and its length in seconds, largest first (months and years at their average).
    private static let lengths: [(NSCalendar.Unit, Double)] = [
        (.year, 31_556_952), (.month, 2_629_746), (.weekOfMonth, 604_800), (.day, 86_400), (.hour, 3_600), (.minute, 60), (.second, 1),
    ]

    private func render(_ all: [(NSCalendar.Unit, Int)], negative: Bool) -> String? {
        guard !all.isEmpty else { return nil }
        var behavior = zeroFormattingBehavior
        if behavior.contains(.default) { behavior = unitsStyle == .positional ? .dropLeading : .dropAll }
        var values = all
        if behavior.contains(.pad) && unitsStyle == .positional {
            // Positional padding keeps every unit.
        } else {
            if behavior.contains(.dropLeading) { while values.count > 1, values[0].1 == 0 { values.removeFirst() } }
            if behavior.contains(.dropTrailing) { while values.count > 1, values[values.count - 1].1 == 0 { values.removeLast() } }
            if behavior.contains(.dropMiddle), values.count > 2 {
                values = [values[0]] + values.dropFirst().dropLast().filter { $0.1 != 0 } + [values[values.count - 1]]
            }
            if behavior == .dropAll, values.allSatisfy({ $0.1 == 0 }) { values = [all[all.count - 1]] }
        }
        if maximumUnitCount > 0, values.count > maximumUnitCount { values = Array(values.prefix(maximumUnitCount)) }
        let sign = negative ? "-" : ""
        if unitsStyle == .positional {
            let fields = values.enumerated().map { index, value -> String in
                let text = String(value.1)
                return index == 0 && !behavior.contains(.pad) ? text : String(repeating: "0", count: max(0, 2 - text.count)) + text
            }
            return sign + fields.joined(separator: ":")
        }
        let parts = values.map { unit, count in Self.name(unit, count, unitsStyle) }
        switch unitsStyle {
        case .abbreviated, .brief: return sign + parts.joined(separator: " ")
        default: return sign + parts.joined(separator: ", ")
        }
    }

    private static func name(_ unit: NSCalendar.Unit, _ count: Int, _ style: UnitsStyle) -> String {
        let one = count == 1
        let (narrow, short, brief, full): (String, String, String, String) = switch unit {
        case .year: ("y", one ? "yr" : "yrs", one ? "yr" : "yrs", one ? "year" : "years")
        case .month: ("mo", one ? "mth" : "mths", one ? "mth" : "mths", one ? "month" : "months")
        case .weekOfMonth: ("w", one ? "wk" : "wks", one ? "wk" : "wks", one ? "week" : "weeks")
        case .day: ("d", one ? "day" : "days", one ? "day" : "days", one ? "day" : "days")
        case .hour: ("h", "hr", "hr", one ? "hour" : "hours")
        case .minute: ("m", "min", "min", one ? "minute" : "minutes")
        default: ("s", "sec", "sec", one ? "second" : "seconds")
        }
        switch style {
        case .abbreviated: return "\(count)\(narrow)"
        case .brief: return "\(count)\(brief)"
        case .short: return "\(count) \(short)"
        default: return "\(count) \(full)"
        }
    }
}

// MARK: - Locale's language

extension Locale {
    /// A language code ("en").
    public struct LanguageCode: Hashable, Sendable, Codable, ExpressibleByStringLiteral, CustomStringConvertible, CustomDebugStringConvertible {
        public let identifier: String
        public init(_ identifier: String) { self.identifier = identifier }
        public init(stringLiteral value: String) { self.identifier = value }
        public var description: String { identifier }
        public var debugDescription: String { identifier }
        public var isISOLanguage: Bool { (2...3).contains(identifier.count) && identifier.allSatisfy(\.isLetter) }
        public static let english = LanguageCode("en")
        public static let chinese = LanguageCode("zh")
        public static let japanese = LanguageCode("ja")
        public static let korean = LanguageCode("ko")
        public static let french = LanguageCode("fr")
        public static let german = LanguageCode("de")
        public static let spanish = LanguageCode("es")
        public static let italian = LanguageCode("it")
        public static let portuguese = LanguageCode("pt")
        public static let russian = LanguageCode("ru")
        public static let arabic = LanguageCode("ar")
        public static let hindi = LanguageCode("hi")
        public static let dutch = LanguageCode("nl")
    }

    /// A region code ("US").
    public struct Region: Hashable, Sendable, Codable, ExpressibleByStringLiteral, CustomStringConvertible, CustomDebugStringConvertible {
        public let identifier: String
        public init(_ identifier: String) { self.identifier = identifier }
        public init(stringLiteral value: String) { self.identifier = value }
        public var description: String { identifier }
        public var debugDescription: String { identifier }
        public var isISORegion: Bool { identifier.count == 2 && identifier.allSatisfy(\.isLetter) || identifier.count == 3 && identifier.allSatisfy(\.isNumber) }
        public static let unitedStates = Region("US")
        public static let unitedKingdom = Region("GB")
        public static let china = Region("CN")
        public static let japan = Region("JP")
        public static let germany = Region("DE")
        public static let france = Region("FR")
    }

    /// A script code ("Hans").
    public struct Script: Hashable, Sendable, Codable, ExpressibleByStringLiteral, CustomStringConvertible, CustomDebugStringConvertible {
        public let identifier: String
        public init(_ identifier: String) { self.identifier = identifier }
        public init(stringLiteral value: String) { self.identifier = value }
        public var description: String { identifier }
        public var debugDescription: String { identifier }
        public static let latin = Script("Latn")
        public static let hanSimplified = Script("Hans")
        public static let hanTraditional = Script("Hant")
        public static let cyrillic = Script("Cyrl")
        public static let arabic = Script("Arab")
        public static let japanese = Script("Jpan")
    }

    /// A language with its script and region ("zh-Hans-CN").
    public struct Language: Hashable, Sendable, Codable {
        public var languageCode: LanguageCode?
        public var script: Script?
        public var region: Region?

        public init(identifier: String) {
            let locale = Locale(identifier: identifier)
            self.init(languageCode: locale.languageCode.map { LanguageCode($0) }, script: locale.scriptCode.map { Script($0) }, region: locale.regionCode.map { Region($0) })
        }

        public init(languageCode: LanguageCode? = nil, script: Script? = nil, region: Region? = nil) {
            self.languageCode = languageCode
            self.script = script
            self.region = region
        }

        public init(components: Components) {
            self.init(languageCode: components.languageCode, script: components.script, region: components.region)
        }

        /// The language's parts, as given ("zh-Hans-CN").
        public var minimalIdentifier: String { [languageCode?.identifier, script?.identifier, region?.identifier].compactMap { $0 }.joined(separator: "-") }
        public var maximalIdentifier: String { minimalIdentifier }
        public var components: Components { Components(languageCode: languageCode, script: script, region: region) }
        /// The language's parent: none is known here.
        public var parent: Language? { nil }
        public func hasCommonParent(with language: Language) -> Bool { languageCode == language.languageCode }
        public func isEquivalent(to language: Language) -> Bool { self == language }

        /// The language, script and region a language is made of.
        public struct Components: Hashable, Sendable, Codable {
            public var languageCode: LanguageCode?
            public var script: Script?
            public var region: Region?
            public init(languageCode: LanguageCode? = nil, script: Script? = nil, region: Region? = nil) {
                self.languageCode = languageCode
                self.script = script
                self.region = region
            }
            public init(identifier: String) {
                let language = Language(identifier: identifier)
                self.init(languageCode: language.languageCode, script: language.script, region: language.region)
            }
        }
    }

    /// The locale's language, with its script and region.
    public var language: Language { Language(identifier: identifier) }
    /// The locale's region.
    public var region: Region? { regionCode.map { Region($0) } }
}

// MARK: - App group containers

extension FileManager {
    /// The app group's shared container: a folder of its own in the page's files.
    public func containerURL(forSecurityApplicationGroupIdentifier groupIdentifier: String) -> URL? {
        URL(fileURLWithPath: "/Library/Group Containers/\(groupIdentifier)/", isDirectory: true)
    }
}

#endif
