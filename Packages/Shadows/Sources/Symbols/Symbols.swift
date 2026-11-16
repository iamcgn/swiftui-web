// Apple's Symbols for the web (ButtonKit): the symbol effect types (`SymbolEffect`,
// `DrawOnSymbolEffect`, `SymbolEffectOptions`), which SwiftUI's runtime plays. A file that
// imports only Symbols sees them as it does on iOS. It lives here, not in the root package,
// because AppKit imports Apple's Symbols on macOS: a root-package module of that name would
// shadow it for every macOS build, the testing library's included. Only the wasm SDK lacks it.
#if os(WASI)
@_exported import SwiftUI
#endif
