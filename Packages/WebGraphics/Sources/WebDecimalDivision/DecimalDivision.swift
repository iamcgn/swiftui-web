// FoundationEssentials' own `Decimal /`, reached under a name WebFoundation's `Decimal /`
// (EssentialsOperators.swift) can call. Inside WebFoundation that operator shadows
// FoundationEssentials' one of the same signature, so `lhs / rhs` there would call itself; this
// module imports FoundationEssentials alone and sees only its operator.
//
// `@_alwaysEmitIntoClient`, like the operator that calls it: the division is compiled into the
// app that divides, and no object WebFoundation ships names `Decimal`. Naming it links
// FoundationEssentials' Decimal and most of the library with it (about 950 KB brotli in
// Counter, decision 0006), which an app that never divides a Decimal should not ship.
#if os(WASI)
import FoundationEssentials

@_alwaysEmitIntoClient
public func _essentialsDecimalDivide(_ lhs: Decimal, _ rhs: Decimal) -> Decimal { lhs / rhs }
#endif
