/// A colour in Oklab, for perceptual blending (SwiftUI blends gradients perceptually; measured
/// against Apple's pixels in `Docs/elements/Gradient.md`).
public struct _Oklab {
    public var L: Double, a: Double, b: Double

    public init(L: Double, a: Double, b: Double) { self.L = L; self.a = a; self.b = b }

    public init(_ color: RGBA) {
        let r = Self.linear(color.red), g = Self.linear(color.green), bl = Self.linear(color.blue)
        let l = _cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * bl)
        let m = _cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * bl)
        let s = _cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * bl)
        L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    }

    public func mixed(with other: _Oklab, t: Double) -> _Oklab {
        _Oklab(L: L + (other.L - L) * t, a: a + (other.a - a) * t, b: b + (other.b - b) * t)
    }

    public func rgba(alpha: Double) -> RGBA {
        let l_ = L + 0.3963377774 * a + 0.2158037573 * b
        let m_ = L - 0.1055613458 * a - 0.0638541728 * b
        let s_ = L - 0.0894841775 * a - 1.2914855480 * b
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        let r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let bl = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        return RGBA(red: Self.encoded(r), green: Self.encoded(g), blue: Self.encoded(bl), alpha: alpha)
    }

    private static func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : _pow((c + 0.055) / 1.055, 2.4)
    }

    private static func encoded(_ c: Double) -> Double {
        let v = min(max(c, 0), 1)
        return v <= 0.0031308 ? v * 12.92 : 1.055 * _pow(v, 1 / 2.4) - 0.055
    }
}
