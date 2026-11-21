// Foundation's measurement formatting on wasm (decision 0017): `Measurement.FormatStyle`
// (`.measurement(width:usage:numberFormatStyle:)`, `measurement.formatted()`), its attributed
// form with the `measurement` attribute on the value and unit runs, and `MeasurementFormatter`
// (CriticalMaps' distances, OscarWeather's unit symbols and stats, Mlem's response times).
// English unit names in the three widths; a usage other than `.asProvided` converts lengths,
// temperatures, speeds, masses and volumes to the locale's measurement system as CLDR's
// preferences do (the United States, Liberia and Myanmar customary, the United Kingdom miles
// and miles per hour, everywhere else metric), other dimensions stay as given. Held to
// Foundation's output on macOS and Linux by the root package's FrameworkTests.
//
// Here and not in WebFoundation for the reason MoreFormats.swift gives: an app that never
// imports Foundation (Counter) ships none of it.
#if os(WASI)
import WebFoundation

// MARK: - Names

/// A unit's English names: narrow, abbreviated, and wide singular and plural.
private struct _UnitNames {
    let narrow: String
    let abbreviated: String
    let one: String
    let other: String
    /// Whether the symbol follows the number without a space at this width ("20°C").
    let narrowJoined: Bool
    let abbreviatedJoined: Bool

    init(_ narrow: String, _ abbreviated: String, _ one: String, _ other: String,
         narrowJoined: Bool = true, abbreviatedJoined: Bool = false) {
        self.narrow = narrow; self.abbreviated = abbreviated; self.one = one; self.other = other
        self.narrowJoined = narrowJoined; self.abbreviatedJoined = abbreviatedJoined
    }

