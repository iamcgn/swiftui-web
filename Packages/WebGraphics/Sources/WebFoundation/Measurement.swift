// Foundation's measurements on wasm, where FoundationEssentials has none (Docs/coverage.md:
// `Measurement<UnitLength>` and `UnitTemperature` in 4 corpus apps, and `.init(value:unit:)`
// behind many "cannot infer contextual base" errors). Units, their converters, conversion,
// arithmetic, comparison and coding follow Foundation; the factors are Foundation's. Formatting
// a measurement for a locale is not here.
#if os(WASI)

/// Converts a unit's values to and from its dimension's base unit.
open class UnitConverter: @unchecked Sendable {
    public init() {}
    /// The value in the base unit.
    open func baseUnitValue(fromValue value: Double) -> Double { value }
    /// The value in this converter's unit.
    open func value(fromBaseUnitValue baseUnitValue: Double) -> Double { baseUnitValue }
}

/// A unit whose base value is `value * coefficient + constant`.
open class UnitConverterLinear: UnitConverter, @unchecked Sendable {
    public let coefficient: Double
    public let constant: Double

    public init(coefficient: Double) {
        self.coefficient = coefficient
        constant = 0
    }

    public init(coefficient: Double, constant: Double) {
        self.coefficient = coefficient
        self.constant = constant
    }

    open override func baseUnitValue(fromValue value: Double) -> Double { value * coefficient + constant }
    open override func value(fromBaseUnitValue baseUnitValue: Double) -> Double { (baseUnitValue - constant) / coefficient }
}

/// A unit of measure, named by its symbol.
open class Unit: Hashable, CustomStringConvertible, @unchecked Sendable {
    /// The unit's symbol: `m`, `°C`.
    open private(set) var symbol: String

    public required init(symbol: String) { self.symbol = symbol }

    open var description: String { symbol }

    open func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? Unit else { return false }
        return type(of: self) == type(of: other) && symbol == other.symbol
    }

    open func hash(into hasher: inout Hasher) { hasher.combine(symbol) }

    public static func == (lhs: Unit, rhs: Unit) -> Bool { lhs.isEqual(rhs) }
}

/// A unit that converts to the other units of its dimension through a base unit.
open class Dimension: Unit, @unchecked Sendable {
    /// How values in this unit convert to the base unit.
    open private(set) var converter: UnitConverter

    public required init(symbol: String, converter: UnitConverter) {
        self.converter = converter
        super.init(symbol: symbol)
    }

    public required init(symbol: String) {
        converter = UnitConverterLinear(coefficient: 1)
        super.init(symbol: symbol)
    }

    /// The dimension's base unit. Each dimension's own class answers it.
    open class func baseUnit() -> Self { fatalError("\(self) has no base unit") }

    open override func isEqual(_ object: Any?) -> Bool {
        guard super.isEqual(object), let other = object as? Dimension else { return false }
        switch (converter as? UnitConverterLinear, other.converter as? UnitConverterLinear) {
        case let (a?, b?): return a.coefficient == b.coefficient && a.constant == b.constant
        default: return converter === other.converter
        }
    }
}

private func linear(_ coefficient: Double, _ constant: Double = 0) -> UnitConverterLinear {
    UnitConverterLinear(coefficient: coefficient, constant: constant)
}

/// Length; the base unit is meters.
open class UnitLength: Dimension, @unchecked Sendable {
    public static let megameters = UnitLength(symbol: "Mm", converter: linear(1_000_000))
    public static let kilometers = UnitLength(symbol: "km", converter: linear(1000))
    public static let hectometers = UnitLength(symbol: "hm", converter: linear(100))
    public static let decameters = UnitLength(symbol: "dam", converter: linear(10))
    public static let meters = UnitLength(symbol: "m", converter: linear(1))
    public static let decimeters = UnitLength(symbol: "dm", converter: linear(0.1))
    public static let centimeters = UnitLength(symbol: "cm", converter: linear(0.01))
    public static let millimeters = UnitLength(symbol: "mm", converter: linear(0.001))
    public static let micrometers = UnitLength(symbol: "µm", converter: linear(0.000001))
    public static let nanometers = UnitLength(symbol: "nm", converter: linear(1e-9))
    public static let picometers = UnitLength(symbol: "pm", converter: linear(1e-12))
    public static let inches = UnitLength(symbol: "in", converter: linear(0.0254))
    public static let feet = UnitLength(symbol: "ft", converter: linear(0.3048))
    public static let yards = UnitLength(symbol: "yd", converter: linear(0.9144))
    public static let miles = UnitLength(symbol: "mi", converter: linear(1609.344))
    public static let scandinavianMiles = UnitLength(symbol: "smi", converter: linear(10000))
    public static let lightyears = UnitLength(symbol: "ly", converter: linear(9.461e+15))
    public static let nauticalMiles = UnitLength(symbol: "NM", converter: linear(1852))
    public static let fathoms = UnitLength(symbol: "ftm", converter: linear(1.8288))
    public static let furlongs = UnitLength(symbol: "fur", converter: linear(201.168))
    public static let astronomicalUnits = UnitLength(symbol: "ua", converter: linear(1.496e+11))
    public static let parsecs = UnitLength(symbol: "pc", converter: linear(3.086e+16))
    open override class func baseUnit() -> Self { meters as! Self }
}

