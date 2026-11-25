// `import Combine` on wasm (decision 0021): WebCombine, the Combine-free publishers SwiftUI is
// built on (the ObservableObject family, Just, the subjects, Future, the operators), under
// the name an app's source imports. Apple's Foundation and SwiftUI import Combine without
// re-exporting it, so a file names Combine's types only after its own `import Combine`.
#if os(WASI)
@_exported import WebCombine
#endif
