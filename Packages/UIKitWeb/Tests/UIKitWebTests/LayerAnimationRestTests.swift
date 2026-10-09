// uk-layers (Layers/CAAnimation.swift, LayerAnimation.swift, CADisplayLink.swift,
// PropertyAnimator.swift): keyframes through every value, additive animations, a group's
// children in their own windows, UIView.animate's repeat / autoreverse / beginFromCurrentState,
// a display link on the scene's clock, and the animator's delay factor, linear scrubbing and
// continuation with a spring.
import Testing
import UIKit
@testable import UIKitWebCore

@Suite @MainActor struct LayerAnimationRestTests {
    private func scene() -> (UIKitScene, UIView) {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.textEngine = try! Goldens.textEngine()
        scene.configureScreen(size: CGSize(width: 320, height: 400), scale: 2)
        let root = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        window.rootViewController = root
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 320, height: 400))
        return (scene, root.view)
    }

    private func presentedX(_ layer: CALayer) -> CGFloat { layer.presented(.position, model: .point(layer.position)).point.x }
    private func presentedOpacity(_ layer: CALayer) -> Double { layer.presented(.opacity, model: .scalar(Double(layer.opacity))).scalar }

    @Test func keyframesAdditiveAndGroups() {
        let (scene, root) = scene()
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        root.addSubview(view)
        let layer = view.layer

        // Keyframes: through every value, linearly between the key times.
        let frames = CAKeyframeAnimation(keyPath: "position.x")
        frames.values = [20, 120, 60, 200]
        frames.keyTimes = [0, 0.25, 0.5, 1]
        frames.duration = 1
        frames.timingFunction = CAMediaTimingFunction(name: .linear)
        layer.add(frames, forKey: "frames")
        _ = scene.advanceFrame(elapsed: 0.125)
        #expect(abs(presentedX(layer) - 70) < 0.01)
        _ = scene.advanceFrame(elapsed: 0.25)   // 0.375: between 120 (0.25) and 60 (0.5)
        #expect(abs(presentedX(layer) - 90) < 0.01)
        _ = scene.advanceFrame(elapsed: 0.375)   // 0.75: between 60 and 200
        #expect(abs(presentedX(layer) - 130) < 0.01)
        _ = scene.advanceFrame(elapsed: 0.3)
        #expect(presentedX(layer) == 20)   // removed: back to the model
        layer.removeAllAnimations()

        // Discrete keyframes hold each value until the next time.
        let steps = CAKeyframeAnimation(keyPath: "opacity")
        steps.values = [1, 0.5, 0.2]
        steps.calculationMode = "discrete"
        steps.duration = 1
        layer.add(steps, forKey: "steps")
        _ = scene.advanceFrame(elapsed: 0.3)
        #expect(presentedOpacity(layer) == 1)
        _ = scene.advanceFrame(elapsed: 0.4)
        #expect(presentedOpacity(layer) == 0.5)
        layer.removeAllAnimations()
        _ = scene.advanceFrame(elapsed: 1)

        // Additive: a delta on top of the model, which may move underneath.
        let nudge = CABasicAnimation(keyPath: "position.x")
        nudge.isAdditive = true
        nudge.fromValue = 0
        nudge.toValue = 100
        nudge.duration = 1
        nudge.timingFunction = CAMediaTimingFunction(name: .linear)
        layer.add(nudge, forKey: "nudge")
        _ = scene.advanceFrame(elapsed: 0.5)
        #expect(abs(presentedX(layer) - 70) < 0.01)
        UIView.performWithoutAnimation { view.center.x = 100 }
        #expect(abs(presentedX(layer) - 150) < 0.01)
        layer.removeAllAnimations()
        _ = scene.advanceFrame(elapsed: 1)

        // A group: the children run in their own windows of the group's duration.
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1; fade.toValue = 0; fade.duration = 0.5; fade.beginTime = 0.5
        fade.timingFunction = CAMediaTimingFunction(name: .linear)
        let slide = CABasicAnimation(keyPath: "position.x")
        slide.fromValue = 100; slide.toValue = 200; slide.duration = 1
        slide.timingFunction = CAMediaTimingFunction(name: .linear)
        let group = CAAnimationGroup()
        group.animations = [fade, slide]
        group.duration = 1
        group.timingFunction = CAMediaTimingFunction(name: .linear)
        layer.add(group, forKey: "group")
        _ = scene.advanceFrame(elapsed: 0.25)
        #expect(presentedOpacity(layer) == 1 && abs(presentedX(layer) - 125) < 0.01)   // the fade has not begun
        _ = scene.advanceFrame(elapsed: 0.5)
        #expect(abs(presentedOpacity(layer) - 0.5) < 0.01 && abs(presentedX(layer) - 175) < 0.01)
        _ = scene.advanceFrame(elapsed: 0.5)
        #expect(presentedOpacity(layer) == 1 && presentedX(layer) == 100)   // removed on completion
    }

    @Test func animateOptionsRepeatAutoreverseAndCurrentState() {
        let (scene, root) = scene()
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        root.addSubview(view)
        var completed = false
        UIView.animate(withDuration: 1, delay: 0, options: [.repeat, .autoreverse, .curveLinear], animations: { view.center.x = 120 }, completion: { _ in completed = true })
        _ = scene.advanceFrame(elapsed: 0.5)
        #expect(abs(presentedX(view.layer) - 70) < 0.01)
        _ = scene.advanceFrame(elapsed: 1)   // 1.5: on the way back
        #expect(abs(presentedX(view.layer) - 70) < 0.01)
        _ = scene.advanceFrame(elapsed: 5)   // 6.5: still going, no completion
        #expect(scene.isAnimating && !completed && abs(presentedX(view.layer) - 70) < 0.01)
        view.layer.removeAllAnimations()
        scene.animationGroups.removeAll()

        // Without beginFromCurrentState a new block starts from the model; with it, from the
        // presented value.
        view.center.x = 20
        UIView.animate(withDuration: 1, delay: 0, options: [.curveLinear], animations: { view.center.x = 120 })
        _ = scene.advanceFrame(elapsed: 0.5)
        UIView.animate(withDuration: 1, delay: 0, options: [.curveLinear], animations: { view.center.x = 220 })
        #expect(abs(presentedX(view.layer) - 120) < 0.01)   // the model's value, 120
        _ = scene.advanceFrame(elapsed: 0.5)
        #expect(abs(presentedX(view.layer) - 170) < 0.01)
        view.layer.removeAllAnimations()
        scene.animationGroups.removeAll()
        view.center.x = 20
        UIView.animate(withDuration: 1, delay: 0, options: [.curveLinear], animations: { view.center.x = 120 })
        _ = scene.advanceFrame(elapsed: 0.5)
        UIView.animate(withDuration: 1, delay: 0, options: [.curveLinear, .beginFromCurrentState], animations: { view.center.x = 220 })
        #expect(abs(presentedX(view.layer) - 70) < 0.01)   // from where it shows
        _ = scene.advanceFrame(elapsed: 0.5)
        #expect(abs(presentedX(view.layer) - 145) < 0.01)
    }

    @Test func displayLinksTickOnTheClock() {
        let (scene, _) = scene()
        var ticks: [(Double, Double)] = []
        let link = CADisplayLink { link in ticks.append((link.timestamp, link.duration)) }
        #expect(!scene.isAnimating)
        link.add(to: nil, forMode: nil)
        #expect(scene.isAnimating)
        _ = scene.advanceFrame(elapsed: 1.0 / 60)
        _ = scene.advanceFrame(elapsed: 1.0 / 30)
        #expect(ticks.count == 2 && abs(ticks[1].0 - ticks[0].0 - 1.0 / 30) < 1e-9 && abs(ticks[1].1 - 1.0 / 30) < 1e-9)
        #expect(abs(link.targetTimestamp - (link.timestamp + 1.0 / 30)) < 1e-9)
        link.isPaused = true
        _ = scene.advanceFrame(elapsed: 1.0 / 60)
        #expect(ticks.count == 2 && scene.isAnimating)
        link.isPaused = false
        link.invalidate()
        _ = scene.advanceFrame(elapsed: 1.0 / 60)
        #expect(ticks.count == 2 && !link.isValid && !scene.isAnimating)

        final class Owner {}
        var owner: Owner? = Owner()
        var owned = 0
        let bound = CADisplayLink(target: owner!) { _ in owned += 1 }
        bound.add(to: nil)
        _ = scene.advanceFrame(elapsed: 0.01)
        owner = nil
        _ = scene.advanceFrame(elapsed: 0.01)
        #expect(owned == 1 && !bound.isValid)   // the target went away: the link invalidates itself
    }

    @Test func animatorDelayFactorScrubbingAndSprings() {
        let (scene, root) = scene()
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        let other = UIView(frame: CGRect(x: 0, y: 100, width: 40, height: 40))
        root.addSubview(view)
        root.addSubview(other)
        let animator = UIViewPropertyAnimator(duration: 1, curve: .linear) { view.center.x = 120 }
        animator.addAnimations({ other.center.x = 120 }, delayFactor: 0.5)
        animator.startAnimation()
        _ = scene.advanceFrame(elapsed: 0.25)
        #expect(abs(presentedX(view.layer) - 45) < 0.01 && presentedX(other.layer) == 20)   // the delayed block waits
        _ = scene.advanceFrame(elapsed: 0.5)   // 0.75: the delayed block is halfway through its half
        #expect(abs(presentedX(other.layer) - 70) < 0.01)
        animator.stopAnimation(false)
        animator.finishAnimation(at: .end)

        // Scrubbing: linear when asked, the curve otherwise; the curve returns when it runs.
        view.center.x = 20
        let eased = UIViewPropertyAnimator(duration: 1, curve: .easeIn) { view.center.x = 120 }
        eased.scrubsLinearly = true
        eased.fractionComplete = 0.5
        #expect(abs(presentedX(view.layer) - 70) < 0.01)
        eased.scrubsLinearly = false
        eased.fractionComplete = 0.5
        #expect(presentedX(view.layer) < 60)   // ease-in: behind the linear midpoint
        eased.stopAnimation(false)
        eased.finishAnimation(at: .start)

        // Continuing a paused animator with a spring carries an initial velocity.
        view.center.x = 20
        let sprung = UIViewPropertyAnimator(duration: 1, curve: .linear) { view.center.x = 120 }
        sprung.startAnimation()
        _ = scene.advanceFrame(elapsed: 0.5)
        sprung.pauseAnimation()
        let x = presentedX(view.layer)
        #expect(abs(x - 70) < 0.01)
        sprung.continueAnimation(withTimingParameters: UISpringTimingParameters(dampingRatio: 0.5, initialVelocity: CGVector(dx: 0, dy: 4)), durationFactor: 0.5)
        #expect(sprung.isRunning && abs(presentedX(view.layer) - 70) < 0.01)   // from where it showed
        _ = scene.advanceFrame(elapsed: 0.1)
        #expect(presentedX(view.layer) > 70)
        _ = scene.advanceFrame(elapsed: 1)
        #expect(view.center.x == 120 && !sprung.isRunning)
    }
}