    /// CLDR's English names, by Foundation's unit symbol.
    static let table: [String: _UnitNames] = [
        // Length
        "Mm": .init("Mm", "Mm", "megameter", "megameters"),
        "km": .init("km", "km", "kilometer", "kilometers"),
        "hm": .init("hm", "hm", "hectometer", "hectometers"),
        "dam": .init("dam", "dam", "decameter", "decameters"),
        "m": .init("m", "m", "meter", "meters"),
        "dm": .init("dm", "dm", "decimeter", "decimeters"),
        "cm": .init("cm", "cm", "centimeter", "centimeters"),
        "mm": .init("mm", "mm", "millimeter", "millimeters"),
        "µm": .init("μm", "μm", "micrometer", "micrometers"),
        "nm": .init("nm", "nm", "nanometer", "nanometers"),
        "pm": .init("pm", "pm", "picometer", "picometers"),
        "in": .init("″", "in", "inch", "inches"),
        "ft": .init("′", "ft", "foot", "feet"),
        "yd": .init("yd", "yd", "yard", "yards"),
        "mi": .init("mi", "mi", "mile", "miles"),
        "smi": .init("smi", "smi", "mile-scandinavian", "miles-scandinavian"),
        "ly": .init("ly", "ly", "light year", "light years"),
        "NM": .init("nmi", "nmi", "nautical mile", "nautical miles"),
        "ftm": .init("fth", "fth", "fathom", "fathoms"),
        "fur": .init("fur", "fur", "furlong", "furlongs"),
        "ua": .init("au", "au", "astronomical unit", "astronomical units"),
        "pc": .init("pc", "pc", "parsec", "parsecs"),
        // Mass
        "kg": .init("kg", "kg", "kilogram", "kilograms"),
        "g": .init("g", "g", "gram", "grams"),
        "mg": .init("mg", "mg", "milligram", "milligrams"),
        "µg": .init("μg", "μg", "microgram", "micrograms"),
        "oz": .init("oz", "oz", "ounce", "ounces"),
        "lb": .init("lb", "lb", "pound", "pounds"),
        "st": .init("st", "st", "stone", "stones"),
        "t": .init("t", "t", "metric ton", "metric tons"),
        "ton": .init("tn", "tn", "ton", "tons"),
        "ct": .init("CD", "CD", "carat", "carats"),
        // Speed
        "m/s": .init("m/s", "m/s", "meter per second", "meters per second"),
        "km/h": .init("km/h", "km/h", "kilometer per hour", "kilometers per hour"),
        "mph": .init("mph", "mph", "mile per hour", "miles per hour"),
        "kn": .init("kn", "kn", "knot", "knots"),
        // Temperature
        "K": .init("K", "K", "kelvin", "kelvins"),
        "°C": .init("°C", "°C", "degree Celsius", "degrees Celsius", abbreviatedJoined: true),
        "°F": .init("°", "°F", "degree Fahrenheit", "degrees Fahrenheit", abbreviatedJoined: true),
        // Duration
        "hr": .init("h", "hr", "hour", "hours"),
        "min": .init("m", "min", "minute", "minutes"),
        "s": .init("s", "sec", "second", "seconds"),
        "ms": .init("ms", "ms", "millisecond", "milliseconds"),
        "µs": .init("μs", "μs", "microsecond", "microseconds"),
        "ns": .init("ns", "ns", "nanosecond", "nanoseconds"),
        // Pressure
        "kPa": .init("kPa", "kPa", "kilopascal", "kilopascals"),
        "hPa": .init("hPa", "hPa", "hectopascal", "hectopascals"),
        "inHg": .init("″ Hg", "inHg", "inch of mercury", "inches of mercury"),
        "bar": .init("bar", "bar", "bar", "bars"),
        "mbar": .init("mb", "mbar", "millibar", "millibars"),
        "mmHg": .init("mmHg", "mmHg", "millimeter of mercury", "millimeters of mercury"),
        "psi": .init("psi", "psi", "pound-force per square inch", "pounds-force per square inch"),
        // Area
        "km²": .init("km²", "km²", "square kilometer", "square kilometers"),
        "m²": .init("m²", "m²", "square meter", "square meters"),
        "cm²": .init("cm²", "cm²", "square centimeter", "square centimeters"),
        "mi²": .init("mi²", "mi²", "square mile", "square miles"),
        "ft²": .init("ft²", "ft²", "square foot", "square feet"),
        "ac": .init("ac", "ac", "acre", "acres"),
        "ha": .init("ha", "ha", "hectare", "hectares"),
        // Volume
        "L": .init("L", "L", "liter", "liters"),
        "dL": .init("dL", "dL", "deciliter", "deciliters"),
        "cL": .init("cL", "cL", "centiliter", "centiliters"),
        "mL": .init("mL", "mL", "milliliter", "milliliters"),
        "m³": .init("m³", "m³", "cubic meter", "cubic meters"),
        "gal": .init("gal", "gal", "gallon", "gallons"),
        "qt": .init("qt", "qt", "quart", "quarts"),
        "pt": .init("pt", "pt", "pint", "pints"),
        "cup": .init("c", "c", "cup", "cups"),
        "fl oz": .init("fl oz", "fl oz", "fluid ounce", "fluid ounces"),
        "tbsp": .init("tbsp", "tbsp", "tablespoon", "tablespoons"),
        "tsp": .init("tsp", "tsp", "teaspoon", "teaspoons"),
        // Angle, energy, power, frequency, storage
        "°": .init("°", "deg", "degree", "degrees"),
        "rad": .init("rad", "rad", "radian", "radians"),
        "kJ": .init("kJ", "kJ", "kilojoule", "kilojoules"),
        "J": .init("J", "J", "joule", "joules"),
        "kCal": .init("kcal", "kcal", "kilocalorie", "kilocalories"),
        "cal": .init("cal", "cal", "calorie", "calories"),
        "kWh": .init("kWh", "kWh", "kilowatt-hour", "kilowatt-hours"),
        "kW": .init("kW", "kW", "kilowatt", "kilowatts"),
        "W": .init("W", "W", "watt", "watts"),
        "hp": .init("hp", "hp", "horsepower", "horsepower"),
        "Hz": .init("Hz", "Hz", "hertz", "hertz"),
        "kHz": .init("kHz", "kHz", "kilohertz", "kilohertz"),
        "MHz": .init("MHz", "MHz", "megahertz", "megahertz"),
        "GHz": .init("GHz", "GHz", "gigahertz", "gigahertz"),
        "B": .init("B", "byte", "byte", "bytes"),
        "kB": .init("kB", "kB", "kilobyte", "kilobytes"),
        "MB": .init("MB", "MB", "megabyte", "megabytes"),
        "GB": .init("GB", "GB", "gigabyte", "gigabytes"),
        "TB": .init("TB", "TB", "terabyte", "terabytes"),
    ]
}

