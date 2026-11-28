// The vector part of Apple's `simd` module, over the standard library's SIMD types: the
// `simd_float3`-style names and the geometric and common functions, in both their C spellings
// (`simd_dot`, `simd_mix`, `simd_clamp`, ...) and the Swift ones (`dot`, `mix(_:_:t:)`,
// `clamp(_:min:max:)`, ...). The `simd` shadow (Packages/Shadows) re-exports it on wasm, where
// Apple's module isn't; WebSIMDTests hold it to Apple's on macOS. The definitions follow Apple's
// simd headers' documentation: mix is x + t(y − x), smoothstep is t²(3 − 2t) of the clamped
// ratio, step is 0 below the edge and 1 from it, fract stays below 1, sign is 0 at 0 and NaN.
// The matrices and quaternions are in SIMDMatrices.swift.

// MARK: - Type names

public typealias simd_float1 = Float
public typealias simd_float2 = SIMD2<Float>
public typealias simd_float3 = SIMD3<Float>
public typealias simd_float4 = SIMD4<Float>
public typealias simd_float8 = SIMD8<Float>
public typealias simd_float16 = SIMD16<Float>
public typealias simd_double1 = Double
public typealias simd_double2 = SIMD2<Double>
public typealias simd_double3 = SIMD3<Double>
public typealias simd_double4 = SIMD4<Double>
public typealias simd_double8 = SIMD8<Double>
public typealias simd_int1 = Int32
public typealias simd_int2 = SIMD2<Int32>
public typealias simd_int3 = SIMD3<Int32>
public typealias simd_int4 = SIMD4<Int32>
public typealias simd_uint1 = UInt32
public typealias simd_uint2 = SIMD2<UInt32>
public typealias simd_uint3 = SIMD3<UInt32>
public typealias simd_uint4 = SIMD4<UInt32>
public typealias simd_uchar4 = SIMD4<UInt8>
public typealias simd_ushort2 = SIMD2<UInt16>
public typealias simd_bool = Bool

public typealias float2 = SIMD2<Float>
public typealias float3 = SIMD3<Float>
public typealias float4 = SIMD4<Float>
public typealias double2 = SIMD2<Double>
public typealias double3 = SIMD3<Double>
public typealias double4 = SIMD4<Double>
public typealias int2 = SIMD2<Int32>
public typealias int3 = SIMD3<Int32>
public typealias int4 = SIMD4<Int32>
public typealias uint2 = SIMD2<UInt32>
public typealias uint3 = SIMD3<UInt32>
public typealias uint4 = SIMD4<UInt32>

// MARK: - Scalars

/// `x` held between `min` and `max`.
public func simd_clamp<T: BinaryFloatingPoint>(_ x: T, _ min: T, _ max: T) -> T { Swift.min(Swift.max(x, min), max) }
/// `x + t(y − x)`.
public func simd_mix<T: BinaryFloatingPoint>(_ x: T, _ y: T, _ t: T) -> T { x + t * (y - x) }
/// 0 below `edge`, 1 from it.
public func simd_step<T: BinaryFloatingPoint>(_ edge: T, _ x: T) -> T { x < edge ? 0 : 1 }
/// A smooth step from 0 at `edge0` to 1 at `edge1`.
public func simd_smoothstep<T: BinaryFloatingPoint>(_ edge0: T, _ edge1: T, _ x: T) -> T {
    let t = simd_clamp((x - edge0) / (edge1 - edge0), 0, 1)
    return t * t * (3 - 2 * t)
}
/// The fractional part of `x`, always below 1.
public func simd_fract<T: BinaryFloatingPoint>(_ x: T) -> T { Swift.min(x - x.rounded(.down), T(1).nextDown) }
/// -1, 0 or 1 by the sign of `x`; 0 for NaN.
public func simd_sign<T: BinaryFloatingPoint>(_ x: T) -> T { x == 0 || x.isNaN ? 0 : (x < 0 ? -1 : 1) }
/// `1 / x`.
public func simd_recip<T: BinaryFloatingPoint>(_ x: T) -> T { 1 / x }
/// `1 / √x`.
public func simd_rsqrt<T: BinaryFloatingPoint>(_ x: T) -> T { 1 / x.squareRoot() }

