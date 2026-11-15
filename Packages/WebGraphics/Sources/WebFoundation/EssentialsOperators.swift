// The operators FoundationEssentials declares on its own types and that no standard-library
// protocol carries: `Date + TimeInterval` and `Decimal / Decimal`. A module's operator methods
// are found through the module's own lookup table, which a name-by-name re-export
// (WebFoundation.swift) does not open: an importer finds `Date` and its methods but not
// `Date.+`. Declared here, they are found through this module, with FoundationEssentials'
// behaviour. (`==`, `<`, `+` on `Decimal` and the rest come with the conformances to Equatable,
// Comparable and the numeric protocols.)
#if os(WASI)
// `_NSDecimalDivide` is the division FoundationEssentials' own `/` makes (NaN on an error).
@_spi(SwiftCorelibsFoundation) import FoundationEssentials

extension Date {
    public static func + (lhs: Date, rhs: TimeInterval) -> Date { lhs.addingTimeInterval(rhs) }
    public static func - (lhs: Date, rhs: TimeInterval) -> Date { lhs.addingTimeInterval(-rhs) }
    public static func += (lhs: inout Date, rhs: TimeInterval) { lhs = lhs.addingTimeInterval(rhs) }
    public static func -= (lhs: inout Date, rhs: TimeInterval) { lhs = lhs.addingTimeInterval(-rhs) }
}

extension Decimal {
    public static func / (lhs: Decimal, rhs: Decimal) -> Decimal {
        var result = Decimal()
        var dividend = lhs, divisor = rhs
        _ = _NSDecimalDivide(&result, &dividend, &divisor, .plain)
        return result
    }

    public static func /= (lhs: inout Decimal, rhs: Decimal) { lhs = lhs / rhs }
}
#endif
