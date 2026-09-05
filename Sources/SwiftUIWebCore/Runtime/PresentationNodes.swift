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
    /// Where a menu without an anchor node opens (context menus: the pointer).
    package let anchorPoint: CGPoint?
    /// Resets the presenting binding; runs `onDismiss`.
    package let onDismissRequested: @MainActor () -> Void
    package private(set) var panel: CGRect = .zero
    package private(set) var contentFrame: CGRect = .zero
    /// The menu row the arrow keys highlighted (an index into `interactiveNodes`).
    package private(set) var highlightedIndex: Int?
    private var arrow: (edge: Edge, tip: CGPoint)?

    package init(runtime: Runtime, kind: _PresentationKind, view: AnyView, environment: EnvironmentValues, anchor: ViewNode?,
                 anchorPoint: CGPoint? = nil, onDismissRequested: @escaping @MainActor () -> Void) {
        self.kind = kind
        self.anchor = anchor
        self.anchorPoint = anchorPoint
        self.onDismissRequested = onDismissRequested
        super.init(parent: runtime.root, runtime: runtime, environment: environment)
        var contentEnvironment = environment
        contentEnvironment.dismiss = DismissAction { [weak self] in self?.dismiss() }
        content = AnyView._makeNode(_NodeContext(view: view, parent: self, environment: contentEnvironment))
    }

    package var isModal: Bool {
        switch kind {
        case .sheet, .alert: return true
        case .popover, .menu, .submenu, .window: return false
        }
    }

    /// Secondary windows: the title bar above the content and the close button in it.
    package static let windowTitleBarHeight: CGFloat = 28
    package static let windowCornerRadius: CGFloat = 10
    package static let windowCascade: CGFloat = 24
    package var closeButtonFrame: CGRect {
        CGRect(x: panel.minX + 13, y: panel.minY + (Self.windowTitleBarHeight - 12) / 2, width: 12, height: 12)
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
        let padding = kind.isMenu ? 0 : PlatformMetrics.presentationPadding
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
            let source = anchor?.frameInRoot ?? anchorPoint.map { CGRect(origin: $0, size: .zero) } ?? .zero
            var origin = CGPoint(x: source.minX, y: source.maxY + PlatformMetrics.menuGap)
            origin.x = min(max(origin.x, 0), max(0, window.width - size.width))
            if origin.y + size.height > window.height { origin.y = max(0, source.minY - PlatformMetrics.menuGap - size.height) }
            panel = CGRect(origin: origin, size: size)
            arrow = nil
        case .window(_, let defaultSize):
            // Content-sized (or the scene's default size), clamped to the window with a margin,
            // centred and cascaded by the number of windows already open.
            let margin = PlatformMetrics.sheetMargin
            let bar = Self.windowTitleBarHeight
            let available = CGSize(width: max(0, window.width - 2 * margin), height: max(0, window.height - 2 * margin - bar))
            var size: CGSize
            if let defaultSize {
                size = CGSize(width: min(defaultSize.width, available.width), height: min(defaultSize.height, available.height))
            } else {
                let natural = target.sizeThatFits(ProposedViewSize(width: nil, height: nil))
                size = CGSize(width: min(natural.width + 2 * padding, available.width), height: min(natural.height + 2 * padding, available.height))
            }
            let index = runtime.presentations.filter { $0.kind.isWindow }.firstIndex { $0 === self } ?? 0
            let cascade = CGFloat(index) * Self.windowCascade
            var origin = CGPoint(x: ((window.width - size.width) / 2 + cascade).rounded(), y: ((window.height - size.height - bar) / 2 + cascade).rounded())
            origin.x = min(max(margin, origin.x), max(margin, window.width - size.width - margin))
            origin.y = min(max(margin, origin.y), max(margin, window.height - size.height - bar - margin))
            panel = CGRect(x: origin.x, y: origin.y, width: size.width, height: size.height + bar)
            arrow = nil
            contentFrame = CGRect(x: panel.minX + padding, y: panel.minY + bar + padding, width: size.width - 2 * padding, height: size.height - 2 * padding)
            target.place(at: contentFrame.origin, anchor: .topLeading, proposal: ProposedViewSize(contentFrame.size), by: runtime.root)
            return
        case .submenu:
            // Beside the parent row, its first item level with the row; flipped to the left
            // when it would overflow.
            let size = target.sizeThatFits(ProposedViewSize(width: nil, height: nil))
            let source = anchor?.frameInRoot ?? .zero
            var origin = CGPoint(x: source.maxX, y: source.minY - PlatformMetrics.menuVerticalPadding)
            if origin.x + size.width > window.width { origin.x = max(0, source.minX - size.width) }
            origin.y = min(max(origin.y, 0), max(0, window.height - size.height))
            panel = CGRect(origin: origin, size: size)
            arrow = nil
        }
        contentFrame = panel.insetBy(dx: padding, dy: padding)
        target.place(at: contentFrame.origin, anchor: .topLeading, proposal: ProposedViewSize(contentFrame.size), by: runtime.root)
    }

    // MARK: Painting

    package func paintPresentation(into list: inout DisplayList, context: PaintContext) {
        // The dim is always black; the panel, its shadow and border follow the appearance (unverified in dark).
        let black = { (alpha: Double) in self.environment._ink(alpha) }
        if isModal {
            list.append(.fillRect(context.absoluteRect(CGRect(origin: .zero, size: runtime.layoutSize)), RGBA(red: 0, green: 0, blue: 0, alpha: PlatformMetrics.presentationDimAlpha)))
        }
        let rect = context.absoluteRect(panel)
        let radius = kind.isMenu ? PlatformMetrics.menuCornerRadius : kind.isWindow ? Self.windowCornerRadius : PlatformMetrics.presentationCornerRadius
        // A soft shadow ring, then the panel and its border.
        list.append(.fillRRect(rect.insetBy(dx: -2, dy: -2), cornerRadius: radius + 2, black(PlatformMetrics.presentationShadowAlpha)))
        list.append(.fillRRect(rect, cornerRadius: radius, environment._windowBackground))
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
            list.append(.fillPath(path, environment._windowBackground))
        }
        if case .window(let title, _) = kind {
            // The title bar: a hairline under it, the traffic lights, the title centred.
            let bar = CGRect(x: panel.minX, y: panel.minY, width: panel.width, height: Self.windowTitleBarHeight)
            let separator = context.absoluteRect(CGRect(x: bar.minX, y: bar.maxY - 0.5, width: bar.width, height: 0.5))
            list.append(.fillRect(separator, black(0.1)))
            let lights: [RGBA] = [RGBA(r: 255, g: 95, b: 87), RGBA(r: 254, g: 188, b: 46), RGBA(r: 40, g: 200, b: 64)]
            for (i, color) in lights.enumerated() {
                let dot = CGRect(x: closeButtonFrame.minX + CGFloat(i) * 20, y: closeButtonFrame.minY, width: 12, height: 12)
                list.append(.fillPath(Path(ellipseIn: context.absoluteRect(dot)), color))
            }
            if let title, !title.isEmpty {
                let font = Font.system(size: 13, weight: .semibold).resolve(profile: environment.platformProfile)
                let layout = runtime.layoutText(title, font: font, width: nil)
                let x = bar.midX - layout.size.width / 2
                let y = bar.minY + (Self.windowTitleBarHeight - layout.size.height) / 2 + layout.firstBaseline
                let color = environment._ink(0.85)
                for line in layout.lines {
                    for fragment in line.fragments where !fragment.text.isEmpty {
                        list.append(.drawText(fragment.text, DisplayFont(font), origin: context.absoluteRect(CGRect(x: x + fragment.x, y: y, width: 0, height: 0)).origin, color))
                    }
                }
            }
        }
        if let highlightedIndex, kind.isMenu {
            let rows = interactiveNodes
            if highlightedIndex < rows.count {
                let row = context.absoluteRect(rows[highlightedIndex].frameInRoot).insetBy(dx: PlatformMetrics.menuHighlightInset, dy: 0)
                list.append(.fillRRect(row, cornerRadius: PlatformMetrics.menuHighlightCornerRadius, black(PlatformMetrics.menuHighlightAlpha)))
            }
        }
        if let target { target.paint(into: &list, context: context.child(at: target.presentedFrame)) }
    }

    // MARK: Keyboard

    /// Menus: Up/Down move the highlight over the rows (wrapping), Return or Space activates the
    /// highlighted row, Escape closes the menu.
    package func handleKey(_ press: KeyPress) -> Bool {
        guard kind.isMenu, press.modifiers.shortcutModifiers.isEmpty else { return false }
        let rows = interactiveNodes
        switch press.key {
        case .downArrow:
            guard !rows.isEmpty else { return true }
            highlightedIndex = highlightedIndex.map { ($0 + 1) % rows.count } ?? 0
        case .upArrow:
            guard !rows.isEmpty else { return true }
            highlightedIndex = highlightedIndex.map { ($0 + rows.count - 1) % rows.count } ?? rows.count - 1
        case .return, .space:
            guard let highlightedIndex, highlightedIndex < rows.count else { return false }
            let row = rows[highlightedIndex]
            row.pressBegan()
            row.pressEnded(inside: true)
        case .escape:
            dismiss()
        default:
            return false
        }
        runtime.setNeedsDisplay()
        return true
    }

    // MARK: Hit testing

    /// The interactive node under `point` (window coordinates), if inside the panel.
    package func interactiveNode(at point: CGPoint) -> (ViewNode & _Interactive)? {
        guard panel.contains(point), let target else { return nil }
        if kind.isWindow, closeButtonFrame.insetBy(dx: -4, dy: -4).contains(point) { return closeButton }
        let local = CGPoint(x: point.x - target.frame.minX, y: point.y - target.frame.minY)
        guard target.contains(local) else { return nil }
        return target.hitTest(local, where: { $0 is _Interactive }) as? (ViewNode & _Interactive)
    }

    /// The traffic-light close control of a secondary window.
    private lazy var closeButton: WindowCloseButton = WindowCloseButton(presentation: self)

    package var interactiveNodes: [ViewNode & _Interactive] {
        (target?.collectNodes(where: { $0 is _Interactive }) ?? []).compactMap { $0 as? (ViewNode & _Interactive) }
    }

    override package var structuralChildren: [ViewNode] { [content] }
    override package var layoutChildren: [ViewNode] { [] }
    /// The content's layout nodes, where the semantics walk starts (it follows painted children,
    /// which only layout nodes have).
    package var semanticsRoots: [ViewNode] { content.layoutChildren }
    override package var nodeDescription: String { "Presentation(\(kind))" }

    override package func unmount() {
        content.unmount()
        super.unmount()
    }
}

