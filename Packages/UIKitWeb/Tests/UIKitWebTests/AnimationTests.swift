// UIView.animate (Layers/LayerAnimation.swift): the model changes at once, painting follows the
// eased interpolation as the scene's clock advances, completions run at the end, and
// performWithoutAnimation applies changes directly.
import Testing
import UIKit
@testable import UIKitWebCore

@Suite @MainActor struct AnimationTests {
    private func window() -> UIWindow {
        UIKitScene.shared.removeAllWindows()
        UIKitScene.shared.configureScreen(size: CGSize(width: 200, height: 200), scale: 2)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        window.makeKeyAndVisible()
        return window
    }

    private func fills(_ window: UIWindow) -> [String] {
        UIKitScene.shared.layout(in: CGSize(width: 200, height: 200))
        return UIKitScene.shared.render(scale: 2, background: false).commands.map(\.description).filter { $0.hasPrefix("fillRect") || $0.hasPrefix("beginGroup") }
    }

    @Test func framesInterpolateAndComplete() {
        let window = window()
        let box = UIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        box.backgroundColor = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
        window.addSubview(box)
        var completed = false
        UIView.animate(withDuration: 1, delay: 0, options: .curveLinear, animations: {
            box.frame = CGRect(x: 100, y: 0, width: 20, height: 20)
        }, completion: { _ in completed = true })
        // The model moved at once; painting still shows the start.
        #expect(box.frame.minX == 100)
        #expect(UIKitScene.shared.isAnimating)
        #expect(fills(window).contains("fillRect(0, 0, 20, 20) #FF0000"))
        // Half way: the box is half way.
        #expect(UIKitScene.shared.advanceFrame(elapsed: 0.5))
        #expect(fills(window).contains("fillRect(50, 0, 20, 20) #FF0000"))
        #expect(!completed)
        // The end: the model's frame, the completion, no more frames.
        #expect(!UIKitScene.shared.advanceFrame(elapsed: 0.6))
        #expect(fills(window).contains("fillRect(100, 0, 20, 20) #FF0000"))
        #expect(completed)
        #expect(!UIKitScene.shared.isAnimating)
    }

    @Test func easingAndOpacity() {
        let window = window()
        let box = UIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        box.backgroundColor = UIColor(red: 0, green: 0, blue: 1, alpha: 1)
        window.addSubview(box)
        UIView.animate(withDuration: 2) {
            box.alpha = 0
            box.frame.origin.x = 100
        }
        _ = UIKitScene.shared.advanceFrame(elapsed: 0.5)
        // Ease in-out at a quarter of the way is behind linear (0.129 of the distance).
        let commands = fills(window)
        let group = commands.first { $0.hasPrefix("beginGroup") }
        #expect(group != nil && group!.contains("0.87"), "\(commands)")
        #expect(commands.contains { $0.hasPrefix("fillRect(12.5, 0, 20, 20)") || $0.hasPrefix("fillRect(13, 0, 20, 20)") }, "\(commands)")
    }

    @Test func withoutAnimationAppliesAtOnce() {
        let window = window()
        let box = UIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        box.backgroundColor = UIColor(red: 0, green: 1, blue: 0, alpha: 1)
        window.addSubview(box)
        UIView.animate(withDuration: 1) {
            UIView.performWithoutAnimation { box.frame.origin.x = 60 }
        }
        #expect(fills(window).contains("fillRect(60, 0, 20, 20) #00FF00"))
        #expect(!UIKitScene.shared.isAnimating)
    }

    @Test func curves() {
        #expect(abs(AnimationCurve.easeInOut.value(at: 0.5) - 0.5) < 1e-6)
        #expect(AnimationCurve.easeIn.value(at: 0.25) < 0.25)
        #expect(AnimationCurve.easeOut.value(at: 0.25) > 0.25)
        #expect(abs(AnimationCurve.spring(damping: 1, velocity: 0).value(at: 1) - 1) < 0.01)
        #expect(AnimationCurve.spring(damping: 0.5, velocity: 0).value(at: 0.3) > 1)   // an underdamped spring overshoots
    }
}