// MARK: - Vectors, C spellings

/// The sum of the elementwise products.
public func simd_dot<V: SIMD>(_ x: V, _ y: V) -> V.Scalar where V.Scalar: BinaryFloatingPoint { (x * y).sum() }
/// The squared length.
public func simd_length_squared<V: SIMD>(_ x: V) -> V.Scalar where V.Scalar: BinaryFloatingPoint { simd_dot(x, x) }
/// The length.
public func simd_length<V: SIMD>(_ x: V) -> V.Scalar where V.Scalar: BinaryFloatingPoint { simd_length_squared(x).squareRoot() }
/// The sum of the absolute values.
public func simd_norm_one<V: SIMD>(_ x: V) -> V.Scalar where V.Scalar: BinaryFloatingPoint { simd_abs(x).sum() }
/// The largest absolute value.
public func simd_norm_inf<V: SIMD>(_ x: V) -> V.Scalar where V.Scalar: BinaryFloatingPoint { simd_abs(x).max() }
/// The squared distance between two points.
public func simd_distance_squared<V: SIMD>(_ x: V, _ y: V) -> V.Scalar where V.Scalar: BinaryFloatingPoint { simd_length_squared(x - y) }
/// The distance between two points.
public func simd_distance<V: SIMD>(_ x: V, _ y: V) -> V.Scalar where V.Scalar: BinaryFloatingPoint { simd_length(x - y) }
/// `x` scaled to length 1.
public func simd_normalize<V: SIMD>(_ x: V) -> V where V.Scalar: BinaryFloatingPoint { x / simd_length(x) }
/// The cross product.
public func simd_cross<T: BinaryFloatingPoint>(_ x: SIMD3<T>, _ y: SIMD3<T>) -> SIMD3<T> {
    SIMD3(x.y * y.z - x.z * y.y, x.z * y.x - x.x * y.z, x.x * y.y - x.y * y.x)
}
/// The cross product of two 2-vectors, as a 3-vector along z.
public func simd_cross<T: BinaryFloatingPoint>(_ x: SIMD2<T>, _ y: SIMD2<T>) -> SIMD3<T> { SIMD3(0, 0, x.x * y.y - x.y * y.x) }
/// `x` projected onto `y`.
public func simd_project<V: SIMD>(_ x: V, _ y: V) -> V where V.Scalar: BinaryFloatingPoint { simd_dot(x, y) / simd_dot(y, y) * y }
/// `x` reflected about the normal `n`.
public func simd_reflect<V: SIMD>(_ x: V, _ n: V) -> V where V.Scalar: BinaryFloatingPoint { x - 2 * simd_dot(x, n) * n }
/// `x` refracted through a surface with normal `n` and index ratio `eta`; zero past the critical angle.
public func simd_refract<V: SIMD>(_ x: V, _ n: V, _ eta: V.Scalar) -> V where V.Scalar: BinaryFloatingPoint {
    let d = simd_dot(x, n)
    let k = 1 - eta * eta * (1 - d * d)
    return k < 0 ? V() : eta * x - (eta * d + k.squareRoot()) * n
}
/// Elementwise `x + t(y − x)`.
public func simd_mix<V: SIMD>(_ x: V, _ y: V, _ t: V) -> V where V.Scalar: BinaryFloatingPoint { x + t * (y - x) }
/// `x` held elementwise between `min` and `max`.
public func simd_clamp<V: SIMD>(_ x: V, _ min: V, _ max: V) -> V where V.Scalar: Comparable {
    pointwiseMin(pointwiseMax(x, min), max)
}
/// The elementwise smaller.
public func simd_min<V: SIMD>(_ x: V, _ y: V) -> V where V.Scalar: Comparable { pointwiseMin(x, y) }
/// The elementwise larger.
public func simd_max<V: SIMD>(_ x: V, _ y: V) -> V where V.Scalar: Comparable { pointwiseMax(x, y) }
/// The elementwise absolute value.
public func simd_abs<V: SIMD>(_ x: V) -> V where V.Scalar: BinaryFloatingPoint { V(x.indices.map { x[$0].magnitude }) }
/// The sum of the elements.
public func simd_reduce_add<V: SIMD>(_ x: V) -> V.Scalar where V.Scalar: BinaryFloatingPoint { x.sum() }
/// The smallest element.
public func simd_reduce_min<V: SIMD>(_ x: V) -> V.Scalar where V.Scalar: BinaryFloatingPoint { x.min() }
/// The largest element.
public func simd_reduce_max<V: SIMD>(_ x: V) -> V.Scalar where V.Scalar: BinaryFloatingPoint { x.max() }
/// Elementwise 0 below `edge`, 1 from it.
public func simd_step<V: SIMD>(_ edge: V, _ x: V) -> V where V.Scalar: BinaryFloatingPoint { elementwise(x) { i, v in simd_step(edge[i], v) } }
/// An elementwise smooth step from 0 at `edge0` to 1 at `edge1`.
public func simd_smoothstep<V: SIMD>(_ edge0: V, _ edge1: V, _ x: V) -> V where V.Scalar: BinaryFloatingPoint {
    elementwise(x) { i, v in simd_smoothstep(edge0[i], edge1[i], v) }
}
/// The elementwise fractional part.
public func simd_fract<V: SIMD>(_ x: V) -> V where V.Scalar: BinaryFloatingPoint { elementwise(x) { _, v in simd_fract(v) } }
/// The elementwise sign.
public func simd_sign<V: SIMD>(_ x: V) -> V where V.Scalar: BinaryFloatingPoint { elementwise(x) { _, v in simd_sign(v) } }
/// The elementwise reciprocal.
public func simd_recip<V: SIMD>(_ x: V) -> V where V.Scalar: BinaryFloatingPoint { 1 / x }
/// The elementwise reciprocal square root.
public func simd_rsqrt<V: SIMD>(_ x: V) -> V where V.Scalar: BinaryFloatingPoint { 1 / x.squareRoot() }
/// The elementwise square root.
public func simd_sqrt<V: SIMD>(_ x: V) -> V where V.Scalar: BinaryFloatingPoint { x.squareRoot() }
/// Elementwise rounding down.
public func simd_floor<V: SIMD>(_ x: V) -> V where V.Scalar: BinaryFloatingPoint { x.rounded(.down) }
/// Elementwise rounding up.
public func simd_ceil<V: SIMD>(_ x: V) -> V where V.Scalar: BinaryFloatingPoint { x.rounded(.up) }
/// Elementwise rounding towards zero.
public func simd_trunc<V: SIMD>(_ x: V) -> V where V.Scalar: BinaryFloatingPoint { x.rounded(.towardZero) }

