// `NSDecimalNumber`'s arithmetic and rounding, `NSString` from bytes, `FileManager`'s path forms
// and strings read from and written to files: what WishKit, TelemetryDeck, OpenGraph,
// SwiftyBeaver and SwiftCommonMark call. The shared cases run against Foundation on macOS and
// Linux too, so the wasm forms answer as Apple's do.
import Testing
import WebFoundation
import WebDecimalFormats

@Suite struct DecimalNumberAndFilesTests {
    func handler(_ mode: NSDecimalNumber.RoundingMode, scale: Int16) -> NSDecimalNumberHandler {
        NSDecimalNumberHandler(roundingMode: mode, scale: scale, raiseOnExactness: false, raiseOnOverflow: false,
                               raiseOnUnderflow: false, raiseOnDivideByZero: false)
    }

    @Test func arithmeticAndRounding() {
        // WishKit's yearly price per month, rounded up to whole cents.
        let monthly = NSDecimalNumber(string: "6.99").multiplying(by: NSDecimalNumber(value: 100)).dividing(by: NSDecimalNumber(value: 12))
        #expect(monthly.doubleValue == 58.25)
        #expect(monthly.rounding(accordingToBehavior: handler(.up, scale: 0)).intValue == 59)
        #expect(monthly.rounding(accordingToBehavior: handler(.down, scale: 0)).intValue == 58)
        // Decimal arithmetic: 0.1 × 3 is 0.3, which rounds up to 0.3 at one place.
        let tenth = NSDecimalNumber(string: "0.1").multiplying(by: NSDecimalNumber(value: 3))
        #expect(tenth.rounding(accordingToBehavior: handler(.up, scale: 1)).doubleValue == 0.3)
        #expect(NSDecimalNumber(string: "2.5").rounding(accordingToBehavior: handler(.plain, scale: 0)).intValue == 3)
        #expect(NSDecimalNumber(string: "2.5").rounding(accordingToBehavior: handler(.bankers, scale: 0)).intValue == 2)
        #expect(NSDecimalNumber(string: "-1.236").rounding(accordingToBehavior: handler(.down, scale: 2)).doubleValue == -1.24)
        #if os(WASI) || canImport(Darwin)
        // Foundation on Linux leaves the sum unrounded.
        #expect(NSDecimalNumber(string: "1.234").adding(NSDecimalNumber(string: "1"), withBehavior: handler(.plain, scale: 1)).doubleValue == 2.2)
        #endif
        // Compared as text: Linux's decimal-to-double conversion is a unit off in the last place.
        #expect(NSDecimalNumber(string: "19.49").subtracting(NSDecimalNumber.one).description == "18.49")
        #expect(NSDecimalNumber(string: "1.5").raising(toPower: 2).doubleValue == 2.25)
        #expect(NSDecimalNumber(string: "1.5").multiplying(byPowerOf10: 2).intValue == 150)
        #expect(NSDecimalNumber(mantissa: 1999, exponent: -2, isNegative: false).description == "19.99")
        #expect(NSDecimalNumber(string: "abc").doubleValue.isNaN)
        #expect(NSDecimalNumber(decimal: Decimal(string: "4.75")!).doubleValue == 4.75)
        #expect(NSDecimalNumber(string: "4.75").decimalValue == Decimal(string: "4.75")!)
    }

    #if os(WASI) || canImport(Darwin)
    /// A behavior of the app's own, as WishKit's `RoundUp` (Foundation on Linux has no `Selector`).
    final class RoundUp: NSDecimalNumberBehaviors {
        func scale() -> Int16 { 0 }
        func exceptionDuringOperation(_ operation: Selector, error: NSDecimalNumber.CalculationError,
                                      leftOperand: NSDecimalNumber, rightOperand: NSDecimalNumber?) -> NSDecimalNumber? { 0 }
        func roundingMode() -> NSDecimalNumber.RoundingMode { .up }
    }

    @Test func appBehavior() {
        #expect(NSDecimalNumber(decimal: 1949 / 12).rounding(accordingToBehavior: RoundUp()).intValue == 163)
    }

    @Test func stringFromBytes() throws {
        let data = Data("héllo wörld".utf8)
        #expect(NSString(data: data, encoding: String.Encoding.utf8.rawValue)?.description == "héllo wörld")
        #expect(NSString(data: Data([0xFF, 0xFE]), encoding: String.Encoding.utf8.rawValue) == nil)
        var converted: NSString?
        #expect(NSString.stringEncoding(for: data, encodingOptions: nil, convertedString: &converted, usedLossyConversion: nil) == String.Encoding.utf8.rawValue)
        #expect(converted?.description == "héllo wörld")
    }
    #endif

    #if os(WASI)
    @Test func guessesFromAByteOrderMark() {
        var converted: NSString?
        let utf16 = Data([0xFF, 0xFE, 0x68, 0x00, 0x69, 0x00])
        #expect(NSString.stringEncoding(for: utf16, encodingOptions: nil, convertedString: &converted, usedLossyConversion: nil) == String.Encoding.utf16.rawValue)
        #expect(converted?.description == "hi")
        // Bytes that are not UTF-8 read as Windows Latin 1.
        #expect(NSString.stringEncoding(for: Data([0x63, 0x61, 0x66, 0xE9]), encodingOptions: nil, convertedString: &converted, usedLossyConversion: nil) == String.Encoding.windowsCP1252.rawValue)
        #expect(converted?.description == "café")
    }
    #endif

    @Test func filesByPath() throws {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent("decimal-files-\(UInt32.random(in: 0...UInt32.max))", isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: directory) }
        let first = directory.appendingPathComponent("app.log").path
        let second = directory.appendingPathComponent("app.1.log").path
        let third = directory.appendingPathComponent("app.2.log").path

        try "line one\n".write(toFile: first, atomically: true, encoding: .utf8)
        #expect(try String(contentsOfFile: first, encoding: .utf8) == "line one\n")
        try manager.moveItem(atPath: first, toPath: second)
        #expect(!manager.fileExists(atPath: first))
        #expect(try String(contentsOf: URL(fileURLWithPath: second), encoding: .utf8) == "line one\n")
        try manager.copyItem(atPath: second, toPath: third)
        #expect(manager.contentsEqual(atPath: second, andPath: third))
        #expect(manager.isReadableFile(atPath: third))
        #expect(manager.isWritableFile(atPath: third))
        #expect(manager.displayName(atPath: third) == "app.2.log")
        #expect(try manager.subpathsOfDirectory(atPath: directory.path).sorted() == ["app.1.log", "app.2.log"])

        var used = String.Encoding.ascii
        #expect(try String(contentsOfFile: third, usedEncoding: &used) == "line one\n")
        #expect(used == .utf8)
        #expect(throws: (any Error).self) { _ = try String(contentsOfFile: first, encoding: .utf8) }
    }
}
