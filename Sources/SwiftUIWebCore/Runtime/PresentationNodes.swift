// The presentation layer: sheets, popovers, alerts and menus are nodes owned by the runtime,
// laid out over the window after the main tree, painted last and hit-tested first
// (Docs/elements/Presentation.md).

/// A presented panel and its content, positioned relative to the window (and an anchor node for
/// popovers and menus).
@MainActor
package final class PresentationNode: ViewNode {
    package let kind: _PresentationKind
    package private(set) var content: TypedNode<AnyView>!
    package weak var anchor: ViewNode?
    /// Resets the presenting binding; runs `onDismiss`.
    package let onDismissRequested: @MainActor () -> Void
    package private(set) var panel: CGRect = .zero
    package private(set) var contentFrame: CGRect = .zero
    private var arrow: (edge: Edge, tip: CGPoint)?

    package init(runtime: Runtime, kind: _PresentationKind, view: AnyView, environment: EnvironmentValues, anchor: ViewNode?,
                 onDismissRequested: @escaping @MainActor () -> Void) {
        self.kind = kind
        self.anchor = anchor
        self.onDismissRequested = onDismissRequested
        super.init(parent: runtime.root, runtime: runtime, environment: environment)
        var contentEnvironment = environment
        contentEnvironment.dismiss = DismissAction { [weak self] in self?.dismiss() }
        content = AnyView._makeNode(_NodeContext(view: view, parent: self, environment: contentEnvironment))
    }

    package var isModal: Bool {
        switch kind {
        case .sheet, .alert: return true
        case .popover, .menu: return false
        }
    }

    /// Removes the presentation and resets its binding.
    package func dismiss() {
        runtime.remove(presentation: self)
        onDismissRequested()
    }

    package func update(view: AnyView) {
        content.update(view: view, environment: content.environment, force: false)
    }

    private var target: ViewNode? { content.layoutChildren.first }

    // MARK: Layout

    package func layout(in window: CGSize) {
        guard let target else { return }
        let padding = kind == .menu ? 0 : PlatformMetrics.presentationPadding
        switch kind {
        case .sheet:
            let limit = ProposedViewSize(width: window.width - 2 * PlatformMetrics.sheetMargin - 2 * padding, height: nil)
            let size = target.sizeThatFits(limit)
            panel = CGRect(x: (window.width - size.width) / 2 - padding, y: 0, width: size.width + 2 * padding, height: size.height + 2 * padding)
            arrow = nil
        case .alert:
            let size = target.sizeThatFits(ProposedViewSize(width: nil, height: nil))
            panel = CGRect(x: (window.width - size.width) / 2, y: (window.height - size.height) / 2, width: size.width, height: size.height)
            arrow = nil
        case .popover(let edge):
            let size = target.sizeThatFits(ProposedViewSize(width: nil, height: nil))
            let width = size.width + 2 * padding, height = size.height + 2 * padding
            let source = anchor?.frameInRoot ?? CGRect(x: window.width / 2, y: window.height / 2, width: 0, height: 0)
            let gap = PlatformMetrics.popoverArrowHeight
            var origin: CGPoint
            switch edge {
            case .top: origin = CGPoint(x: source.midX - width / 2, y: source.maxY + gap)
            case .bottom: origin = CGPoint(x: source.midX - width / 2, y: source.minY - gap - height)
            case .leading: origin = CGPoint(x: source.maxX + gap, y: source.midY - height / 2)
            case .trailing: origin = CGPoint(x: source.minX - gap - width, y: source.midY - height / 2)
            }
            origin.x = min(max(origin.x, PlatformMetrics.sheetMargin), max(PlatformMetrics.sheetMargin, window.width - width - PlatformMetrics.sheetMargin)).rounded()
            origin.y = min(max(origin.y, PlatformMetrics.sheetMargin), max(PlatformMetrics.sheetMargin, window.height - height - PlatformMetrics.sheetMargin)).rounded()
            panel = CGRect(origin: origin, size: CGSize(width: width, height: height))
            let tip: CGPoint
            switch edge {
            case .top: tip = CGPoint(x: source.midX, y: source.maxY)
            case .bottom: tip = CGPoint(x: source.midX, y: source.minY)
            case .leading: tip = CGPoint(x: source.maxX, y: source.midY)
            case .trailing: tip = CGPoint(x: source.minX, y: source.midY)
            }
            arrow = (edge, tip)
        case .menu:
            let size = target.sizeThatFits(ProposedViewSize(width: nil, height: nil))
            let source = anchor?.frameInRoot ?? .zero
            var origin = CGPoint(x: source.minX, y: source.maxY + PlatformMetrics.menuGap)
            origin.x = min(max(origin.x, 0), max(0, window.width - size.width))
            if origin.y + size.height > window.height { origin.y = max(0, source.minY - PlatformMetrics.menuGap - size.height) }
            panel = CGRect(origin: origin, size: size)
            arrow = nil
        }
        contentFrame = panel.insetBy(dx: padding, dy: padding)
        target.place(at: contentFrame.origin, anchor: .topLeading, proposal: ProposedViewSize(contentFrame.size), by: runtime.root)
    }

    // MARK: Painting

    package func paintPresentation(into list: inout DisplayList, context: PaintContext) {
        let black = { (alpha: Double) in RGBA(red: 0, green: 0, blue: 0, alpha: alpha) }
        if isModal {
            list.append(.fillRect(context.absoluteRect(CGRect(origin: .zero, size: runtime.layoutSize)), black(PlatformMetrics.presentationDimAlpha)))
        }
        let rect = context.absoluteRect(panel)
        let radius = kind == .menu ? PlatformMetrics.menuCornerRadius : PlatformMetrics.presentationCornerRadius
        // A soft shadow ring, then the panel and its border.
        list.append(.fillRRect(rect.insetBy(dx: -2, dy: -2), cornerRadius: radius + 2, black(PlatformMetrics.presentationShadowAlpha)))
        list.append(.fillRRect(rect, cornerRadius: radius, RGBA(red: 1, green: 1, blue: 1, alpha: 1)))
        list.append(.strokePath(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: radius),
                                style: StrokeStyle(lineWidth: 1), black(PlatformMetrics.presentationBorderAlpha)))
        if let arrow {
            let h = PlatformMetrics.popoverArrowHeight, w = PlatformMetrics.popoverArrowWidth / 2
            let tip = CGPoint(x: context.origin.x + arrow.tip.x, y: context.origin.y + arrow.tip.y)
            var path = Path()
            path.move(to: tip)
            switch arrow.edge {
            case .top: path.addLine(to: CGPoint(x: tip.x - w, y: tip.y + h)); path.addLine(to: CGPoint(x: tip.x + w, y: tip.y + h))
            case .bottom: path.addLine(to: CGPoint(x: tip.x - w, y: tip.y - h)); path.addLine(to: CGPoint(x: tip.x + w, y: tip.y - h))
            case .leading: path.addLine(to: CGPoint(x: tip.x + h, y: tip.y - w)); path.addLine(to: CGPoint(x: tip.x + h, y: tip.y + w))
            case .trailing: path.addLine(to: CGPoint(x: tip.x - h, y: tip.y - w)); path.addLine(to: CGPoint(x: tip.x - h, y: tip.y + w))
            }
            path.closeSubpath()
            list.append(.fillPath(path, RGBA(red: 1, green: 1, blue: 1, alpha: 1)))
        }
        if let target { target.paint(into: &list, context: context.child(at: target.presentedFrame)) }
    }

    // MARK: Hit testing

    /// The interactive node under `point` (window coordinates), if inside the panel.
    package func interactiveNode(at point: CGPoint) -> (ViewNode & _Interactive)? {
        guard panel.contains(point), let target else { return nil }
        let local = CGPoint(x: point.x - target.frame.minX, y: point.y - target.frame.minY)
        guard target.contains(local) else { return nil }
        return target.hitTest(local, where: { $0 is _Interactive }) as? (ViewNode & _Interactive)
    }

    package var interactiveNodes: [ViewNode & _Interactive] {
        (target?.collectNodes(where: { $0 is _Interactive }) ?? []).compactMap { $0 as? (ViewNode & _Interactive) }
    }

    override package var structuralChildren: [ViewNode] { [content] }
    override package var layoutChildren: [ViewNode] { [] }
    override package var nodeDescription: String { "Presentation(\(kind))" }

    override package func unmount() {
        content.unmount()
        super.unmount()
    }
}

