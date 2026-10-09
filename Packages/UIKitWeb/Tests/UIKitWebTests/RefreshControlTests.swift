// uk-refresh (Controls/UIRefreshControl.swift, UIScrollView.refreshControl): a pull past the
// threshold starts a refresh and sends valueChanged, the content rests under the control while
// it refreshes and returns when it ends; a programmatic beginRefreshing sends nothing.
import Testing
import UIKit
@testable import UIKitWebCore

@Suite @MainActor struct RefreshControlTests {
    @Test func aPullStartsARefresh() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.textEngine = try! Goldens.textEngine()
        scene.configureScreen(size: CGSize(width: 320, height: 400), scale: 2)
        let root = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        window.rootViewController = root
        window.makeKeyAndVisible()
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scroll.contentSize = CGSize(width: 320, height: 2000)
        let control = UIRefreshControl()
        var refreshes = 0
        control.addAction(UIAction { _ in refreshes += 1 }, for: .valueChanged)
        scroll.refreshControl = control
        root.view.addSubview(scroll)
        scene.layout(in: CGSize(width: 320, height: 400))
        #expect(control.superview === scroll && control.isHidden && control.frame == CGRect(x: 0, y: 0, width: 320, height: 60))
        #expect(scroll.adjustedContentInset.top == 0)

        // A short pull shows the control growing and lets go of it.
        scene.pointerDown(at: CGPoint(x: 160, y: 100), type: .touch, time: 0)
        scene.pointerMoved(to: CGPoint(x: 160, y: 130), time: 0.05)
        scene.pointerMoved(to: CGPoint(x: 160, y: 140), time: 0.1)
        #expect(!control.isHidden && control.pullFraction > 0 && control.pullFraction < 1 && scroll.contentOffset.y < 0)
        scene.pointerUp(at: CGPoint(x: 160, y: 140), time: 0.15)
        _ = scene.advanceFrame(elapsed: 0.5)
        #expect(refreshes == 0 && !control.isRefreshing && scroll.contentOffset.y == 0)

        // A pull past the threshold refreshes: the content rests 60 down under the spinner.
        scene.pointerDown(at: CGPoint(x: 160, y: 100), type: .touch, time: 1)
        scene.pointerMoved(to: CGPoint(x: 160, y: 150), time: 1.05)
        scene.pointerMoved(to: CGPoint(x: 160, y: 200), time: 1.1)
        scene.pointerUp(at: CGPoint(x: 160, y: 200), time: 1.15)
        #expect(refreshes == 1 && control.isRefreshing && scene.isAnimating)
        _ = scene.advanceFrame(elapsed: 0.5)
        scene.layout(in: CGSize(width: 320, height: 400))
        #expect(scroll.adjustedContentInset.top == 60 && scroll.contentOffset.y == -60)
        #expect(control.frame == CGRect(x: 0, y: -60, width: 320, height: 60) && !control.isHidden)
        let spokes = scene.render(scale: 2, background: false).commands.filter { if case .strokePath = $0 { return true } else { return false } }
        #expect(spokes.count >= 8)
        control.endRefreshing()
        scene.layout(in: CGSize(width: 320, height: 400))
        #expect(!control.isRefreshing && control.isHidden && scroll.contentOffset.y == 0 && !scene.isAnimating)

        // A programmatic refresh sends no event; a title makes the control taller.
        control.attributedTitle = NSAttributedString(string: "Pull to refresh")
        control.beginRefreshing()
        scene.layout(in: CGSize(width: 320, height: 400))
        #expect(refreshes == 1 && control.frame.height == 84.5 && scroll.adjustedContentInset.top == 84.5)
        control.endRefreshing()
    }
}
