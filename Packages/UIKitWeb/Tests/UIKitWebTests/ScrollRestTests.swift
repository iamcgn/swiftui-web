// uk-scroll-rest (Controls/UIScrollView.swift): zooming with setZoomScale, zoom(to:) and a
// pinch about its centre with the delegate's callbacks, keyboardDismissMode on a drag,
// scroll-to-top as a status bar tap, and the indicator insets.
import Testing
import UIKit
@testable import UIKitWebCore

@MainActor private final class Zoomer: UIScrollViewDelegate {
    let view: UIView
    var zooms = 0
    var began = 0, ended: [CGFloat] = []
    var toTop = 0
    init(view: UIView) { self.view = view }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { view }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { zooms += 1 }
    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) { began += 1 }
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) { ended.append(scale) }
    func scrollViewDidScrollToTop(_ scrollView: UIScrollView) { toTop += 1 }
}

@Suite @MainActor struct ScrollRestTests {
    private func scene() -> (UIKitScene, UIViewController) {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.textEngine = try! Goldens.textEngine()
        scene.configureScreen(size: CGSize(width: 320, height: 400), scale: 2)
        let root = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        window.rootViewController = root
        window.makeKeyAndVisible()
        return (scene, root)
    }

    @Test func zoomingScalesTheDelegatesView() {
        let (scene, root) = scene()
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 200, height: 150))
        let content = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 150))
        let zoomer = Zoomer(view: content)
        scroll.delegate = zoomer
        scroll.minimumZoomScale = 0.5
        scroll.maximumZoomScale = 3
        scroll.addSubview(content)
        scroll.contentSize = content.bounds.size
        root.view.addSubview(scroll)
        scene.layout(in: CGSize(width: 320, height: 400))
        scroll.setZoomScale(2, animated: false)
        #expect(scroll.zoomScale == 2 && content.frame == CGRect(x: 0, y: 0, width: 400, height: 300) && scroll.contentSize == CGSize(width: 400, height: 300))
        #expect(zoomer.zooms == 1 && scroll.contentOffset == .zero)
        scroll.zoomScale = 5   // clamped to the maximum
        #expect(scroll.zoomScale == 3)
        scroll.zoom(to: CGRect(x: 50, y: 50, width: 100, height: 75), animated: false)
        #expect(scroll.zoomScale == 2 && scroll.contentOffset == CGPoint(x: 100, y: 100))
        // A pinch from 2 to 1 about (100, 75) keeps the content point under the fingers there.
        scene.pinch(.began, scale: 1, rotation: 0, at: CGPoint(x: 100, y: 75), time: 0)
        #expect(!scroll.isZooming)   // the recognizer begins once the fingers move
        scene.pinch(.changed, scale: 0.5, rotation: 0, at: CGPoint(x: 100, y: 75), time: 0.1)
        #expect(scroll.isZooming && zoomer.began == 1)
        #expect(scroll.zoomScale == 1 && content.frame.size == CGSize(width: 200, height: 150))
        #expect(scroll.contentOffset == .zero)   // (200, 175) / 2 − (100, 75) = (0, 12.5), clamped to the 150 pt content
        scene.pinch(.ended, scale: 0.5, rotation: 0, at: CGPoint(x: 100, y: 75), time: 0.2)
        #expect(!scroll.isZooming && zoomer.ended == [1])
        scroll.setZoomScale(0.5, animated: false)
        #expect(content.frame == CGRect(x: 0, y: 0, width: 100, height: 75) && scroll.contentSize == CGSize(width: 100, height: 75))
    }

    @Test func dragsDismissTheKeyboardAndTapsScrollToTop() {
        let (scene, root) = scene()
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scroll.contentSize = CGSize(width: 320, height: 2000)
        scroll.keyboardDismissMode = .onDrag
        let field = UITextField(frame: CGRect(x: 16, y: 16, width: 200, height: 34))
        scroll.addSubview(field)
        root.view.addSubview(scroll)
        scene.layout(in: CGSize(width: 320, height: 400))
        field.becomeFirstResponder()
        #expect(field.isFirstResponder)
        scene.pointerDown(at: CGPoint(x: 160, y: 300), type: .touch, time: 0)
        scene.pointerMoved(to: CGPoint(x: 160, y: 250), time: 0.05)
        scene.pointerMoved(to: CGPoint(x: 160, y: 200), time: 0.1)
        #expect(!field.isFirstResponder && scroll.contentOffset.y > 0)
        scene.pointerMoved(to: CGPoint(x: 160, y: 200), time: 0.6)   // a still finger: no momentum
        scene.pointerUp(at: CGPoint(x: 160, y: 200), time: 0.7)
        scroll.setContentOffset(CGPoint(x: 0, y: 500), animated: false)

        // A status bar tap scrolls the frontmost scroll view to its top, unless told not to.
        let zoomer = Zoomer(view: UIView())
        scroll.delegate = zoomer
        #expect(scene.scrollToTop())
        _ = scene.advanceFrame(elapsed: 1)
        #expect(scroll.contentOffset.y == 0 && zoomer.toTop == 1)
        scroll.setContentOffset(CGPoint(x: 0, y: 500), animated: false)
        scroll.scrollsToTop = false
        #expect(!scene.scrollToTop() && scroll.contentOffset.y == 500)

        // Indicator insets replace the 3 pt margins on their edges (uikit/scroll/zoom).
        scroll.scrollsToTop = true
        scroll.verticalScrollIndicatorInsets = UIEdgeInsets(top: 10, left: 0, bottom: 10, right: 4)
        scroll.setContentOffset(CGPoint(x: 0, y: 100), animated: false)
        scene.layout(in: CGSize(width: 320, height: 400))
        let bar = scroll.verticalIndicator.frame
        #expect(bar.minX == 320 - 4 - 3 && bar.minY >= 100 + 10)
    }
}