/// The parts of a formatted measurement, for its attributed form.
private struct _MeasurementParts {
    let number: String
    let unit: String
    /// What goes between the number and the unit ("" or " ").
    let separator: String
    var string: String { number + separator + unit }
}

/// The locale's measurement system, as CLDR's unit preferences read it.
private enum _MeasurementSystem {
    case metric, us, uk

    init(_ locale: Locale) {
        switch locale.regionCode {
        case "US", "LR", "MM": self = .us
        case "GB": self = .uk
        default: self = .metric
        }
    }
}

// MARK: - Usage

/// What a measurement is for, which picks the unit it is shown in.
public struct MeasurementFormatUnitUsage<UnitType: Dimension>: Codable, Hashable, Sendable {
    package enum Kind: String, Codable, Hashable, Sendable {
        case general, asProvided, person, personHeight, road, focalLength, rainfall, snowfall, weather, food, workout
    }
    package let kind: Kind
    package init(_ kind: Kind) { self.kind = kind }

    /// The locale's usual unit for the dimension.
    public static var general: Self { Self(.general) }
    /// The measurement's own unit.
    public static var asProvided: Self { Self(.asProvided) }
}

extension MeasurementFormatUnitUsage where UnitType == UnitLength {
    public static var person: Self { Self(.person) }
    public static var personHeight: Self { Self(.personHeight) }
    public static var road: Self { Self(.road) }
    public static var focalLength: Self { Self(.focalLength) }
    public static var rainfall: Self { Self(.rainfall) }
    public static var snowfall: Self { Self(.snowfall) }
}

extension MeasurementFormatUnitUsage where UnitType == UnitTemperature {
    public static var person: Self { Self(.person) }
    public static var weather: Self { Self(.weather) }
}

extension MeasurementFormatUnitUsage where UnitType == UnitMass {
    public static var personWeight: Self { Self(.person) }
}

extension MeasurementFormatUnitUsage where UnitType == UnitEnergy {
    public static var food: Self { Self(.food) }
    public static var workout: Self { Self(.workout) }
}

// MARK: - Format style

/// The unit a measurement is shown in for a usage and locale, and whether it was converted.
private func _shown<UnitType: Dimension>(_ measurement: Measurement<UnitType>, usage: MeasurementFormatUnitUsage<UnitType>.Kind,
                                         locale: Locale) -> (Measurement<UnitType>, converted: Bool) {
    guard usage != .asProvided else { return (measurement, false) }
    let system = _MeasurementSystem(locale)
    func to(_ unit: Dimension) -> (Measurement<UnitType>, converted: Bool) {
        guard let unit = unit as? UnitType, unit != measurement.unit else { return (measurement, false) }
        return (measurement.converted(to: unit), true)
    }
    if let length = measurement as? Measurement<UnitLength> {
        let meters = abs(length.converted(to: .meters).value)
        if system == .metric {
            switch usage {
            case .road: return to(meters >= 1000 ? UnitLength.kilometers : UnitLength.meters)
            case .personHeight, .person: return to(UnitLength.centimeters)
            case .rainfall, .snowfall: return to(usage == .rainfall ? UnitLength.millimeters : UnitLength.centimeters)
            case .focalLength: return to(UnitLength.millimeters)
            default: return to(meters >= 1000 ? UnitLength.kilometers : meters >= 1 ? UnitLength.meters : UnitLength.centimeters)
            }
        }
        let miles = meters / 1609.344
        switch usage {
        case .road: return to(miles >= 0.5 ? UnitLength.miles : UnitLength.feet)
        case .personHeight, .person, .rainfall, .snowfall: return to(UnitLength.inches)
        case .focalLength: return to(UnitLength.millimeters)
        default: return to(miles >= 1 ? UnitLength.miles : meters >= 0.3048 ? UnitLength.feet : UnitLength.inches)
        }
    }
    if measurement is Measurement<UnitTemperature> {
        return to(system == .us ? UnitTemperature.fahrenheit : UnitTemperature.celsius)
    }
    if measurement is Measurement<UnitSpeed> {
        return to(system == .metric ? UnitSpeed.kilometersPerHour : UnitSpeed.milesPerHour)
    }
    if let mass = measurement as? Measurement<UnitMass> {
        guard system == .us else { return to(abs(mass.converted(to: .kilograms).value) >= 1 ? UnitMass.kilograms : UnitMass.grams) }
        return to(abs(mass.converted(to: .pounds).value) >= 1 ? UnitMass.pounds : UnitMass.ounces)
    }
    if let volume = measurement as? Measurement<UnitVolume> {
        guard system == .us else { return to(abs(volume.converted(to: .liters).value) >= 1 ? UnitVolume.liters : UnitVolume.milliliters) }
        return to(abs(volume.converted(to: .gallons).value) >= 1 ? UnitVolume.gallons : UnitVolume.fluidOunces)
    }
    return (measurement, false)
}

