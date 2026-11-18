// Apple's `OSLog` module for wasm (Docs/coverage.md: 6 apps): on iOS it re-exports `os`, where
// `Logger` lives, and adds reading the log store back, which a page has no store for. Apple's
// also re-exports Foundation, so a file that imports only OSLog (and Combine) names
// `ProcessInfo` and formats a `String` as a `CVarArg` (the Composable Architecture's Logger and
// SignpostReducer).
#if os(WASI)
@_exported import os
@_exported import Foundation
#endif
