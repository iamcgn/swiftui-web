// WeatherKit on the web: the weather service's queries and every value it answers with
// (current conditions, minute, hour and day forecasts, alerts, availability, attribution), so
// apps that show weather build and run (FoodTruck's truck and city cards). Apple's service is
// reached through the device with a token signed for the app, which a page has neither of, so
// every request fails as Apple's does when it can't be reached (`WeatherError.unknown`), after
// the call returns, and an app's no-weather path runs. Conditions, compass directions and UV
// categories describe themselves in English, as Apple's do.
@_exported import WebFoundation
import CoreLocation

/// The service that gives the weather for a place.
public final class WeatherService: Sendable {
    /// The service apps share.
    public static let shared = WeatherService()

    public init() {}

    /// Every data set for a place: current conditions, forecasts, alerts and availability.
    public func weather(for location: CLLocation) async throws -> Weather {
        throw WeatherError.unknown
    }

    /// One data set for a place, such as `.current` or `.hourly`.
    public func weather<T>(for location: CLLocation, including dataSet: WeatherQuery<T>) async throws -> T {
        throw WeatherError.unknown
    }

    public func weather<T1, T2>(for location: CLLocation, including dataSet1: WeatherQuery<T1>,
                                _ dataSet2: WeatherQuery<T2>) async throws -> (T1, T2) {
        throw WeatherError.unknown
    }

    public func weather<T1, T2, T3>(for location: CLLocation, including dataSet1: WeatherQuery<T1>,
                                    _ dataSet2: WeatherQuery<T2>, _ dataSet3: WeatherQuery<T3>) async throws -> (T1, T2, T3) {
        throw WeatherError.unknown
    }

    public func weather<T1, T2, T3, T4>(for location: CLLocation, including dataSet1: WeatherQuery<T1>,
                                        _ dataSet2: WeatherQuery<T2>, _ dataSet3: WeatherQuery<T3>,
                                        _ dataSet4: WeatherQuery<T4>) async throws -> (T1, T2, T3, T4) {
        throw WeatherError.unknown
    }

    public func weather<T1, T2, T3, T4, T5>(for location: CLLocation, including dataSet1: WeatherQuery<T1>,
                                            _ dataSet2: WeatherQuery<T2>, _ dataSet3: WeatherQuery<T3>,
                                            _ dataSet4: WeatherQuery<T4>, _ dataSet5: WeatherQuery<T5>) async throws -> (T1, T2, T3, T4, T5) {
        throw WeatherError.unknown
    }

    public func weather<T1, T2, T3, T4, T5, T6>(for location: CLLocation, including dataSet1: WeatherQuery<T1>,
                                                _ dataSet2: WeatherQuery<T2>, _ dataSet3: WeatherQuery<T3>,
                                                _ dataSet4: WeatherQuery<T4>, _ dataSet5: WeatherQuery<T5>,
                                                _ dataSet6: WeatherQuery<T6>) async throws -> (T1, T2, T3, T4, T5, T6) {
        throw WeatherError.unknown
    }

    /// The attribution apps must show beside the weather, from the same service.
    public var attribution: WeatherAttribution {
        get async throws { throw WeatherError.unknown }
    }
}

/// What a weather request failed with.
public enum WeatherError: LocalizedError, Hashable, Sendable {
    /// The app isn't allowed to use the service.
    case permissionDenied
    /// The service couldn't be reached or answered with an error.
    case unknown

    public var errorDescription: String? {
        switch self {
        case .permissionDenied: return "The app isn't allowed to use the weather service."
        case .unknown: return "The weather service couldn't be reached."
        }
    }
    public var failureReason: String? { errorDescription }
}

/// A data set to ask the service for, typed by what it answers with.
public struct WeatherQuery<T>: Sendable {
    enum Kind: Hashable, Sendable {
        case current, minute, hourly, daily, alerts, availability
        case hourlyRange(Date, Date), dailyRange(Date, Date)
    }
    let kind: Kind
}

