// UISplitViewController (uk-splitviewcontroller, Containers/UISplitViewController.swift): the
// modes' geometry beyond the goldens, show / hide and the toggle, the delegate's say in the
// collapse, and a collapse that expands again with the secondary back in its column.
import Testing
@testable import UIKitWebCore
import UIKit

@Suite @MainActor struct SplitViewControllerTests {
    final class Delegate: NSObject, UISplitViewControllerDelegate {
        var events: [String] = []
        var topColumn: UISplitViewController.Column = .secondary
        func splitViewController(_ svc: UISplitViewController, topColumnForCollapsingToProposedTopColumn proposedTopColumn: UISplitViewController.Column) -> UISplitViewController.Column {
            events.append("collapse to \(proposedTopColumn)")
            return topColumn
        }
        func splitViewControllerDidCollapse(_ svc: UISplitViewController) { events.append("collapsed") }
        func splitViewControllerDidExpand(_ svc: UISplitViewController) { events.append("expanded") }
        func splitViewController(_ svc: UISplitViewController, willChangeTo displayMode: UISplitViewController.DisplayMode) { events.append("mode \(displayMode)") }
        func splitViewController(_ svc: UISplitViewController, willHide column: UISplitViewController.Column) { events.append("hide \(column)") }
        func splitViewController(_ svc: UISplitViewController, willShow column: UISplitViewController.Column) { events.append("show \(column)") }
    }

