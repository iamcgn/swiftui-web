// Menu nodes (Docs/elements/Menu.md): the pull-down button (`MenuButtonNode`), a submenu row
// inside a presented menu (`SubmenuRowNode`), context menus (`ContextMenuNode`) and the runtime's
// secondary-click entry point. Menus themselves are presentations (`PresentationNode`).

@MainActor
private var nextMenuIdentifier = 6_000_000

/// The pull-down button: an `NSPopUpButton`-style box around the label with a single chevron;
/// a press presents the content as a menu under the button. With a primary action the button
/// is split: the label part runs the action, the indicator part opens the menu.
@MainActor
package final class MenuButtonNode: LayoutNode<_MenuHost>, _Interactive {
    private var label: TypedNode<AnyView>!
    private let identifier: Int
    private var labelFrame: CGRect = .zero
    /// The split button's divider (x in the node's space), when there is a primary action.
    private var dividerX: CGFloat?

    package init(_ context: _NodeContext<_MenuHost>) {
        nextMenuIdentifier += 1
        identifier = nextMenuIdentifier
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        label = AnyView._makeNode(_NodeContext(view: context.view.label, parent: self, environment: labelEnvironment()))
    }

    private var enabled: Bool { environment.isEnabled }

    private func labelEnvironment() -> EnvironmentValues {
        var environment = environment
        environment.font = .system(size: PlatformMetrics.buttonLabelSize)
        if !enabled { environment.foregroundColor = Color.black.opacity(PlatformMetrics.popUpDisabledTextAlpha) }
        return environment
    }

    override package func update(view: _MenuHost, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        label.update(view: view.label, environment: labelEnvironment(), force: force)
    }

    private var target: ViewNode? { label.layoutChildren.first }

    // MARK: Layout

    private struct Plan {
        var size: CGSize
        var label: CGRect
        var dividerX: CGFloat?
    }

    private func plan() -> Plan {
        let labelSize = target?.sizeThatFits(.unspecified) ?? .zero
        let trailing: CGFloat
        var dividerX: CGFloat?
        if view.primaryAction != nil {
            dividerX = PlatformMetrics.popUpTextInset + labelSize.width + PlatformMetrics.menuSplitGap
            trailing = PlatformMetrics.menuSplitGap + PlatformMetrics.menuSplitDividerWidth + PlatformMetrics.menuSplitTrailing
        } else if view.indicator {
            trailing = PlatformMetrics.popUpChevronGap + PlatformMetrics.popUpChevronWidth + PlatformMetrics.popUpChevronTrailing
        } else {
            trailing = PlatformMetrics.popUpTextInset
        }
        let width = PlatformMetrics.popUpTextInset + labelSize.width + trailing
        let height = max(PlatformMetrics.popUpHeight, labelSize.height)
        return Plan(size: CGSize(width: width, height: height),
                    label: CGRect(x: PlatformMetrics.popUpTextInset, y: (height - labelSize.height) / 2, width: labelSize.width, height: labelSize.height),
                    dividerX: dividerX)
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize { plan().size }

    override package func layoutContents(proposal: ProposedViewSize) {
        let plan = plan()
        labelFrame = plan.label
        dividerX = plan.dividerX
        target?.place(at: plan.label.origin, anchor: .topLeading, proposal: ProposedViewSize(plan.label.size), by: self)
    }

    override package var layoutSpacing: ViewSpacing { .textLikeControl }
    override package var paintedChildren: [ViewNode] { target.map { [$0] } ?? [] }
    override package var structuralChildren: [ViewNode] { [label] }
    override package var nodeDescription: String { "Menu" }

    override package func unmount() {
        label.unmount()
        super.unmount()
    }

    // MARK: Painting

    private func black(_ alpha: Double) -> RGBA { environment._ink(alpha) }

    override package func paint(into list: inout DisplayList, context: PaintContext) {
        let bounds = absoluteBounds(context)
        if view.bordered {
            list.append(.fillRRect(bounds, cornerRadius: PlatformMetrics.popUpCornerRadius,
                                   black(enabled ? PlatformMetrics.popUpFill : PlatformMetrics.popUpDisabledFill)))
        }
        if let target { target.paint(into: &list, context: context.child(at: target.presentedFrame)) }
        let chevronAlpha = enabled ? PlatformMetrics.radioDotAlpha : PlatformMetrics.popUpDisabledTextAlpha
        if let dividerX {
            let x = context.round(bounds.minX + dividerX)
            list.append(.fillRect(CGRect(x: x, y: bounds.minY + PlatformMetrics.menuSplitDividerInset, width: PlatformMetrics.menuSplitDividerWidth,
                                         height: bounds.height - 2 * PlatformMetrics.menuSplitDividerInset), black(PlatformMetrics.menuSplitDividerAlpha)))
            appendChevron(into: &list, centerX: bounds.maxX - PlatformMetrics.menuSplitChevronTrailing, midY: bounds.midY,
                          stroke: PlatformMetrics.menuSplitChevronStroke, alpha: chevronAlpha)
        } else if view.indicator {
            appendChevron(into: &list, centerX: bounds.maxX - PlatformMetrics.pullDownChevronTrailing, midY: bounds.midY,
                          stroke: PlatformMetrics.popUpChevronStroke, alpha: chevronAlpha)
        }
    }

    /// A single downward chevron centred at `centerX`, `midY`.
    private func appendChevron(into list: inout DisplayList, centerX: CGFloat, midY: CGFloat, stroke: CGFloat, alpha: Double) {
        let halfWidth = PlatformMetrics.popUpChevronWidth / 2, rise = PlatformMetrics.pullDownChevronHalfHeight
        var chevron = Path()
        chevron.move(to: CGPoint(x: centerX - halfWidth, y: midY - rise))
        chevron.addLine(to: CGPoint(x: centerX, y: midY + rise))
        chevron.addLine(to: CGPoint(x: centerX + halfWidth, y: midY - rise))
        list.append(.strokePath(chevron, style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round), black(alpha)))
    }

    // MARK: Interaction

    package func pressBegan() {}
    package func pressEnded(inside: Bool) { pressEnded(inside: inside, at: CGPoint(x: frame.width, y: 0)) }

    package func pressEnded(inside: Bool, at point: CGPoint) {
        guard inside, enabled else { return }
        if let dividerX, let action = view.primaryAction, point.x < dividerX {
            action.run()
            runtime.setNeedsDisplay()
            return
        }
        presentMenu()
    }

    package func presentMenu() {
        runtime.present(kind: .menu, view: AnyView(_MenuContent(content: view.content)), environment: environment, anchor: self) {}
    }

    package var semantics: SemanticsNode {
        let text = label.descendants(where: { $0 is TextNode }).compactMap { ($0 as? TextNode)?.view.resolvedString }.joined(separator: " ")
        return SemanticsNode(role: .popUpButton, label: text, frame: frameInRoot, identifier: identifier)
    }
}

