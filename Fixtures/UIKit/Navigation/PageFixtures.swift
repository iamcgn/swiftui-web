// UIPageViewController (uk-pageviewcontroller, Docs/elements/UIKit/Navigation.md): three pages
// in the scroll style with the page indicator the data source's counts bring, moved forward by
// a step, and a vertical page-curl controller.
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

/// A coloured page with its number.
final class PageController: UIViewController {
    var index = 0
    var colour = UIColor.white

    static func make(index: Int, colour: UIColor) -> PageController {
        let controller = PageController()
        controller.index = index
        controller.colour = colour
        return controller
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = colour
        let label = UILabel()
        label.text = "Page \(index + 1)"
        label.font = .systemFont(ofSize: 28, weight: .semibold)
        label.textColor = .white
        label.sizeToFit()
        label.frame.origin = CGPoint(x: 24, y: 24)
        view.addSubview(label.probe("page\(index + 1)"))
    }
}

@MainActor final class Pages: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    let pages = [PageController.make(index: 0, colour: .systemBlue), PageController.make(index: 1, colour: .systemGreen), PageController.make(index: 2, colour: .systemOrange)]
    var transitions: [Int] = []

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? PageController, page.index > 0 else { return nil }
        return pages[page.index - 1]
    }
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? PageController, page.index + 1 < pages.count else { return nil }
        return pages[page.index + 1]
    }
    func presentationCount(for pageViewController: UIPageViewController) -> Int { pages.count }
    func presentationIndex(for pageViewController: UIPageViewController) -> Int {
        (pageViewController.viewControllers?.first as? PageController)?.index ?? 0
    }
    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        if completed, let page = pageViewController.viewControllers?.first as? PageController { transitions.append(page.index) }
    }
}

@MainActor public final class PageModel {
    let source = Pages()
    var controller: UIPageViewController?
    public init() {}
}

public enum PageFixtures {
    public static let all = [scroll, curl]

    /// The scroll style with a 20 pt inter-page spacing and the indicator at the bottom.
    public static let scroll = UIKitFixture("uikit/page/scroll", size: CGSize(width: 320, height: 400), model: { PageModel() }, steps: [
        UIKitFixtureStep("forward") { model in
            model.controller?.setViewControllers([model.source.pages[1]], direction: .forward, animated: false)
        },
    ]) { model in
        let controller = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal, options: [.interPageSpacing: 20])
        controller.dataSource = model.source
        controller.delegate = model.source
        controller.setViewControllers([model.source.pages[0]], direction: .forward, animated: false)
        model.controller = controller
        controller.loadViewIfNeeded()
        controller.view.probe("pager")
        return controller
    }

    /// The page-curl style scrolling vertically, without an indicator (no counts).
    public static let curl = UIKitFixture("uikit/page/curl", size: CGSize(width: 320, height: 400)) {
        final class Source: NSObject, UIPageViewControllerDataSource {
            let pages = [PageController.make(index: 0, colour: .systemIndigo), PageController.make(index: 1, colour: .systemTeal)]
            func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
                (viewController as? PageController)?.index == 1 ? pages[0] : nil
            }
            func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
                (viewController as? PageController)?.index == 0 ? pages[1] : nil
            }
        }
        let source = Source()
        PageFixtures.sources.append(source)
        let controller = UIPageViewController(transitionStyle: .pageCurl, navigationOrientation: .vertical, options: nil)
        controller.dataSource = source
        controller.setViewControllers([source.pages[0]], direction: .forward, animated: false)
        controller.loadViewIfNeeded()
        controller.view.probe("curl")
        return controller
    }

    @MainActor static var sources: [NSObject] = []
}
#endif