extension WeatherQuery where T == CurrentWeather {
    /// The weather now.
    public static var current: WeatherQuery<CurrentWeather> { WeatherQuery(kind: .current) }
}

extension WeatherQuery where T == Forecast<MinuteWeather>? {
    /// The next hour's precipitation, minute by minute, where the service has it.
    public static var minute: WeatherQuery<Forecast<MinuteWeather>?> { WeatherQuery(kind: .minute) }
}

extension WeatherQuery where T == Forecast<HourWeather> {
    /// The hourly forecast from now.
    public static var hourly: WeatherQuery<Forecast<HourWeather>> { WeatherQuery(kind: .hourly) }
    /// The hourly forecast between two dates.
    public static func hourly(startDate: Date, endDate: Date) -> WeatherQuery<Forecast<HourWeather>> {
        WeatherQuery(kind: .hourlyRange(startDate, endDate))
    }
}

extension WeatherQuery where T == Forecast<DayWeather> {
    /// The daily forecast from today.
    public static var daily: WeatherQuery<Forecast<DayWeather>> { WeatherQuery(kind: .daily) }
    /// The daily forecast between two dates.
    public static func daily(startDate: Date, endDate: Date) -> WeatherQuery<Forecast<DayWeather>> {
        WeatherQuery(kind: .dailyRange(startDate, endDate))
    }
}

extension WeatherQuery where T == [WeatherAlert]? {
    /// The severe-weather alerts for the place, where the service has them.
    public static var alerts: WeatherQuery<[WeatherAlert]?> { WeatherQuery(kind: .alerts) }
}

extension WeatherQuery where T == WeatherAvailability {
    /// Which data sets the service has for the place.
    public static var availability: WeatherQuery<WeatherAvailability> { WeatherQuery(kind: .availability) }
}

/// When the data was fetched, until when it holds, and for where.
public struct WeatherMetadata: Equatable, Sendable {
    public let date: Date
    public let expirationDate: Date
    public let location: CLLocation
}

/// A forecast: its periods in order, and the metadata of the request.
public struct Forecast<Element: Equatable & Sendable>: RandomAccessCollection, Equatable, Sendable {
    public let forecast: [Element]
    public let metadata: WeatherMetadata
    public var startIndex: Int { forecast.startIndex }
    public var endIndex: Int { forecast.endIndex }
    public subscript(position: Int) -> Element { forecast[position] }
}

/// All of a place's weather at once.
public struct Weather: Equatable, Sendable {
    public let currentWeather: CurrentWeather
    public let minuteForecast: Forecast<MinuteWeather>?
    public let hourlyForecast: Forecast<HourWeather>
    public let dailyForecast: Forecast<DayWeather>
    public let weatherAlerts: [WeatherAlert]?
    public let availability: WeatherAvailability
}

/// The weather now.
public struct CurrentWeather: Equatable, Sendable {
    public let date: Date
    public let apparentTemperature: Measurement<UnitTemperature>
    public let cloudCover: Double
    public let condition: WeatherCondition
    public let dewPoint: Measurement<UnitTemperature>
    public let humidity: Double
    public let isDaylight: Bool
    public let precipitationIntensity: Measurement<UnitSpeed>
    public let pressure: Measurement<UnitPressure>
    public let pressureTrend: PressureTrend
    public let symbolName: String
    public let temperature: Measurement<UnitTemperature>
    public let uvIndex: UVIndex
    public let visibility: Measurement<UnitLength>
    public let wind: Wind
    public let metadata: WeatherMetadata
}

/// One minute of the next hour's precipitation.
public struct MinuteWeather: Equatable, Sendable {
    public let date: Date
    public let precipitation: Precipitation
    public let precipitationChance: Double
    public let precipitationIntensity: Measurement<UnitSpeed>
}