/// Mass; the base unit is kilograms.
open class UnitMass: Dimension, @unchecked Sendable {
    public static let kilograms = UnitMass(symbol: "kg", converter: linear(1))
    public static let grams = UnitMass(symbol: "g", converter: linear(0.001))
    public static let decigrams = UnitMass(symbol: "dg", converter: linear(0.0001))
    public static let centigrams = UnitMass(symbol: "cg", converter: linear(0.00001))
    public static let milligrams = UnitMass(symbol: "mg", converter: linear(0.000001))
    public static let micrograms = UnitMass(symbol: "µg", converter: linear(1e-9))
    public static let nanograms = UnitMass(symbol: "ng", converter: linear(1e-12))
    public static let picograms = UnitMass(symbol: "pg", converter: linear(1e-15))
    public static let ounces = UnitMass(symbol: "oz", converter: linear(0.0283495))
    public static let pounds = UnitMass(symbol: "lb", converter: linear(0.453592))
    public static let stones = UnitMass(symbol: "st", converter: linear(0.157473))
    public static let metricTons = UnitMass(symbol: "t", converter: linear(1000))
    public static let shortTons = UnitMass(symbol: "ton", converter: linear(907.185))
    public static let carats = UnitMass(symbol: "ct", converter: linear(0.0002))
    public static let ouncesTroy = UnitMass(symbol: "oz t", converter: linear(0.03110348))
    public static let slugs = UnitMass(symbol: "slug", converter: linear(14.5939))
    open override class func baseUnit() -> Self { kilograms as! Self }
}

/// Speed; the base unit is meters per second.
open class UnitSpeed: Dimension, @unchecked Sendable {
    public static let metersPerSecond = UnitSpeed(symbol: "m/s", converter: linear(1))
    public static let kilometersPerHour = UnitSpeed(symbol: "km/h", converter: linear(0.277778))
    public static let milesPerHour = UnitSpeed(symbol: "mph", converter: linear(0.44704))
    public static let knots = UnitSpeed(symbol: "kn", converter: linear(0.514444))
    open override class func baseUnit() -> Self { metersPerSecond as! Self }
}

/// Temperature; the base unit is kelvin.
open class UnitTemperature: Dimension, @unchecked Sendable {
    public static let kelvin = UnitTemperature(symbol: "K", converter: linear(1))
    public static let celsius = UnitTemperature(symbol: "°C", converter: linear(1, 273.15))
    public static let fahrenheit = UnitTemperature(symbol: "°F", converter: linear(0.55555555555556, 255.37222222222427))
    open override class func baseUnit() -> Self { kelvin as! Self }
}

/// Time; the base unit is seconds.
open class UnitDuration: Dimension, @unchecked Sendable {
    public static let hours = UnitDuration(symbol: "hr", converter: linear(3600))
    public static let minutes = UnitDuration(symbol: "min", converter: linear(60))
    public static let seconds = UnitDuration(symbol: "s", converter: linear(1))
    public static let milliseconds = UnitDuration(symbol: "ms", converter: linear(0.001))
    public static let microseconds = UnitDuration(symbol: "µs", converter: linear(0.000001))
    public static let nanoseconds = UnitDuration(symbol: "ns", converter: linear(1e-9))
    public static let picoseconds = UnitDuration(symbol: "ps", converter: linear(1e-12))
    open override class func baseUnit() -> Self { seconds as! Self }
}