extension Runtime {
    /// Presents `view` in a panel of `kind` over the window.
    @discardableResult
    package func present(kind: _PresentationKind, view: AnyView, environment: EnvironmentValues, anchor: ViewNode?, at point: CGPoint? = nil,
                         onDismissRequested: @escaping @MainActor () -> Void) -> PresentationNode {
        let node = PresentationNode(runtime: self, kind: kind, view: view, environment: environment, anchor: anchor, anchorPoint: point,
                                    onDismissRequested: onDismissRequested)
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
            if let hit = presentation.interactiveNode(at: point) {
                if presentation.kind.isWindow, presentations.last !== presentation {
                    presentations.removeAll { $0 === presentation }
                    presentations.append(presentation)
                    setNeedsDisplay()
                }
                return (hit, true)
            }
            if presentation.panel.contains(point) { return (nil, true) }
            if presentation.isModal { return (nil, true) }
            // A press beside a window leaves it open and goes on to what is under it.
            if presentation.kind.isWindow { continue }
            presentation.dismiss()
            // A press outside a submenu closes it and goes on to its parent menu.
            if presentation.kind == .submenu { continue }
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

/// The close control in a secondary window's title bar.
@MainActor
package final class WindowCloseButton: ViewNode, _Interactive {
    private weak var owner: PresentationNode?

    package init(presentation: PresentationNode) {
        self.owner = presentation
        super.init(parent: presentation, runtime: presentation.runtime, environment: presentation.environment)
    }

    package func pressBegan() {}
    package func pressEnded(inside: Bool) { if inside { owner?.dismiss() } }
    package var semantics: SemanticsNode {
        SemanticsNode(role: .button, label: "Close", frame: owner?.closeButtonFrame ?? .zero, identifier: ObjectIdentifier(self).hashValue)
    }
    override package var nodeDescription: String { "WindowClose" }
}
