// `import Combine` on wasm (decision 0021): WebCombine, the Combine-free publishers SwiftUI is
// built on (the ObservableObject family, Just, the subjects, Future, the operators), under
// the name an app's source imports. Apple's Foundation re-exports Combine, so the shadow
// `Foundation` re-exports this module too.
#if os(WASI)
@_exported import WebCombine
#endif