/// Pressure; the base unit is newtons per square meter.
open class UnitPressure: Dimension, @unchecked Sendable {
    public static let newtonsPerMetersSquared = UnitPressure(symbol: "N/m²", converter: linear(1))
    public static let gigapascals = UnitPressure(symbol: "GPa", converter: linear(1e9))
    public static let megapascals = UnitPressure(symbol: "MPa", converter: linear(1_000_000))
    public static let kilopascals = UnitPressure(symbol: "kPa", converter: linear(1000))
    public static let hectopascals = UnitPressure(symbol: "hPa", converter: linear(100))
    public static let inchesOfMercury = UnitPressure(symbol: "inHg", converter: linear(3386.39))
    public static let bars = UnitPressure(symbol: "bar", converter: linear(100_000))
    public static let millibars = UnitPressure(symbol: "mbar", converter: linear(100))
    public static let millimetersOfMercury = UnitPressure(symbol: "mmHg", converter: linear(133.322387415))
    public static let poundsForcePerSquareInch = UnitPressure(symbol: "psi", converter: linear(6894.76))
    open override class func baseUnit() -> Self { newtonsPerMetersSquared as! Self }
}

/// Area; the base unit is square meters.
open class UnitArea: Dimension, @unchecked Sendable {
    public static let squareMegameters = UnitArea(symbol: "Mm²", converter: linear(1e12))
    public static let squareKilometers = UnitArea(symbol: "km²", converter: linear(1e6))
    public static let squareMeters = UnitArea(symbol: "m²", converter: linear(1))
    public static let squareCentimeters = UnitArea(symbol: "cm²", converter: linear(0.0001))
    public static let squareMillimeters = UnitArea(symbol: "mm²", converter: linear(0.000001))
    public static let squareMicrometers = UnitArea(symbol: "µm²", converter: linear(1e-12))
    public static let squareNanometers = UnitArea(symbol: "nm²", converter: linear(1e-18))
    public static let squareInches = UnitArea(symbol: "in²", converter: linear(0.00064516))
    public static let squareFeet = UnitArea(symbol: "ft²", converter: linear(0.092903))
    public static let squareYards = UnitArea(symbol: "yd²", converter: linear(0.836127))
    public static let squareMiles = UnitArea(symbol: "mi²", converter: linear(2.59e+6))
    public static let acres = UnitArea(symbol: "ac", converter: linear(4046.86))
    public static let ares = UnitArea(symbol: "a", converter: linear(100))
    public static let hectares = UnitArea(symbol: "ha", converter: linear(10000))
    open override class func baseUnit() -> Self { squareMeters as! Self }
}

/// Volume; the base unit is liters.
open class UnitVolume: Dimension, @unchecked Sendable {
    public static let megaliters = UnitVolume(symbol: "ML", converter: linear(1_000_000))
    public static let kiloliters = UnitVolume(symbol: "kL", converter: linear(1000))
    public static let liters = UnitVolume(symbol: "L", converter: linear(1))
    public static let deciliters = UnitVolume(symbol: "dL", converter: linear(0.1))
    public static let centiliters = UnitVolume(symbol: "cL", converter: linear(0.01))
    public static let milliliters = UnitVolume(symbol: "mL", converter: linear(0.001))
    public static let cubicKilometers = UnitVolume(symbol: "km³", converter: linear(1e12))
    public static let cubicMeters = UnitVolume(symbol: "m³", converter: linear(1000))
    public static let cubicDecimeters = UnitVolume(symbol: "dm³", converter: linear(1))
    public static let cubicCentimeters = UnitVolume(symbol: "cm³", converter: linear(0.001))
    public static let cubicMillimeters = UnitVolume(symbol: "mm³", converter: linear(0.000001))
    public static let cubicInches = UnitVolume(symbol: "in³", converter: linear(0.0163871))
    public static let cubicFeet = UnitVolume(symbol: "ft³", converter: linear(28.3168))
    public static let cubicYards = UnitVolume(symbol: "yd³", converter: linear(764.555))
    public static let cubicMiles = UnitVolume(symbol: "mi³", converter: linear(4.168e+12))
    public static let acreFeet = UnitVolume(symbol: "af", converter: linear(1.233e+6))
    public static let bushels = UnitVolume(symbol: "bsh", converter: linear(35.2391))
    public static let teaspoons = UnitVolume(symbol: "tsp", converter: linear(0.00492892))
    public static let tablespoons = UnitVolume(symbol: "tbsp", converter: linear(0.0147868))
    public static let fluidOunces = UnitVolume(symbol: "fl oz", converter: linear(0.0295735))
    public static let cups = UnitVolume(symbol: "cup", converter: linear(0.24))
    public static let pints = UnitVolume(symbol: "pt", converter: linear(0.473176))
    public static let quarts = UnitVolume(symbol: "qt", converter: linear(0.946353))
    public static let gallons = UnitVolume(symbol: "gal", converter: linear(3.78541))
    public static let imperialTeaspoons = UnitVolume(symbol: "tsp", converter: linear(0.00591939))
    public static let imperialTablespoons = UnitVolume(symbol: "tbsp", converter: linear(0.0177582))
    public static let imperialFluidOunces = UnitVolume(symbol: "fl oz", converter: linear(0.0284131))
    public static let imperialPints = UnitVolume(symbol: "pt", converter: linear(0.568261))
    public static let imperialQuarts = UnitVolume(symbol: "qt", converter: linear(1.13652))
    public static let imperialGallons = UnitVolume(symbol: "gal", converter: linear(4.54609))
    public static let metricCups = UnitVolume(symbol: "metric cup", converter: linear(0.25))
    open override class func baseUnit() -> Self { liters as! Self }
}