extension Runtime {
    /// Presents `view` in a panel of `kind` over the window.
    @discardableResult
    package func present(kind: _PresentationKind, view: AnyView, environment: EnvironmentValues, anchor: ViewNode?,
                         onDismissRequested: @escaping @MainActor () -> Void) -> PresentationNode {
        let node = PresentationNode(runtime: self, kind: kind, view: view, environment: environment, anchor: anchor, onDismissRequested: onDismissRequested)
        presentations.append(node)
        requestLayout()
        return node
    }

    package func remove(presentation node: PresentationNode) {
        guard let index = presentations.firstIndex(where: { $0 === node }) else { return }
        presentations.remove(at: index)
        node.unmount()
        requestLayout()
    }

    /// Dismisses the topmost presentation, if any (hosts call this for Escape). Returns whether one was.
    @discardableResult
    public func dismissTopmostPresentation() -> Bool {
        guard let top = presentations.last else { return false }
        top.dismiss()
        return true
    }

    /// Whether anything is presented over the window.
    public var hasPresentations: Bool { !presentations.isEmpty }

    package func layoutPresentations(in size: CGSize) {
        for presentation in presentations { presentation.layout(in: size) }
    }

    package func paintPresentations(into list: inout DisplayList, context: PaintContext) {
        for presentation in presentations { presentation.paintPresentation(into: &list, context: context) }
    }

