// Foundation's formatting that apps call and the wasm stand-ins add (Packages/WebGraphics
// WebFoundationFormats/MoreFormats.swift and WebDecimalFormats/DecimalFormats.swift): the same
// answers as Foundation's on macOS and Linux, in en_US.
import Testing
import WebFoundation
import WebFoundationFormats
import WebDecimalFormats

private let english = Locale(identifier: "en_US")

/// Reads `currencyCode` without its deprecation on Apple platforms (apps still call it, and
/// warnings are errors here).
private protocol CurrencyNaming { var currencyCode: String? { get } }
extension Locale: CurrencyNaming {}

@Suite struct FoundationFormatTests {
    #if os(WASI)
    /// String's index-range substrings (OldOS's App Store); Foundation's are deprecated, so the
    /// wasm stand-ins alone are called here.
    @Test func indexRangeSubstrings() {
        let link = "https://apps.example/app/id12345?mt=8"
        let start = link.firstIndex(of: "d")!, end = link.firstIndex(of: "?")!
        #expect(link.substring(with: start..<end) == "d12345")
        #expect(link.substring(from: end) == "?mt=8")
        #expect(link.substring(to: start) == "https://apps.example/app/i")
    }
    #endif

    @Test func separators() {
        func both(_ identifier: String) -> [String?] {
            let locale = Locale(identifier: identifier)
            return [locale.decimalSeparator, locale.groupingSeparator]
        }
        #expect(both("en_US") == [".", ","])
        #expect(both("de_DE") == [",", "."])
        #expect(both("fr_FR") == [",", "\u{202F}"])
        #if canImport(Darwin)
        // macOS 26's locale data groups Swiss German with an ASCII apostrophe; earlier releases,
        // and the wasm table, with a right single quotation mark.
        if #available(macOS 26, *) {
            #expect(both("de_CH") == [".", "'"])
        } else {
            #expect(both("de_CH") == [".", "\u{2019}"])
        }
        #else
        #expect(both("de_CH") == [".", "\u{2019}"])
        #endif
        #expect(both("pt_BR") == [",", "."])
        #expect(both("es_MX") == [".", ","])
        #expect(both("ru_RU") == [",", "\u{00A0}"])
        #expect(both("ja_JP") == [".", ","])
    }

    @Test func decimals() {
        let amount = Decimal(string: "1234.5")!
        #expect(amount.formatted(.number.locale(english)) == "1,234.5")
        #expect(amount.formatted(.currency(code: "USD").locale(english)) == "$1,234.50")
        #expect(amount.formatted(.number.precision(.fractionLength(2)).locale(english)) == "1,234.50")
        #expect(amount.formatted(.number.grouping(.never).locale(english)) == "1234.5")
        #expect(Decimal(string: "0.25")!.formatted(.percent.locale(english)) == "25%")
        #expect(Decimal(string: "-3")!.formatted(.currency(code: "EUR").locale(english)) == "-€3.00")
        #expect(Decimal(string: "1500")!.formatted(.currency(code: "JPY").locale(english)) == "¥1,500")
    }

    // FoodTruck's sales charts: significant digits round whole digits and pad to the minimum.
    @Test func significantDigits() {
        #expect(12345.0.formatted(.number.precision(.significantDigits(3)).locale(english)) == "12,300")
        #expect(0.123456.formatted(.number.precision(.significantDigits(3)).locale(english)) == "0.123")
        #expect(0.123456.formatted(.percent.precision(.significantDigits(3)).locale(english)) == "12.3%")
        #expect(2.71828.formatted(.number.precision(.significantDigits(1...3)).locale(english)) == "2.72")
        #expect(2.0.formatted(.number.precision(.significantDigits(3)).locale(english)) == "2.00")
        #expect(98765.formatted(.number.precision(.significantDigits(2)).locale(english)) == "99,000")
        #expect(Int64(9007199254740993).formatted(.number.precision(.significantDigits(1...19)).locale(english)) == "9,007,199,254,740,993")
        #expect(Int64.max.formatted(.number.precision(.significantDigits(1...19)).locale(english)) == "9,223,372,036,854,775,807")
    }

    @Test func lists() {
        #expect(["a", "b", "c"].formatted(.list(type: .and).locale(english)) == "a, b, and c")
        #expect(["a", "b"].formatted(.list(type: .and).locale(english)) == "a and b")
        #expect(["a", "b", "c"].formatted(.list(type: .or).locale(english)) == "a, b, or c")
        #expect(["a"].formatted(.list(type: .and).locale(english)) == "a")
    }

    @Test func durations() {
        let duration = Duration.seconds(3905)
        #expect(duration.formatted(.time(pattern: .hourMinuteSecond).locale(english)) == "1:05:05")
        #expect(duration.formatted(.time(pattern: .minuteSecond).locale(english)) == "65:05")
        #expect(duration.formatted(.time(pattern: .hourMinute).locale(english)) == "1:05")
        let units = Duration.seconds(3 * 3600 + 5 * 60)
        #expect(units.formatted(.units(width: .narrow).locale(english)) == "3h 5m")
        #expect(units.formatted(.units(width: .wide).locale(english)) == "3 hours, 5 minutes")
        #expect(units.formatted(.units(allowed: [.minutes], width: .wide).locale(english)) == "185 minutes")
    }

    @Test func languages() {
        let locale = Locale(identifier: "en_US")
        #expect(locale.language.languageCode?.identifier == "en")
        #expect(locale.language.region?.identifier == "US")
        #expect(locale.region?.identifier == "US")
        #expect(Locale(identifier: "zh_Hans_CN").language.script?.identifier == "Hans")
    }

    #if os(WASI) || canImport(Darwin)
    @Test func dateComponents() {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        #expect(formatter.string(from: 3725) == "1:02:05")
        formatter.allowedUnits = [.minute, .second]
        #expect(formatter.string(from: 65) == "1:05")
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        #expect(formatter.string(from: 3725) == "1h 2m 5s")
        #expect(formatter.string(from: 3600) == "1h")
        formatter.unitsStyle = .full
        #expect(formatter.string(from: 3725) == "1 hour, 2 minutes, 5 seconds")
    }
    #endif

    #if os(WASI)
    @Test func groupContainers() {
        #expect(FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.app")?.path.hasSuffix("group.app") == true)
    }
    #endif
    @Test func byteCounts() {
        func file(_ count: Int64) -> String { ByteCountFormatter.string(fromByteCount: count, countStyle: .file) }
        #expect(file(0) == "Zero KB")
        #expect(file(1) == "1 byte")
        #expect(file(999) == "999 bytes")
        #expect(file(1_000) == "1 KB")
        #expect(file(1_500_000) == "1.5 MB")
        #expect(file(2_000_000_000) == "2 GB")
        #expect(file(1_234_567_890) == "1.23 GB")
        #expect(ByteCountFormatter.string(fromByteCount: 1_048_576, countStyle: .memory) == "1 MB")
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = .useMB
        formatter.countStyle = .decimal
        #expect(formatter.string(fromByteCount: 1_500_000) == "1.5 MB")
    }

    @Test func nsStringNumbers() {
        func string(_ text: String) -> NSString { NSString(string: text) }
        #expect(string("12.5 kg").doubleValue == 12.5)
        #expect(string("  -3e2xyz").doubleValue == -300)
        #expect(string(".5").doubleValue == 0.5)
        #expect(string("abc").doubleValue == 0)
        #expect(string("42abc").integerValue == 42)
        #expect(string("-7.9").intValue == -7)
        #expect(string("YES").boolValue && string("007").boolValue && !string("0").boolValue && !string("no").boolValue)
    }

    @Test func currentCalendarAndTemporaryDirectory() {
        #expect(NSCalendar.current.identifier == Calendar.current.identifier)
        #expect(NSTemporaryDirectory().hasSuffix("/"))
    }
}

