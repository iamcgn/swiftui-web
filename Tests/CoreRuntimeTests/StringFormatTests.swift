// `String(format:)`: the numeric cases run everywhere, so Foundation on Apple platforms and Linux
// checks the expectations the wasm stand-in has to meet; the string and positional cases are
// wasm's (Linux's Foundation takes no Swift strings for `%@`). On wasm the cases call the
// stand-in's formatter by name: another file of this target imports the SDK's own Foundation,
// whose `String(format:)` (CVarArg, so preferred) would otherwise answer.
import Testing
import WebFoundation

private func format(_ format: String, _ arguments: Any...) -> String {
    #if os(WASI)
    _PrintfFormat.format(format, arguments)
    #else
    format(format, arguments: arguments.map { $0 as! CVarArg })
    #endif
}

@Suite struct StringFormatTests {
    @Test func integersAndFlags() {
        #expect(format("%5.2f|%-4d|%04d|%x|%X|%o", 3.14159, 7, 42, 255, 255, 8) == " 3.14|7   |0042|ff|FF|10")
        #expect(format("%+d|% d|%i|%#x|%#o|%lld|%lu", 5, 5, 3, 255, 8, Int64(-9), UInt(3)) == "+5| 5|3|0xff|010|-9|3")
        #expect(format("%*d|%-*d|", 5, 42, 3, 1) == "   42|1  |")
        #expect(format("%u|%x|%hhd|%ld", -1, -1, 300, Int64(5_000_000_000)) == "4294967295|ffffffff|44|5000000000")
        #expect(format("100%% of %d", 3) == "100% of 3")
    }

    @Test func floatingPoint() {
        #expect(format("%e|%.1e|%E", 12345.678, 9.96, 0.5) == "1.234568e+04|1.0e+01|5.000000E-01")
        #expect(format("%g|%g|%g|%G|%g", 0.0001234, 1234567.0, 100.0, 1e-10, 0.0) == "0.0001234|1.23457e+06|100|1E-10|0")
        #expect(format("%.2f|%.0f|%.0f|%05.1f|%.3f", 2.675, 2.5, 3.5, -2.25, Float(0.1)) == "2.67|2|4|-02.2|0.100")
        #expect(format("%5.1f%%|%-8.3f|", 42.0, 1.0) == " 42.0%|1.000   |")
    }

    #if os(WASI)
    @Test func stringsAndPositions() {
        #expect(format("%@ has %d items", "cart", 3) == "cart has 3 items")
        #expect(format("%2$@ %1$@", "world", "hello") == "hello world")
        #expect(format("[%5@][%-5@][%.3s]", "ab", "cd", "abcdef") == "[   ab][cd   ][abc]")
        #expect(format("%c%c", 72, Character("i")) == "Hi")
        let missing: String? = nil
        let present: String? = "here"
        #expect(format("%@ %@", missing as Any, present as Any) == "(null) here")
        #expect(_PrintfFormat.format("%d items", [4]) == "4 items")
        #expect("Total: " + format("%.1f", 9.25) == "Total: 9.2")
        #expect(format("%d of %d", 1, 2) == "1 of 2")
        #expect(format("%d|%.1f", NSNumber(value: 7), NSNumber(value: 1.5)) == "7|1.5")
    }
    #endif
}
