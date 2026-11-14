// Arithmetic on Angle and EdgeInsets through their animatable data (SwiftUI's `_VectorMath`):
// SwiftUIPager subtracts angles, PureSwiftUI adds and scales them, and inset maths adds, scales
// and negates `EdgeInsets`, all as SwiftUI does.
import Testing
import SwiftUI
import SwiftUIWebCore

@Suite struct VectorMathTests {
    @Test func anglesAddSubtractAndScale() {
        let a = Angle.degrees(90), b = Angle.degrees(30)
        #expect(abs((a - b).degrees - 60) < 1e-9)
        #expect(abs((a + b).degrees - 120) < 1e-9)
        #expect(abs((a * 0.5).degrees - 45) < 1e-9)
        #expect(abs((a / 3).degrees - 30) < 1e-9)
        #expect((-a).degrees == -90)
        var c = a
        c += b
        c -= .degrees(60)
        c *= 2
        c /= 4
        #expect(abs(c.degrees - 30) < 1e-9)
        c.negate()
        #expect(abs(c.degrees + 30) < 1e-9)
        #expect(abs(Angle.radians(-2).magnitude - 2) < 1e-12)
    }

    @Test func insetsAddSubtractScaleAndNegate() {
        let a = EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4)
        let b = EdgeInsets(top: 10, leading: 20, bottom: 30, trailing: 40)
        #expect(a + b == EdgeInsets(top: 11, leading: 22, bottom: 33, trailing: 44))
        #expect(b - a == EdgeInsets(top: 9, leading: 18, bottom: 27, trailing: 36))
        #expect(a * 2 == EdgeInsets(top: 2, leading: 4, bottom: 6, trailing: 8))
        #expect(b / 10 == EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4))
        #expect(-a == EdgeInsets(top: -1, leading: -2, bottom: -3, trailing: -4))
        #expect(abs(EdgeInsets(top: 3, leading: 4, bottom: 0, trailing: 0).magnitude - 5) < 1e-12)
    }

    /// Generic code over `_VectorMath` works for both.
    @Test func genericCodeSeesTheOperators() {
        func midpoint<T: _VectorMath>(_ x: T, _ y: T) -> T { (x + y) / 2 }
        #expect(abs(midpoint(Angle.degrees(10), .degrees(50)).degrees - 30) < 1e-9)
        #expect(midpoint(EdgeInsets(), EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                == EdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2))
    }
}