// Measurement formatting (WebFoundationFormats/MeasurementFormats.swift): CriticalMaps' road
// distances, OscarWeather's unit symbols and Mlem's response times. Linux's Foundation has no
// measurement format style or working MeasurementFormatter, so these hold on macOS and wasm.
#if !os(Linux)
@Suite struct MeasurementFormatTests {
    @Test func providedUnitsInEachWidth() {
        let distance = Measurement(value: 5, unit: UnitLength.kilometers)
        #expect(distance.formatted(.measurement(width: .abbreviated, usage: .asProvided).locale(english)) == "5 km")
        #expect(distance.formatted(.measurement(width: .wide, usage: .asProvided).locale(english)) == "5 kilometers")
        #expect(distance.formatted(.measurement(width: .narrow, usage: .asProvided).locale(english)) == "5km")
        #expect(Measurement(value: 1, unit: UnitLength.kilometers).formatted(.measurement(width: .wide, usage: .asProvided).locale(english)) == "1 kilometer")
        let warm = Measurement(value: 20, unit: UnitTemperature.celsius)
        #expect(warm.formatted(.measurement(width: .abbreviated, usage: .asProvided).locale(english)) == "20°C")
        #expect(warm.formatted(.measurement(width: .wide, usage: .asProvided).locale(english)) == "20 degrees Celsius")
        let scrolled = Measurement(value: 1234.4, unit: UnitLength.meters)
        #expect(scrolled.formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))).locale(english)) == "1,234 m")
    }

