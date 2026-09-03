// Trigonometry for geometry code. Apple platforms and Linux use the system libm that
// `GeometryImports.swift` exports; on wasm the libm symbols trap (as `pow` did for scroll
// momentum, decision 0006), so the core carries its own series implementations, accurate to
// about 1e-15 after argument reduction, which is far below the 1e-3 path tolerance.
#if os(WASI)
private let _halfPi = Double.pi / 2
private let _twoPi = Double.pi * 2

/// sin on [-π/2, π/2] by Taylor series (12 terms: the x²¹ term at π/2 is 2e-16).
private func _sinReduced(_ x: Double) -> Double {
    let x2 = x * x
    var term = x, sum = x
    var n = 1.0
    for _ in 0..<12 {
        term *= -x2 / ((n + 1) * (n + 2))
        sum += term
        n += 2
    }
    return sum
}

/// cos on [-π/2, π/2] by Taylor series.
private func _cosReduced(_ x: Double) -> Double {
    let x2 = x * x
    var term = 1.0, sum = 1.0
    var n = 0.0
    for _ in 0..<12 {
        term *= -x2 / ((n + 1) * (n + 2))
        sum += term
        n += 2
    }
    return sum
}

/// Reduces to [-π, π].
private func _reduce(_ x: Double) -> Double {
    var r = x.truncatingRemainder(dividingBy: _twoPi)
    if r > .pi { r -= _twoPi } else if r < -.pi { r += _twoPi }
    return r
}

package func _sin(_ x: Double) -> Double {
    guard x.isFinite else { return .nan }
    let r = _reduce(x)
    if r > _halfPi { return _sinReduced(.pi - r) }
    if r < -_halfPi { return _sinReduced(-.pi - r) }
    return _sinReduced(r)
}

package func _cos(_ x: Double) -> Double {
    guard x.isFinite else { return .nan }
    let r = _reduce(x)
    if r > _halfPi { return -_cosReduced(.pi - r) }
    if r < -_halfPi { return -_cosReduced(-.pi - r) }
    return _cosReduced(r)
}

package func _tan(_ x: Double) -> Double { _sin(x) / _cos(x) }

/// atan on [0, ∞) : halve the argument twice (atan x = 2 atan(x / (1 + √(1 + x²)))), then a series.
private func _atanPositive(_ x: Double) -> Double {
    if x > 1 { return _halfPi - _atanPositive(1 / x) }
    var y = x
    var scale = 1.0
    for _ in 0..<3 {
        y = y / (1 + (1 + y * y).squareRoot())
        scale *= 2
    }
    let y2 = y * y
    var term = y, sum = y
    var n = 1.0
    for _ in 0..<12 {
        term *= -y2
        n += 2
        sum += term / n
    }
    return sum * scale
}

package func _atan2(_ y: Double, _ x: Double) -> Double {
    if x.isNaN || y.isNaN { return .nan }
    if x == 0 {
        if y > 0 { return _halfPi }
        if y < 0 { return -_halfPi }
        return 0
    }
    let a = _atanPositive(abs(y / x))
    if x > 0 { return y < 0 ? -a : a }
    return y < 0 ? a - .pi : .pi - a
}

package func _acos(_ x: Double) -> Double {
    guard x >= -1, x <= 1 else { return .nan }
    return _halfPi - _atan2(x, (1 - x * x).squareRoot())
}
#else
@inline(__always) package func _cos(_ x: Double) -> Double { cos(x) }
@inline(__always) package func _sin(_ x: Double) -> Double { sin(x) }
@inline(__always) package func _tan(_ x: Double) -> Double { tan(x) }
@inline(__always) package func _atan2(_ y: Double, _ x: Double) -> Double { atan2(y, x) }
@inline(__always) package func _acos(_ x: Double) -> Double { acos(x) }
#endif

@inline(__always) package func _hypot(_ x: Double, _ y: Double) -> Double { (x * x + y * y).squareRoot() }