/// A row inside a presented menu that opens its content as a submenu beside the row.
@MainActor
package final class SubmenuRowNode: LayoutNode<_SubmenuHost>, _Interactive {
    private var child: TypedNode<AnyView>!
    private let identifier: Int

    package init(_ context: _NodeContext<_SubmenuHost>) {
        nextMenuIdentifier += 1
        identifier = nextMenuIdentifier
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        child = AnyView._makeNode(_NodeContext(view: Self.row(for: context.view), parent: self, environment: context.environment))
    }

    private static func row(for view: _SubmenuHost) -> AnyView {
        AnyView(_MenuRowLabel(label: view.label, submenu: true))
    }

    override package func update(view: _SubmenuHost, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        child.update(view: Self.row(for: view), environment: environment, force: force)
    }

    private var target: ViewNode? { child.layoutChildren.first }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize { target?.sizeThatFits(proposal) ?? .zero }
    override package func dimensions(in proposal: ProposedViewSize) -> ViewDimensions { target?.dimensions(in: proposal) ?? ViewDimensions(size: .zero) }
    override package func layoutContents(proposal: ProposedViewSize) {
        target?.place(at: .zero, anchor: .topLeading, proposal: proposal, by: self)
    }
    override package var paintedChildren: [ViewNode] { target.map { [$0] } ?? [] }
    override package var structuralChildren: [ViewNode] { [child] }
    override package var nodeDescription: String { "Submenu" }

    override package func unmount() {
        child.unmount()
        super.unmount()
    }

    package func pressBegan() {}
    package func pressEnded(inside: Bool) {
        guard inside, environment.isEnabled else { return }
        runtime.present(kind: .submenu, view: AnyView(_MenuContent(content: view.content)), environment: environment, anchor: self) {}
    }

    package var semantics: SemanticsNode {
        let text = child.descendants(where: { $0 is TextNode }).compactMap { ($0 as? TextNode)?.view.resolvedString }.joined(separator: " ")
        return SemanticsNode(role: .popUpButton, label: text, frame: frameInRoot, identifier: identifier)
    }
}

/// A node that presents a menu on a secondary click inside it.
@MainActor
package protocol _ContextMenuProviding: AnyObject {
    func presentContextMenu(at point: CGPoint)
}

@MainActor
package final class ContextMenuNode<Content: View>: UnaryLayoutModifierNode<Content, _ContextMenuModifier>, _ContextMenuProviding {
    package func presentContextMenu(at point: CGPoint) {
        runtime.present(kind: .menu, view: AnyView(_MenuContent(content: modifier.content)), environment: environment, anchor: nil, at: point) {}
    }
}

extension Runtime {
    /// A secondary (right) click at `point` (window coordinates): presents the context menu of
    /// the deepest view under it that has one. Over a presentation it behaves as a primary press
    /// (a click outside a menu dismisses it).
    public func secondaryPointerDown(at point: CGPoint) {
        if hasPresentations {
            let presented = presentationHit(at: point)
            if presented.handled { return }
        }
        for node in root.layoutChildren.reversed() {
            let shift = node.hitTestOffset
            let local = CGPoint(x: point.x - node.frame.minX - shift.x, y: point.y - node.frame.minY - shift.y)
            if node.clipsHitTesting, !node.contains(local) { continue }
            if let hit = node.hitTest(local, where: { $0 is _ContextMenuProviding }) as? _ContextMenuProviding {
                hit.presentContextMenu(at: point)
                return
            }
        }
    }

    /// Dismisses every presented menu and submenu (a menu item ran).
    package func dismissMenus() {
        for presentation in presentations.reversed() where presentation.kind.isMenu { presentation.dismiss() }
    }
}
