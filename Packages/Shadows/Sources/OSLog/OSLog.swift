// Apple's `OSLog` module for wasm (Docs/coverage.md: 6 apps): on iOS it re-exports `os`, where
// `Logger` lives, and adds reading the log store back, which a page has no store for.
#if os(WASI)
@_exported import os
#endif
