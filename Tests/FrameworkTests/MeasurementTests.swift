// Measurements (Packages/WebGraphics/Sources/WebFoundation/Measurement.swift on wasm, Foundation's
// own on macOS and Linux): converting between units, arithmetic, comparing across units and
// coding give Foundation's answers.
import Testing
import WebFoundation

private func close(_ a: Double, _ b: Double, within tolerance: Double = 1e-3) -> Bool { abs(a - b) <= tolerance }

@Suite struct MeasurementTests {
    @Test func converts() {
        // Apple's Foundation (and the web) use 1609.344; Linux's corelibs Foundation uses 1609.34.
        #expect(close(Measurement(value: 1, unit: UnitLength.miles).converted(to: .meters).value, 1609.344, within: 0.01))
        #expect(close(Measurement(value: 72, unit: UnitTemperature.fahrenheit).converted(to: .celsius).value, 22.222))
        #expect(close(Measurement(value: 0, unit: UnitTemperature.celsius).converted(to: .kelvin).value, 273.15))
        #expect(close(Measurement(value: 1, unit: UnitSpeed.knots).converted(to: .kilometersPerHour).value, 1.852))
        #expect(close(Measurement(value: 1500, unit: UnitDuration.milliseconds).converted(to: .seconds).value, 1.5))
        #expect(close(Measurement(value: 2, unit: UnitMass.pounds).converted(to: .kilograms).value, 0.907184))
        #expect(close(Measurement(value: 1, unit: UnitVolume.liters).converted(to: .milliliters).value, 1000))

        var distance = Measurement(value: 5, unit: UnitLength.kilometers)
        distance.convert(to: .meters)
        #expect(distance.value == 5000)
        #expect(distance.unit == UnitLength.meters)
        #expect(distance.unit.symbol == "m")
        #expect(UnitTemperature.celsius.symbol == "°C")
    }

    @Test func arithmetic() {
        let km = Measurement(value: 1, unit: UnitLength.kilometers)
        #expect((km + km).value == 2)
        #expect((km + km).unit == UnitLength.kilometers)
        let mixed = km + Measurement(value: 500, unit: UnitLength.meters)
        #expect(mixed.unit == UnitLength.meters)
        #expect(mixed.value == 1500)
        #expect((km - Measurement(value: 250, unit: UnitLength.meters)).value == 750)
        #expect((km * 3).value == 3)
        #expect((2 * km).value == 2)
        #expect((km / 4).value == 0.25)
    }

    @Test func comparesAcrossUnits() {
        let km = Measurement(value: 1, unit: UnitLength.kilometers)
        #expect(km == Measurement(value: 1000, unit: UnitLength.meters))
        #expect(km != Measurement(value: 999, unit: UnitLength.meters))
        #expect(km > Measurement(value: 999, unit: UnitLength.meters))
        #expect(Measurement(value: 1, unit: UnitLength.feet) < Measurement(value: 1, unit: UnitLength.yards))
        let sorted = [km, Measurement(value: 10, unit: UnitLength.meters), Measurement(value: 1, unit: UnitLength.miles)].sorted()
        #expect(sorted.map(\.unit.symbol) == ["m", "km", "mi"])
        #expect(Set([km, Measurement(value: 1000, unit: UnitLength.meters)]).count == 1)
    }

    @Test func codesInFoundationsForm() throws {
        let reading = Measurement(value: 21.5, unit: UnitTemperature.celsius)
        let data = try JSONEncoder().encode(reading)
        let decoded = try JSONDecoder().decode(Measurement<UnitTemperature>.self, from: data)
        #expect(decoded == reading)
        #expect(decoded.unit.symbol == "°C")
        #expect(close(decoded.converted(to: .kelvin).value, 294.65))

        let json = #"{"value":3,"unit":{"symbol":"km","converter":{"coefficient":1000,"constant":0}}}"#
        let length = try JSONDecoder().decode(Measurement<UnitLength>.self, from: Data(json.utf8))
        #expect(length == Measurement(value: 3000, unit: UnitLength.meters))
    }
}
