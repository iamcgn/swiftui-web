// `NSDecimalNumber`'s arithmetic and rounding on wasm. The decimal number is `NSNumber` holding a
// double (NSNumber.swift), so these work on the double: a price, a share of one, a total rounded
// to cents, the amounts apps compute with them (WishKit's monthly price rounded up). A result is
// first taken to twelve significant digits, so that 0.1 × 3 rounded up to one place is 0.3, as
// Apple's decimal arithmetic gives, and not the 0.4 the double 0.30000000000000004 would round to.
// `init(decimal:)` and `decimalValue` are WebDecimalFormats', where `Decimal` is linked.
// Every member is on the final class or a struct, so a wasm build keeps only those an app calls.
#if os(WASI)
import FoundationEssentials

/// The value of `scale` that rounds nothing.
public let NSDecimalNoScale = Int16.max

extension NSNumber {
    /// How a result is rounded to its scale.
    public enum RoundingMode: UInt, Sendable {
        /// Half away from zero.
        case plain = 0
        /// Toward negative infinity.
        case down = 1
        /// Toward positive infinity.
        case up = 2
        /// Half to the even digit.
        case bankers = 3
    }

    /// What went wrong in a calculation, handed to a behavior's `exceptionDuringOperation`.
    public enum CalculationError: UInt, Sendable {
        case noError = 0, lossOfPrecision = 1, underflow = 2, overflow = 3, divideByZero = 4
    }

    public static var zero: NSDecimalNumber { NSDecimalNumber(value: 0) }
    public static var one: NSDecimalNumber { NSDecimalNumber(value: 1) }
    public static var notANumber: NSDecimalNumber { NSDecimalNumber(value: Double.nan) }
    public static var minimum: NSDecimalNumber { NSDecimalNumber(value: -Double.greatestFiniteMagnitude) }
    public static var maximum: NSDecimalNumber { NSDecimalNumber(value: Double.greatestFiniteMagnitude) }
    /// The default behavior: plain rounding, no scale, every error raised (here: the result
    /// stays not-a-number, as nothing is thrown across these calls).
    public class var defaultBehavior: NSDecimalNumberBehaviors { NSDecimalNumberHandler.default }

    /// The number `mantissa × 10^exponent`, negated when `isNegative`.
    public convenience init(mantissa: UInt64, exponent: Int16, isNegative: Bool) {
        let value = Self._snap(Double(mantissa) * Self._power(Int(exponent)))
        self.init(value: isNegative ? -value : value)
    }

    /// The number a decimal string spells (`"6.99"`, `"-1.5e3"`); not-a-number for any other text.
    public convenience init(string numberValue: String?) {
        let text = (numberValue ?? "").filter { $0 != " " && $0 != "\t" && $0 != "\n" }
        self.init(value: Double(text).map(Self._snap) ?? .nan)
    }
    /// The string read with the locale's decimal separator: a comma for the languages that write
    /// one (`"6,99"` in a French locale), the point otherwise.
    public convenience init(string numberValue: String?, locale: Any?) {
        var text = numberValue
        if let locale = locale as? Locale {
            let language = locale.identifier.prefix { $0 != "_" && $0 != "-" }
            if Self._commaLanguages.contains(String(language)) {
                text = text?.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            }
        }
        self.init(string: text)
    }
    private static let _commaLanguages: Set<String> = ["de", "fr", "es", "it", "pt", "nl", "ru", "pl", "sv", "da", "nb", "nn", "fi",
                                                        "tr", "cs", "sk", "hu", "ro", "uk", "el", "id", "vi", "hr", "sl", "sr", "bg", "lt", "lv", "et"]

    public func adding(_ decimalNumber: NSDecimalNumber) -> NSDecimalNumber { adding(decimalNumber, withBehavior: nil) }
    public func adding(_ decimalNumber: NSDecimalNumber, withBehavior behavior: NSDecimalNumberBehaviors?) -> NSDecimalNumber {
        _result(doubleValue + decimalNumber.doubleValue, behavior)
    }
    public func subtracting(_ decimalNumber: NSDecimalNumber) -> NSDecimalNumber { subtracting(decimalNumber, withBehavior: nil) }
    public func subtracting(_ decimalNumber: NSDecimalNumber, withBehavior behavior: NSDecimalNumberBehaviors?) -> NSDecimalNumber {
        _result(doubleValue - decimalNumber.doubleValue, behavior)
    }
    public func multiplying(by decimalNumber: NSDecimalNumber) -> NSDecimalNumber { multiplying(by: decimalNumber, withBehavior: nil) }
    public func multiplying(by decimalNumber: NSDecimalNumber, withBehavior behavior: NSDecimalNumberBehaviors?) -> NSDecimalNumber {
        _result(doubleValue * decimalNumber.doubleValue, behavior)
    }
    public func dividing(by decimalNumber: NSDecimalNumber) -> NSDecimalNumber { dividing(by: decimalNumber, withBehavior: nil) }
    public func dividing(by decimalNumber: NSDecimalNumber, withBehavior behavior: NSDecimalNumberBehaviors?) -> NSDecimalNumber {
        if decimalNumber.doubleValue == 0 {
            return (behavior ?? NSDecimalNumber.defaultBehavior).exceptionDuringOperation(
                NSSelectorFromString("decimalNumberByDividingBy:withBehavior:"), error: .divideByZero, leftOperand: self, rightOperand: decimalNumber) ?? .notANumber
        }
        return _result(doubleValue / decimalNumber.doubleValue, behavior)
    }
    public func raising(toPower power: Int) -> NSDecimalNumber { raising(toPower: power, withBehavior: nil) }
    public func raising(toPower power: Int, withBehavior behavior: NSDecimalNumberBehaviors?) -> NSDecimalNumber {
        var result = 1.0
        for _ in 0..<max(power, 0) { result *= doubleValue }
        return _result(result, behavior)
    }
    public func multiplying(byPowerOf10 power: Int16) -> NSDecimalNumber { multiplying(byPowerOf10: power, withBehavior: nil) }
    public func multiplying(byPowerOf10 power: Int16, withBehavior behavior: NSDecimalNumberBehaviors?) -> NSDecimalNumber {
        _result(doubleValue * Self._power(Int(power)), behavior)
    }
    /// The number rounded to the behavior's scale in its rounding mode.
    public func rounding(accordingToBehavior behavior: NSDecimalNumberBehaviors?) -> NSDecimalNumber {
        _result(doubleValue, behavior ?? NSDecimalNumber.defaultBehavior)
    }

