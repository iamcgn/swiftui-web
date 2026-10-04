// TabView nodes (Docs/elements/TabView.md): the tab bar (segments sized by their titles over a
// pill, the selected one filled) centred at the top, a bordered box from 10 pt down, and the
// selected tab's content centred in the area under the bar. iOS (`tabBarAtBottom`,
// Docs/elements/iOS.md): a floating capsule at the window's bottom holding a symbol and a
// label per tab, the selected one on a grey pill; the content fills the area above it.

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

    /// The tab's symbol: the label's first system image (the iOS bar shows it above the title).
    package var symbolName: String? {
        for node in label.descendants(where: { $0 is ImageNode }) {
            if let image = node as? ImageNode, case .system(let name) = image.view.source { return name }
        }
        return nil
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
    private var icons: [TypedNode<AnyView>] = []
    private var badges: [TypedNode<AnyView>] = []
    private let identifier: Int

    package struct Tab {
        package let node: ViewNode
        package let tag: AnyHashable
        package let title: String
        package let symbol: String?
        /// The tab's `badge`, and whether the tab is enabled (`disabled` on the tab or its content).
        package let badge: String?
        package let isEnabled: Bool
        package var shown: ViewNode?
        package var icon: ViewNode?
        package var badgeLabel: ViewNode?
        package var segment: CGRect = .zero
    }

    private var bottomBar: Bool { PlatformMetrics.tabBarAtBottom }

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
            let titled = entry.node.descendants(where: { $0 is any _TabItemTitled }).first as? any _TabItemTitled ?? Self.tabItem(above: entry.node)
            let badge = (Self.modifier(above: entry.node) { $0 as? any _TabBadgeProviding })?.badgeText
                ?? (entry.node.descendants(where: { $0 is any _TabBadgeProviding }).first as? any _TabBadgeProviding)?.badgeText
            result.append(Tab(node: entry.node, tag: tag, title: titled?.title ?? "", symbol: titled?.symbolName, badge: badge, isEnabled: entry.node.environment.isEnabled))
        }
        while titles.count > result.count { titles.removeLast().unmount() }
        while icons.count > result.count { icons.removeLast().unmount() }
        while badges.count > result.count { badges.removeLast().unmount() }
        let bottomBar = bottomBar
        for index in result.indices {
            let selected = view.selection.isSelected(result[index].tag)
            let tabEnabled = enabled && result[index].isEnabled
            let text: AnyView
            if bottomBar {
                let tint: Color = selected ? .accentColor : .primary
                text = AnyView(Text(result[index].title).font(.system(size: PlatformMetrics.tabLabelSize, weight: .medium)).foregroundStyle(tint))
                let icon = AnyView(Image(systemName: result[index].symbol ?? "").font(.system(size: PlatformMetrics.tabIconSize)).foregroundStyle(tint))
                if index < icons.count {
                    icons[index].update(view: icon, environment: environment, force: false)
                } else {
                    icons.append(AnyView._makeNode(_NodeContext(view: icon, parent: self, environment: environment)))
                }
                result[index].icon = icons[index].layoutChildren.first
                // The badge: its text in white on a red capsule (ios/tabs/badges).
                let badgeView = AnyView(Text(result[index].badge ?? "").font(.system(size: PlatformMetrics.tabBadgeFontSize)).foregroundStyle(Color.white))
                if index < badges.count {
                    badges[index].update(view: badgeView, environment: environment, force: false)
                } else {
                    badges.append(AnyView._makeNode(_NodeContext(view: badgeView, parent: self, environment: environment)))
                }
                result[index].badgeLabel = result[index].badge == nil ? nil : badges[index].layoutChildren.first
            } else {
                let alpha = selected ? PlatformMetrics.segmentedSelectedTextAlpha : PlatformMetrics.segmentedTextAlpha
                text = AnyView(Text(result[index].title).font(.system(size: PlatformMetrics.buttonLabelSize))
                    .foregroundColor(Color.black.opacity(tabEnabled ? alpha : alpha / 2)))
            }
            if index < titles.count {
                titles[index].update(view: text, environment: environment, force: false)
            } else {
                titles.append(AnyView._makeNode(_NodeContext(view: text, parent: self, environment: environment)))
            }
            result[index].shown = titles[index].layoutChildren.first
        }
        return result
    }

    /// iOS: the capsule at the window's bottom, a slot per tab sharing its width, the selected
    /// tab's pill in its slot.
    private func planBottomBar(size: CGSize) -> (tabs: [Tab], bar: CGRect, selected: Int?) {
        var tabs = collectTabs()
        let selected = tabs.firstIndex { view.selection.isSelected($0.tag) } ?? (tabs.isEmpty ? nil : 0)
        let inset = PlatformMetrics.tabBarCapsuleSideInset
        let bar = CGRect(x: inset, y: size.height - PlatformMetrics.tabBarCapsuleBottomInset - PlatformMetrics.tabBarCapsuleHeight,
                         width: max(0, size.width - 2 * inset), height: PlatformMetrics.tabBarCapsuleHeight)
        let slot = tabs.isEmpty ? 0 : (bar.width - 2 * PlatformMetrics.tabBarInnerPadding) / CGFloat(tabs.count)
        let pill = PlatformMetrics.tabPillSize
        for index in tabs.indices {
            let centre = bar.minX + PlatformMetrics.tabBarInnerPadding + slot * (CGFloat(index) + 0.5)
            tabs[index].segment = CGRect(x: centre - pill.width / 2, y: bar.minY + PlatformMetrics.tabPillTop, width: pill.width, height: pill.height)
        }
        return (tabs, bar, selected)
    }

    /// The `tabItem` node between `node` and this tab view, if the modifier wraps the leaf.
    private static func tabItem(above node: ViewNode) -> (any _TabItemTitled)? {
        modifier(above: node) { $0 as? any _TabItemTitled }
    }

    /// The first node between `node` and the tab view that `match` accepts.
    private static func modifier<T>(above node: ViewNode, _ match: (ViewNode) -> T?) -> T? {
        var current = node.parent
        while let candidate = current, !(candidate is TabViewNode) {
            if let found = match(candidate) { return found }
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
        let plan = bottomBar ? planBottomBar(size: CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)) : plan(width: proposal.width ?? 0)
        let contentSize = plan.selected.map { plan.tabs[$0].node.sizeThatFits(.unspecified) } ?? .zero
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? max(plan.bar.width, contentSize.width)
        let height = proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? PlatformMetrics.tabBarHeight + contentSize.height
        return CGSize(width: width, height: height)
    }

    override package func layoutContents(proposal: ProposedViewSize) {
        if bottomBar { layoutBottomBar(); return }
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

    /// iOS: the symbol 7.5 below the pill's top and the label on its baseline 44 below it, both
    /// centred in the slot; the content fills the area above the bar's region.
    private func layoutBottomBar() {
        let plan = planBottomBar(size: frame.size)
        tabs = plan.tabs
        bar = plan.bar
        selectedIndex = plan.selected
        for (index, tab) in tabs.enumerated() {
            let pill = tab.segment
            if let icon = tab.icon {
                let size = icon.sizeThatFits(.unspecified)
                icon.place(at: CGPoint(x: pill.midX - size.width / 2, y: pill.minY + PlatformMetrics.tabIconTop), anchor: .topLeading,
                           proposal: ProposedViewSize(size), by: self)
            }
            if let shown = tab.shown {
                let dimensions = shown.dimensions(in: .unspecified)
                let baseline = dimensions[VerticalAlignment.firstTextBaseline]
                shown.place(at: CGPoint(x: pill.midX - dimensions.width / 2, y: pill.minY + PlatformMetrics.tabLabelBaseline - baseline), anchor: .topLeading,
                            proposal: ProposedViewSize(dimensions.size), by: self)
            }
            if let badge = tab.badgeLabel, let icon = tab.icon {
                // The badge's text centres in a capsule whose centre sits at the symbol's top-right.
                let size = badge.sizeThatFits(.unspecified)
                let capsule = badgeCapsule(for: size, icon: icon.frame)
                badge.place(at: CGPoint(x: capsule.midX - size.width / 2, y: capsule.midY - size.height / 2), anchor: .topLeading,
                            proposal: ProposedViewSize(size), by: self)
            }
            if index == plan.selected {
                let area = CGRect(x: 0, y: 0, width: frame.width, height: max(0, frame.height - PlatformMetrics.tabBarContentBottomInset))
                let contentSize = tab.node.sizeThatFits(ProposedViewSize(area.size))
                tab.node.place(at: CGPoint(x: area.midX - contentSize.width / 2, y: area.midY - contentSize.height / 2), anchor: .topLeading,
                               proposal: ProposedViewSize(area.size), by: self)
            }
        }
    }

    /// The red capsule behind a badge's text (ios/tabs/badges): its left edge `tabBadgeLeading`
    /// right of the symbol's centre, its top `tabBadgeRise` above the symbol, at least
    /// `tabBadgeMinimumWidth` wide.
    private func badgeCapsule(for text: CGSize, icon: CGRect) -> CGRect {
        let height = PlatformMetrics.tabBadgeHeight
        let width = max(PlatformMetrics.tabBadgeMinimumWidth, text.width + 2 * PlatformMetrics.tabBadgePadding)
        return CGRect(x: icon.midX + PlatformMetrics.tabBadgeLeading, y: icon.minY - PlatformMetrics.tabBadgeRise, width: width, height: height)
    }

    override package var paintedChildren: [ViewNode] {
        tabs.compactMap(\.shown) + tabs.compactMap(\.icon) + tabs.compactMap(\.badgeLabel) + (selectedIndex.map { [tabs[$0].node] } ?? [])
    }
    override package var structuralChildren: [ViewNode] { [content] + titles + icons + badges }
    override package var nodeDescription: String { "TabView" }

    override package func unmount() {
        content.unmount()
        for node in titles { node.unmount() }
        for node in icons { node.unmount() }
        for node in badges { node.unmount() }
        super.unmount()
    }

    // MARK: Painting

    private func black(_ alpha: Double) -> RGBA { environment._ink(alpha) }

    override package func paint(into list: inout DisplayList, context: PaintContext) {
        if bottomBar { paintBottomBar(into: &list, context: context); return }
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

    /// iOS: the content, then the capsule over a soft shadow, the selected pill, the symbols and labels.
    private func paintBottomBar(into list: inout DisplayList, context: PaintContext) {
        if let selectedIndex, selectedIndex < tabs.count {
            let content = tabs[selectedIndex].node
            content.paint(into: &list, context: context.child(at: content.presentedFrame))
        }
        let barRect = context.absoluteRect(bar)
        let radius = bar.height / 2
        // The shadow: a few rings below the capsule, fading out over 20 pt (approximate: the real one is blurred).
        for (spread, alpha) in [(2.0, 0.035), (6.0, 0.025), (11.0, 0.018), (17.0, 0.012)] {
            list.append(.fillRRect(barRect.insetBy(dx: -spread / 2, dy: -spread / 2).offsetBy(dx: 0, dy: spread / 2), cornerRadius: radius + spread / 2, black(alpha)))
        }
        list.append(.fillRRect(barRect, cornerRadius: radius, PlatformMetrics.tabBarCapsuleFill))
        if let selectedIndex, selectedIndex < tabs.count {
            let pill = context.absoluteRect(tabs[selectedIndex].segment)
            list.append(.fillRRect(pill, cornerRadius: pill.height / 2, black(PlatformMetrics.tabPillAlpha)))
        }
        for tab in tabs {
            if let icon = tab.icon { icon.paint(into: &list, context: context.child(at: icon.presentedFrame)) }
            if let shown = tab.shown { shown.paint(into: &list, context: context.child(at: shown.presentedFrame)) }
            if let badge = tab.badgeLabel, let icon = tab.icon {
                let capsule = context.absoluteRect(badgeCapsule(for: badge.frame.size, icon: icon.frame))
                list.append(.fillRRect(capsule, cornerRadius: capsule.height / 2, PlatformMetrics.tabBadgeFill))
                badge.paint(into: &list, context: context.child(at: badge.presentedFrame))
            }
        }
    }

    // MARK: Interaction

    package func pressBegan() {}
    package func pressEnded(inside: Bool) {}

    package func pressEnded(inside: Bool, at point: CGPoint) {
        guard inside, enabled, let tab = tabs.first(where: { $0.segment.contains(point) }), tab.isEnabled else { return }
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
        var next = current + step
        // Disabled tabs are skipped.
        while tabs.indices.contains(next), !tabs[next].isEnabled { next += step }
        guard tabs.indices.contains(next), next != current else { return true }
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
    var symbolName: String? { get }
}

extension TabItemNode: _TabItemTitled {}


// MARK: - Badges

/// What a tab view reads from a `badge` on the way down to a tab.
@MainActor
package protocol _TabBadgeProviding: AnyObject {
    var badgeText: String? { get }
}

/// Records a `badge`; transparent for layout.
@MainActor
package final class BadgeNode<Content: View>: UnaryLayoutModifierNode<Content, _BadgeModifier>, _TabBadgeProviding {
    package var badgeText: String? { modifier.text }
}

// MARK: - The page style

/// Node for the page style: every tab is a page the node's size, laid out side by side and
/// shown by the selection; a horizontal swipe turns the page; the page indicator's dots sit
/// at the bottom (Docs/elements/TabView.md, "Page style").
@MainActor
package final class PagedTabViewNode: LayoutNode<_PagedTabViewPrimitive>, _Interactive {
    private var content: TypedNode<AnyView>!
    private let identifier: Int
    package private(set) var pages: [(node: ViewNode, tag: AnyHashable)] = []
    package private(set) var selectedIndex: Int = 0
    package var dragAxes: Axis.Set { .horizontal }

    package init(_ context: _NodeContext<_PagedTabViewPrimitive>) {
        nextTabIdentifier += 1
        identifier = nextTabIdentifier
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        content = AnyView._makeNode(_NodeContext(view: context.view.content, parent: self, environment: context.environment))
    }

    override package func update(view: _PagedTabViewPrimitive, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        content.update(view: view.content, environment: environment, force: force)
    }

    private func collectPages() -> [(node: ViewNode, tag: AnyHashable)] {
        _collectOptions(content).enumerated().map { index, entry in
            (entry.node, entry.node.layoutValue(for: TagKey.self) ?? AnyHashable(index))
        }
    }

    /// The page style fills its proposal; unproposed, the largest page.
    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        let pages = collectPages()
        var largest = CGSize.zero
        for page in pages {
            let size = page.node.sizeThatFits(.unspecified)
            largest.width = max(largest.width, size.width)
            largest.height = max(largest.height, size.height)
        }
        return CGSize(width: proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? largest.width,
                      height: proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? largest.height)
    }

    override package func layoutContents(proposal: ProposedViewSize) {
        pages = collectPages()
        selectedIndex = pages.firstIndex { view.selection.isSelected($0.tag) } ?? 0
        let size = frame.size
        for (index, page) in pages.enumerated() {
            let pageSize = page.node.sizeThatFits(ProposedViewSize(size))
            let x = CGFloat(index - selectedIndex) * size.width
            page.node.place(at: CGPoint(x: x + (size.width - pageSize.width) / 2, y: (size.height - pageSize.height) / 2), anchor: .topLeading,
                            proposal: ProposedViewSize(size), by: self)
        }
    }

    override package var clipsHitTesting: Bool { true }
    override package var paintedChildren: [ViewNode] { pages.map(\.node) }
    override package var structuralChildren: [ViewNode] { [content] }
    override package var nodeDescription: String { "PagedTabView" }

    override package func unmount() {
        content.unmount()
        super.unmount()
    }

    override package func paint(into list: inout DisplayList, context: PaintContext) {
        let bounds = absoluteBounds(context)
        list.append(.save)
        list.append(.clipRect(bounds))
        paintChildren(into: &list, context: context)
        list.append(.restore)
        guard view.showsIndex, pages.count > 1 else { return }
        // The indicator: a dot per page on one row above the bottom, the current one in the ink.
        let diameter = PlatformMetrics.pageIndicatorDotDiameter, pitch = PlatformMetrics.pageIndicatorDotPitch
        let total = diameter + pitch * CGFloat(pages.count - 1)
        let y = bounds.maxY - PlatformMetrics.pageIndicatorBottomInset - diameter
        var x = bounds.midX - total / 2
        for index in pages.indices {
            let color = PlatformMetrics.pageIndicatorColor.multiplyingAlpha(by: index == selectedIndex ? PlatformMetrics.pageIndicatorCurrentAlpha : PlatformMetrics.pageIndicatorAlpha)
            list.append(.fillPath(Path(ellipseIn: CGRect(x: x, y: y, width: diameter, height: diameter)), color))
            x += pitch
        }
    }

    // MARK: Swiping

    private var pressStart: CGPoint?
    private var pressLast: CGPoint?

    package func pressBegan() {}
    package func pressBegan(at point: CGPoint) {
        pressStart = point
        pressLast = point
    }
    package func pressMoved(to point: CGPoint) { pressLast = point }
    package func pressEnded(inside: Bool) {
        pressStart = nil
        pressLast = nil
    }

    /// A horizontal swipe past the threshold turns to the next or previous page.
    package func pressEnded(inside: Bool, at point: CGPoint) {
        defer { pressStart = nil; pressLast = nil }
        guard let start = pressStart, environment.isEnabled else { return }
        let dx = point.x - start.x
        guard abs(dx) >= PlatformMetrics.pageSwipeThreshold, abs(dx) > abs(point.y - start.y) else { return }
        let next = dx < 0 ? selectedIndex + 1 : selectedIndex - 1
        guard pages.indices.contains(next) else { return }
        view.selection.select(pages[next].tag)
        runtime.requestLayout()
    }

    package var semantics: SemanticsNode {
        var node = SemanticsNode(role: .group, label: "", frame: frameInRoot, identifier: identifier)
        node.value = pages.isEmpty ? nil : "\(selectedIndex + 1) of \(pages.count)"
        return node
    }
    package var exposesChildren: Bool { true }
}