/// The number of a converted measurement when no number style is given: whole above ten,
/// two significant digits below, as Foundation rounds a measurement it chose the unit of.
private func _convertedNumber(_ value: Double) -> String {
    let magnitude = abs(value)
    var core = _NumberFormatting()
    if magnitude >= 10 || magnitude == 0 {
        core = core.precision(.fractionLength(0))
    } else {
        // Two significant digits: one decimal from 1 to 10, two from 0.1, and so on.
        var digits = 1
        var scaled = magnitude
        while scaled < 1 && digits < 6 { scaled *= 10; digits += 1 }
        core = core.precision(.fractionLength(0...digits))
    }
    return core.format(value)
}

private func _parts<UnitType: Dimension>(_ measurement: Measurement<UnitType>, width: _MeasurementWidth,
                                         usage: MeasurementFormatUnitUsage<UnitType>.Kind, locale: Locale,
                                         numberFormatStyle: FloatingPointFormatStyle<Double>?) -> _MeasurementParts {
    let (shown, converted) = _shown(measurement, usage: usage, locale: locale)
    let number: String
    if let numberFormatStyle {
        number = numberFormatStyle.format(shown.value)
    } else if converted {
        number = _convertedNumber(shown.value)
    } else {
        number = FloatingPointFormatStyle<Double>().format(shown.value)
    }
    let symbol = shown.unit.symbol
    guard let names = _UnitNames.table[symbol] else {
        return _MeasurementParts(number: number, unit: symbol, separator: width == .narrow ? "" : " ")
    }
    switch width {
    case .narrow: return _MeasurementParts(number: number, unit: names.narrow, separator: names.narrowJoined ? "" : " ")
    case .abbreviated: return _MeasurementParts(number: number, unit: names.abbreviated, separator: names.abbreviatedJoined ? "" : " ")
    case .wide: return _MeasurementParts(number: number, unit: number == "1" ? names.one : names.other, separator: " ")
    }
}

package enum _MeasurementWidth: String, Codable, Hashable, Sendable { case wide, abbreviated, narrow }

extension Measurement where UnitType: Dimension {
    /// A style that formats a measurement with its unit ("5 km", "20°C", "3 miles").
    public struct FormatStyle: WebFoundation.FormatStyle, Codable, Hashable, Sendable {
        /// How long the unit's name is.
        public struct UnitWidth: Codable, Hashable, Sendable {
            package let kind: _MeasurementWidth
            /// "5 kilometers".
            public static var wide: UnitWidth { UnitWidth(kind: .wide) }
            /// "5 km".
            public static var abbreviated: UnitWidth { UnitWidth(kind: .abbreviated) }
            /// "5km".
            public static var narrow: UnitWidth { UnitWidth(kind: .narrow) }
        }

        public var width: UnitWidth
        public var locale: Locale
        public var usage: MeasurementFormatUnitUsage<UnitType>?
        public var numberFormatStyle: FloatingPointFormatStyle<Double>?
        /// Whether a scale name is left off ("billion"); kept, since no scale names are shown.
        public var hidesScaleName = false

        public init(width: UnitWidth, locale: Locale = .autoupdatingCurrent, usage: MeasurementFormatUnitUsage<UnitType> = .general,
                    numberFormatStyle: FloatingPointFormatStyle<Double>? = nil) {
            self.width = width
            self.locale = locale
            self.usage = usage
            self.numberFormatStyle = numberFormatStyle
        }

        public func format(_ measurement: Measurement<UnitType>) -> String {
            _parts(measurement, width: width.kind, usage: (usage ?? .general).kind, locale: locale, numberFormatStyle: numberFormatStyle).string
        }

        public func locale(_ locale: Locale) -> Self { var copy = self; copy.locale = locale; return copy }

