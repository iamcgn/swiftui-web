// Apple's `Darwin` for wasm: the C library (WASILibc), and what Darwin declares beyond it that
// packages call in their `#if canImport(Darwin)` branches, which are their iOS code: the unfair
// lock (combine-schedulers' `Lock`, Mlem) and the mach clock (DarwinShims, the C half).
// SwiftUIWeb's own sources test for Apple's with `canImport(Darwin) && !os(WASI)`.
#if os(WASI)
@_exported import WASILibc
@_exported import DarwinShims
#endif
