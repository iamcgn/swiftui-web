// UITableViewController (Docs/elements/UIKit/TableView.md): a controller whose view is a table
// view it is the data source and delegate of. Its data source and delegate methods are `open`
// members of the class, so a subclass overrides them (`override func tableView(_:cellForRowAt:)`),
// as UIKit's subclasses do. The first appearance loads the rows; each appearance clears the
// selection unless `clearsSelectionOnViewWillAppear` is off.

import WebFoundation

/// A view controller that specializes in managing a table view.
@preconcurrency @MainActor
open class UITableViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let style: UITableView.Style
    private var hasLoadedRows = false

    /// A controller whose table view has `style`.
    public init(style: UITableView.Style) {
        self.style = style
        super.init(nibName: nil, bundle: nil)
    }

    /// A controller with a plain table view.
    public override init(nibName: String? = nil, bundle: Bundle? = nil) {
        self.style = .plain
        super.init(nibName: nibName, bundle: bundle)
    }

    public required init?(coder: NSCoder) {
        self.style = .plain
        super.init(coder: coder)
    }

    /// The table view the controller manages: its view.
    open var tableView: UITableView! {
        get { view as? UITableView }
        set { view = newValue }
    }

    /// Whether each appearance deselects the selected rows.
    open var clearsSelectionOnViewWillAppear = true

    /// The table view's refresh control.
    open var refreshControl: UIRefreshControl? {
        get { tableView.refreshControl }
        set { tableView.refreshControl = newValue }
    }

    /// Makes a table view of the controller's style, with the controller as its data source and
    /// delegate.
    override open func loadView() {
        let table = UITableView(frame: UIScreen.main.bounds, style: style)
        table.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        table.dataSource = self
        table.delegate = self
        view = table
    }

    override open func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !hasLoadedRows {
            hasLoadedRows = true
            tableView.reloadData()
        }
        if clearsSelectionOnViewWillAppear {
            for path in tableView.indexPathsForSelectedRows ?? [] { tableView.deselectRow(at: path, animated: animated) }
        }
    }

    // MARK: UITableViewDataSource

    open func numberOfSections(in tableView: UITableView) -> Int { 1 }
    open func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 0 }
    /// No rows by default, so the default is never asked; a subclass with rows overrides it.
    open func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        UITableViewCell(style: .default, reuseIdentifier: nil)
    }
    open func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { nil }
    open func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { nil }
    open func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool { true }
    open func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {}
    open func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool { false }
    open func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {}
    open func sectionIndexTitles(for tableView: UITableView) -> [String]? { nil }
    open func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int { index }

    // MARK: UITableViewDelegate

    open func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { tableView.rowHeight }
    /// The row height to plan with before a row is measured: the table's estimate.
    open func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat { tableView.estimatedRowHeight }
    open func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat { UITableView.automaticDimension }
    open func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat { UITableView.automaticDimension }
    open func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? { nil }
    open func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? { nil }
    open func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? { indexPath }
    open func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {}
    open func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {}
    open func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {}
    open func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {}
    open func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle { .delete }
    open func tableView(_ tableView: UITableView, titleForDeleteConfirmationButtonForRowAt indexPath: IndexPath) -> String? { nil }
    open func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool { true }
    open func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? { nil }
    open func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? { nil }
    open func tableView(_ tableView: UITableView, willBeginEditingRowAt indexPath: IndexPath) {}
    open func tableView(_ tableView: UITableView, didEndEditingRowAt indexPath: IndexPath?) {}

    // MARK: UIScrollViewDelegate

    open func scrollViewDidScroll(_ scrollView: UIScrollView) {}
    open func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {}
    open func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {}
    open func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {}
    open func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {}
    open func viewForZooming(in scrollView: UIScrollView) -> UIView? { nil }
    open func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {}
    open func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {}
    open func scrollViewDidZoom(_ scrollView: UIScrollView) {}
    open func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool { true }
    open func scrollViewDidScrollToTop(_ scrollView: UIScrollView) {}
}
