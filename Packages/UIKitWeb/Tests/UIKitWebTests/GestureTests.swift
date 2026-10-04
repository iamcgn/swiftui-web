// Gesture recognizers (Events/UIGestureRecognizer.swift, TouchRouter.arbitrate): swipes, screen
// edge pans, pinches and rotations from the scene's pinch, exclusivity between recognizers,
// simultaneous recognition through the delegate, and failure requirements.
import Testing
import UIKit

@Suite @MainActor struct GestureTests {
    private func makeScene(_ view: UIView) -> UIKitScene {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 300, height: 300), scale: 2)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        window.addSubview(view)
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 300, height: 300))
        return scene
    }

    private func press(_ scene: UIKitScene, from start: CGPoint, to end: CGPoint, start t0: Double = 0, end t1: Double = 0.1, steps: Int = 2) {
        scene.pointerDown(at: start, type: .touch, time: t0)
        for step in 1...steps {
            let f = CGFloat(step) / CGFloat(steps)
            scene.pointerMoved(to: CGPoint(x: start.x + (end.x - start.x) * f, y: start.y + (end.y - start.y) * f), time: t0 + (t1 - t0) * Double(f))
        }
        scene.pointerUp(at: end, time: t1)
    }

    @Test func swipesRecognizeDirectionAndSpeed() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        var states: [UIGestureRecognizer.State] = []
        let swipe = UISwipeGestureRecognizer { states.append($0.state) }
        swipe.direction = [.right, .down]
        view.addGestureRecognizer(swipe)
        let scene = makeScene(view)
        press(scene, from: CGPoint(x: 50, y: 50), to: CGPoint(x: 130, y: 55))
        #expect(states == [.ended])
        // Leftwards is not allowed; a slow move is no swipe (failures are not reported to the
        // action); downwards counts.
        press(scene, from: CGPoint(x: 150, y: 50), to: CGPoint(x: 60, y: 52))
        press(scene, from: CGPoint(x: 50, y: 50), to: CGPoint(x: 130, y: 55), end: 1.5)
        #expect(states == [.ended])
        press(scene, from: CGPoint(x: 50, y: 50), to: CGPoint(x: 55, y: 140))
        #expect(states == [.ended, .ended])
    }

    @Test func screenEdgePansStartAtTheirEdge() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        var states: [UIGestureRecognizer.State] = []
        var translations: [CGFloat] = []
        let edge = UIScreenEdgePanGestureRecognizer { recognizer in
            states.append(recognizer.state)
            translations.append((recognizer as! UIPanGestureRecognizer).translation(in: nil).x)
        }
        edge.edges = .left
        view.addGestureRecognizer(edge)
        let scene = makeScene(view)
        press(scene, from: CGPoint(x: 8, y: 100), to: CGPoint(x: 80, y: 102), steps: 3)
        #expect(states == [.began, .changed, .changed, .ended])
        #expect(translations.last == 72)
        states.removeAll()
        press(scene, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 180, y: 102))
        #expect(states.isEmpty)
    }

    final class Together: UIGestureRecognizerDelegate {
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    }

    @Test func pinchesAndRotationsFromTheScene() {
        let view = UIView(frame: CGRect(x: 50, y: 50, width: 200, height: 200))
        var log: [String] = []
        let pinch = UIPinchGestureRecognizer { log.append("pinch \($0.state) \(String(format: "%.2f", ($0 as! UIPinchGestureRecognizer).scale))") }
        let rotation = UIRotationGestureRecognizer { log.append("rotate \($0.state) \(Int((($0 as! UIRotationGestureRecognizer).rotation * 180 / .pi).rounded()))") }
        view.addGestureRecognizer(pinch)
        view.addGestureRecognizer(rotation)
        let scene = makeScene(view)
        scene.pinch(.began, scale: 1, rotation: 0, at: CGPoint(x: 150, y: 150), time: 0)
        scene.pinch(.changed, scale: 1.005, rotation: 0, at: CGPoint(x: 150, y: 150), time: 0.1)
        #expect(log.isEmpty)
        scene.pinch(.changed, scale: 1.5, rotation: 0.3, at: CGPoint(x: 150, y: 150), time: 0.2)
        // The pinch begins first; the rotation, not allowed alongside, fails (unreported).
        #expect(log == ["pinch began 1.50"])
        #expect(pinch.location(in: view) == CGPoint(x: 100, y: 100) && pinch.numberOfTouches == 2)
        #expect(abs(pinch.velocity - 4.95) < 0.01)
        scene.pinch(.ended, scale: 1.6, rotation: 0.3, at: CGPoint(x: 150, y: 150), time: 0.3)
        #expect(log.last == "pinch ended 1.60" && pinch.state == .possible && pinch.scale == 1)
        // With a delegate allowing simultaneous recognition both run.
        let together = Together()
        pinch.delegate = together
        log.removeAll()
        scene.pinch(.began, scale: 1, rotation: 0, at: CGPoint(x: 150, y: 150), time: 1)
        scene.pinch(.changed, scale: 1.2, rotation: .pi / 4, at: CGPoint(x: 150, y: 150), time: 1.1)
        scene.pinch(.changed, scale: 1.3, rotation: .pi / 2, at: CGPoint(x: 150, y: 150), time: 1.2)
        scene.pinch(.ended, scale: 1.3, rotation: .pi / 2, at: CGPoint(x: 150, y: 150), time: 1.3)
        #expect(log == ["pinch began 1.20", "rotate began 45", "pinch changed 1.30", "rotate changed 90", "pinch ended 1.30", "rotate ended 90"])
        // A pinch away from the view reaches nothing.
        log.removeAll()
        scene.pinch(.began, scale: 1, rotation: 0, at: CGPoint(x: 10, y: 10), time: 2)
        scene.pinch(.changed, scale: 2, rotation: 0, at: CGPoint(x: 10, y: 10), time: 2.1)
        scene.pinch(.ended, scale: 2, rotation: 0, at: CGPoint(x: 10, y: 10), time: 2.2)
        #expect(log.isEmpty)
    }

    @Test func oneRecognizerWinsUnlessAllowedTogether() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        var log: [String] = []
        let pan = UIPanGestureRecognizer { log.append("pan \($0.state)") }
        let press = UILongPressGestureRecognizer { log.append("press \($0.state)") }
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(press)
        let scene = makeScene(view)
        self.press(scene, from: CGPoint(x: 50, y: 50), to: CGPoint(x: 100, y: 50))
        // The pan began; the long press, still waiting for its duration, fails (unreported).
        #expect(log == ["pan began", "pan changed", "pan ended"])
        log.removeAll()
        let together = Together()
        pan.delegate = together
        self.press(scene, from: CGPoint(x: 50, y: 50), to: CGPoint(x: 100, y: 50))
        #expect(log == ["pan began", "pan changed", "pan ended"])
    }

    final class Deferring: UIGestureRecognizerDelegate {
        let other: UIGestureRecognizer
        init(other: UIGestureRecognizer) { self.other = other }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool { otherGestureRecognizer === other }
    }

    @Test func failureRequirementsOrderTaps() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        var log: [String] = []
        let single = UITapGestureRecognizer { _ in log.append("single") }
        let double = UITapGestureRecognizer { _ in log.append("double") }
        double.numberOfTapsRequired = 2
        single.require(toFail: double)
        view.addGestureRecognizer(single)
        view.addGestureRecognizer(double)
        let scene = makeScene(view)
        let p = CGPoint(x: 100, y: 100)
        // The first tap: the double tap is undecided when the touch ends, so the single fires;
        // the second tap recognizes the double tap, which fails the single.
        scene.pointerDown(at: p, type: .touch, time: 0); scene.pointerUp(at: p, time: 0.05)
        #expect(log == ["single"])
        scene.pointerDown(at: p, type: .touch, time: 0.2); scene.pointerUp(at: p, time: 0.25)
        #expect(log == ["single", "double"])
        // The delegate form: a pan that must wait for a swipe fails when the swipe recognizes.
        log.removeAll()
        let pan = UIPanGestureRecognizer { log.append("pan \($0.state)") }
        let swipe = UISwipeGestureRecognizer { log.append("swipe \($0.state)") }
        let deferring = Deferring(other: swipe)
        pan.delegate = deferring
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(swipe)
        press(scene, from: CGPoint(x: 50, y: 150), to: CGPoint(x: 130, y: 152), steps: 4)
        #expect(log == ["swipe ended"])
    }
}
