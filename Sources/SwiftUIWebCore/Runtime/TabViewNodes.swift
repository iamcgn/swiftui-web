// TabView nodes (Docs/elements/TabView.md): the tab bar (segments sized by their titles over a
// pill, the selected one filled) centred at the top, a bordered box from 10 pt down, and the
// selected tab's content centred in the area under the bar.

@MainActor
private var nextTabIdentifier = 8_000_000

/// `tabItem`: transparent to layout; keeps its label mounted (unlaid out) for its title.
@MainActor
package final class TabItemNode<Content: View>: UnaryLayoutModifierNode<Content, _TabItemModifier> {
    private var label: TypedNode<AnyView>!

    override package init(_ context: _NodeContext<ModifiedContent<Content, _TabItemModifier>>) {
        super.init(context)
        label = AnyView._makeNode(_NodeContext(view: context.view.modifier.label, parent: self, environment: context.environment))
    }

    override package func update(view: ModifiedContent<Content, _TabItemModifier>, environment: EnvironmentValues, force: Bool) {
        super.update(view: view, environment: environment, force: force)
        label.update(view: view.modifier.label, environment: environment, force: force)
    }

    /// The tab's title: the label's texts.
    package var title: String {
        label.descendants(where: { $0 is TextNode }).compactMap { ($0 as? TextNode)?.view.resolvedString }.joined(separator: " ")
    }

    override package var structuralChildren: [ViewNode] { super.structuralChildren + [label] }

    override package func unmount() {
        label.unmount()
        super.unmount()
    }
}

