// UIKit views animated with a SwiftUI animation (iOS 18's `UIView.animate(_:changes:completion:)`,
// which the iOS SDK declares in SwiftUI): the changes run at once and UIKit plays them with the
// animation's curve, a spring as a spring, over its duration after its delay. swift-navigation's
// `UIKitAnimation` (EhPanda) animates its bindings' changes this way.
import SwiftUIWebCore
import UIKitWebCore

extension UIView {
    /// Animates the view changes `changes` makes with a SwiftUI animation; `completion` runs
    /// when the animation ends. An animation that repeats for ever repeats (its completion
    /// never comes) and one that reverses plays back on each odd cycle; a counted repeat
    /// plays once.
    public static func animate(_ animation: Animation, changes: () -> Void, completion: (() -> Void)? = nil) {
        let timing: any UITimingCurveProvider
        switch animation.curve {
        case .linear:
            timing = UICubicTimingParameters(animationCurve: .linear)
        case let .bezier(x1, y1, x2, y2):
            timing = UICubicTimingParameters(controlPoint1: CGPoint(x: x1, y: y1), controlPoint2: CGPoint(x: x2, y: y2))
        case let .spring(_, zeta, velocity):
            timing = UISpringTimingParameters(dampingRatio: CGFloat(zeta), initialVelocity: CGVector(dx: 0, dy: velocity))
        }
        var options: UIView.AnimationOptions = []
        if animation.repeatCount == 0 { options.insert(.repeat) }
        if animation.autoreverses { options.insert(.autoreverse) }
        let speed = animation.speed > 0 ? animation.speed : 1
        UIView._animate(duration: animation.duration / speed, delay: animation.delay / speed, timing: timing, options: options,
                        animations: changes, completion: completion.map { completion in { _ in completion() } })
    }
}
