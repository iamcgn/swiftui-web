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
package final class NavigationSplitViewNode: LayoutNode<_NavigationSplitViewHost>, _Interactive, _HoverTracking, _PointerStyled {
    package private(set) var sidebar: TypedNode<AnyView>!
    package private(set) var content: TypedNode<AnyView>?
    /// The detail column: an implicit navigation stack over the detail view.
    package private(set) var detail: NavigationStackNode!
    private let detailPath = _DetailPath()
    private var context: _NavigationContext!

    package private(set) var sidebarFrame: CGRect?
    package private(set) var contentFrame: CGRect?
    package private(set) var detailFrame: CGRect = .zero
    /// Widths the user dragged the dividers to (sw-splitview), clamped to the columns' ranges.
    package private(set) var sidebarWidthOverride: CGFloat?
    package private(set) var contentWidthOverride: CGFloat?
    private enum Divider { case sidebar, content }
    private var drag: (divider: Divider, startX: CGFloat, startWidth: CGFloat)?
    private var hoveredDivider: Divider?

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
        detail.onDepthChanged = { [weak self] before, after in self?.detailPathDidChange(from: before, to: after) }
    }

    /// Compact: a link pushing onto the detail's stack shows the detail; the stack popping back
    /// to its root (one group: the detail view) returns to the sidebar (or content) column.
    private func detailPathDidChange(from before: Int, to after: Int) {
        guard isCompact else { return }
        if after > before, compactColumn != .detail {
            view.compactBinding.set(.detail)
            setCompact(.detail)
            runtime.requestLayout(invalidatingSizes: true)
        } else if after <= 1, before > after, compactColumn == .detail {
            let column: NavigationSplitViewColumn = content != nil && view.compactColumn == .content ? .content : .sidebar
            view.compactBinding.set(column)
            setCompact(column)
            runtime.requestLayout(invalidatingSizes: true)
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

    /// A compact width (an iPhone) shows one column: the preferred compact column, the detail
    /// once a link in a leading column pushes (its stack's back pops back to the column).
    package var isCompact: Bool { environment.horizontalSizeClass == .compact }

    package var compactColumn: NavigationSplitViewColumn {
        let column = view.compactColumn
        if column == .content, content == nil { return .sidebar }
        return column
    }

    package var showsSidebar: Bool {
        if isCompact { return compactColumn == .sidebar }
        switch view.visibility.kind {
        case .automatic, .all: return true
        case .doubleColumn: return content == nil
        case .detailOnly: return false
        }
    }

    package var showsContent: Bool {
        guard content != nil else { return false }
        if isCompact { return compactColumn == .content }
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
        view = _NavigationSplitViewHost(sidebar: view.sidebar, content: view.content, detail: view.detail, visibility: visibility, binding: view.binding,
                                        compactColumn: view.compactColumn, compactBinding: view.compactBinding)
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
        if isCompact {
            // One column fills the width.
            let whole = CGRect(origin: .zero, size: size)
            switch compactColumn {
            case .sidebar: plan.sidebar = whole; plan.detail = CGRect(x: size.width, y: 0, width: 0, height: size.height)
            case .content where content != nil: plan.content = whole; plan.detail = CGRect(x: size.width, y: 0, width: 0, height: size.height)
            default: plan.detail = whole
            }
            return plan
        }
        if showsSidebar {
            let range = Self.columnWidth(of: sidebar) ?? _SplitColumnWidth()
            let width = range.clamped(sidebarWidthOverride ?? range.resolved(default: PlatformMetrics.sidebarDefaultWidth))
            let inset = PlatformMetrics.sidebarInset
            plan.sidebar = CGRect(x: inset, y: inset, width: width, height: max(0, size.height - 2 * inset))
            x = inset + width
        }
        if showsContent, let content {
            let range = Self.columnWidth(of: content) ?? _SplitColumnWidth()
            let width = range.clamped(contentWidthOverride ?? range.resolved(default: PlatformMetrics.splitContentDefaultWidth))
            plan.content = CGRect(x: x, y: 0, width: width, height: size.height)
            x += width
            plan.divider = CGRect(x: x, y: 0, width: PlatformMetrics.dividerThickness, height: size.height)
            x += PlatformMetrics.dividerThickness
        }
        plan.detail = CGRect(x: x, y: 0, width: max(0, size.width - x), height: size.height)
        return plan
    }

    // MARK: Dividers (sw-splitview)

    /// The 8 pt zone on each side of a divider where a drag resizes the column.
    private static let dragZone: CGFloat = 4

    private func divider(at point: CGPoint) -> Divider? {
        guard !isCompact else { return nil }
        if let sidebar = sidebarFrame, abs(point.x - sidebar.maxX) <= Self.dragZone { return .sidebar }
        if let content = contentFrame, abs(point.x - (content.maxX + PlatformMetrics.dividerThickness / 2)) <= Self.dragZone { return .content }
        return nil
    }

    /// Presses in a divider's zone are the split view's; everything else goes to the columns.
    override package func capturesHit(at point: CGPoint) -> Bool { divider(at: point) != nil }

    package var isInteractive: Bool { true }
    package func pressBegan() {}
    private static var nextIdentifier = 9_800_000
    private lazy var identifier: Int = { Self.nextIdentifier += 1; return Self.nextIdentifier }()
    /// A group for the semantics overlay (not focusable: only its dividers take the pointer).
    package var semantics: SemanticsNode { SemanticsNode(role: .group, label: "", frame: frameInRoot, identifier: identifier) }

    package func pressBegan(at point: CGPoint) {
        guard let divider = divider(at: point) else { return }
        switch divider {
        case .sidebar: drag = (.sidebar, point.x, sidebarFrame?.width ?? 0)
        case .content: drag = (.content, point.x, contentFrame?.width ?? 0)
        }
    }

    package func pressMoved(to point: CGPoint) {
        guard let drag else { return }
        let width = drag.startWidth + point.x - drag.startX
        switch drag.divider {
        case .sidebar: sidebarWidthOverride = max(0, width)
        case .content: contentWidthOverride = max(0, width)
        }
        runtime.requestLayout(invalidatingSizes: true)
    }

    package func pressEnded(inside: Bool) {
        guard let drag else { return }
        self.drag = nil
        // A sidebar dragged narrower than half its minimum (half the default without one)
        // collapses, as AppKit's does; its width comes back when it shows again.
        if drag.divider == .sidebar, let width = sidebarWidthOverride {
            let range = Self.columnWidth(of: sidebar) ?? _SplitColumnWidth()
            let minimum = range.min ?? PlatformMetrics.sidebarDefaultWidth
            if width < minimum / 2 {
                sidebarWidthOverride = nil
                view.binding.set(.detailOnly)
                let visibility = view.binding.get()
                view = _NavigationSplitViewHost(sidebar: view.sidebar, content: view.content, detail: view.detail, visibility: visibility, binding: view.binding,
                                                compactColumn: view.compactColumn, compactBinding: view.compactBinding)
            }
        }
        runtime.requestLayout(invalidatingSizes: true)
    }

    package func hoverChanged(inside: Bool, at point: CGPoint) {
        let divider = inside ? divider(at: point) : nil
        if divider != hoveredDivider { hoveredDivider = divider }
    }

    /// The column-resize cursor over a divider.
    package var pointerStyle: PointerStyle? { hoveredDivider != nil || drag != nil ? .columnResize(directions: .all) : nil }

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
        // A compact split keeps the hidden detail out of the layout (its probes stay silent).
        if !isCompact || compactColumn == .detail { placeColumn(detail, in: plan.detail) }
    }

    private func setCompact(_ column: NavigationSplitViewColumn) {
        view = _NavigationSplitViewHost(sidebar: view.sidebar, content: view.content, detail: view.detail, visibility: view.visibility, binding: view.binding,
                                        compactColumn: column, compactBinding: view.compactBinding)
    }

    override package var paintedChildren: [ViewNode] {
        (sidebarFrame != nil ? sidebar.layoutChildren : []) + (contentFrame != nil ? content?.layoutChildren ?? [] : []) + (isCompact && compactColumn != .detail ? [] : [detail])
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
            // The column's fill and, on macOS 27, the half-point line along its trailing edge
            // (inside the area after it: the detail starts at the column's edge).
            list.append(.fillRRect(context.absoluteRect(panel), cornerRadius: PlatformMetrics.sidebarCornerRadius, PlatformMetrics.sidebarPanelColor))
            if PlatformMetrics.sidebarDividerThickness > 0 {
                let line = CGRect(x: panel.maxX, y: panel.minY, width: PlatformMetrics.sidebarDividerThickness, height: panel.height)
                list.append(.fillRect(context.absoluteRect(line), PlatformMetrics.sidebarDividerColor))
            }
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
