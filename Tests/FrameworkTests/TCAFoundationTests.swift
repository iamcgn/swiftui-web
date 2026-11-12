// The Foundation members The Composable Architecture's stack reaches for in iOS code:
// swift-custom-dump prints exceptions and attributed strings, swift-clocks and the TCA test store
// format durations down to the microsecond. They run against Apple's Foundation on macOS too, so
// both answer the same.
#if os(WASI) || canImport(Darwin)
import Testing
import WebFoundation
import WebFoundationFormats

private let english = Locale(identifier: "en_US")

@Suite struct TCAFoundationTests {
    @Test func exceptionsCarryTheirNameReasonAndUserInfo() {
        let exception = NSException(name: NSExceptionName("TestException"), reason: "it broke", userInfo: ["code": 7])
        #expect(exception.name == NSExceptionName("TestException"))
        #expect(exception.name.rawValue == "TestException")
        #expect(exception.reason == "it broke")
        #expect(exception.userInfo?["code"] as? Int == 7)
        #expect(NSException(name: .invalidArgumentException, reason: nil, userInfo: nil).reason == nil)
    }

    @Test func theUncaughtExceptionHandlerIsKept() {
        let previous = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler { _ in }
        #expect(NSGetUncaughtExceptionHandler() != nil)
        NSSetUncaughtExceptionHandler(nil)
        #expect(NSGetUncaughtExceptionHandler() == nil)
        NSSetUncaughtExceptionHandler(previous)
    }

    @Test func durationsFormatDownToTheNanosecond() {
        let duration = Duration.milliseconds(1) + .microseconds(5)
        #expect(duration.formatted(.units(allowed: [.milliseconds, .microseconds], width: .wide).locale(english))
                == "1 millisecond, 5 microseconds")
        #expect(Duration.microseconds(250).formatted(.units(allowed: [.microseconds], width: .wide).locale(english))
                == "250 microseconds")
        #expect(Duration.nanoseconds(42).formatted(.units(allowed: [.nanoseconds], width: .wide).locale(english))
                == "42 nanoseconds")
        #expect(Duration.seconds(2).formatted(.units(allowed: [.seconds, .milliseconds], width: .wide).locale(english))
                == "2 seconds")
    }

    @Test func attributedStringsBridgeToTheirObjectForm() {
        let object = NSAttributedString(AttributedString("hello"))
        #expect(object.string == "hello")
        #expect(object.length == 5)
    }
}
#endif