private func elementwise<V: SIMD>(_ x: V, _ f: (Int, V.Scalar) -> V.Scalar) -> V {
    var out = x
    for i in x.indices { out[i] = f(i, x[i]) }
    return out
}

// MARK: - Vectors, Swift spellings

public func dot<V: SIMD>(_ x: V, _ y: V) -> V.Scalar where V.Scalar: BinaryFloatingPoint { simd_dot(x, y) }
public func length<V: SIMD>(_ x: V) -> V.Scalar where V.Scalar: BinaryFloatingPoint { simd_length(x) }
public func length_squared<V: SIMD>(_ x: V) -> V.Scalar where V.Scalar: BinaryFloatingPoint { simd_length_squared(x) }
public func norm_one<V: SIMD>(_ x: V) -> V.Scalar where V.Scalar: BinaryFloatingPoint { simd_norm_one(x) }
public func norm_inf<V: SIMD>(_ x: V) -> V.Scalar where V.Scalar: BinaryFloatingPoint { simd_norm_inf(x) }
public func distance<V: SIMD>(_ x: V, _ y: V) -> V.Scalar where V.Scalar: BinaryFloatingPoint { simd_distance(x, y) }
public func distance_squared<V: SIMD>(_ x: V, _ y: V) -> V.Scalar where V.Scalar: BinaryFloatingPoint { simd_distance_squared(x, y) }
public func normalize<V: SIMD>(_ x: V) -> V where V.Scalar: BinaryFloatingPoint { simd_normalize(x) }
public func cross<T: BinaryFloatingPoint>(_ x: SIMD3<T>, _ y: SIMD3<T>) -> SIMD3<T> { simd_cross(x, y) }
public func cross<T: BinaryFloatingPoint>(_ x: SIMD2<T>, _ y: SIMD2<T>) -> SIMD3<T> { simd_cross(x, y) }
public func project<V: SIMD>(_ x: V, _ y: V) -> V where V.Scalar: BinaryFloatingPoint { simd_project(x, y) }
public func reflect<V: SIMD>(_ x: V, n: V) -> V where V.Scalar: BinaryFloatingPoint { simd_reflect(x, n) }
public func refract<V: SIMD>(_ x: V, n: V, eta: V.Scalar) -> V where V.Scalar: BinaryFloatingPoint { simd_refract(x, n, eta) }
public func mix<V: SIMD>(_ x: V, _ y: V, t: V) -> V where V.Scalar: BinaryFloatingPoint { simd_mix(x, y, t) }
public func mix<V: SIMD>(_ x: V, _ y: V, t: V.Scalar) -> V where V.Scalar: BinaryFloatingPoint { simd_mix(x, y, V(repeating: t)) }
public func clamp<V: SIMD>(_ x: V, min: V, max: V) -> V where V.Scalar: BinaryFloatingPoint { simd_clamp(x, min, max) }
public func clamp<V: SIMD>(_ x: V, min: V.Scalar, max: V.Scalar) -> V where V.Scalar: BinaryFloatingPoint {
    simd_clamp(x, V(repeating: min), V(repeating: max))
}
public func step<V: SIMD>(_ x: V, edge: V) -> V where V.Scalar: BinaryFloatingPoint { simd_step(edge, x) }
public func smoothstep<V: SIMD>(_ x: V, edge0: V, edge1: V) -> V where V.Scalar: BinaryFloatingPoint { simd_smoothstep(edge0, edge1, x) }
public func fract<V: SIMD>(_ x: V) -> V where V.Scalar: BinaryFloatingPoint { simd_fract(x) }
public func sign<V: SIMD>(_ x: V) -> V where V.Scalar: BinaryFloatingPoint { simd_sign(x) }
public func recip<V: SIMD>(_ x: V) -> V where V.Scalar: BinaryFloatingPoint { simd_recip(x) }
public func rsqrt<V: SIMD>(_ x: V) -> V where V.Scalar: BinaryFloatingPoint { simd_rsqrt(x) }
public func abs<V: SIMD>(_ x: V) -> V where V.Scalar: BinaryFloatingPoint { simd_abs(x) }
public func min<V: SIMD>(_ x: V, _ y: V) -> V where V.Scalar: BinaryFloatingPoint { simd_min(x, y) }
public func max<V: SIMD>(_ x: V, _ y: V) -> V where V.Scalar: BinaryFloatingPoint { simd_max(x, y) }
public func min<V: SIMD>(_ x: V, _ y: V.Scalar) -> V where V.Scalar: BinaryFloatingPoint { simd_min(x, V(repeating: y)) }
public func max<V: SIMD>(_ x: V, _ y: V.Scalar) -> V where V.Scalar: BinaryFloatingPoint { simd_max(x, V(repeating: y)) }
public func reduce_add<V: SIMD>(_ x: V) -> V.Scalar where V.Scalar: BinaryFloatingPoint { simd_reduce_add(x) }
public func reduce_min<V: SIMD>(_ x: V) -> V.Scalar where V.Scalar: BinaryFloatingPoint { simd_reduce_min(x) }
public func reduce_max<V: SIMD>(_ x: V) -> V.Scalar where V.Scalar: BinaryFloatingPoint { simd_reduce_max(x) }
public func floor<V: SIMD>(_ x: V) -> V where V.Scalar: BinaryFloatingPoint { simd_floor(x) }
public func ceil<V: SIMD>(_ x: V) -> V where V.Scalar: BinaryFloatingPoint { simd_ceil(x) }
public func trunc<V: SIMD>(_ x: V) -> V where V.Scalar: BinaryFloatingPoint { simd_trunc(x) }
public func sqrt<V: SIMD>(_ x: V) -> V where V.Scalar: BinaryFloatingPoint { simd_sqrt(x) }
