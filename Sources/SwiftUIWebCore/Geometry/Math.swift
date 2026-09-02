// Trigonometry for geometry code, spelled once per platform: wasi-libc provides the C symbols
// directly (Foundation's wrappers would pull in its ICU data, decision 0006); Apple platforms and
// Linux get them from the system module `GeometryImports.swift` exports.
#if os(WASI)
@_silgen_name("cos") private func _c_cos(_ x: Double) -> Double
@_silgen_name("sin") private func _c_sin(_ x: Double) -> Double
@_silgen_name("tan") private func _c_tan(_ x: Double) -> Double
@_silgen_name("atan2") private func _c_atan2(_ y: Double, _ x: Double) -> Double
@_silgen_name("acos") private func _c_acos(_ x: Double) -> Double
@inline(__always) package func _cos(_ x: Double) -> Double { _c_cos(x) }
@inline(__always) package func _sin(_ x: Double) -> Double { _c_sin(x) }
@inline(__always) package func _tan(_ x: Double) -> Double { _c_tan(x) }
@inline(__always) package func _atan2(_ y: Double, _ x: Double) -> Double { _c_atan2(y, x) }
@inline(__always) package func _acos(_ x: Double) -> Double { _c_acos(x) }
#else
@inline(__always) package func _cos(_ x: Double) -> Double { cos(x) }
@inline(__always) package func _sin(_ x: Double) -> Double { sin(x) }
@inline(__always) package func _tan(_ x: Double) -> Double { tan(x) }
@inline(__always) package func _atan2(_ y: Double, _ x: Double) -> Double { atan2(y, x) }
@inline(__always) package func _acos(_ x: Double) -> Double { acos(x) }
#endif

@inline(__always) package func _hypot(_ x: Double, _ y: Double) -> Double { (x * x + y * y).squareRoot() }
