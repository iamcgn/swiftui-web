// `position` and the safe-area nodes (API/Position.swift).

/// `position`: the modified view takes the proposed size (the child's where nothing is
/// proposed) and centres the child at the point.
@MainActor
package final class PositionNode<Content: View>: UnaryLayoutModifierNode<Content, _PositionLayout> {
    override package var changesChildSize: Bool { true }
    override package var paintsOutsideFrame: Bool { true }

    override package func size(forChild childSize: CGSize, proposal: ProposedViewSize) -> CGSize {
        CGSize(width: proposal.width ?? childSize.width, height: proposal.height ?? childSize.height)
    }

    override package func childOrigin(_ child: ViewDimensions, in size: CGSize) -> CGPoint {
        CGPoint(x: modifier.position.x - child.width / 2, y: modifier.position.y - child.height / 2)
    }
}

/// Shared by `safeAreaInset` and `safeAreaPadding`: `insets` (measured per layout) shrink a plain
/// child's bounds; a child that extends into the safe area keeps the full bounds and reads the
/// insets through `_SafeAreaProvider` (scroll views inset their content).
@MainActor
package class SafeAreaNode<Content: View, Modifier: ViewModifier>: UnaryLayoutModifierNode<Content, Modifier>, _SafeAreaProvider {
    override package var changesChildSize: Bool { true }
    /// Nested safe-area modifiers keep an extending child (a scroll view) extending; the
    /// insets accumulate through `safeAreaInsets(for:)`.
    override package var extendsIntoSafeArea: Bool { targets.count == 1 && targets[0].extendsIntoSafeArea }

    /// The insets this node adds, for the given proposal (an inset view is measured against it).
    package func insets(for proposal: ProposedViewSize) -> EdgeInsets { EdgeInsets() }

    package func safeAreaInsets(for child: ViewNode) -> EdgeInsets {
        // Insets accumulate through nested safe-area modifiers.
        let inherited = inheritedSafeAreaInsets
        let own = insets(for: ProposedViewSize(frame.size))
        return EdgeInsets(top: inherited.top + own.top, leading: inherited.leading + own.leading,
                          bottom: inherited.bottom + own.bottom, trailing: inherited.trailing + own.trailing)
    }

    private func extends(_ target: ViewNode) -> Bool { target.extendsIntoSafeArea }

    override package func measure(_ target: ViewNode, proposal: ProposedViewSize) -> CGSize {
        let insets = insets(for: proposal)
        if extends(target) { return target.sizeThatFits(proposal) }
        let reduced = Self.reduce(proposal, by: insets)
        let size = target.sizeThatFits(reduced)
        return CGSize(width: size.width + insets.leading + insets.trailing, height: size.height + insets.top + insets.bottom)
    }

    override package func dimensions(of target: ViewNode, in proposal: ProposedViewSize) -> ViewDimensions {
        let insets = insets(for: proposal)
        if extends(target) { return target.dimensions(in: proposal) }
        let dims = target.dimensions(in: Self.reduce(proposal, by: insets))
        let size = CGSize(width: dims.width + insets.leading + insets.trailing, height: dims.height + insets.top + insets.bottom)
        return dims.offset(by: CGPoint(x: insets.leading, y: insets.top), size: size)
    }

    override package func placeTarget(_ target: ViewNode, in bounds: CGRect, proposal: ProposedViewSize, by placer: ViewNode) {
        let insets = insets(for: proposal)
        if extends(target) {
            target.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size), by: placer)
        } else {
            let inner = CGRect(x: bounds.minX + insets.leading, y: bounds.minY + insets.top,
                               width: max(0, bounds.width - insets.leading - insets.trailing), height: max(0, bounds.height - insets.top - insets.bottom))
            target.place(at: inner.origin, anchor: .topLeading, proposal: ProposedViewSize(inner.size), by: placer)
        }
        placeInset(in: bounds, by: placer)
    }

    /// Places the inset view (if any) along its edge.
    package func placeInset(in bounds: CGRect, by placer: ViewNode) {}

    package static func reduce(_ proposal: ProposedViewSize, by insets: EdgeInsets) -> ProposedViewSize {
        ProposedViewSize(width: proposal.width.map { max(0, $0 - insets.leading - insets.trailing) },
                         height: proposal.height.map { max(0, $0 - insets.top - insets.bottom) })
    }
}

