// The operators FoundationEssentials declares on its own types and that no standard-library
// protocol carries: `Date + TimeInterval` and `Decimal / Decimal`. A module's operator methods
// are found through the module's own lookup table, which a name-by-name re-export
// (WebFoundation.swift) does not open: an importer finds `Date` and its methods but not
// `Date.+`. Declared here, they are found through this module, with FoundationEssentials'
// behaviour. (`==`, `<`, `+` on `Decimal` and the rest come with the conformances to Equatable,
// Comparable and the numeric protocols.)
#if os(WASI)
import FoundationEssentials
import WebDecimalDivision

extension Date {
    public static func + (lhs: Date, rhs: TimeInterval) -> Date { lhs.addingTimeInterval(rhs) }
    public static func - (lhs: Date, rhs: TimeInterval) -> Date { lhs.addingTimeInterval(-rhs) }
    public static func += (lhs: inout Date, rhs: TimeInterval) { lhs = lhs.addingTimeInterval(rhs) }
    public static func -= (lhs: inout Date, rhs: TimeInterval) { lhs = lhs.addingTimeInterval(-rhs) }
}

// Emitted into the app that divides, never into WebFoundation's object: a function here that
// names `Decimal` links FoundationEssentials' Decimal into every app (WebDecimalDivision says
// why, decision 0006).
extension Decimal {
    @_alwaysEmitIntoClient
    public static func / (lhs: Decimal, rhs: Decimal) -> Decimal { _essentialsDecimalDivide(lhs, rhs) }

    @_alwaysEmitIntoClient
    public static func /= (lhs: inout Decimal, rhs: Decimal) { lhs = _essentialsDecimalDivide(lhs, rhs) }
}
#endif
