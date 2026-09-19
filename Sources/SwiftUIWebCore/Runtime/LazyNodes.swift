// Laziness and pinning (Docs/elements/Lazy.md, "Laziness and pinning"). `LazyContainerNode`
// wraps a lazy stack's or grid's layout, marks the content lazy and pins section headers and
// footers to the enclosing scroll view's edges; `LazyPlaceholderNode` stands in for a `ForEach`
// element that has not scrolled into view yet, sized by the elements that have.

/// A `ForEach` whose elements are created as they scroll into view.
@MainActor
package protocol _LazyMaterializing: AnyObject {
    /// Creates the elements whose placeholders intersect `visible` (content coordinates, the
    /// scroll content's origin at `origin` in root coordinates); true when any was created.
    func materialize(visible: CGRect, contentOrigin origin: CGPoint) -> Bool
    /// Whether `materialize` would create anything.
    func needsMaterialization(visible: CGRect, contentOrigin origin: CGPoint) -> Bool
    /// Creates the element identified by `id` (its `ForEach` identity, or the `id(_:)` at the
    /// top of its content) if a placeholder stands for it; true when it did.
    func materialize(id: AnyHashable) -> Bool
    /// Whether a placeholder stands for the element identified by `id`.
    func hasPlaceholder(id: AnyHashable) -> Bool
}

/// The owner of placeholders: estimates their size from the elements it has created.
@MainActor
package protocol _LazyEstimating: AnyObject {
    func estimatedSize(for proposal: ProposedViewSize) -> CGSize
}

/// The view a placeholder node stands for (never built from a view tree).
public struct _LazyPlaceholder: View {
    public typealias Body = Never
    public static func _makeNode(_ context: _NodeContext<_LazyPlaceholder>) -> TypedNode<_LazyPlaceholder> {
        fatalError("placeholders are made by their ForEach")
    }
}

/// Stands in for an element not yet created: the average size of the created ones along the
/// lazy axis, the proposal across it; paints nothing.
@MainActor
package final class LazyPlaceholderNode: LayoutNode<_LazyPlaceholder> {
    private unowned let owner: any _LazyEstimating

    init(owner: any _LazyEstimating & ViewNode) {
        self.owner = owner
        super.init(view: _LazyPlaceholder(), parent: owner, runtime: owner.runtime, environment: owner.environment)
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        owner.estimatedSize(for: proposal)
    }

    override package var nodeDescription: String { "LazyPlaceholder" }
}

/// The part of a section a layout node belongs to.
package enum _LazySectionRole { case header, footer }

/// Whether `node` is in a section's header or footer, looking up to `container`.
@MainActor
package func _lazySectionRole(of node: ViewNode, in container: ViewNode) -> _LazySectionRole? {
    var current = node
    while let parent = current.parent, parent !== container {
        if let section = parent as? _SectionNodeProviding {
            if section._headerNode === current { return .header }
            if section._footerNode === current { return .footer }
            return nil
        }
        current = parent
    }
    return nil
}

