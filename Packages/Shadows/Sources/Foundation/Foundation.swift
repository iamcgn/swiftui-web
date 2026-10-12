// `import Foundation` on wasm (decision 0021): WebFoundation's value types (decision 0017) and
// the modules Apple's Foundation re-exports, so an app file that imports Foundation beside
// SwiftUI sees one `URL`, one `Data`, libm's functions, `@Observable` and `DispatchQueue`.
#if os(WASI)
@_exported import WebFoundation
@_exported import WASILibc
@_exported import Observation
#endif