    private func host(_ split: UISplitViewController, width: CGFloat, height: CGFloat = 600) -> UIWindow {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: width, height: height), scale: 2)
        scene.textEngine = try! Goldens.textEngine()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        window.rootViewController = split
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: width, height: height))
        return window
    }

    private func controller(_ title: String) -> UIViewController {
        let controller = UIViewController()
        controller.title = title
        return controller
    }

    @Test func showHideAndTheToggle() {
        let split = UISplitViewController(style: .doubleColumn)
        let primary = controller("Sidebar"), secondary = controller("Detail")
        split.setViewController(primary, for: .primary)
        split.setViewController(secondary, for: .secondary)
        let delegate = Delegate()
        split.delegate = delegate
        let window = host(split, width: 800)
        #expect(!split.isCollapsed && split.displayMode == .oneBesideSecondary && split.primaryColumnWidth == 320)
        #expect(primary.navigationController?.view.frame == CGRect(x: 0, y: 0, width: 320, height: 600))
        #expect(secondary.navigationController?.view.frame == CGRect(x: 0, y: 0, width: 800, height: 600))
        // The toggle sits at the sidebar's trailing edge; the secondary's bar keeps out of the sidebar.
        #expect(primary.navigationItem.rightBarButtonItems?.first === split.displayModeButtonItem)
        #expect(secondary.navigationController?.navigationBar.leadingInset == 320)
        split.hide(.primary)
        window.layoutIfNeeded()
        #expect(split.displayMode == .secondaryOnly && primary.navigationController?.view.superview == nil)
        #expect(secondary.navigationItem.leftBarButtonItems?.count == 1 && secondary.navigationController?.navigationBar.leadingInset == 0)
        #expect(delegate.events.contains("hide primary") && delegate.events.contains("mode secondaryOnly"))
        // The secondary's toggle shows the sidebar again.
        secondary.navigationItem.leftBarButtonItems?.first?.primaryAction?.perform(sender: nil)
        window.layoutIfNeeded()
        #expect(split.displayMode == .oneBesideSecondary && primary.navigationController?.view.superview != nil)
        // Overlay: the primary over the dimmed secondary, 16 from its edge for the toggle.
        split.preferredSplitBehavior = .overlay
        split.preferredDisplayMode = .oneOverSecondary
        window.layoutIfNeeded()
        #expect(split.displayMode == .oneOverSecondary && secondary.navigationController?.navigationBar.leadingInset == 0)
        #expect(primary.navigationController?.navigationBar.edgeInset == 16 && !split.dimmingIsHidden)
        // A trailing primary edge mirrors the columns.
        split.preferredSplitBehavior = .tile
        split.preferredDisplayMode = .oneBesideSecondary
        split.primaryEdge = .trailing
        window.layoutIfNeeded()
        #expect(primary.navigationController?.view.frame.minX == 480)
    }

    @Test func tripleColumnsAndTheirModes() {
        let split = UISplitViewController(style: .tripleColumn)
        let primary = controller("Sidebar"), supplementary = controller("List"), secondary = controller("Detail")
        split.setViewController(primary, for: .primary)
        split.setViewController(supplementary, for: .supplementary)
        split.setViewController(secondary, for: .secondary)
        let window = host(split, width: 1000)
        // 1000 cannot tile three: the primary overlays (uikit/split/triple).
        #expect(split.displayMode == .twoBesideSecondary && split.primaryColumnWidth == 280 && split.supplementaryColumnWidth == 340)
        #expect(supplementary.navigationController?.view.frame == CGRect(x: 0, y: 0, width: 340, height: 600))
        #expect(secondary.navigationController?.view.frame == CGRect(x: 341, y: 0, width: 659, height: 600))
        #expect(primary.navigationController?.view.frame.width == 280 && !split.dimmingIsHidden)
        // Wide enough, all three tile.
        window.frame = CGRect(x: 0, y: 0, width: 1200, height: 600)
        UIKitScene.shared.layout(in: CGSize(width: 1200, height: 600))
        #expect(split.dimmingIsHidden && supplementary.navigationController?.view.frame.minX == 280 && secondary.navigationController?.view.frame.minX == 621)
        // "One" beside the secondary is the supplementary; hiding the primary goes there.
        split.hide(.primary)
        window.layoutIfNeeded()
        #expect(split.displayMode == .oneBesideSecondary && primary.navigationController?.view.superview == nil && supplementary.navigationController?.view.frame.minX == 0)
        split.hide(.supplementary)
        window.layoutIfNeeded()
        #expect(split.displayMode == .secondaryOnly && supplementary.navigationController?.view.superview == nil)
        split.show(.primary)
        window.layoutIfNeeded()
        #expect(split.displayMode == .twoBesideSecondary)
    }

    @Test func collapsingAndExpanding() {
        let split = UISplitViewController(style: .doubleColumn)
        let primary = controller("Sidebar"), secondary = controller("Detail")
        split.setViewController(primary, for: .primary)
        split.setViewController(secondary, for: .secondary)
        let delegate = Delegate()
        split.delegate = delegate
        let window = host(split, width: 320, height: 480)
        // Compact: the secondary collapses onto the primary's stack, on top.
        #expect(split.isCollapsed && delegate.events.contains("collapse to secondary") && delegate.events.contains("collapsed"))
        #expect(primary.navigationController?.viewControllers.last === secondary && primary.navigationController?.view.frame.width == 320)
        // Expanding gives the secondary its column back.
        window.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        UIKitScene.shared.layout(in: CGSize(width: 800, height: 600))
        #expect(!split.isCollapsed && delegate.events.contains("expanded"))
        #expect(primary.navigationController?.viewControllers.count == 1 && secondary.navigationController?.view.frame.width == 800)
        // A delegate keeping the primary on top collapses without the push; `showDetailViewController` pushes then.
        delegate.topColumn = .primary
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        UIKitScene.shared.layout(in: CGSize(width: 320, height: 480))
        #expect(split.isCollapsed && primary.navigationController?.viewControllers.count == 1)
        let pushed = controller("Pushed")
        primary.showDetailViewController(pushed, sender: nil)
        #expect(primary.navigationController?.viewControllers.last === pushed)
        // A compact column stands in for everything in a compact width.
        let compact = UISplitViewController(style: .doubleColumn)
        compact.setViewController(controller("Sidebar"), for: .primary)
        compact.setViewController(controller("Detail"), for: .secondary)
        let standIn = controller("Compact")
        compact.setViewController(standIn, for: .compact)
        _ = host(compact, width: 320, height: 480)
        #expect(standIn.parent === compact && standIn.view.frame.width == 320 && compact.viewController(for: .compact) === standIn)
        compact.show(.secondary)
        #expect(standIn.parent === compact, "a compact column that is no stack takes no push")
    }
}
