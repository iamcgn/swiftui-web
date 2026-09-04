// NavigationSplitView runtime (Docs/elements/NavigationSplitView.md): the sidebar is a white
// rounded panel inset 8 pt on every side of its column; the next column starts at the panel's
// trailing edge; a content column is a plain full-height column followed by a 1 pt divider;
// the detail takes the rest, its content centred. Links in the leading columns push onto an
// implicit navigation stack in the detail column.

/// `navigationSplitViewColumnWidth`: transparent to layout; the split view reads its width.
@MainActor
package final class SplitColumnWidthNode<Content: View>: UnaryLayoutModifierNode<Content, _NavigationSplitViewColumnWidthModifier> {
    package var columnWidth: _SplitColumnWidth { modifier.width }
}

@MainActor
package final class NavigationSplitViewNode: LayoutNode<_NavigationSplitViewHost> {
    package private(set) var sidebar: TypedNode<AnyView>!
    package private(set) var content: TypedNode<AnyView>?
    /// The detail column: an implicit navigation stack over the detail view.
    package private(set) var detail: NavigationStackNode!
    private let detailPath = _DetailPath()
    private var context: _NavigationContext!

    package private(set) var sidebarFrame: CGRect?
    package private(set) var contentFrame: CGRect?
    package private(set) var detailFrame: CGRect = .zero

    /// The detail stack's own path (links in the leading columns push here).
    @MainActor
    private final class _DetailPath {
        var values: [AnyHashable] = []
    }

    package init(_ context: _NodeContext<_NavigationSplitViewHost>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        let path = detailPath
        let binding = _NavigationPathBinding(get: { path.values }, set: { path.values = $0 })
        detail = NavigationStackNode(_NodeContext(view: _NavigationStackHost(root: context.view.detail, path: binding, values: []),
                                                  parent: self, environment: context.environment))
        self.context = _NavigationContext(stack: detail)
        sidebar = AnyView._makeNode(_NodeContext(view: context.view.sidebar, parent: self, environment: sidebarEnvironment))
        if let view = context.view.content {
            content = AnyView._makeNode(_NodeContext(view: view, parent: self, environment: leadingEnvironment))
        }
    }

    /// Leading columns' links and destination registrations target the detail stack.
    private var leadingEnvironment: EnvironmentValues {
        var environment = environment
        environment._navigationContext = context
        return environment
    }

    private var sidebarEnvironment: EnvironmentValues {
        var environment = leadingEnvironment
        environment._inSidebarColumn = true
        return environment
    }

    override package func update(view: _NavigationSplitViewHost, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        sidebar.update(view: view.sidebar, environment: sidebarEnvironment, force: force)
        switch (view.content, content) {
        case (let view?, let node?): node.update(view: view, environment: leadingEnvironment, force: force)
        case (let view?, nil): content = AnyView._makeNode(_NodeContext(view: view, parent: self, environment: leadingEnvironment))
        case (nil, let node?): node.unmount(); content = nil
        case (nil, nil): break
        }
        detail.update(view: _NavigationStackHost(root: view.detail, path: detail.view.path, values: detailPath.values),
                      environment: environment, force: force)
    }

    // MARK: Visibility

    package var showsSidebar: Bool {
        switch view.visibility.kind {
        case .automatic, .all: return true
        case .doubleColumn: return content == nil
        case .detailOnly: return false
        }
    }

    package var showsContent: Bool {
        guard content != nil else { return false }
        switch view.visibility.kind {
        case .automatic, .all, .doubleColumn: return true
        case .detailOnly: return false
        }
    }

    /// Hides the sidebar when it shows, shows every column otherwise (the sidebar toggle).
    package func toggleSidebar() {
        view.binding.set(showsSidebar ? .detailOnly : .all)
        // Re-read so a binding nobody observes still takes effect.
        let visibility = view.binding.get()
        view = _NavigationSplitViewHost(sidebar: view.sidebar, content: view.content, detail: view.detail, visibility: visibility, binding: view.binding)
        runtime.requestLayout()
    }

    // MARK: Layout

    private static func columnWidth(of node: ViewNode) -> _SplitColumnWidth? {
        node.descendants(where: { $0 is any _SplitColumnWidthProviding }).compactMap { ($0 as? any _SplitColumnWidthProviding)?.columnWidth }.first
    }

    private struct Plan {
        var sidebar: CGRect?
        var content: CGRect?
        var divider: CGRect?
        var detail: CGRect
    }

    private func plan(size: CGSize) -> Plan {
        var x: CGFloat = 0
        var plan = Plan(detail: .zero)
        if showsSidebar {
            let width = (Self.columnWidth(of: sidebar) ?? _SplitColumnWidth()).resolved(default: PlatformMetrics.sidebarDefaultWidth)
            let inset = PlatformMetrics.sidebarInset
            plan.sidebar = CGRect(x: inset, y: inset, width: width, height: max(0, size.height - 2 * inset))
            x = inset + width
        }
        if showsContent, let content {
            let width = (Self.columnWidth(of: content) ?? _SplitColumnWidth()).resolved(default: PlatformMetrics.splitContentDefaultWidth)
            plan.content = CGRect(x: x, y: 0, width: width, height: size.height)
            x += width
            plan.divider = CGRect(x: x, y: 0, width: PlatformMetrics.dividerThickness, height: size.height)
            x += PlatformMetrics.dividerThickness
        }
        plan.detail = CGRect(x: x, y: 0, width: max(0, size.width - x), height: size.height)
        return plan
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        // The split view fills its proposal; unproposed it takes its columns' widths.
        let plan = plan(size: CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0))
        let detailSize = detail.sizeThatFits(.unspecified)
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? plan.detail.minX + detailSize.width
        let height = proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? detailSize.height
        return CGSize(width: width, height: height)
    }

    /// Places a column's content: filling views fill the area, others are centred in it.
    private func placeColumn(_ node: ViewNode, in area: CGRect) {
        let proposal = ProposedViewSize(area.size)
        let size = node.sizeThatFits(proposal)
        node.place(at: CGPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2), anchor: .topLeading, proposal: proposal, by: self)
    }

    override package func layoutContents(proposal: ProposedViewSize) {
        let plan = plan(size: frame.size)
        sidebarFrame = plan.sidebar
        contentFrame = plan.content
        detailFrame = plan.detail
        if let area = plan.sidebar { for node in sidebar.layoutChildren { placeColumn(node, in: area) } }
        if let area = plan.content, let content { for node in content.layoutChildren { placeColumn(node, in: area) } }
        placeColumn(detail, in: plan.detail)
    }

    override package var paintedChildren: [ViewNode] {
        (sidebarFrame != nil ? sidebar.layoutChildren : []) + (contentFrame != nil ? content?.layoutChildren ?? [] : []) + [detail]
    }
    override package var structuralChildren: [ViewNode] { [sidebar, content, detail].compactMap { $0 } }
    override package var nodeDescription: String { "NavigationSplitView" }

    override package func unmount() {
        sidebar.unmount()
        content?.unmount()
        detail.unmount()
        super.unmount()
    }

    // MARK: Painting

    override package func paint(into list: inout DisplayList, context: PaintContext) {
        if let panel = sidebarFrame {
            list.append(.fillRRect(context.absoluteRect(panel), cornerRadius: PlatformMetrics.sidebarCornerRadius, PlatformMetrics.sidebarPanelColor))
            for node in sidebar.layoutChildren { node.paint(into: &list, context: context.child(at: node.presentedFrame)) }
        }
        if contentFrame != nil, let content {
            for node in content.layoutChildren { node.paint(into: &list, context: context.child(at: node.presentedFrame)) }
            if let plan = plan(size: frame.size).divider {
                list.append(.fillRect(context.absoluteRect(plan), RGBA(red: 0, green: 0, blue: 0, alpha: PlatformMetrics.splitDividerAlpha)))
            }
        }
        detail.paint(into: &list, context: context.child(at: detail.presentedFrame))
    }
}

/// A node that sets its column's width (the `navigationSplitViewColumnWidth` modifier node).
@MainActor
package protocol _SplitColumnWidthProviding: AnyObject {
    var columnWidth: _SplitColumnWidth { get }
}

extension SplitColumnWidthNode: _SplitColumnWidthProviding {}

extension Runtime {
    /// Toggles the sidebar of the outermost navigation split view (a host's toolbar button or
    /// the ⌃⌘S shortcut). Returns false when there is none.
    @discardableResult
    public func toggleSidebar() -> Bool {
        guard let split = root.descendants(where: { $0 is NavigationSplitViewNode }).first as? NavigationSplitViewNode else { return false }
        split.toggleSidebar()
        return true
    }
}
