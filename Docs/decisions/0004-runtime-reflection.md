# 0004. DynamicProperty discovery uses stdlib key-path reflection; @Observable uses withObservationTracking

Date: 2026-09-01
Status: accepted

## Context
Without AttributeGraph the runtime must find `@State`-style stored properties in arbitrary user
`View` structs and install storage into them, and must know which `@Observable` properties a
body read. Both had to be proven on wasm before designing the runtime around them.

## Decision
- Field discovery: `@_spi(Reflection) import Swift` + `_forEachFieldWithKeyPath(of:options:body:)`,
  cached per view type; the value type is tested against the `DynamicProperty` protocol and the
  existential is opened once to build an installer closure.
- Dependency tracking: each body evaluation runs inside `withObservationTracking`; `onChange`
  marks the node dirty and schedules a flush.
- `CGFloat`/`CGRect` come from `Foundation` on wasm/Linux and from the `CoreGraphics` overlay on
  Apple platforms; the thin `SwiftUI` module re-exports both so unmodified sources compile.

## Evidence
Spike 0.4 (`Tests/CoreRuntimeTests/ReflectionSpikeTests.swift`), 2026-09-01: key-path discovery
(field names in declaration order, generic `SpikeState<Value>` installed through the opened
existential), `Mirror`, `AnyHashable`, `withObservationTracking` firing synchronously on mutation,
and `CGRect(x:y:width:height:)` all pass **natively on macOS and on wasm32-unknown-wasip1**
(`swift package --disable-sandbox --swift-sdk swift-6.3.3-RELEASE_wasm js test`, Node 18).

## Consequences
- No registration macro is needed; `@State` etc. can be plain property wrappers.
- wasm32 gotcha recorded: `Int` is 32-bit there (a `1 << 53` overflowed in the spike). Use
  `Int64`/`UInt64`/`Double` for anything that must exceed 2^31, and test on wasm early.