/// Node for `_LazyContainer`: sizes and places its single layout child, then pins the sections'
/// headers and footers within the enclosing scroll view's visible region (`lazy/pinned-*`).
@MainActor
package final class LazyContainerNode<Content: View>: LayoutNode<_LazyContainer<Content>> {
    package private(set) var child: TypedNode<Content>!
    /// Header and footer nodes moved to a pinned position, painted after everything else.
    private var pinnedNodes: [ViewNode] = []

    init(_ context: _NodeContext<_LazyContainer<Content>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        child = Content._makeNode(_NodeContext(view: context.view.content, parent: self, environment: Self.contentEnvironment(context.environment, axis: context.view.axis)))
    }

    override package func update(view: _LazyContainer<Content>, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        child.update(view: view.content, environment: Self.contentEnvironment(environment, axis: view.axis), force: force)
    }

    private static func contentEnvironment(_ environment: EnvironmentValues, axis: Axis) -> EnvironmentValues {
        var environment = environment
        environment._lazyContainerAxis = axis
        return environment
    }

    private var target: ViewNode? { child.layoutChildren.first }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        target?.sizeThatFits(proposal) ?? .zero
    }

    override package func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        target?.dimensions(in: proposal) ?? ViewDimensions(size: .zero)
    }

    override package var layoutPriority: Double { target?.layoutPriority ?? 0 }
    override package var layoutSpacing: ViewSpacing { target?.layoutSpacing ?? ViewSpacing() }
    /// Pinning depends on the scroll offset: a scroll frame lays the content out again.
    override package var readsGeometry: Bool { !view.pinnedViews.isEmpty }

    override package func layoutContents(proposal: ProposedViewSize) {
        guard let target else { return }
        target.place(at: .zero, anchor: .topLeading, proposal: proposal, by: self)
        pin()
    }

    // MARK: Pinning

    private struct SectionNodes {
        var header: [ViewNode]
        var content: [ViewNode]
        var footer: [ViewNode]
        var all: [ViewNode] { header + content + footer }
    }

    /// The sections among the layout container's content, in order (rows are not looked into).
    private func sections() -> [SectionNodes] {
        guard let container = child.descendants(where: { $0 is _ScrollTargetContainer }).first as? _ScrollTargetContainer else { return [] }
        var result: [SectionNodes] = []
        func walk(_ node: ViewNode) {
            if let section = node as? _SectionNodeProviding {
                result.append(SectionNodes(header: section._headerNode.layoutChildren, content: section._contentNode.layoutChildren, footer: section._footerNode.layoutChildren))
            } else if !node.isLayoutNode {
                for child in node.structuralChildren { walk(child) }
            }
        }
        walk(container.targetContent)
        return result
    }

    /// The extent of `nodes` along the lazy axis, in this node's coordinates.
    private func extent(of nodes: [ViewNode]) -> (start: CGFloat, end: CGFloat)? {
        let origin = frameInRoot.origin
        var result: (start: CGFloat, end: CGFloat)?
        for node in nodes {
            let frame = node.frameInRoot
            let start = view.axis == .vertical ? frame.minY - origin.y : frame.minX - origin.x
            let end = start + (view.axis == .vertical ? frame.height : frame.width)
            result = result.map { (min($0.start, start), max($0.end, end)) } ?? (start, end)
        }
        return result
    }

    /// Moves `nodes` along the axis by `delta`, placing them again so their subtrees (and the
    /// probes in them) follow.
    private func shift(_ nodes: [ViewNode], by delta: CGFloat) {
        for node in nodes {
            let origin = CGPoint(x: node.frame.minX + (view.axis == .horizontal ? delta : 0), y: node.frame.minY + (view.axis == .vertical ? delta : 0))
            node.place(at: origin, anchor: .topLeading, proposal: ProposedViewSize(node.frame.size), by: node.layoutParent ?? self)
            node.paintsDeferred = true
        }
        pinnedNodes += nodes
    }

    /// A header whose section has scrolled past the visible start sticks there until the
    /// section ends (its end, or the next header, pushes it off); a footer whose section has
    /// come into view sticks at the visible end until its own place scrolls up to it.
    private func pin() {
        for node in pinnedNodes { node.paintsDeferred = false }
        pinnedNodes = []
        let pinned = view.pinnedViews
        guard !pinned.isEmpty, let scroll = enclosingScroll() else { return }
        let sections = sections()
        guard !sections.isEmpty else { return }
        let origin = frameInRoot.origin
        let scrollFrame = scroll.frameInRoot, insets = scroll.contentInsets
        let visibleStart = view.axis == .vertical ? scrollFrame.minY + insets.top - origin.y : scrollFrame.minX + insets.leading - origin.x
        let visibleEnd = view.axis == .vertical ? scrollFrame.maxY - insets.bottom - origin.y : scrollFrame.maxX - insets.trailing - origin.x
        for (index, section) in sections.enumerated() {
            guard let bounds = extent(of: section.all) else { continue }
            if pinned.contains(.sectionHeaders), let header = extent(of: section.header) {
                let length = header.end - header.start
                var limit = bounds.end - length
                if index + 1 < sections.count, let next = extent(of: sections[index + 1].header) { limit = min(limit, next.start - length) }
                if header.start < visibleStart, bounds.end > visibleStart {
                    let target = min(visibleStart, limit)
                    if target > header.start { shift(section.header, by: target - header.start) }
                }
            }
            if pinned.contains(.sectionFooters), let footer = extent(of: section.footer) {
                let length = footer.end - footer.start
                let floor = extent(of: section.header)?.end ?? bounds.start
                if footer.end > visibleEnd, bounds.start < visibleEnd {
                    let target = max(visibleEnd - length, floor)
                    if target < footer.start { shift(section.footer, by: target - footer.start) }
                }
            }
        }
    }

    private func enclosingScroll() -> (any _ScrollViewport)? {
        var node = parent
        while let current = node {
            if let scroll = current as? any _ScrollViewport { return scroll }
            node = current.parent
        }
        return nil
    }

    // MARK: Painting

    override package var paintedChildren: [ViewNode] { target.map { [$0] } ?? [] }

    override package func paint(into list: inout DisplayList, context: PaintContext) {
        super.paint(into: &list, context: context)
        guard !pinnedNodes.isEmpty else { return }
        let origin = frameInRoot.origin
        for node in pinnedNodes {
            let frame = node.frameInRoot
            node.paint(into: &list, context: context.child(at: CGRect(x: frame.minX - origin.x, y: frame.minY - origin.y, width: frame.width, height: frame.height)))
        }
    }

    override package var structuralChildren: [ViewNode] { [child] }
    override package var nodeDescription: String { "LazyContainer" }
}

/// A scroll view as the lazy nodes see it: its frame and content insets.
@MainActor
package protocol _ScrollViewport: AnyObject {
    var frameInRoot: CGRect { get }
    var contentInsets: EdgeInsets { get }
}

extension ScrollNode: _ScrollViewport {}
