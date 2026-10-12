// UISplitViewController (uk-splitviewcontroller, Docs/elements/UIKit/Navigation.md): the
// column styles and display modes measured on the iPad simulator (IOS_DEVICE=ipad), and the
// compact collapse on the iPhone. Each column is a plain screen with a coloured ground so the
// columns' frames show.
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

/// A column's screen: its title in the bar, a ground colour, a label 16 in.
final class ColumnController: UIViewController {
    var ground: UIColor = .systemBackground
    var text = ""
    var probeName = ""

    static func make(title: String, ground: UIColor, text: String, probe: String) -> ColumnController {
        let controller = ColumnController()
        controller.title = title
        controller.ground = ground
        controller.text = text
        controller.probeName = probe
        return controller
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ground
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 17)
        label.sizeToFit()
        label.frame.origin = CGPoint(x: 16, y: 16)
        view.addSubview(label.probe(probeName))
    }
}

@MainActor public final class SplitModel {
    var split: UISplitViewController?
    public init() {}
}

public enum SplitFixtures {
    public static let all = [columns, triple, modes, compact, collapsed]

    @MainActor static func makeSplit(style: UISplitViewController.Style, model: SplitModel, compactColumn: Bool = true) -> UISplitViewController {
        let split = UISplitViewController(style: style)
        let primary = ColumnController.make(title: "Sidebar", ground: .systemGray6, text: "Primary", probe: "primary")
        let secondary = ColumnController.make(title: "Detail", ground: .systemBackground, text: "Secondary", probe: "secondary")
        split.setViewController(primary, for: .primary)
        split.setViewController(secondary, for: .secondary)
        if style == .tripleColumn {
            let supplementary = ColumnController.make(title: "List", ground: .systemGray5, text: "Supplementary", probe: "supplementary")
            split.setViewController(supplementary, for: .supplementary)
        }
        // The compact column shows as it is (UIKit wraps the other columns, not this one): a
        // navigation controller, so `show(.secondary)` has a stack to push onto.
        if compactColumn {
            let compact = ColumnController.make(title: "Compact", ground: .systemGray6, text: "Compact", probe: "compact")
            split.setViewController(UINavigationController(rootViewController: compact), for: .compact)
        }
        model.split = split
        split.view.probe("split")
        return split
    }

    /// Two columns side by side in 800 × 600: the sidebar at the split view's default width,
    /// the detail beside it.
    public static let columns = UIKitFixture("uikit/split/columns", size: CGSize(width: 800, height: 600),
                                             model: { SplitModel() },
                                             steps: [UIKitFixtureStep("hide") { model in
                                                         model.split?.preferredDisplayMode = .secondaryOnly
                                                         model.split?.view.layoutIfNeeded()
                                                     }]) { model in
        let split = makeSplit(style: .doubleColumn, model: model)
        split.preferredDisplayMode = .oneBesideSecondary
        return split
    }

    /// Three columns in 1000 × 600.
    public static let triple = UIKitFixture("uikit/split/triple", size: CGSize(width: 1000, height: 600),
                                            model: { SplitModel() },
                                            steps: [UIKitFixtureStep("one") { model in
                                                        model.split?.preferredDisplayMode = .oneBesideSecondary
                                                        model.split?.view.layoutIfNeeded()
                                                    }]) { model in
        let split = makeSplit(style: .tripleColumn, model: model)
        split.preferredDisplayMode = .twoBesideSecondary
        return split
    }

    /// The overlay and displace modes, and a custom primary width, in 800 × 600.
    public static let modes = UIKitFixture("uikit/split/modes", size: CGSize(width: 800, height: 600),
                                           model: { SplitModel() },
                                           steps: [UIKitFixtureStep("displace") { model in
                                                       model.split?.preferredSplitBehavior = .displace
                                                       model.split?.preferredDisplayMode = .oneOverSecondary
                                                       model.split?.view.layoutIfNeeded()
                                                   },
                                                   UIKitFixtureStep("width") { model in
                                                       model.split?.preferredSplitBehavior = .tile
                                                       model.split?.preferredDisplayMode = .oneBesideSecondary
                                                       model.split?.preferredPrimaryColumnWidth = 240
                                                       model.split?.view.layoutIfNeeded()
                                                   }]) { model in
        let split = makeSplit(style: .doubleColumn, model: model)
        split.preferredSplitBehavior = .overlay
        split.preferredDisplayMode = .oneOverSecondary
        return split
    }

    /// The compact width (the iPhone): the split view shows its compact column alone
    /// (`show(.secondary)` does nothing then: the compact column stands in for the others).
    public static let compact = UIKitFixture("uikit/split/compact", size: CGSize(width: 320, height: 480),
                                             model: { SplitModel() },
                                             steps: [UIKitFixtureStep("secondary") { model in
                                                         model.split?.show(.secondary)
                                                         model.split?.view.layoutIfNeeded()
                                                     }]) { model in
        makeSplit(style: .doubleColumn, model: model)
    }

    /// The compact width without a compact column: the primary's stack shows, and
    /// `show(.secondary)` pushes the secondary onto it.
    public static let collapsed = UIKitFixture("uikit/split/collapsed", size: CGSize(width: 320, height: 480),
                                               model: { SplitModel() },
                                               steps: [UIKitFixtureStep("secondary") { model in
                                                           model.split?.show(.secondary)
                                                           model.split?.view.layoutIfNeeded()
                                                       }]) { model in
        makeSplit(style: .doubleColumn, model: model, compactColumn: false)
    }
}
#endif
