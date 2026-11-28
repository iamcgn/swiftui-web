// The `simd` shadow's vector functions (WebSIMD's SIMDMath.swift): each one matches its definition
// worked by hand, the Swift spellings match the C ones, and on macOS, where Apple's simd is at
// hand, every C function matches Apple's for the same vectors.
import Testing
import WebSIMD
#if canImport(simd)
import simd
#endif

@Suite struct SIMDMathTests {
    static let a = SIMD3<Float>(0.25, -1.5, 2)
    static let b = SIMD3<Float>(3, 0.5, -0.75)
    static let t = SIMD3<Float>(0, 0.4, 1)
    static let n = SIMD3<Float>(0, 1, 0)

    private func near(_ x: Float, _ y: Float, _ tolerance: Float = 1e-5) -> Bool { Swift.abs(x - y) <= tolerance * Swift.max(1, Swift.abs(y)) }
    private func near(_ x: SIMD3<Float>, _ y: SIMD3<Float>) -> Bool { (0..<3).allSatisfy { near(x[$0], y[$0]) } }

    @Test func theGeometricFunctionsMatchTheirDefinitions() {
        let a = Self.a, b = Self.b
        #expect(WebSIMD.simd_dot(a, b) == 0.75 - 0.75 - 1.5)
        #expect(WebSIMD.simd_length_squared(a) == 0.0625 + 2.25 + 4)
        #expect(near(WebSIMD.simd_length(SIMD2<Float>(3, 4)), 5))
        #expect(Swift.abs(WebSIMD.simd_distance(SIMD2<Double>(1, 1), SIMD2<Double>(4, 5)) - 5) < 1e-12)
        #expect(near(WebSIMD.simd_length(WebSIMD.simd_normalize(a)), 1))
        #expect(WebSIMD.simd_cross(SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0)) == SIMD3(0, 0, 1))
        #expect(WebSIMD.simd_cross(SIMD2<Float>(2, 0), SIMD2<Float>(0, 3)) == SIMD3(0, 0, 6))
        #expect(WebSIMD.simd_reflect(SIMD3<Float>(1, -1, 0), Self.n) == SIMD3(1, 1, 0))
        #expect(WebSIMD.simd_refract(SIMD3<Float>(0, -1, 0), Self.n, 1) == SIMD3(0, -1, 0))
        #expect(WebSIMD.simd_refract(SIMD3<Float>(1, -0.01, 0), Self.n, 1.5) == SIMD3(0, 0, 0), "past the critical angle")
        #expect(WebSIMD.simd_project(SIMD2<Float>(3, 4), SIMD2<Float>(1, 0)) == SIMD2(3, 0))
        #expect(WebSIMD.simd_norm_one(a) == 3.75)
        #expect(WebSIMD.simd_norm_inf(a) == 2)
    }