    /// The interactive node a press at `point` reaches through the presentations: a hit in the
    /// topmost panel, nothing under a modal panel, and a press outside a popover or menu
    /// dismisses it (and is consumed). Returns `nil` with `handled` when the main tree must not
    /// be searched.
    package func presentationHit(at point: CGPoint) -> (node: (ViewNode & _Interactive)?, handled: Bool) {
        for presentation in presentations.reversed() {
            if let hit = presentation.interactiveNode(at: point) { return (hit, true) }
            if presentation.panel.contains(point) { return (nil, true) }
            if presentation.isModal { return (nil, true) }
            presentation.dismiss()
            return (nil, true)
        }
        return (nil, false)
    }
}

/// Presents while its `presented` flag is true; dismisses when it turns false or the node leaves.
@MainActor
package final class PresentationSyncNode<Content: View>: UnaryLayoutModifierNode<Content, _PresentationSync> {
    private var presented: PresentationNode?

    override package init(_ context: _NodeContext<ModifiedContent<Content, _PresentationSync>>) {
        super.init(context)
        sync()
    }

    override package func update(view: ModifiedContent<Content, _PresentationSync>, environment: EnvironmentValues, force: Bool) {
        super.update(view: view, environment: environment, force: force)
        sync()
    }

    private func sync() {
        if modifier.presented {
            if let presented, presented.isMounted {
                presented.update(view: modifier.content.make())
            } else {
                let binding = modifier.binding, onDismiss = modifier.onDismiss
                presented = runtime.present(kind: modifier.kind, view: modifier.content.make(), environment: environment, anchor: self) {
                    binding.wrappedValue = false
                    onDismiss?.run()
                }
            }
        } else if let presented {
            self.presented = nil
            if presented.isMounted { runtime.remove(presentation: presented) }
            modifier.onDismiss?.run()
        }
    }

    override package func unmount() {
        if let presented, presented.isMounted { runtime.remove(presentation: presented) }
        presented = nil
        super.unmount()
    }
}
