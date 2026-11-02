// `import CoreFoundation` on wasm (decision 0021): the wasm SDK has no Core Foundation, and
// packages import it by name for its CF types and constants (Kingfisher's image code, keychain
// wrappers). WebFoundation's names (CoreFoundation.swift there) are what it means here.
#if os(WASI)
@_exported import WebFoundation
#endif