/// `safeAreaInset`: the inset view sits at its edge over the safe area it creates (its length
/// plus the spacing, default 8).
@MainActor
package final class SafeAreaInsetNode<Content: View, Inset: View>: SafeAreaNode<Content, _SafeAreaInsetModifier<Inset>> {
    private var inset: TypedNode<Inset>!

    override package init(_ context: _NodeContext<ModifiedContent<Content, _SafeAreaInsetModifier<Inset>>>) {
        super.init(context)
        inset = Inset._makeNode(_NodeContext(view: context.view.modifier.inset, parent: self, environment: environment))
    }

    override package func update(view: ModifiedContent<Content, _SafeAreaInsetModifier<Inset>>, environment: EnvironmentValues, force: Bool) {
        super.update(view: view, environment: environment, force: force)
        inset.update(view: view.modifier.inset, environment: environment, force: force)
    }

    override package func unmount() {
        inset.unmount()
        super.unmount()
    }

    private var spacing: CGFloat { modifier.spacing ?? 8 }
    private var isVertical: Bool { modifier.edge == .top || modifier.edge == .bottom }

    /// The inset view's proposal: the cross length, nothing along the edge's axis.
    private func insetProposal(_ proposal: ProposedViewSize) -> ProposedViewSize {
        isVertical ? ProposedViewSize(width: proposal.width, height: nil) : ProposedViewSize(width: nil, height: proposal.height)
    }

    private func insetLength(for proposal: ProposedViewSize) -> CGFloat {
        let sizes = inset.layoutChildren.map { $0.sizeThatFits(insetProposal(proposal)) }
        return sizes.map { isVertical ? $0.height : $0.width }.max() ?? 0
    }

    override package func insets(for proposal: ProposedViewSize) -> EdgeInsets {
        let length = insetLength(for: proposal) + spacing
        switch modifier.edge {
        case .top: return EdgeInsets(top: length, leading: 0, bottom: 0, trailing: 0)
        case .bottom: return EdgeInsets(top: 0, leading: 0, bottom: length, trailing: 0)
        case .leading: return EdgeInsets(top: 0, leading: length, bottom: 0, trailing: 0)
        case .trailing: return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: length)
        }
    }

    override package func placeInset(in bounds: CGRect, by placer: ViewNode) {
        let proposal = insetProposal(ProposedViewSize(bounds.size))
        for node in inset.layoutChildren {
            let dims = node.dimensions(in: proposal)
            var origin: CGPoint
            switch modifier.edge {
            case .top: origin = CGPoint(x: 0, y: 0)
            case .bottom: origin = CGPoint(x: 0, y: bounds.height - dims.height)
            case .leading: origin = CGPoint(x: 0, y: 0)
            case .trailing: origin = CGPoint(x: bounds.width - dims.width, y: 0)
            }
            // Aligned across the edge within the bounds.
            let container = ViewDimensions(size: bounds.size)
            if isVertical {
                origin.x = container[modifier.alignment.horizontal] - dims[modifier.alignment.horizontal]
            } else {
                origin.y = container[modifier.alignment.vertical] - dims[modifier.alignment.vertical]
            }
            node.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), anchor: .topLeading, proposal: proposal, by: placer)
        }
    }

    override package var structuralChildren: [ViewNode] { [child, inset] }
    /// The inset view paints (and is hit tested) over the content.
    override package var paintedChildren: [ViewNode] { super.paintedChildren + inset.layoutChildren }

    override package var nodeDescription: String { "SafeAreaInset" }
}

/// `safeAreaPadding`: fixed insets, no view.
@MainActor
package final class SafeAreaPaddingNode<Content: View>: SafeAreaNode<Content, _SafeAreaPaddingModifier> {
    override package func insets(for proposal: ProposedViewSize) -> EdgeInsets { modifier.resolvedInsets }
    override package var nodeDescription: String { "SafeAreaPadding" }
}

/// `ignoresSafeArea`: keeps the full bounds under a safe-area modifier and gives its child no
/// safe area on the ignored edges.
@MainActor
package final class IgnoresSafeAreaNode<Content: View>: UnaryLayoutModifierNode<Content, _IgnoresSafeAreaModifier>, _SafeAreaProvider {
    override package var extendsIntoSafeArea: Bool { true }
    override package var forwardsSafeArea: Bool { false }

    package func safeAreaInsets(for child: ViewNode) -> EdgeInsets {
        var insets = inheritedSafeAreaInsets
        let edges = modifier.edges
        if edges.contains(.top) { insets.top = 0 }
        if edges.contains(.bottom) { insets.bottom = 0 }
        if edges.contains(.leading) { insets.leading = 0 }
        if edges.contains(.trailing) { insets.trailing = 0 }
        return insets
    }
}