/// One hour of the forecast.
public struct HourWeather: Equatable, Sendable {
    public let date: Date
    public let apparentTemperature: Measurement<UnitTemperature>
    public let cloudCover: Double
    public let condition: WeatherCondition
    public let dewPoint: Measurement<UnitTemperature>
    public let humidity: Double
    public let isDaylight: Bool
    public let precipitation: Precipitation
    public let precipitationChance: Double
    public let precipitationAmount: Measurement<UnitLength>
    public let pressure: Measurement<UnitPressure>
    public let pressureTrend: PressureTrend
    public let symbolName: String
    public let temperature: Measurement<UnitTemperature>
    public let uvIndex: UVIndex
    public let visibility: Measurement<UnitLength>
    public let wind: Wind
}

/// One day of the forecast.
public struct DayWeather: Equatable, Sendable {
    public let date: Date
    public let condition: WeatherCondition
    public let highTemperature: Measurement<UnitTemperature>
    public let lowTemperature: Measurement<UnitTemperature>
    public let precipitation: Precipitation
    public let precipitationChance: Double
    public let precipitationAmount: Measurement<UnitLength>
    public let snowfallAmount: Measurement<UnitLength>
    public let sun: SunEvents
    public let moon: MoonEvents
    public let symbolName: String
    public let uvIndex: UVIndex
    public let wind: Wind
}

/// The times of a day's sunrise, sunset and twilights, where they happen.
public struct SunEvents: Equatable, Sendable {
    public let astronomicalDawn: Date?
    public let nauticalDawn: Date?
    public let civilDawn: Date?
    public let sunrise: Date?
    public let solarNoon: Date?
    public let sunset: Date?
    public let civilDusk: Date?
    public let nauticalDusk: Date?
    public let astronomicalDusk: Date?
    public let solarMidnight: Date?
}

/// A day's moonrise, moonset and phase.
public struct MoonEvents: Equatable, Sendable {
    public let phase: MoonPhase
    public let moonrise: Date?
    public let moonset: Date?
}

/// The phase of the moon.
public enum MoonPhase: String, CaseIterable, Codable, Hashable, Sendable, CustomStringConvertible {
    case new, waxingCrescent, firstQuarter, waxingGibbous, full, waningGibbous, lastQuarter, waningCrescent
    public var description: String { _words(rawValue) }
    public var accessibilityDescription: String { description }
    public var symbolName: String {
        switch self {
        case .new: return "moonphase.new.moon"
        case .waxingCrescent: return "moonphase.waxing.crescent"
        case .firstQuarter: return "moonphase.first.quarter"
        case .waxingGibbous: return "moonphase.waxing.gibbous"
        case .full: return "moonphase.full.moon"
        case .waningGibbous: return "moonphase.waning.gibbous"
        case .lastQuarter: return "moonphase.last.quarter"
        case .waningCrescent: return "moonphase.waning.crescent"
        }
    }
}

/// The weather's condition, as the forecast names it.
public enum WeatherCondition: String, CaseIterable, Codable, Hashable, Sendable, CustomStringConvertible {
    case blizzard, blowingDust, blowingSnow, breezy, clear, cloudy, drizzle, flurries, foggy
    case freezingDrizzle, freezingRain, frigid, hail, haze, heavyRain, heavySnow, hot, hurricane
    case isolatedThunderstorms, mostlyClear, mostlyCloudy, partlyCloudy, rain, scatteredThunderstorms
    case sleet, smoky, snow, strongStorms, sunFlurries, sunShowers, thunderstorms, tropicalStorm
    case windy, wintryMix

    /// The condition in words, such as "Partly Cloudy".
    public var description: String { _words(rawValue) }
    public var accessibilityDescription: String { description }
}

/// The kind of precipitation.
public enum Precipitation: String, CaseIterable, Codable, Hashable, Sendable, CustomStringConvertible {
    case none, hail, mixed, rain, sleet, snow
    public var description: String { rawValue == "none" ? "No Precipitation" : _words(rawValue) }
    public var accessibilityDescription: String { description }
}