    @Test func theCommonFunctionsMatchTheirDefinitions() {
        let a = Self.a, b = Self.b
        #expect(WebSIMD.simd_mix(a, b, Self.t) == SIMD3(0.25, -1.5 + 0.4 * 2, -0.75))
        #expect(WebSIMD.simd_clamp(a, SIMD3(repeating: -1), SIMD3(repeating: 1)) == SIMD3(0.25, -1, 1))
        #expect(WebSIMD.simd_min(a, b) == SIMD3(0.25, -1.5, -0.75))
        #expect(WebSIMD.simd_max(a, b) == SIMD3(3, 0.5, 2))
        #expect(WebSIMD.simd_abs(a) == SIMD3(0.25, 1.5, 2))
        #expect(WebSIMD.simd_reduce_add(a) == 0.75)
        #expect(WebSIMD.simd_reduce_min(a) == -1.5)
        #expect(WebSIMD.simd_reduce_max(a) == 2)
        #expect(WebSIMD.simd_step(SIMD3<Float>(repeating: 0.25), a) == SIMD3(1, 0, 1), "1 from the edge itself")
        #expect(WebSIMD.simd_smoothstep(SIMD3<Float>(repeating: 0), SIMD3<Float>(repeating: 4), SIMD3(-1, 1, 5)) == SIMD3(0, 0.15625, 1))
        #expect(WebSIMD.simd_fract(SIMD3<Float>(1.25, -0.25, 3)) == SIMD3(0.25, 0.75, 0))
        #expect(WebSIMD.simd_fract(Float(-1e-9)) < 1, "fract stays below 1")
        #expect(WebSIMD.simd_sign(SIMD3<Float>(-3, 0, .nan)) == SIMD3(-1, 0, 0))
        #expect(WebSIMD.simd_sign(Float(7)) == 1)
        #expect(WebSIMD.simd_recip(SIMD2<Float>(2, 4)) == SIMD2(0.5, 0.25))
        #expect(WebSIMD.simd_rsqrt(SIMD2<Float>(4, 16)) == SIMD2(0.5, 0.25))
        #expect(WebSIMD.simd_floor(SIMD2<Float>(-1.5, 1.5)) == SIMD2(-2, 1))
        #expect(WebSIMD.simd_ceil(SIMD2<Float>(-1.5, 1.5)) == SIMD2(-1, 2))
        #expect(WebSIMD.simd_trunc(SIMD2<Float>(-1.5, 1.5)) == SIMD2(-1, 1))
        #expect(WebSIMD.simd_clamp(Float(3), 0, 1) == 1)
        #expect(WebSIMD.simd_mix(Float(2), 4, 0.25) == 2.5)
        #expect(WebSIMD.simd_smoothstep(Double(0), 2, 1) == 0.5)
        #expect(WebSIMD.simd_step(Float(1), 0.5) == 0)
    }

    @Test func theSwiftSpellingsMatchTheCOnes() {
        let a = Self.a, b = Self.b
        #expect(WebSIMD.dot(a, b) == WebSIMD.simd_dot(a, b))
        #expect(WebSIMD.length(a) == WebSIMD.simd_length(a))
        #expect(WebSIMD.length_squared(a) == WebSIMD.simd_length_squared(a))
        #expect(WebSIMD.distance(a, b) == WebSIMD.simd_distance(a, b))
        #expect(WebSIMD.distance_squared(a, b) == WebSIMD.simd_distance_squared(a, b))
        #expect(WebSIMD.normalize(a) == WebSIMD.simd_normalize(a))
        #expect(WebSIMD.cross(a, b) == WebSIMD.simd_cross(a, b))
        #expect(WebSIMD.reflect(a, n: Self.n) == WebSIMD.simd_reflect(a, Self.n))
        #expect(WebSIMD.refract(a, n: Self.n, eta: 0.5) == WebSIMD.simd_refract(a, Self.n, 0.5))
        #expect(WebSIMD.mix(a, b, t: Self.t) == WebSIMD.simd_mix(a, b, Self.t))
        #expect(WebSIMD.mix(a, b, t: 0.5) == WebSIMD.simd_mix(a, b, SIMD3(repeating: 0.5)))
        #expect(WebSIMD.clamp(a, min: -1, max: 1) == WebSIMD.simd_clamp(a, SIMD3(repeating: -1), SIMD3(repeating: 1)))
        #expect(WebSIMD.step(a, edge: b) == WebSIMD.simd_step(b, a))
        #expect(WebSIMD.smoothstep(a, edge0: b, edge1: b + 1) == WebSIMD.simd_smoothstep(b, b + 1, a))
        #expect(WebSIMD.min(a, 0) == SIMD3(0, -1.5, 0))
        #expect(WebSIMD.max(a, b) == WebSIMD.simd_max(a, b))
        #expect(WebSIMD.abs(a) == WebSIMD.simd_abs(a))
        #expect(WebSIMD.reduce_add(a) == WebSIMD.simd_reduce_add(a))
        #expect(WebSIMD.sqrt(SIMD2<Float>(9, 4)) == SIMD2(3, 2))
        let named: WebSIMD.simd_float3 = WebSIMD.simd_float3(repeating: 1)
        let short: WebSIMD.float3 = named
        #expect(short == SIMD3<Float>(1, 1, 1))
    }

