// The simd library SceneKit code calls (Docs/elements/SceneKit.md, "simd"): Apple's SceneKit
// brings the simd module with it, so a file that imports SceneKit names `simd_float4x4`,
// `simd_quatf` and `simd_normalize` without importing simd. Where the platform has the simd
// module (Apple's) it is re-exported. Elsewhere (wasm, Linux) WebGraphics' WebSIMD is: the vector
// names over the standard library's SIMD types, column-major 3x3 and 4x4 float matrices, unit
// quaternions as (ix, iy, iz, r) and the functions that work on them. The `simd` shadow
// re-exports the same module on wasm, so a file importing both sees one set.
#if canImport(simd) && !os(WASI)
@_exported import simd
#else
@_exported import WebSIMD
#endif
