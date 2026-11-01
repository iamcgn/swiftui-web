// Foundation's formatting that apps call and the wasm stand-ins add (Packages/WebGraphics
// WebFoundationFormats/MoreFormats.swift and WebDecimalFormats/DecimalFormats.swift): the same
// answers as Foundation's on macOS and Linux, in en_US.
import Testing
import WebFoundation
import WebFoundationFormats
import WebDecimalFormats

private let english = Locale(identifier: "en_US")

@Suite struct FoundationFormatTests {
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
}
