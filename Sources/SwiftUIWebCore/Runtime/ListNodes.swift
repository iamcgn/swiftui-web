// The list's content node: lays rows, section headers and footers out in a column with the
// style's insets, paints row backgrounds, separators and the selection, and turns presses into
// selection changes (Docs/elements/List.md).

@MainActor
private var nextListIdentifier = 4_000_000

@MainActor
package final class ListContentNode<Content: View>: LayoutNode<_ListContent<Content>>, _Interactive {
    package private(set) var child: TypedNode<Content>!
    private let identifier: Int

    /// One laid-out element of the list.
    package struct Element {
        package enum Kind { case row, header, footer }
        package let kind: Kind
        package let node: ViewNode
        package let id: AnyHashable?
        package var frame: CGRect = .zero          // the cell, full list width
        package var contentFrame: CGRect = .zero   // where the node is placed
        package var separator: Bool = true          // a separator below the cell
        package var separatorTint: Color?
        package var isSectionStart = false
        /// The slot of a header shown pinned at the top instead: laid out, not painted.
        package var isHidden = false
    }

    package private(set) var elements: [Element] = []
    private var backgrounds: [ObjectIdentifier: TypedNode<AnyView>] = [:]

    package init(_ context: _NodeContext<_ListContent<Content>>) {
        nextListIdentifier += 1
        identifier = nextListIdentifier
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: Self.styled(context.environment, context.view.profile))
        child = Content._makeNode(_NodeContext(view: context.view.content, parent: self, environment: environment))
    }

    /// Rows inherit the style's font and colour; section headers and footers their styling.
    private static func styled(_ environment: EnvironmentValues, _ profile: _ListProfile) -> EnvironmentValues {
        var environment = environment
        if let font = profile.rowFont { environment.font = font }
        if let color = profile.rowForeground { environment.foregroundColor = color }
        environment._sectionStyling = _SectionStyling(font: .subheadline.weight(.semibold), foreground: .secondary)
        environment._labelIconLayout = _LabelIconLayout(iconWidth: PlatformMetrics.listLabelIconWidth,
                                                        spacing: PlatformMetrics.listLabelIconSpacing, tint: .accentColor)
        environment._inListRow = true
        return environment
    }

    override package func update(view: _ListContent<Content>, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = Self.styled(environment, view.profile)
        clearNeedsUpdate()
        child.update(view: view.content, environment: self.environment, force: force)
    }

    private var profile: _ListProfile { view.profile }

    // MARK: Elements

    /// Walks the content: sections contribute header, rows and footer; `ForEach` rows carry their
    /// identity; a unary modifier on a section or `ForEach` applies to each element (its proxy
    /// stands in for the element); other containers are transparent.
    private func collect() -> [Element] {
        var result: [Element] = []
        func walk(_ node: ViewNode, id: AnyHashable?, sectionStart: inout Bool, wrap: (ViewNode) -> ViewNode) {
            if let section = node as? any _SectionNodeProviding {
                var start = true
                for header in section._headerNode.layoutChildren {
                    var element = Element(kind: .header, node: wrap(header), id: nil)
                    element.isSectionStart = start; start = false
                    result.append(element)
                }
                walk(section._contentNode, id: id, sectionStart: &start, wrap: wrap)
                for footer in section._footerNode.layoutChildren {
                    var element = Element(kind: .footer, node: wrap(footer), id: nil)
                    element.isSectionStart = start; start = false
                    result.append(element)
                }
                sectionStart = true
                return
            }
            if let forEach = node as? any _ForEachNodeProviding {
                for (entryID, entryNode) in forEach._entries { walk(entryNode, id: entryID, sectionStart: &sectionStart, wrap: wrap) }
                return
            }
            if let modifier = node as? any _UnaryLayoutModifier {
                var proxies: [ObjectIdentifier: ViewNode] = [:]
                for (target, proxy) in zip(modifier.targets, node.layoutChildren) { proxies[ObjectIdentifier(target)] = proxy }
                walk(modifier.modifiedContent, id: id, sectionStart: &sectionStart) { wrap(proxies[ObjectIdentifier($0)] ?? $0) }
                return
            }
            if node.isLayoutNode {
                var element = Element(kind: .row, node: wrap(node), id: id)
                element.isSectionStart = sectionStart; sectionStart = false
                result.append(element)
                return
            }
            for structural in node.structuralChildren { walk(structural, id: id, sectionStart: &sectionStart, wrap: wrap) }
        }
        var start = false
        walk(child, id: nil, sectionStart: &start) { $0 }
        if view.pinsFirstHeader, let first = result.first, first.kind == .header { result[0].isHidden = true }
        return result
    }

    private func rowInsets(_ node: ViewNode) -> EdgeInsets {
        node.layoutValue(for: ListRowInsetsKey.self)
            ?? EdgeInsets(top: PlatformMetrics.listRowVerticalInset, leading: 0, bottom: PlatformMetrics.listRowVerticalInset, trailing: 0)
    }

    // MARK: Layout

    private struct Plan {
        var elements: [Element]
        var height: CGFloat
    }

    private func plan(width: CGFloat) -> Plan {
        var elements = collect()
        var y = profile.topInset
        let last = elements.indices.last
        for index in elements.indices {
            var element = elements[index]
            if index > 0, element.isSectionStart { y += PlatformMetrics.listSectionSpacing }
            let contentWidth = width - 2 * profile.margin
            switch element.kind {
            case .header, .footer:
                let pad = PlatformMetrics.listSectionHeaderPadding
                let size = element.node.sizeThatFits(ProposedViewSize(width: contentWidth, height: nil))
                element.contentFrame = CGRect(x: profile.margin, y: y + pad, width: contentWidth, height: size.height)
                element.frame = CGRect(x: 0, y: y, width: width, height: size.height + 2 * pad)
                element.separator = profile.showsSeparators && index != last && !element.isHidden
            case .row:
                let insets = rowInsets(element.node)
                let available = max(0, contentWidth - insets.leading - insets.trailing)
                let size = element.node.sizeThatFits(ProposedViewSize(width: available, height: nil))
                let height = max(profile.minimumRowHeight, size.height + insets.top + insets.bottom)
                element.frame = CGRect(x: 0, y: y, width: width, height: height)
                let contentY = y + (height - size.height) / 2
                element.contentFrame = CGRect(x: profile.margin + insets.leading, y: contentY, width: available, height: size.height)
                let (visibility, edges) = element.node.layoutValue(for: ListRowSeparatorKey.self)
                element.separator = profile.showsSeparators && index != last && !(visibility == .hidden && edges.contains(.bottom))
                let (tint, tintEdges) = element.node.layoutValue(for: ListRowSeparatorTintKey.self)
                if tintEdges.contains(.bottom) { element.separatorTint = tint }
            }
            y = element.frame.maxY
            elements[index] = element
        }
        return Plan(elements: elements, height: y)
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? PlatformMetrics.listIdealWidth
        return CGSize(width: width, height: plan(width: width).height)
    }

    override package func layoutContents(proposal: ProposedViewSize) {
        let width = frame.width
        let plan = plan(width: width)
        elements = plan.elements
        var live = Set<ObjectIdentifier>()
        for element in elements {
            let target = element.contentFrame
            let size = element.node.sizeThatFits(ProposedViewSize(target.size))
            element.node.place(at: target.origin, anchor: .topLeading,
                               proposal: ProposedViewSize(width: target.width, height: element.kind == .row ? size.height : target.height), by: self)
            if element.kind == .row, let background = element.node.layoutValue(for: ListRowBackgroundKey.self) {
                let key = ObjectIdentifier(element.node)
                live.insert(key)
                let node = backgrounds[key] ?? AnyView._makeNode(_NodeContext(view: background.view, parent: self, environment: environment))
                node.update(view: background.view, environment: environment, force: false)
                backgrounds[key] = node
                let cell = profile.rowBackgroundExtendsToEdges ? element.frame : element.frame.insetBy(dx: profile.margin, dy: 0)
                for layer in node.layoutChildren {
                    layer.place(at: cell.origin, anchor: .topLeading, proposal: ProposedViewSize(cell.size), by: self)
                }
            }
        }
        for (key, node) in backgrounds where !live.contains(key) {
            node.unmount()
            backgrounds[key] = nil
        }
    }

    override package var paintedChildren: [ViewNode] { elements.map(\.node) }
    override package var structuralChildren: [ViewNode] { [child] }
    override package var nodeDescription: String { "List" }

    override package func unmount() {
        for node in backgrounds.values { node.unmount() }
        backgrounds.removeAll()
        super.unmount()
    }

    // MARK: Painting

    private func isSelected(_ element: Element) -> Bool {
        guard let id = element.id, let selection = view.selection else { return false }
        return selection.isSelected(id)
    }

    override package func paint(into list: inout DisplayList, context: PaintContext) {
        let selected = elements.map(isSelected)
        // Separators first: below each element that has one, from its content's leading edge to
        // the style's trailing margin; none next to a selected row, and a row background covers
        // its own (list/modifiers).
        for (index, element) in elements.enumerated() where element.separator {
            if selected[index] || (index + 1 < elements.count && selected[index + 1]) { continue }
            let color = element.separatorTint?.resolve(in: environment)
                ?? RGBA(red: 0, green: 0, blue: 0, alpha: PlatformMetrics.listSeparatorAlpha)
            let x = element.contentFrame.minX
            let line = CGRect(x: x, y: element.frame.maxY - PlatformMetrics.listSeparatorThickness,
                              width: max(0, frame.width - profile.separatorTrailing - x), height: PlatformMetrics.listSeparatorThickness)
            list.append(.fillRect(context.absoluteRect(line), color))
        }
        for (index, element) in elements.enumerated() where !element.isHidden {
            if element.kind == .row, let background = backgrounds[ObjectIdentifier(element.node)] {
                for layer in background.layoutChildren { layer.paint(into: &list, context: context.child(at: layer.frame)) }
            }
            if selected[index] {
                let cell = context.absoluteRect(element.frame.insetBy(dx: PlatformMetrics.listSelectionInset, dy: 0))
                list.append(.fillRRect(cell, cornerRadius: PlatformMetrics.listSelectionCornerRadius,
                                       RGBA(red: 0, green: 0, blue: 0, alpha: PlatformMetrics.listSelectionAlpha)))
            }
            element.node.paint(into: &list, context: context.child(at: element.node.frame))
        }
    }

    // MARK: Selection

    package func pressBegan() {}
    package func pressEnded(inside: Bool) {}

    package func pressEnded(inside: Bool, at point: CGPoint) {
        guard inside, let element = elements.first(where: { $0.kind == .row && $0.frame.contains(point) }) else { return }
        // A row that is a `NavigationLink` pushes; a selectable row toggles its selection.
        element.node.layoutValue(for: NavigationLinkActivationKey.self)?.run()
        if let selection = view.selection, let id = element.id {
            selection.toggle(id)
            runtime.setNeedsDisplay()
        }
    }

    package var semantics: SemanticsNode {
        SemanticsNode(role: .button, label: "", frame: frameInRoot, identifier: identifier)
    }
}

/// How a container styles the headers and footers of its sections.
package struct _SectionStyling: Equatable {
    package var font: Font
    package var foreground: Color
}

package struct SectionStylingKey: EnvironmentKey {
    package static let defaultValue: _SectionStyling? = nil
}

extension EnvironmentValues {
    package var _sectionStyling: _SectionStyling? {
        get { self[SectionStylingKey.self] }
        set { self[SectionStylingKey.self] = newValue }
    }
}

/// Type-erased access to a section's three subtrees.
@MainActor
package protocol _SectionNodeProviding: AnyObject {
    var _headerNode: ViewNode { get }
    var _contentNode: ViewNode { get }
    var _footerNode: ViewNode { get }
}

/// Type-erased access to a `ForEach`'s entries.
@MainActor
package protocol _ForEachNodeProviding: AnyObject {
    var _entries: [(AnyHashable, ViewNode)] { get }
}
