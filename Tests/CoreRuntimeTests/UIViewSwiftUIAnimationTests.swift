// UIKit views animated with a SwiftUI animation (Sources/SwiftUIWebUIKit/UIViewAnimation.swift),
// as swift-navigation's `UIKitAnimation` (EhPanda) animates its bindings: the changes apply at
// once, the scene plays them for the animation's duration after its delay, and the completion
// comes at the end.
import Testing
import SwiftUI

@Suite @MainActor struct UIViewSwiftUIAnimationTests {
    private func view() -> (UIKitScene, UIView) {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 320, height: 400), scale: 2)
        let root = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        window.rootViewController = root
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 320, height: 400))
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        root.view.addSubview(view)
        return (scene, view)
    }

    @Test func aCurveAndASpringPlayForTheirDurations() {
        let (scene, view) = view()
        var done = 0
        UIView.animate(.easeInOut(duration: 0.4), changes: { view.center.x = 120 }, completion: { done += 1 })
        #expect(view.center.x == 120 && scene.isAnimating && done == 0)
        _ = scene.advanceFrame(elapsed: 0.2)
        #expect(done == 0)
        _ = scene.advanceFrame(elapsed: 0.25)
        #expect(done == 1 && !scene.isAnimating)

        // A spring after a delay: nothing ends before the delay and the spring have run.
        UIView.animate(.spring(duration: 0.5).delay(0.3), changes: { view.alpha = 0.5 }, completion: { done += 1 })
        #expect(view.alpha == 0.5)
        _ = scene.advanceFrame(elapsed: 0.6)
        #expect(done == 1 && scene.isAnimating)
        _ = scene.advanceFrame(elapsed: 3)
        #expect(done == 2 && !scene.isAnimating)
        scene.removeAllWindows()
    }

    @Test func withoutAnimationsTheChangesAndCompletionComeAtOnce() {
        let (scene, view) = view()
        var done = false
        UIView.performWithoutAnimation {
            UIView.animate(.linear(duration: 1), changes: { view.center.y = 200 }, completion: { done = true })
        }
        #expect(view.center.y == 200 && done && !scene.isAnimating)
        scene.removeAllWindows()
    }
}