/// Whether the air pressure is rising, falling or steady.
public enum PressureTrend: String, CaseIterable, Codable, Hashable, Sendable, CustomStringConvertible {
    case rising, falling, steady
    public var description: String { _words(rawValue) }
    public var accessibilityDescription: String { description }
}

/// The ultraviolet index and its exposure category.
public struct UVIndex: Equatable, Hashable, Sendable {
    /// How much exposure the index means.
    public enum ExposureCategory: String, CaseIterable, Codable, Comparable, Hashable, Sendable, CustomStringConvertible {
        case low, moderate, high, veryHigh, extreme
        /// The range of index values in the category.
        public var rangeValue: ClosedRange<Int> {
            switch self {
            case .low: return 0...2
            case .moderate: return 3...5
            case .high: return 6...7
            case .veryHigh: return 8...10
            case .extreme: return 11...Int.max
            }
        }
        public var description: String { _words(rawValue) }
        public var accessibilityDescription: String { description }
        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rangeValue.lowerBound < rhs.rangeValue.lowerBound }
    }

    public let value: Int
    public let category: ExposureCategory

    init(value: Int) {
        self.value = value
        category = ExposureCategory.allCases.last { $0.rangeValue.lowerBound <= value } ?? .low
    }
}

/// The wind: its speed, gusts and the direction it blows from.
public struct Wind: Equatable, Sendable {
    /// One of the sixteen points of the compass.
    public enum CompassDirection: String, CaseIterable, Codable, Hashable, Sendable, CustomStringConvertible {
        case north, northNortheast, northeast, eastNortheast, east, eastSoutheast, southeast, southSoutheast
        case south, southSouthwest, southwest, westSouthwest, west, westNorthwest, northwest, northNorthwest

        /// The point for a direction in degrees (0 is north, 90 east).
        init(degrees: Double) {
            var normalised = degrees.truncatingRemainder(dividingBy: 360)
            if normalised < 0 { normalised += 360 }
            let index = Int((normalised + 11.25) / 22.5) % 16
            self = Self.allCases[index]
        }

        /// The point's letters, such as "NNE".
        public var abbreviation: String {
            ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
             "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"][Self.allCases.firstIndex(of: self) ?? 0]
        }
        public var description: String { _words(rawValue) }
        public var accessibilityDescription: String { description }
    }

    public let compassDirection: CompassDirection
    public let direction: Measurement<UnitAngle>
    public let gust: Measurement<UnitSpeed>?
    public let speed: Measurement<UnitSpeed>
}

/// A severe-weather alert for the place.
public struct WeatherAlert: Equatable, Sendable {
    public let detailsURL: URL
    public let source: String
    public let summary: String
    public let region: String?
    public let severity: WeatherSeverity
    public let metadata: WeatherMetadata
}

/// How severe an alert is.
public enum WeatherSeverity: String, CaseIterable, Codable, Hashable, Sendable, CustomStringConvertible {
    case minor, moderate, severe, extreme, unknown
    public var description: String { _words(rawValue) }
    public var accessibilityDescription: String { description }
}

/// Which data sets the service has for a place.
public struct WeatherAvailability: Equatable, Sendable {
    /// Whether one data set is there.
    public enum AvailabilityKind: String, Codable, Hashable, Sendable {
        case available, temporarilyUnavailable, unsupported, unknown
    }
    public let minuteAvailability: AvailabilityKind
    public let alertAvailability: AvailabilityKind
}

/// The data source's name, marks and legal page, which apps show beside the weather.
public struct WeatherAttribution: Equatable, Sendable {
    public let serviceName: String
    public let legalPageURL: URL
    public let legalAttributionText: String
    public let combinedMarkLightURL: URL
    public let combinedMarkDarkURL: URL
    public let squareMarkURL: URL
}

/// "partlyCloudy" as "Partly Cloudy".
func _words(_ name: String) -> String {
    var result = ""
    for character in name {
        if result.isEmpty {
            result.append(Character(character.uppercased()))
        } else {
            if character.isUppercase { result.append(" ") }
            result.append(character)
        }
    }
    return result
}