        /// The same style, with the number and unit marked by the `measurement` attribute.
        public var attributed: AttributedStyle { AttributedStyle(base: self) }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.width == rhs.width && lhs.locale == rhs.locale && lhs.usage == rhs.usage
                && lhs.numberFormatStyle == rhs.numberFormatStyle && lhs.hidesScaleName == rhs.hidesScaleName
        }
        public func hash(into hasher: inout Hasher) { hasher.combine(width); hasher.combine(locale); hasher.combine(usage) }

        private enum CodingKeys: String, CodingKey { case width, locale, usage, hidesScaleName }
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            width = try container.decode(UnitWidth.self, forKey: .width)
            locale = try container.decode(Locale.self, forKey: .locale)
            usage = try container.decodeIfPresent(MeasurementFormatUnitUsage<UnitType>.self, forKey: .usage)
            hidesScaleName = try container.decodeIfPresent(Bool.self, forKey: .hidesScaleName) ?? false
            numberFormatStyle = nil
        }
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(width, forKey: .width)
            try container.encode(locale, forKey: .locale)
            try container.encodeIfPresent(usage, forKey: .usage)
            try container.encode(hidesScaleName, forKey: .hidesScaleName)
        }
    }

    /// The format style's attributed form: the number's run and the unit's run carry the
    /// `measurement` attribute (`.value` and `.unit`).
    public struct AttributedStyle: WebFoundation.FormatStyle, Hashable, Sendable {
        public var base: FormatStyle
        public func format(_ measurement: Measurement<UnitType>) -> AttributedString {
            let parts = _parts(measurement, width: base.width.kind, usage: (base.usage ?? .general).kind, locale: base.locale,
                               numberFormatStyle: base.numberFormatStyle)
            var value = AttributeContainer()
            value[AttributeScopes.FoundationAttributes.MeasurementAttribute.self] = .value
            var unit = AttributeContainer()
            unit[AttributeScopes.FoundationAttributes.MeasurementAttribute.self] = .unit
            var result = AttributedString(parts.number, attributes: value)
            if !parts.separator.isEmpty { result.append(AttributedString(parts.separator)) }
            result.append(AttributedString(parts.unit, attributes: unit))
            return result
        }
        public func locale(_ locale: Locale) -> Self { Self(base: base.locale(locale)) }
    }

    /// The measurement in its abbreviated form for the current locale ("5 km", or "3.1 mi").
    public func formatted() -> String { FormatStyle(width: .abbreviated).format(self) }
}

extension Measurement {
    public func formatted<S: WebFoundation.FormatStyle>(_ style: S) -> S.FormatOutput where S.FormatInput == Measurement<UnitType> {
        style.format(self)
    }
}

extension WebFoundation.FormatStyle {
    /// A measurement style: `.measurement(width: .abbreviated, usage: .road)`.
    public static func measurement<UnitType: Dimension>(width: Measurement<UnitType>.FormatStyle.UnitWidth = .abbreviated,
                                                        usage: MeasurementFormatUnitUsage<UnitType> = .general,
                                                        numberFormatStyle: FloatingPointFormatStyle<Double>? = nil) -> Self
        where Self == Measurement<UnitType>.FormatStyle {
        Measurement<UnitType>.FormatStyle(width: width, usage: usage, numberFormatStyle: numberFormatStyle)
    }
}

extension AttributeScopes.FoundationAttributes {
    /// Marks the parts of a formatted measurement: its number and its unit.
    public enum MeasurementAttribute: AttributedStringKey {
        public enum Component: Int, Codable, Hashable, Sendable { case value, unit }
        public typealias Value = Component
        public static let name = "Foundation.MeasurementAttribute"
    }

    public var measurement: MeasurementAttribute { fatalError("an attribute key path, never instantiated") }
}

// MARK: - MeasurementFormatter

