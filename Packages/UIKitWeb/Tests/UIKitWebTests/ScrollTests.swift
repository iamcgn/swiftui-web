// UIScrollView momentum (Controls/UIScrollView.swift): a pan that ends with velocity carries the
// content on the scene's clock, decelerating at UIKit's rate, and stops at the edge or below a
// floor; a touch on the content stops it.
import Testing
import UIKit
@testable import UIKitWebCore

@Suite @MainActor struct ScrollTests {
    final class Log: UIScrollViewDelegate {
        var events: [String] = []
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) { events.append("endDrag \(decelerate)") }
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { events.append("endDecelerate") }
    }

    private func scrollView() -> (UIScrollView, Log) {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 200, height: 300), scale: 2)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 300))
        let scroll = UIScrollView(frame: window.bounds)
        scroll.contentSize = CGSize(width: 200, height: 2000)
        let log = Log()
        scroll.delegate = log
        window.addSubview(scroll)
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 200, height: 300))
        return (scroll, log)
    }

    @Test func aFlickCarriesTheContentAndDecelerates() {
        let (scroll, log) = scrollView()
        let scene = UIKitScene.shared
        // A quick upward drag of 100 pt over 0.1 s.
        scene.pointerDown(at: CGPoint(x: 100, y: 200), type: .touch, time: 0)
        scene.pointerMoved(to: CGPoint(x: 100, y: 150), time: 0.05)
        scene.pointerMoved(to: CGPoint(x: 100, y: 100), time: 0.1)
        scene.pointerUp(at: CGPoint(x: 100, y: 100), time: 0.1)
        #expect(scroll.contentOffset.y == 100)
        #expect(scroll.isDecelerating)
        #expect(scene.isAnimating)
        #expect(log.events == ["endDrag true"])
        // Momentum keeps the content moving, slower each frame.
        _ = scene.advanceFrame(elapsed: 0.1)
        let afterFirst = scroll.contentOffset.y
        #expect(afterFirst > 100)
        _ = scene.advanceFrame(elapsed: 0.1)
        let afterSecond = scroll.contentOffset.y
        #expect(afterSecond - afterFirst < afterFirst - 100)
        // It stops eventually and the delegate hears.
        for _ in 0..<100 where scroll.isDecelerating { _ = scene.advanceFrame(elapsed: 0.1) }
        #expect(!scroll.isDecelerating)
        #expect(log.events.last == "endDecelerate")
        #expect(!scene.isAnimating)
    }

    @Test func aTouchStopsTheMomentum() {
        let (scroll, log) = scrollView()
        let scene = UIKitScene.shared
        scene.pointerDown(at: CGPoint(x: 100, y: 250), type: .touch, time: 0)
        scene.pointerMoved(to: CGPoint(x: 100, y: 100), time: 0.1)
        scene.pointerUp(at: CGPoint(x: 100, y: 100), time: 0.1)
        #expect(scroll.isDecelerating)
        _ = scene.advanceFrame(elapsed: 0.05)
        scene.pointerDown(at: CGPoint(x: 100, y: 150), type: .touch, time: 0.2)
        #expect(!scroll.isDecelerating)
        #expect(log.events.last == "endDecelerate")
        scene.pointerUp(at: CGPoint(x: 100, y: 150), time: 0.25)
    }
}
