// UIScrollView zooming and inset rules (uk-scroll-rest, Docs/elements/UIKit/UIScrollView.md):
// a zoomed image, a view zoomed to a rectangle, a zoomed-out view, the indicator insets, and a
// navigation controller's scroll view whose short content still starts under the bar.
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

@MainActor public final class ZoomModel {
    let photo = UIScrollView()
    let photoView = UIImageView(image: UIKitFixtureImage.named("photo"))
    let panel = UIScrollView()
    let panelView = UIView()
    let zoomer = Zoomer()
    public init() {}
}

final class Zoomer: NSObject, UIScrollViewDelegate {
    var views: [ObjectIdentifier: UIView] = [:]
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { views[ObjectIdentifier(scrollView)] }
}

public enum ScrollRestFixtures {
    public static let all = [zoom, navigationInset]

    /// The 80 × 60 photo zoomed to 2 in a 200 × 150 scroll view, a 200 × 150 panel zoomed to a
    /// 100 × 75 rectangle, and a scroll view scrolled 100 with its indicator insets set; the
    /// step zooms the photo out to a half.
    public static let zoom = UIKitFixture("uikit/scroll/zoom", size: CGSize(width: 320, height: 420), model: { ZoomModel() }, steps: [
        UIKitFixtureStep("zoomOut") { model in
            model.photo.setZoomScale(0.5, animated: false)
        },
    ]) { model in
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 420))
        root.backgroundColor = .white

        model.photo.frame = CGRect(x: 16, y: 16, width: 200, height: 150)
        model.photo.backgroundColor = .systemGray5
        model.photo.minimumZoomScale = 0.5
        model.photo.maximumZoomScale = 4
        model.photo.delegate = model.zoomer
        model.zoomer.views[ObjectIdentifier(model.photo)] = model.photoView
        model.photo.addSubview(model.photoView.probe("photoView"))
        model.photo.contentSize = model.photoView.bounds.size
        root.addSubview(model.photo.probe("photo"))
        model.photo.setZoomScale(2, animated: false)

        model.panel.frame = CGRect(x: 16, y: 182, width: 200, height: 150)
        model.panel.backgroundColor = .systemGray5
        model.panel.minimumZoomScale = 1
        model.panel.maximumZoomScale = 3
        model.panel.delegate = model.zoomer
        model.panelView.frame = CGRect(x: 0, y: 0, width: 200, height: 150)
        model.panelView.backgroundColor = .systemTeal
        let mark = UIView(frame: CGRect(x: 50, y: 50, width: 100, height: 75))
        mark.backgroundColor = .systemIndigo
        model.panelView.addSubview(mark.probe("mark"))
        model.zoomer.views[ObjectIdentifier(model.panel)] = model.panelView
        model.panel.addSubview(model.panelView.probe("panelView"))
        model.panel.contentSize = model.panelView.bounds.size
        root.addSubview(model.panel.probe("panel"))
        model.panel.zoom(to: CGRect(x: 50, y: 50, width: 100, height: 75), animated: false)

        let indicators = UIScrollView(frame: CGRect(x: 16, y: 348, width: 200, height: 56))
        indicators.backgroundColor = .systemGray5
        indicators.contentSize = CGSize(width: 200, height: 600)
        indicators.verticalScrollIndicatorInsets = UIEdgeInsets(top: 10, left: 0, bottom: 10, right: 4)
        indicators.contentOffset = CGPoint(x: 0, y: 100)
        root.addSubview(indicators.probe("indicators"))
        indicators.flashScrollIndicators()
        return root
    }

    /// A navigation controller's screen whose view is a scroll view with content shorter than
    /// the screen: `.automatic` still starts it under the bar (`.never` does not).
    public static let navigationInset = UIKitFixture("uikit/nav/scroll-inset", size: CGSize(width: 320, height: 400)) {
        let screen = UIViewController()
        screen.title = "Short"
        let scroll = UIScrollView()
        scroll.contentSize = CGSize(width: 320, height: 120)
        let label = UILabel()
        label.text = "Short content"
        label.font = .systemFont(ofSize: 17)
        label.sizeToFit()
        label.frame.origin = CGPoint(x: 16, y: 16)
        scroll.addSubview(label.probe("label"))
        let never = UIScrollView(frame: CGRect(x: 0, y: 300, width: 320, height: 100))
        never.contentInsetAdjustmentBehavior = .never
        never.contentSize = CGSize(width: 320, height: 80)
        let neverLabel = UILabel()
        neverLabel.text = "Never adjusted"
        neverLabel.font = .systemFont(ofSize: 17)
        neverLabel.sizeToFit()
        neverLabel.frame.origin = CGPoint(x: 16, y: 16)
        never.addSubview(neverLabel.probe("neverLabel"))
        screen.loadViewIfNeeded()
        screen.view.backgroundColor = .systemBackground
        scroll.frame = CGRect(x: 0, y: 0, width: 320, height: 300)
        screen.view.addSubview(scroll.probe("scroll"))
        screen.view.addSubview(never.probe("never"))
        let navigation = UINavigationController(rootViewController: screen)
        navigation.navigationBar.probe("bar")
        return navigation
    }
}
#endif