/// Formats measurements as strings, the older interface to the same formatting.
open class MeasurementFormatter: Formatter, @unchecked Sendable {
    /// How the unit is chosen.
    public struct UnitOptions: OptionSet, Hashable, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        /// The measurement's own unit.
        public static let providedUnit = UnitOptions(rawValue: 1 << 0)
        /// The unit that keeps the number small (accepted; the locale's unit is used).
        public static let naturalScale = UnitOptions(rawValue: 1 << 1)
        /// A temperature without its "C" or "F" ("20°").
        public static let temperatureWithoutUnit = UnitOptions(rawValue: 1 << 2)
    }

    /// How long the unit's name is: `.short` "5km", `.medium` "5 km", `.long` "5 kilometers".
    public enum UnitStyle: Int, Sendable { case short = 1, medium, long }

    open var unitOptions: UnitOptions = []
    open var unitStyle: UnitStyle = .medium
    open var locale: Locale! = .current
    /// The number's format: decimal with up to three fraction digits unless replaced. Its fraction
    /// digit limits and grouping are used; setting nil restores the default.
    open var numberFormatter: NumberFormatter! {
        get { _numberFormatter }
        set { _numberFormatter = newValue ?? Self._defaultNumberFormatter() }
    }
    private var _numberFormatter: NumberFormatter = MeasurementFormatter._defaultNumberFormatter()

    private static func _defaultNumberFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3
        formatter.usesGroupingSeparator = true
        return formatter
    }

    public override init() { super.init() }

    open func string<UnitType: Unit>(from measurement: Measurement<UnitType>) -> String {
        guard let dimension = measurement.unit as? Dimension else {
            return FloatingPointFormatStyle<Double>().format(measurement.value) + " " + measurement.unit.symbol
        }
        let width: _MeasurementWidth
        switch unitStyle {
        case .short: width = .narrow
        case .medium: width = .abbreviated
        case .long: width = .wide
        }
        let generic = Measurement<Dimension>(value: measurement.value, unit: dimension)
        let usage: MeasurementFormatUnitUsage<Dimension>.Kind = unitOptions.contains(.providedUnit) ? .asProvided : .general
        let parts = _typedParts(generic, dimension: dimension, width: width, usage: usage)
        if unitOptions.contains(.temperatureWithoutUnit), dimension is UnitTemperature {
            return parts.number + "°"
        }
        return parts.string
    }

    /// The parts for a measurement whose dimension is known only at run time.
    private func _typedParts(_ measurement: Measurement<Dimension>, dimension: Dimension, width: _MeasurementWidth,
                             usage: MeasurementFormatUnitUsage<Dimension>.Kind) -> _MeasurementParts {
        let locale = locale ?? .current
        let formatter = _numberFormatter
        var style = FloatingPointFormatStyle<Double>()
            .precision(.fractionLength(formatter.minimumFractionDigits...max(formatter.minimumFractionDigits, formatter.maximumFractionDigits)))
        if !formatter.usesGroupingSeparator { style = style.grouping(.never) }
        func typed<D: Dimension>(_ unit: D) -> _MeasurementParts {
            _parts(Measurement<D>(value: measurement.value, unit: unit), width: width,
                   usage: MeasurementFormatUnitUsage<D>.Kind(rawValue: usage.rawValue) ?? .general, locale: locale, numberFormatStyle: style)
        }
        switch dimension {
        case let unit as UnitLength: return typed(unit)
        case let unit as UnitTemperature: return typed(unit)
        case let unit as UnitSpeed: return typed(unit)
        case let unit as UnitMass: return typed(unit)
        case let unit as UnitVolume: return typed(unit)
        default: return typed(dimension)
        }
    }

    /// The unit's name alone at the formatter's width ("km", "kilometers").
    open func string(from unit: Unit) -> String {
        guard let names = _UnitNames.table[unit.symbol] else { return unit.symbol }
        switch unitStyle {
        case .short: return names.narrow
        case .medium: return names.abbreviated
        case .long: return names.other
        }
    }

    open override func string(for obj: Any?) -> String? {
        // A Measurement<UnitLength> doesn't cast to Measurement<Dimension>, so read any
        // measurement through its value and unit.
        guard let measurement = obj as? _AnyMeasurement else { return nil }
        return string(from: Measurement<Unit>(value: measurement._measurementValue, unit: measurement._measurementUnit))
    }
}

/// Any `Measurement`, whatever its unit type, for `MeasurementFormatter.string(for:)`.
private protocol _AnyMeasurement {
    var _measurementValue: Double { get }
    var _measurementUnit: Unit { get }
}

extension Measurement: _AnyMeasurement {
    fileprivate var _measurementValue: Double { value }
    fileprivate var _measurementUnit: Unit { unit }
}
#endif