/// Angle; the base unit is degrees.
open class UnitAngle: Dimension, @unchecked Sendable {
    public static let degrees = UnitAngle(symbol: "°", converter: linear(1))
    public static let arcMinutes = UnitAngle(symbol: "ʹ", converter: linear(0.016667))
    public static let arcSeconds = UnitAngle(symbol: "ʺ", converter: linear(0.00027778))
    public static let radians = UnitAngle(symbol: "rad", converter: linear(57.2958))
    public static let gradians = UnitAngle(symbol: "grad", converter: linear(0.9))
    public static let revolutions = UnitAngle(symbol: "rev", converter: linear(360))
    open override class func baseUnit() -> Self { degrees as! Self }
}

/// Energy; the base unit is joules.
open class UnitEnergy: Dimension, @unchecked Sendable {
    public static let kilojoules = UnitEnergy(symbol: "kJ", converter: linear(1000))
    public static let joules = UnitEnergy(symbol: "J", converter: linear(1))
    public static let kilocalories = UnitEnergy(symbol: "kCal", converter: linear(4184))
    public static let calories = UnitEnergy(symbol: "cal", converter: linear(4.184))
    public static let kilowattHours = UnitEnergy(symbol: "kWh", converter: linear(3_600_000))
    open override class func baseUnit() -> Self { joules as! Self }
}

/// Power; the base unit is watts.
open class UnitPower: Dimension, @unchecked Sendable {
    public static let terawatts = UnitPower(symbol: "TW", converter: linear(1e12))
    public static let gigawatts = UnitPower(symbol: "GW", converter: linear(1e9))
    public static let megawatts = UnitPower(symbol: "MW", converter: linear(1e6))
    public static let kilowatts = UnitPower(symbol: "kW", converter: linear(1000))
    public static let watts = UnitPower(symbol: "W", converter: linear(1))
    public static let milliwatts = UnitPower(symbol: "mW", converter: linear(0.001))
    public static let microwatts = UnitPower(symbol: "µW", converter: linear(0.000001))
    public static let nanowatts = UnitPower(symbol: "nW", converter: linear(1e-9))
    public static let picowatts = UnitPower(symbol: "pW", converter: linear(1e-12))
    public static let femtowatts = UnitPower(symbol: "fW", converter: linear(1e-15))
    public static let horsepower = UnitPower(symbol: "hp", converter: linear(745.7))
    open override class func baseUnit() -> Self { watts as! Self }
}

/// Frequency; the base unit is hertz.
open class UnitFrequency: Dimension, @unchecked Sendable {
    public static let terahertz = UnitFrequency(symbol: "THz", converter: linear(1e12))
    public static let gigahertz = UnitFrequency(symbol: "GHz", converter: linear(1e9))
    public static let megahertz = UnitFrequency(symbol: "MHz", converter: linear(1e6))
    public static let kilohertz = UnitFrequency(symbol: "kHz", converter: linear(1000))
    public static let hertz = UnitFrequency(symbol: "Hz", converter: linear(1))
    public static let millihertz = UnitFrequency(symbol: "mHz", converter: linear(0.001))
    public static let microhertz = UnitFrequency(symbol: "µHz", converter: linear(0.000001))
    public static let nanohertz = UnitFrequency(symbol: "nHz", converter: linear(1e-9))
    public static let framesPerSecond = UnitFrequency(symbol: "FPS", converter: linear(1))
    open override class func baseUnit() -> Self { hertz as! Self }
}