@MainActor
package final class TabViewNode: LayoutNode<_TabViewPrimitive>, _Interactive, _KeyHandling {
    private var content: TypedNode<AnyView>!
    private var titles: [TypedNode<AnyView>] = []
    private let identifier: Int

    package struct Tab {
        package let node: ViewNode
        package let tag: AnyHashable
        package let title: String
        package var shown: ViewNode?
        package var segment: CGRect = .zero
    }

    package private(set) var tabs: [Tab] = []
    package private(set) var bar: CGRect = .zero
    private var selectedIndex: Int?

    package init(_ context: _NodeContext<_TabViewPrimitive>) {
        nextTabIdentifier += 1
        identifier = nextTabIdentifier
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        content = AnyView._makeNode(_NodeContext(view: context.view.content, parent: self, environment: context.environment))
    }

    override package func update(view: _TabViewPrimitive, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        content.update(view: view.content, environment: environment, force: force)
    }

    private var enabled: Bool { environment.isEnabled }

    /// The tabs: the content's leaves with their tags (the index without one) and the title of
    /// the `tabItem` on the way down to each.
    private func collectTabs() -> [Tab] {
        let entries = _collectOptions(content)
        var result: [Tab] = []
        for (index, entry) in entries.enumerated() {
            let tag: AnyHashable = entry.node.layoutValue(for: TagKey.self) ?? AnyHashable(index)
            let title = entry.node.descendants(where: { $0 is any _TabItemTitled }).compactMap { ($0 as? any _TabItemTitled)?.title }.first
                ?? Self.tabItem(above: entry.node)?.title ?? ""
            result.append(Tab(node: entry.node, tag: tag, title: title))
        }
        while titles.count > result.count { titles.removeLast().unmount() }
        for index in result.indices {
            let selected = view.selection.isSelected(result[index].tag)
            let alpha = selected ? PlatformMetrics.segmentedSelectedTextAlpha : PlatformMetrics.segmentedTextAlpha
            let text = AnyView(Text(result[index].title).font(.system(size: PlatformMetrics.buttonLabelSize))
                .foregroundColor(Color.black.opacity(enabled ? alpha : alpha / 2)))
            if index < titles.count {
                titles[index].update(view: text, environment: environment, force: false)
            } else {
                titles.append(AnyView._makeNode(_NodeContext(view: text, parent: self, environment: environment)))
            }
            result[index].shown = titles[index].layoutChildren.first
        }
        return result
    }

    /// The `tabItem` node between `node` and this tab view, if the modifier wraps the leaf.
    private static func tabItem(above node: ViewNode) -> (any _TabItemTitled)? {
        var current = node.parent
        while let candidate = current, !(candidate is TabViewNode) {
            if let titled = candidate as? any _TabItemTitled { return titled }
            current = candidate.parent
        }
        return nil
    }

    // MARK: Layout

    private func plan(width: CGFloat) -> (tabs: [Tab], bar: CGRect, selected: Int?) {
        var tabs = collectTabs()
        let selected = tabs.firstIndex { view.selection.isSelected($0.tag) } ?? (tabs.isEmpty ? nil : 0)
        var x: CGFloat = 0
        for index in tabs.indices {
            let titleWidth = tabs[index].shown?.sizeThatFits(.unspecified).width ?? 0
            let segmentWidth = titleWidth + 2 * PlatformMetrics.tabSegmentPadding
            tabs[index].segment = CGRect(x: x, y: 0, width: segmentWidth, height: PlatformMetrics.tabBarHeight)
            x += segmentWidth + PlatformMetrics.tabDividerWidth
        }
        // The bar is a whole number of points wide (160 for 49 + 49 + 59.5 + 2 dividers), centred to the half point.
        let barWidth = (max(0, x - PlatformMetrics.tabDividerWidth)).rounded(.up)
        let bar = CGRect(x: ((width - barWidth) / 2 * 2).rounded(.down) / 2, y: 0, width: barWidth, height: PlatformMetrics.tabBarHeight)
        for index in tabs.indices { tabs[index].segment.origin.x += bar.minX }
        return (tabs, bar, selected)
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        // The tab view fills its proposal; unproposed it takes the bar and the content.
        let plan = plan(width: proposal.width ?? 0)
        let contentSize = plan.selected.map { plan.tabs[$0].node.sizeThatFits(.unspecified) } ?? .zero
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? max(plan.bar.width, contentSize.width)
        let height = proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? PlatformMetrics.tabBarHeight + contentSize.height
        return CGSize(width: width, height: height)
    }

    override package func layoutContents(proposal: ProposedViewSize) {
        let plan = plan(width: frame.width)
        tabs = plan.tabs
        bar = plan.bar
        selectedIndex = plan.selected
        for (index, tab) in tabs.enumerated() {
            guard let shown = tab.shown else { continue }
            let size = shown.sizeThatFits(.unspecified)
            shown.place(at: CGPoint(x: tab.segment.midX - size.width / 2, y: tab.segment.midY - size.height / 2), anchor: .topLeading,
                        proposal: ProposedViewSize(size), by: self)
            if index == plan.selected {
                let area = CGRect(x: 0, y: PlatformMetrics.tabBarHeight, width: frame.width, height: max(0, frame.height - PlatformMetrics.tabBarHeight))
                let contentSize = tab.node.sizeThatFits(ProposedViewSize(area.size))
                tab.node.place(at: CGPoint(x: area.midX - contentSize.width / 2, y: area.midY - contentSize.height / 2), anchor: .topLeading,
                               proposal: ProposedViewSize(area.size), by: self)
            }
        }
    }

    override package var paintedChildren: [ViewNode] {
        tabs.compactMap(\.shown) + (selectedIndex.map { [tabs[$0].node] } ?? [])
    }
    override package var structuralChildren: [ViewNode] { [content] + titles }
    override package var nodeDescription: String { "TabView" }

    override package func unmount() {
        content.unmount()
        for node in titles { node.unmount() }
        super.unmount()
    }

    // MARK: Painting

    private func black(_ alpha: Double) -> RGBA { environment._ink(alpha) }

    override package func paint(into list: inout DisplayList, context: PaintContext) {
        let bounds = absoluteBounds(context)
        // The content box from 10 pt down, then the bar over its top edge.
        let box = CGRect(x: bounds.minX, y: bounds.minY + PlatformMetrics.tabBoxTop, width: bounds.width, height: max(0, bounds.height - PlatformMetrics.tabBoxTop))
        list.append(.fillRRect(box, cornerRadius: PlatformMetrics.tabBoxCornerRadius, black(PlatformMetrics.tabBoxFillAlpha)))
        list.append(.strokePath(Path(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), cornerRadius: PlatformMetrics.tabBoxCornerRadius, style: .circular),
                                style: StrokeStyle(lineWidth: 1), black(PlatformMetrics.tabBoxBorderAlpha)))
        if let selectedIndex, selectedIndex < tabs.count {
            let content = tabs[selectedIndex].node
            content.paint(into: &list, context: context.child(at: content.presentedFrame))
        }
        let barRect = context.absoluteRect(bar)
        list.append(.fillRRect(barRect, cornerRadius: PlatformMetrics.tabBarCornerRadius, black(enabled ? PlatformMetrics.segmentedFill : PlatformMetrics.popUpDisabledFill)))
        if let selectedIndex, selectedIndex < tabs.count {
            let cell = context.absoluteRect(tabs[selectedIndex].segment).insetBy(dx: PlatformMetrics.tabSelectedInset, dy: PlatformMetrics.tabSelectedInset)
            list.append(.fillRRect(cell, cornerRadius: PlatformMetrics.tabBarCornerRadius - PlatformMetrics.tabSelectedInset,
                                   black(enabled ? PlatformMetrics.segmentedSelectedFill : PlatformMetrics.segmentedSelectedFill / 2)))
        }
        for index in tabs.indices.dropFirst() where index != selectedIndex && index - 1 != selectedIndex {
            let x = context.round(context.origin.x + tabs[index].segment.minX - PlatformMetrics.tabDividerWidth)
            let line = CGRect(x: x, y: barRect.minY + PlatformMetrics.segmentedDividerInset, width: PlatformMetrics.tabDividerWidth,
                              height: barRect.height - 2 * PlatformMetrics.segmentedDividerInset)
            list.append(.fillRect(line, black(PlatformMetrics.segmentedDividerAlpha)))
        }
        for tab in tabs {
            if let shown = tab.shown { shown.paint(into: &list, context: context.child(at: shown.presentedFrame)) }
        }
    }

    // MARK: Interaction

    package func pressBegan() {}
    package func pressEnded(inside: Bool) {}

    package func pressEnded(inside: Bool, at point: CGPoint) {
        guard inside, enabled, let tab = tabs.first(where: { $0.segment.contains(point) }) else { return }
        view.selection.select(tab.tag)
        runtime.setNeedsDisplay()
    }

    /// Left/Right move the selection to the previous/next tab.
    package func handleKey(_ press: KeyPress) -> Bool {
        guard enabled, press.modifiers.shortcutModifiers.isEmpty, !tabs.isEmpty else { return false }
        let step: Int
        switch press.key {
        case .rightArrow, .downArrow: step = 1
        case .leftArrow, .upArrow: step = -1
        default: return false
        }
        let current = selectedIndex ?? 0
        let next = min(max(current + step, 0), tabs.count - 1)
        guard next != current else { return true }
        view.selection.select(tabs[next].tag)
        runtime.setNeedsDisplay()
        return true
    }

    package var semantics: SemanticsNode {
        var node = SemanticsNode(role: .segmented, label: tabs.map(\.title).joined(separator: ", "), frame: frameInRoot, identifier: identifier)
        node.value = selectedIndex.map { tabs[$0].title }
        return node
    }
    package var exposesChildren: Bool { true }
}

/// A node that titles a tab (the `tabItem` modifier node).
@MainActor
package protocol _TabItemTitled: AnyObject {
    var title: String { get }
}

extension TabItemNode: _TabItemTitled {}
