// Apple's `simd` module for wasm, as far as its vector code goes: the `simd_float3`-style type
// names and the geometric and common functions in their C and Swift spellings, from WebGraphics'
// WebSIMD (held to Apple's simd by WebSIMDTests on macOS). OscarWeather's atmosphere renderer
// mixes and clamps colours with them. The matrix and quaternion types aren't here yet.
#if os(WASI)
@_exported import WebSIMD
#endif