/// Acceleration; the base unit is meters per second squared.
open class UnitAcceleration: Dimension, @unchecked Sendable {
    public static let metersPerSecondSquared = UnitAcceleration(symbol: "m/s²", converter: linear(1))
    public static let gravity = UnitAcceleration(symbol: "g", converter: linear(9.81))
    open override class func baseUnit() -> Self { metersPerSecondSquared as! Self }
}

/// Information storage; the base unit is bits.
open class UnitInformationStorage: Dimension, @unchecked Sendable {
    public static let bits = UnitInformationStorage(symbol: "bit", converter: linear(1))
    public static let nibbles = UnitInformationStorage(symbol: "nibble", converter: linear(4))
    public static let bytes = UnitInformationStorage(symbol: "B", converter: linear(8))
    public static let kilobits = UnitInformationStorage(symbol: "kb", converter: linear(1000))
    public static let megabits = UnitInformationStorage(symbol: "Mb", converter: linear(1e6))
    public static let gigabits = UnitInformationStorage(symbol: "Gb", converter: linear(1e9))
    public static let kilobytes = UnitInformationStorage(symbol: "kB", converter: linear(8000))
    public static let megabytes = UnitInformationStorage(symbol: "MB", converter: linear(8e6))
    public static let gigabytes = UnitInformationStorage(symbol: "GB", converter: linear(8e9))
    public static let terabytes = UnitInformationStorage(symbol: "TB", converter: linear(8e12))
    public static let kibibytes = UnitInformationStorage(symbol: "KiB", converter: linear(8192))
    public static let mebibytes = UnitInformationStorage(symbol: "MiB", converter: linear(8_388_608))
    public static let gibibytes = UnitInformationStorage(symbol: "GiB", converter: linear(8_589_934_592))
    open override class func baseUnit() -> Self { bits as! Self }
}

/// An amount in a unit: `Measurement(value: 72, unit: UnitTemperature.fahrenheit)`.
public struct Measurement<UnitType: Unit>: CustomStringConvertible, CustomDebugStringConvertible, @unchecked Sendable {
    public var value: Double
    public let unit: UnitType

    public init(value: Double, unit: UnitType) {
        self.value = value
        self.unit = unit
    }

    public var description: String { "\(value) \(unit.symbol)" }
    public var debugDescription: String { description }
}

extension Measurement where UnitType: Dimension {
    /// The measurement in another unit of its dimension.
    public func converted(to otherUnit: UnitType) -> Measurement<UnitType> {
        if unit == otherUnit { return self }
        let base = unit.converter.baseUnitValue(fromValue: value)
        return Measurement(value: otherUnit.converter.value(fromBaseUnitValue: base), unit: otherUnit)
    }

    /// Converts the measurement to another unit of its dimension.
    public mutating func convert(to otherUnit: UnitType) { self = converted(to: otherUnit) }

    var baseValue: Double { unit.converter.baseUnitValue(fromValue: value) }

    public static func + (lhs: Measurement<UnitType>, rhs: Measurement<UnitType>) -> Measurement<UnitType> {
        if lhs.unit == rhs.unit { return Measurement(value: lhs.value + rhs.value, unit: lhs.unit) }
        return Measurement(value: lhs.baseValue + rhs.baseValue, unit: UnitType.baseUnit())
    }

    public static func - (lhs: Measurement<UnitType>, rhs: Measurement<UnitType>) -> Measurement<UnitType> {
        if lhs.unit == rhs.unit { return Measurement(value: lhs.value - rhs.value, unit: lhs.unit) }
        return Measurement(value: lhs.baseValue - rhs.baseValue, unit: UnitType.baseUnit())
    }
}

extension Measurement {
    /// Adds two measurements in the same unit (a unit with no dimension cannot convert).
    public static func + (lhs: Measurement<UnitType>, rhs: Measurement<UnitType>) -> Measurement<UnitType> {
        precondition(lhs.unit == rhs.unit, "Measurements in \(lhs.unit.symbol) and \(rhs.unit.symbol) cannot be added")
        return Measurement(value: lhs.value + rhs.value, unit: lhs.unit)
    }

    public static func - (lhs: Measurement<UnitType>, rhs: Measurement<UnitType>) -> Measurement<UnitType> {
        precondition(lhs.unit == rhs.unit, "Measurements in \(lhs.unit.symbol) and \(rhs.unit.symbol) cannot be subtracted")
        return Measurement(value: lhs.value - rhs.value, unit: lhs.unit)
    }