    private func _result(_ value: Double, _ behavior: NSDecimalNumberBehaviors?) -> NSDecimalNumber {
        let snapped = Self._snap(value)
        guard let behavior, behavior.scale() != NSDecimalNoScale, snapped.isFinite else { return NSDecimalNumber(value: snapped) }
        return NSDecimalNumber(value: Self._round(snapped, scale: Int(behavior.scale()), mode: behavior.roundingMode()))
    }

    package static func _round(_ value: Double, scale: Int, mode: RoundingMode) -> Double {
        let factor = _power(scale)
        let scaled = _snap(value * factor)
        let rule: FloatingPointRoundingRule
        switch mode {
        case .plain: rule = .toNearestOrAwayFromZero
        case .down: rule = .down
        case .up: rule = .up
        case .bankers: rule = .toNearestOrEven
        }
        return _snap(scaled.rounded(rule) / factor)
    }

    /// The value at twelve significant digits (the double's noise below them dropped).
    package static func _snap(_ value: Double) -> Double {
        guard value.isFinite, value != 0 else { return value }
        let magnitude = Int((abs(value)).log10Floor)
        let factor = _power(11 - magnitude)
        guard factor.isFinite, factor > 0 else { return value }
        let snapped = (value * factor).rounded() / factor
        return snapped.isFinite ? snapped : value
    }

    package static func _power(_ exponent: Int) -> Double {
        var result = 1.0
        for _ in 0..<abs(exponent) { result *= 10 }
        return exponent < 0 ? 1 / result : result
    }
}

private extension Double {
    /// ⌊log10(self)⌋ for a positive finite value, by repeated division (no libm on the path).
    var log10Floor: Double {
        var exponent = 0.0
        var value = self
        while value >= 10 { value /= 10; exponent += 1 }
        while value < 1 { value *= 10; exponent -= 1 }
        return exponent
    }
}

/// How a decimal number's operations round and what they do on an error.
public protocol NSDecimalNumberBehaviors {
    func roundingMode() -> NSDecimalNumber.RoundingMode
    func scale() -> Int16
    func exceptionDuringOperation(_ operation: Selector, error: NSDecimalNumber.CalculationError,
                                  leftOperand: NSDecimalNumber, rightOperand: NSDecimalNumber?) -> NSDecimalNumber?
}

/// A behavior made of its settings: `NSDecimalNumberHandler(roundingMode: .plain, scale: 2, …)`
/// rounds results to cents.
public final class NSDecimalNumberHandler: NSDecimalNumberBehaviors, @unchecked Sendable {
    private let mode: NSDecimalNumber.RoundingMode
    private let places: Int16

    public static let `default` = NSDecimalNumberHandler(roundingMode: .plain, scale: NSDecimalNoScale, raiseOnExactness: false,
                                                         raiseOnOverflow: true, raiseOnUnderflow: true, raiseOnDivideByZero: true)
    public class var defaultDecimalNumberHandler: NSDecimalNumberHandler { .default }

    public init(roundingMode: NSDecimalNumber.RoundingMode, scale: Int16, raiseOnExactness exact: Bool, raiseOnOverflow overflow: Bool,
                raiseOnUnderflow underflow: Bool, raiseOnDivideByZero divideByZero: Bool) {
        mode = roundingMode
        places = scale
    }

    public func roundingMode() -> NSDecimalNumber.RoundingMode { mode }
    public func scale() -> Int16 { places }
    /// Not-a-number for a division by zero (Apple raises an Objective-C exception, which a wasm
    /// page cannot catch, when `raiseOnDivideByZero`); nil, the result kept, for the other errors.
    public func exceptionDuringOperation(_ operation: Selector, error: NSDecimalNumber.CalculationError,
                                         leftOperand: NSDecimalNumber, rightOperand: NSDecimalNumber?) -> NSDecimalNumber? {
        error == .divideByZero ? .notANumber : nil
    }
}
#endif
