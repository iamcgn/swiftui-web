// Hover (Events/Hover.swift): a pointer move without a press hovers the view under it; hover
// recognizers begin, change and end; a pointer interaction's style and a button's pointer
// effect set the scene's cursor.
import Testing
import UIKit

@Suite @MainActor struct HoverTests {
    final class Beam: UIPointerInteractionDelegate {
        func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
            UIPointerStyle(shape: .horizontalBeam(length: 20))
        }
    }

    @Test func pointerMovesHoverTheViewUnderThem() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 300, height: 300), scale: 2)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        let view = UIView(frame: CGRect(x: 50, y: 50, width: 100, height: 100))
        var states: [UIGestureRecognizer.State] = []
        var locations: [CGPoint] = []
        let hover = UIHoverGestureRecognizer { recognizer in
            states.append(recognizer.state)
            locations.append(recognizer.location(in: recognizer.view))
        }
        view.addGestureRecognizer(hover)
        let beam = Beam()
        view.addInteraction(UIPointerInteraction(delegate: beam))
        let button = UIButton(type: .system)
        button.frame = CGRect(x: 50, y: 200, width: 100, height: 40)
        button.isPointerInteractionEnabled = true
        window.addSubview(view)
        window.addSubview(button)
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 300, height: 300))

        scene.pointerMoved(to: CGPoint(x: 60, y: 60), time: 1)
        #expect(states == [.began])
        #expect(locations.last == CGPoint(x: 10, y: 10))
        #expect(scene.pointerCursor == "text")
        scene.pointerMoved(to: CGPoint(x: 80, y: 90), time: 1.1)
        #expect(states == [.began, .changed])
        #expect(locations.last == CGPoint(x: 30, y: 40))
        scene.pointerMoved(to: CGPoint(x: 100, y: 220), time: 1.2)
        #expect(states == [.began, .changed, .ended])
        #expect(scene.pointerCursor == "pointer", "the button's pointer effect")
        scene.pointerMoved(to: CGPoint(x: 10, y: 10), time: 1.3)
        #expect(scene.pointerCursor == nil)
        scene.pointerMoved(to: CGPoint(x: 60, y: 60), time: 1.4)
        scene.pointerLeft()
        #expect(states.suffix(2) == [.began, .ended])
        #expect(scene.pointerCursor == nil)
        // A press drags instead of hovering.
        scene.pointerDown(at: CGPoint(x: 60, y: 60), type: .mouse, time: 2)
        let before = states.count
        scene.pointerMoved(to: CGPoint(x: 70, y: 70), time: 2.1)
        #expect(states.count == before)
        scene.pointerUp(at: CGPoint(x: 70, y: 70), time: 2.2)
    }
}
