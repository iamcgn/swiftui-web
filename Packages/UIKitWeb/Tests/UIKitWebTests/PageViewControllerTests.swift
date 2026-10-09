// uk-pageviewcontroller (Containers/UIPageViewController.swift): the slots and the indicator,
// a drag loading the neighbours and settling on the next page with the delegate's callbacks,
// the edges without neighbours, setViewControllers, and a tap on the page control.
import Testing
import UIKit
@testable import UIKitWebCore

@MainActor private final class Page: UIViewController {
    let index: Int
    init(_ index: Int) { self.index = index; super.init(nibName: nil, bundle: nil) }
}

@MainActor private final class Source: UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    let pages = [Page(0), Page(1), Page(2)]
    var pending: [[Int]] = []
    var finished: [(previous: [Int], completed: Bool)] = []
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? Page, page.index > 0 else { return nil }
        return pages[page.index - 1]
    }
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? Page, page.index < 2 else { return nil }
        return pages[page.index + 1]
    }
    func presentationCount(for pageViewController: UIPageViewController) -> Int { 3 }
    func presentationIndex(for pageViewController: UIPageViewController) -> Int { (pageViewController.viewControllers?.first as? Page)?.index ?? 0 }
    func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        pending.append(pendingViewControllers.compactMap { ($0 as? Page)?.index })
    }
    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        self.finished.append((previousViewControllers.compactMap { ($0 as? Page)?.index }, completed))
    }
}

@Suite @MainActor struct PageViewControllerTests {
    private func drag(_ scene: UIKitScene, from start: CGPoint, to end: CGPoint) {
        scene.pointerDown(at: start, type: .touch, time: 0)
        scene.pointerMoved(to: CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2), time: 0.05)
        scene.pointerMoved(to: end, time: 0.1)
        scene.pointerMoved(to: end, time: 0.6)   // a still finger: no momentum
        scene.pointerUp(at: end, time: 0.7)
    }

    @Test func pagesScrollBetweenNeighbours() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.textEngine = try! Goldens.textEngine()
        scene.configureScreen(size: CGSize(width: 320, height: 400), scale: 2)
        let source = Source()
        let pager = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal, options: [.interPageSpacing: 20])
        pager.dataSource = source
        pager.delegate = source
        pager.setViewControllers([source.pages[0]], direction: .forward, animated: false)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        window.rootViewController = pager
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 320, height: 400))
        #expect(pager.scrollView.frame == CGRect(x: -10, y: 0, width: 340, height: 374))
        #expect(pager.scrollView.contentOffset == CGPoint(x: 340, y: 0) && source.pages[0].view.convert(source.pages[0].view.bounds, to: nil) == CGRect(x: 0, y: 0, width: 320, height: 374))
        #expect(!pager.pageControl.isHidden && pager.pageControl.frame == CGRect(x: 123, y: 374, width: 74, height: 26) && pager.pageControl.currentPage == 0)
        #expect(pager.children.count == 1 && source.pages[1].viewIfLoaded == nil)

        // A drag to the left brings the next page; the neighbours load as the drag begins.
        drag(scene, from: CGPoint(x: 300, y: 200), to: CGPoint(x: 20, y: 200))
        #expect(source.pending == [[1]])   // the first page has no page before it
        _ = scene.advanceFrame(elapsed: 1)
        scene.layout(in: CGSize(width: 320, height: 400))
        #expect((pager.viewControllers?.first as? Page)?.index == 1)
        #expect(source.finished.last?.previous == [0] && source.finished.last?.completed == true)
        #expect(pager.pageControl.currentPage == 1 && pager.children.count == 1)
        #expect(source.pages[1].view.convert(source.pages[1].view.bounds, to: nil) == CGRect(x: 0, y: 0, width: 320, height: 374))
        #expect(pager.scrollView.contentOffset == CGPoint(x: 340, y: 0))

        // A short drag settles back on the same page.
        drag(scene, from: CGPoint(x: 300, y: 200), to: CGPoint(x: 240, y: 200))
        _ = scene.advanceFrame(elapsed: 1)
        scene.layout(in: CGSize(width: 320, height: 400))
        #expect((pager.viewControllers?.first as? Page)?.index == 1 && source.finished.last?.completed == false)

        // The page control steps forward; the last page cannot be dragged past.
        pager.pageControl.currentPage = 2
        pager.pageControl.sendActions(for: .valueChanged)
        scene.layout(in: CGSize(width: 320, height: 400))
        #expect((pager.viewControllers?.first as? Page)?.index == 2 && pager.pageControl.currentPage == 2)
        drag(scene, from: CGPoint(x: 300, y: 200), to: CGPoint(x: 20, y: 200))
        _ = scene.advanceFrame(elapsed: 1)
        scene.layout(in: CGSize(width: 320, height: 400))
        #expect((pager.viewControllers?.first as? Page)?.index == 2 && pager.scrollView.contentOffset == CGPoint(x: 340, y: 0))
        pager.setViewControllers([source.pages[0]], direction: .reverse, animated: false)
        scene.layout(in: CGSize(width: 320, height: 400))
        #expect((pager.viewControllers?.first as? Page)?.index == 0 && source.finished.last?.previous == [2])
    }
}