    public static func * (lhs: Measurement<UnitType>, rhs: Double) -> Measurement<UnitType> { Measurement(value: lhs.value * rhs, unit: lhs.unit) }
    public static func * (lhs: Double, rhs: Measurement<UnitType>) -> Measurement<UnitType> { Measurement(value: lhs * rhs.value, unit: rhs.unit) }
    public static func / (lhs: Measurement<UnitType>, rhs: Double) -> Measurement<UnitType> { Measurement(value: lhs.value / rhs, unit: lhs.unit) }
    public static func / (lhs: Double, rhs: Measurement<UnitType>) -> Measurement<UnitType> { Measurement(value: lhs / rhs.value, unit: rhs.unit) }
}

extension Measurement: Equatable, Hashable {
    /// Equal when the values match in one unit, or (for units of one dimension) in the base unit.
    public static func == <LeftHandSideType, RightHandSideType>(lhs: Measurement<LeftHandSideType>, rhs: Measurement<RightHandSideType>) -> Bool {
        if lhs.unit.isEqual(rhs.unit) { return lhs.value == rhs.value }
        if let l = lhs.unit as? Dimension, let r = rhs.unit as? Dimension, type(of: l).baseUnit() == type(of: r).baseUnit() {
            return l.converter.baseUnitValue(fromValue: lhs.value) == r.converter.baseUnitValue(fromValue: rhs.value)
        }
        return false
    }

    public static func == (lhs: Measurement<UnitType>, rhs: Measurement<UnitType>) -> Bool {
        if lhs.unit.isEqual(rhs.unit) { return lhs.value == rhs.value }
        if let l = lhs.unit as? Dimension, let r = rhs.unit as? Dimension {
            return l.converter.baseUnitValue(fromValue: lhs.value) == r.converter.baseUnitValue(fromValue: rhs.value)
        }
        return false
    }

    public func hash(into hasher: inout Hasher) {
        if let dimension = unit as? Dimension {
            hasher.combine(dimension.converter.baseUnitValue(fromValue: value))
        } else {
            hasher.combine(value)
            hasher.combine(unit)
        }
    }
}

extension Measurement: Comparable where UnitType: Dimension {
    public static func < (lhs: Measurement<UnitType>, rhs: Measurement<UnitType>) -> Bool {
        if lhs.unit == rhs.unit { return lhs.value < rhs.value }
        return lhs.baseValue < rhs.baseValue
    }
}

extension Measurement: Codable {
    private enum CodingKeys: String, CodingKey { case value, unit }
    private enum UnitCodingKeys: String, CodingKey { case symbol, converter }
    private enum ConverterCodingKeys: String, CodingKey { case coefficient, constant }

    /// Decodes Foundation's form: the value, and the unit as its symbol and linear converter.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let value = try container.decode(Double.self, forKey: .value)
        let unitContainer = try container.nestedContainer(keyedBy: UnitCodingKeys.self, forKey: .unit)
        let symbol = try unitContainer.decode(String.self, forKey: .symbol)
        let unit: UnitType
        if let dimension = UnitType.self as? Dimension.Type {
            let converter = try unitContainer.nestedContainer(keyedBy: ConverterCodingKeys.self, forKey: .converter)
            let coefficient = try converter.decode(Double.self, forKey: .coefficient)
            let constant = try converter.decode(Double.self, forKey: .constant)
            unit = dimension.init(symbol: symbol, converter: UnitConverterLinear(coefficient: coefficient, constant: constant)) as! UnitType
        } else {
            unit = UnitType(symbol: symbol)
        }
        self.init(value: value, unit: unit)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
        var unitContainer = container.nestedContainer(keyedBy: UnitCodingKeys.self, forKey: .unit)
        try unitContainer.encode(unit.symbol, forKey: .symbol)
        if let dimension = unit as? Dimension {
            guard let linear = dimension.converter as? UnitConverterLinear else {
                throw EncodingError.invalidValue(dimension.converter, .init(codingPath: encoder.codingPath,
                    debugDescription: "Only a linear converter can be encoded"))
            }
            var converter = unitContainer.nestedContainer(keyedBy: ConverterCodingKeys.self, forKey: .converter)
            try converter.encode(linear.coefficient, forKey: .coefficient)
            try converter.encode(linear.constant, forKey: .constant)
        }
    }
}
#endif
