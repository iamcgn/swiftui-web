// `ProjectionTransform(_: CATransform3D)`: SwiftUIExperiments' text scroll builds a perspective
// with Core Animation's functions and hands it to `projectionEffect` (Docs/elements/Transform.md).
import Testing
import SwiftUI
import SwiftUIWebUIKit
import UIKitWebCore

#if !os(WASI)
@Suite struct CoreAnimationProjectionTests {
    @Test func aCoreAnimationTransformProjectsOntoTheViewsPlane() {
        var t = CATransform3DIdentity
        t.m34 = -1 / 500
        t = CATransform3DTranslate(t, 0, 20, -100)
        let p = ProjectionTransform(t)
        #expect(p.m11 == t.m11 && p.m12 == t.m12 && p.m13 == t.m14)
        #expect(p.m21 == t.m21 && p.m22 == t.m22 && p.m23 == t.m24)
        #expect(p.m31 == t.m41 && p.m32 == t.m42 && p.m33 == t.m44)
        // Moved back in depth under a perspective, the view gets smaller: w is 1.2.
        let w = t.m44
        #expect(abs(w - 1.2) < 1e-12)
        #expect(p.affine == CGAffineTransform(a: 1 / w, b: 0, c: 0, d: 1 / w, tx: 0, ty: 20 / w))
        #expect(CGPoint(x: 10, y: 0).applying(p) == CGPoint(x: 10 / w, y: 20 / w))
        #expect(ProjectionTransform(CATransform3DIdentity).isIdentity)
    }
}
#endif