    #if canImport(simd)
    @Test func everyFunctionMatchesApplesSimd() {
        let vectors: [SIMD3<Float>] = [Self.a, Self.b, Self.t, Self.n, SIMD3(-2.5, 7, 0.125), SIMD3(1e-3, -4, 9)]
        for x in vectors {
            #expect(near(WebSIMD.simd_length(x), simd.simd_length(x)))
            #expect(near(WebSIMD.simd_length_squared(x), simd.simd_length_squared(x)))
            #expect(WebSIMD.simd_fract(x) == simd.simd_fract(x))
            #expect(WebSIMD.simd_sign(x) == simd.simd_sign(x))
            #expect(WebSIMD.simd_abs(x) == simd.simd_abs(x))
            #expect(WebSIMD.simd_reduce_add(x) == simd.simd_reduce_add(x))
            #expect(WebSIMD.simd_reduce_min(x) == simd.simd_reduce_min(x))
            #expect(WebSIMD.simd_reduce_max(x) == simd.simd_reduce_max(x))
            if simd.simd_length(x) > 0 { #expect(near(WebSIMD.simd_normalize(x), simd.simd_normalize(x))) }
            for y in vectors {
                #expect(near(WebSIMD.simd_dot(x, y), simd.simd_dot(x, y)))
                #expect(near(WebSIMD.simd_distance(x, y), simd.simd_distance(x, y)))
                #expect(near(WebSIMD.simd_cross(x, y), simd.simd_cross(x, y)))
                #expect(WebSIMD.simd_min(x, y) == simd.simd_min(x, y))
                #expect(WebSIMD.simd_max(x, y) == simd.simd_max(x, y))
                #expect(near(WebSIMD.simd_mix(x, y, Self.t), simd.simd_mix(x, y, Self.t)))
                #expect(WebSIMD.simd_step(y, x) == simd.simd_step(y, x))
                #expect(near(WebSIMD.simd_reflect(x, Self.n), simd.simd_reflect(x, Self.n)))
                #expect(near(WebSIMD.simd_refract(simd.simd_normalize(x), Self.n, 0.75), simd.simd_refract(simd.simd_normalize(x), Self.n, 0.75)))
                if simd.simd_length(y) > 0 { #expect(near(WebSIMD.simd_project(x, y), simd.simd_project(x, y))) }
                let lo = simd.simd_min(x, y), hi = simd.simd_max(x, y)
                #expect(WebSIMD.simd_clamp(Self.a, lo, hi) == simd.simd_clamp(Self.a, lo, hi))
                if lo != hi, (0..<3).allSatisfy({ lo[$0] != hi[$0] }) {
                    #expect(near(WebSIMD.simd_smoothstep(lo, hi, Self.b), simd.simd_smoothstep(lo, hi, Self.b)))
                }
            }
        }
        for v: Float in [-3.5, -0.25, 0, 0.5, 2.75] {
            #expect(WebSIMD.simd_clamp(v, -1, 1) == simd.simd_clamp(v, -1, 1))
            #expect(WebSIMD.simd_mix(v, 4, 0.3) == simd.simd_mix(v, 4, 0.3))
            #expect(WebSIMD.simd_step(0.5, v) == simd.simd_step(0.5, v))
            #expect(near(WebSIMD.simd_smoothstep(-1, 2, v), simd.simd_smoothstep(-1, 2, v)))
            #expect(WebSIMD.simd_fract(v) == simd.simd_fract(v))
            #expect(WebSIMD.simd_sign(v) == simd.simd_sign(v))
        }
    }
    #endif
}