    @Test func usagesConvertToTheLocalesUnits() {
        // Apple's own examples for the format style.
        let trip = Measurement(value: 100, unit: UnitLength.kilometers)
        #expect(trip.formatted(.measurement(width: .wide, usage: .road).locale(english)) == "62 miles")
        let fever = Measurement(value: 38, unit: UnitTemperature.celsius)
        #expect(fever.formatted(.measurement(width: .wide, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(1))).locale(english)) == "100.4 degrees Fahrenheit")
        #expect(Measurement(value: 5, unit: UnitLength.kilometers).formatted(.measurement(width: .abbreviated, usage: .road).locale(Locale(identifier: "de_DE"))) == "5 km")
    }

    // OscarWeather picks its display units with `UnitTemperature(forLocale:)` and the rest.
    @Test func unitsForALocaleAndUsage() {
        let us = Locale(identifier: "en_US"), de = Locale(identifier: "de_DE"), gb = Locale(identifier: "en_GB")
        #expect(UnitTemperature(forLocale: us) == .fahrenheit)
        #expect(UnitTemperature(forLocale: de) == .celsius)
        #expect(UnitSpeed(forLocale: us, usage: .wind) == .milesPerHour)
        #expect(UnitSpeed(forLocale: de, usage: .wind) == .kilometersPerHour)
        #expect(UnitLength(forLocale: us, usage: .road) == .miles)
        #expect(UnitLength(forLocale: de, usage: .road) == .kilometers)
        #expect(UnitLength(forLocale: gb, usage: .road) == .miles)
        #expect(UnitLength(forLocale: us, usage: .rainfall) == .inches)
        #expect(UnitLength(forLocale: de, usage: .rainfall) == .millimeters)
        #expect(UnitPressure(forLocale: us, usage: .barometric) == .inchesOfMercury)
        #expect(UnitPressure(forLocale: de, usage: .barometric) == .hectopascals)
    }

    @Test func signStrategies() {
        let english = Locale(identifier: "en_US")
        #expect(1.5.formatted(.number.sign(strategy: .always()).locale(english)) == "+1.5")
        #expect((-1.5).formatted(.number.sign(strategy: .always()).locale(english)) == "-1.5")
        #expect(0.0.formatted(.number.sign(strategy: .always()).locale(english)) == "+0")
        #expect(0.0.formatted(.number.sign(strategy: .always(includingZero: false)).locale(english)) == "0")
        #expect((-1.5).formatted(.number.sign(strategy: .never).locale(english)) == "1.5")
        #expect(2.25.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false)).locale(english)) == "+2.2")
        #expect(5.formatted(.number.sign(strategy: .always()).locale(english)) == "+5")
        #expect(0.25.formatted(.percent.sign(strategy: .always()).locale(english)) == "+25%")
    }

    @Test func theAttributedFormMarksTheUnit() {
        let text = Measurement(value: 1, unit: UnitLength.kilometers).formatted(.measurement(width: .abbreviated, usage: .asProvided).locale(english).attributed)
        let unit = text.runs.filter { $0.measurement == .unit }.map { String(text[$0.range].characters) }.joined()
        let value = text.runs.filter { $0.measurement == .value }.map { String(text[$0.range].characters) }.joined()
        #expect(unit == "km" && value == "1")
        #expect(String(text.characters) == "1 km")
    }

    @Test func measurementFormatterUsesTheProvidedUnit() {
        let formatter = MeasurementFormatter()
        formatter.locale = english
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .short
        let latency = Measurement(value: 250, unit: UnitDuration.milliseconds)
        #expect(formatter.string(from: latency) == "250ms")
        formatter.unitStyle = .medium
        #expect(formatter.string(from: latency) == "250 ms")
        formatter.unitStyle = .long
        #expect(formatter.string(from: latency) == "250 milliseconds")
    }

    @Test func measurementFormatterRoundsToThreeDigitsByDefault() {
        let formatter = MeasurementFormatter()
        formatter.locale = english
        formatter.unitOptions = .providedUnit
        #expect(formatter.numberFormatter != nil)
        let length = Measurement(value: 12.3456, unit: UnitLength.meters)
        #expect(formatter.string(from: length) == "12.346 m")
        #expect(formatter.string(for: length) == "12.346 m")
        // A replacement number formatter's digit limits are used.
        let oneDigit = NumberFormatter()
        oneDigit.numberStyle = .decimal
        oneDigit.maximumFractionDigits = 1
        formatter.numberFormatter = oneDigit
        #expect(formatter.string(from: length) == "12.3 m")
    }

    /// A formatter's currency symbols (Dime lists them to match search text).
    @Test func numberFormatterNamesItsCurrency() {
        let formatter = NumberFormatter()
        formatter.locale = english
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        #expect(formatter.currencySymbol == "€")
        #expect(formatter.internationalCurrencySymbol == "EUR")
        formatter.currencyCode = "USD"
        #expect(formatter.currencySymbol == "$")
        #expect(formatter.internationalCurrencySymbol == "USD")
        formatter.currencyCode = "CHF"
        #expect(formatter.currencySymbol == "CHF")
    }
}
#endif
