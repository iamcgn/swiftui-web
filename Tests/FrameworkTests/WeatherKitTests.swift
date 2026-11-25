// WeatherKit (Sources/WeatherKit): FoodTruck's truck and city cards ask the shared service for a
// place's weather and hourly forecast; on the web each request fails as Apple's does when its
// service can't be reached, and the condition names an app shows read as Apple's do.
import Testing
import CoreLocation
@testable import WeatherKit

@Suite struct WeatherKitTests {
    private let location = CLLocation(latitude: 37.33, longitude: -122.03)

    @Test func requestsFailAsWhenTheServiceCantBeReached() async {
        await #expect(throws: WeatherError.unknown) { try await WeatherService.shared.weather(for: location) }
        await #expect(throws: WeatherError.unknown) {
            try await WeatherService.shared.weather(for: location, including: .hourly).forecast
        }
        await #expect(throws: WeatherError.unknown) {
            try await WeatherService.shared.weather(for: location, including: .current, .daily)
        }
        await #expect(throws: WeatherError.unknown) { try await WeatherService.shared.attribution }
        #expect(WeatherError.unknown.errorDescription == "The weather service couldn't be reached.")
    }

    @Test func queriesCarryTheirDataSet() {
        #expect(WeatherQuery<Forecast<HourWeather>>.hourly.kind == .hourly)
        #expect(WeatherQuery<Forecast<DayWeather>>.daily.kind == .daily)
        let start = Date(timeIntervalSince1970: 0), end = Date(timeIntervalSince1970: 3600)
        #expect(WeatherQuery<Forecast<HourWeather>>.hourly(startDate: start, endDate: end).kind == .hourlyRange(start, end))
        #expect(WeatherQuery<[WeatherAlert]?>.alerts.kind == .alerts && WeatherQuery<Forecast<MinuteWeather>?>.minute.kind == .minute)
    }

    @Test func conditionsAndDirectionsReadInWords() {
        #expect(WeatherCondition.partlyCloudy.description == "Partly Cloudy")
        #expect(WeatherCondition.clear.description == "Clear")
        #expect(WeatherCondition.allCases.count == 34)
        #expect(Wind.CompassDirection(degrees: 22.5).abbreviation == "NNE")
        #expect(Wind.CompassDirection(degrees: 350) == .north)
        #expect(Wind.CompassDirection(degrees: -90) == .west)
        #expect(Precipitation.none.description == "No Precipitation")
        #expect(UVIndex(value: 7).category == .high && UVIndex(value: 12).category == .extreme)
        #expect(UVIndex.ExposureCategory.moderate < .veryHigh)
    }
}
