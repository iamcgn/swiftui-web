// The list's content node: lays rows, section headers and footers out in a column with the
// style's insets, paints row backgrounds, separators and the selection, and turns presses into
// selection changes (Docs/elements/List.md).
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

@MainActor
private var nextListIdentifier = 4_000_000

/// A list whose ground colour a navigation stack extends under its bar (iOS grouped lists).
@MainActor
package protocol _ListGroundProviding: AnyObject {
    var _groundColor: Color? { get }
}

@MainActor
package final class ListContentNode<Content: View>: LayoutNode<_ListContent<Content>>, _Interactive, _KeyHandling, _ListGroundProviding {
    package var _groundColor: Color? { profile.cards ? profile.background : nil }
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
        /// The `ForEach` the row belongs to and its offset in it (edit actions).
        package var owner: (any _ForEachNodeProviding)?
        package var offset = 0
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
        environment._sectionStyling = _SectionStyling(font: profile.headerFont ?? .subheadline.weight(.semibold), foreground: .secondary, footerFont: profile.footerFont)
        let metrics = environment.platformProfile.metrics   // read explicitly: updates run outside a profile selection
        environment._labelIconLayout = _LabelIconLayout(iconWidth: metrics.listLabelIconWidth, spacing: metrics.listLabelIconSpacing,
                                                        tint: .accentColor, scale: metrics.listLabelIconScale)
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
        func walk(_ node: ViewNode, id: AnyHashable?, owner: (any _ForEachNodeProviding)? = nil, offset: Int = 0,
                  sectionStart: inout Bool, wrap: @MainActor (ViewNode) -> ViewNode) {
            if let section = node as? any _SectionNodeProviding {
                var start = true
                for header in section._headerNode.layoutChildren {
                    var element = Element(kind: .header, node: wrap(header), id: nil)
                    element.isSectionStart = start; start = false
                    result.append(element)
                }
                walk(section._contentNode, id: id, owner: owner, offset: offset, sectionStart: &start, wrap: wrap)
                for footer in section._footerNode.layoutChildren {
                    var element = Element(kind: .footer, node: wrap(footer), id: nil)
                    element.isSectionStart = start; start = false
                    result.append(element)
                }
                sectionStart = true
                return
            }
            if let forEach = node as? any _ForEachNodeProviding {
                for (index, (entryID, entryNode)) in forEach._entries.enumerated() {
                    walk(entryNode, id: entryID, owner: forEach, offset: index, sectionStart: &sectionStart, wrap: wrap)
                }
                return
            }
            if let modifier = node as? any _UnaryLayoutModifier {
                var proxies: [ObjectIdentifier: ViewNode] = [:]
                for (target, proxy) in zip(modifier.targets, node.layoutChildren) { proxies[ObjectIdentifier(target)] = proxy }
                walk(modifier.modifiedContent, id: id, owner: owner, offset: offset, sectionStart: &sectionStart) { wrap(proxies[ObjectIdentifier($0)] ?? $0) }
                return
            }
            if node.isLayoutNode {
                // A row outside a `ForEach` is identified by its `tag`, read through the modifiers
                // above it (ios/list/selection).
                let row = wrap(node)
                var element = Element(kind: .row, node: row, id: id ?? row.layoutValue(for: TagKey.self))
                element.isSectionStart = sectionStart; sectionStart = false
                element.owner = owner
                element.offset = offset
                result.append(element)
                return
            }
            for structural in node.structuralChildren { walk(structural, id: id, owner: owner, offset: offset, sectionStart: &sectionStart, wrap: wrap) }
        }
        var start = false
        walk(child, id: nil, sectionStart: &start) { $0 }
        if view.pinsFirstHeader, let first = result.first, first.kind == .header { result[0].isHidden = true }
        return result
    }

    private func rowInsets(_ node: ViewNode) -> EdgeInsets {
        if let insets = node.layoutValue(for: ListRowInsetsKey.self) { return insets }
        if profile.rowPadding > 0 {
            return EdgeInsets(top: profile.rowPadding, leading: profile.contentInset, bottom: profile.rowPadding, trailing: profile.contentInset)
        }
        return EdgeInsets(top: PlatformMetrics.listRowVerticalInset, leading: 0, bottom: PlatformMetrics.listRowVerticalInset, trailing: 0)
    }

    /// Whether the style lays out the iOS way (rows padded, headers with their own gaps).
    private var iOSLayout: Bool { profile.rowPadding > 0 }

    // MARK: Layout

    private struct Plan {
        var elements: [Element]
        var height: CGFloat
    }

    private func plan(width: CGFloat) -> Plan {
        var elements = collect()
        var y = profile.topInset
        let last = elements.indices.last
        // iOS: a first section that opens with a header starts at its header's gap, not the top inset.
        if iOSLayout, let first = elements.first, first.kind == .header { y = 0 }
        for index in elements.indices {
            var element = elements[index]
            if index > 0, element.isSectionStart {
                if !iOSLayout {
                    y += PlatformMetrics.listSectionSpacing
                } else if element.kind == .row, elements[index - 1].kind == .row {
                    // iOS: a card without a header sits the top inset (35) below the previous
                    // card (ios/representable/form); headers and footers carry their own gaps.
                    y += profile.topInset
                }
            }
            let contentWidth = width - 2 * profile.margin
            switch element.kind {
            case .header where iOSLayout:
                // iOS: the header text sits `headerTop` below the previous card (`firstHeaderTop` at
                // the top, `listGroupedFooterToHeader` below a footer's slot) and `headerBottom`
                // above its card, inset like a row's content.
                let afterFooter = index > 0 && elements[index - 1].kind == .footer
                let top = index == 0 ? profile.firstHeaderTop : afterFooter ? PlatformMetrics.listGroupedFooterToHeader : profile.headerTop
                let size = element.node.sizeThatFits(ProposedViewSize(width: nil, height: nil))
                element.contentFrame = CGRect(x: profile.margin + profile.contentInset, y: y + top,
                                              width: min(size.width, contentWidth - 2 * profile.contentInset), height: size.height)
                element.frame = CGRect(x: 0, y: y, width: width, height: top + size.height + profile.headerBottom)
                element.separator = false
            case .footer where iOSLayout:
                // iOS (ios/list/footer): the footnote text 8 below its card in a 21 pt slot (UIKit's
                // label height for the 18.5 pt line), the next card 23.5 below the slot.
                let size = element.node.sizeThatFits(ProposedViewSize(width: nil, height: nil))
                let followedByHeader = index + 1 < elements.count && elements[index + 1].kind == .header
                element.contentFrame = CGRect(x: profile.margin + profile.contentInset, y: y + PlatformMetrics.listGroupedFooterTop,
                                              width: min(size.width, contentWidth - 2 * profile.contentInset), height: size.height)
                element.frame = CGRect(x: 0, y: y, width: width,
                                       height: PlatformMetrics.listGroupedFooterTop + max(size.height, PlatformMetrics.listFooterSlotHeight)
                                           + (followedByHeader ? 0 : PlatformMetrics.listGroupedFooterBottom))
                element.separator = false
            case .header, .footer:
                let pad = PlatformMetrics.listSectionHeaderPadding
                let size = element.node.sizeThatFits(ProposedViewSize(width: contentWidth, height: nil))
                element.contentFrame = CGRect(x: profile.margin, y: y + pad, width: contentWidth, height: size.height)
                element.frame = CGRect(x: 0, y: y, width: width, height: size.height + 2 * pad)
                element.separator = profile.showsSeparators && index != last && !element.isHidden
            case .row:
                var insets = rowInsets(element.node)
                // iOS edit mode: the content moves in for the delete circle and leaves the grip its slot.
                if editingAccessories, canDelete(element) { insets.leading += PlatformMetrics.listEditLeadingInset }
                if editingAccessories, canMove(element) { insets.trailing += PlatformMetrics.listEditGripWidth }
                let available = max(0, contentWidth - insets.leading - insets.trailing)
                let size = element.node.sizeThatFits(ProposedViewSize(width: available, height: nil))
                let height = max(profile.minimumRowHeight, size.height + insets.top + insets.bottom)
                element.frame = CGRect(x: 0, y: y, width: width, height: height)
                let contentY = y + (height - size.height) / 2
                let shift = swipe?.row == index ? swipe!.offset : 0
                element.contentFrame = CGRect(x: profile.margin + insets.leading + shift, y: contentY, width: available, height: size.height)
                let (visibility, edges) = element.node.layoutValue(for: ListRowSeparatorKey.self)
                // A card's last row has no separator: the next element is a header, footer or nothing.
                let followedByRow = index + 1 < elements.count && elements[index + 1].kind == .row && !(iOSLayout && elements[index + 1].isSectionStart)
                element.separator = profile.showsSeparators && index != last && !(visibility == .hidden && edges.contains(.bottom)) && (!iOSLayout || followedByRow)
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
        layoutStrips()
    }

    override package var paintedChildren: [ViewNode] { elements.map(\.node) }
    override package var structuralChildren: [ViewNode] { [child] + strips.values.flatMap { Array($0.values) } }
    override package var nodeDescription: String { "List" }

    override package func unmount() {
        for node in backgrounds.values { node.unmount() }
        for byEdge in strips.values { for node in byEdge.values { node.unmount() } }
        backgrounds.removeAll()
        super.unmount()
    }

    // MARK: Painting

    private func isSelected(_ element: Element) -> Bool {
        guard let id = element.id, let selection = view.selection else { return false }
        return selection.isSelected(id)
    }

    /// iOS inset grouped: the runs of rows between headers and footers, each a white card.
    private var cardFrames: [CGRect] {
        var cards: [CGRect] = []
        var current: CGRect?
        for element in elements {
            if element.kind == .row, !(element.isSectionStart && current != nil) {
                current = current.map { $0.union(element.frame) } ?? element.frame
            } else {
                if let card = current { cards.append(card) }
                current = element.kind == .row ? element.frame : nil
            }
        }
        if let card = current { cards.append(card) }
        return cards.map { $0.insetBy(dx: profile.margin, dy: 0) }
    }

    override package func paint(into list: inout DisplayList, context: PaintContext) {
        let selected = elements.map(isSelected)
        if profile.cards {
            for card in cardFrames {
                list.append(.fillPath(Path(roundedRect: context.absoluteRect(card), cornerRadius: profile.cardCornerRadius, style: .continuous),
                                      environment._groupedCard))
            }
        }
        // Separators first: below each element that has one, from its content's leading edge to
        // the style's trailing margin; none next to a selected row, and a row background covers
        // its own (list/modifiers).
        for (index, element) in elements.enumerated() where element.separator {
            if selected[index] || (index + 1 < elements.count && selected[index + 1]) { continue }
            let color = element.separatorTint?.resolve(in: environment)
                ?? environment._ink(PlatformMetrics.listSeparatorAlpha)
            let x = element.contentFrame.minX
            let line = CGRect(x: x, y: element.frame.maxY - PlatformMetrics.listSeparatorThickness,
                              width: max(0, frame.width - profile.separatorTrailing - x), height: PlatformMetrics.listSeparatorThickness)
            list.append(.fillRect(context.absoluteRect(line), color))
        }
        for (index, element) in elements.enumerated() where !element.isHidden {
            if element.kind == .row, let background = backgrounds[ObjectIdentifier(element.node)] {
                for layer in background.layoutChildren { layer.paint(into: &list, context: context.child(at: layer.presentedFrame)) }
            }
            if selected[index] {
                let cell = context.absoluteRect(element.frame.insetBy(dx: PlatformMetrics.listSelectionInset, dy: 0))
                // A focused list shows its selection in the accent colour; iOS fills the row with its grey.
                let color = PlatformMetrics.listSelectionFill
                    ?? (runtime.focusedIdentifier == identifier && runtime.focusVisible
                        ? Color.accentColor.opacity(PlatformMetrics.listFocusedSelectionAlpha).resolve(in: environment)
                        : environment._ink(PlatformMetrics.listSelectionAlpha))
                list.append(.fillRRect(cell, cornerRadius: PlatformMetrics.listSelectionCornerRadius, color))
            }
            element.node.paint(into: &list, context: context.child(at: element.node.presentedFrame))
            if let state = swipe, state.row == index, state.offset != 0 {
                // The revealed strip, clipped to the card.
                let edge: HorizontalEdge = state.offset < 0 ? .trailing : .leading
                if let strip = strips[ObjectIdentifier(element.node)]?[edge], let target = stripNode(strip) {
                    let card = CGRect(x: profile.margin, y: element.frame.minY, width: frame.width - 2 * profile.margin, height: element.frame.height)
                    list.append(.save)
                    list.append(.clipRect(context.absoluteRect(card)))
                    target.paint(into: &list, context: context.child(at: target.presentedFrame))
                    list.append(.restore)
                }
            }
            if editingAccessories, element.kind == .row { paintEditAccessories(for: element, into: &list, context: context) }
            // iOS: a navigation link row shows a chevron at its trailing edge.
            if profile.linkChevron, element.kind == .row, element.node.layoutValue(for: NavigationLinkActivationKey.self) != nil {
                let size = PlatformMetrics.listLinkChevronSize
                let right = context.origin.x + element.contentFrame.maxX - PlatformMetrics.listLinkChevronTrailing
                let midY = context.origin.y + element.frame.midY
                var chevron = Path()
                chevron.move(to: CGPoint(x: right - size.width, y: midY - size.height / 2))
                chevron.addLine(to: CGPoint(x: right, y: midY))
                chevron.addLine(to: CGPoint(x: right - size.width, y: midY + size.height / 2))
                list.append(.strokePath(chevron, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round), environment._ink(PlatformMetrics.listLinkChevronAlpha)))
            }
        }
    }

    /// iOS edit mode (ios/list/editing): a red disc with a white minus at the row's leading edge
    /// when the row can be deleted, three grey lines at its trailing edge when it can be moved.
    private func paintEditAccessories(for element: Element, into list: inout DisplayList, context: PaintContext) {
        let midY = element.frame.midY
        if canDelete(element) {
            let size = PlatformMetrics.listEditCircleSize
            let disc = CGRect(x: profile.margin + PlatformMetrics.listEditCircleInset, y: midY - size / 2, width: size, height: size)
            list.append(.fillPath(Path(ellipseIn: context.absoluteRect(disc)), PlatformMetrics.listEditCircleFill))
            let minus = PlatformMetrics.listEditMinusSize
            list.append(.fillRect(context.absoluteRect(CGRect(x: disc.midX - minus.width / 2, y: disc.midY - minus.height / 2, width: minus.width, height: minus.height)), RGBA(r: 255, g: 255, b: 255)))
        }
        if canMove(element) {
            let line = PlatformMetrics.listEditGripLineSize
            let right = frame.width - profile.margin - PlatformMetrics.listEditGripTrailingInset
            for index in -1...1 {
                let y = midY + CGFloat(index) * PlatformMetrics.listEditGripPitch - line.height / 2
                list.append(.fillRect(context.absoluteRect(CGRect(x: right - line.width, y: y, width: line.width, height: line.height)), PlatformMetrics.listEditGripFill))
            }
        }
    }

    // MARK: Selection

    package func pressBegan() {}
    package func pressEnded(inside: Bool) {}

    // MARK: Reordering (onMove)

    /// The row a press started on, and how far it has been dragged along the list.
    private var pressedRow: Int?
    private var pressStart: CGPoint = .zero
    private var dragOffset: CGFloat = 0
    private var reordering = false

    // MARK: Swipe actions (swipeActions, the implicit Delete of onDelete on iOS)

    /// The row shifted sideways: its index, its offset (negative reveals the trailing edge) and
    /// whether the offset rests open at an edge.
    private struct Swipe {
        var row: Int
        var offset: CGFloat = 0
        var open = false
        var dragging = false
        var startOffset: CGFloat = 0
        /// The finger's distance from where it started plus the resting offset (unresisted).
        var travel: CGFloat = 0
    }
    private var swipe: Swipe?
    /// The mounted action strips per row (by the row node), per edge.
    private var strips: [ObjectIdentifier: [HorizontalEdge: TypedNode<AnyView>]] = [:]

    /// The action sets of a row: its `swipeActions` and, on iOS, a trailing Delete for a row of a
    /// `ForEach` with `onDelete` that declares no trailing actions itself.
    private func actionSets(for element: Element) -> [_SwipeActionSet] {
        guard element.kind == .row, environment.platformProfile.isIOS, !isEditing else { return [] }
        var sets = element.node.layoutValue(for: SwipeActionsKey.self)
        if !sets.contains(where: { $0.edge == .trailing }), canDelete(element), let owner = element.owner, let delete = owner._onDelete {
            let offset = element.offset
            sets.append(_SwipeActionSet(edge: .trailing, allowsFullSwipe: true, content: AnyView(Button("Delete", role: .destructive) { delete(IndexSet(integer: offset)) })))
        }
        return sets
    }

    /// Mounts or updates the strip of an edge's actions for a row; nil when it has none.
    private func strip(for element: Element, edge: HorizontalEdge) -> TypedNode<AnyView>? {
        let sets = actionSets(for: element).filter { $0.edge == edge }
        let key = ObjectIdentifier(element.node)
        guard !sets.isEmpty else {
            if let node = strips[key]?[edge] { node.unmount(); strips[key]?[edge] = nil }
            return nil
        }
        let view = AnyView(HStack(spacing: 0) { ForEach(Array(sets.enumerated()), id: \.offset) { $0.element.content } }
            .buttonStyle(_SwipeActionButtonStyle()).font(.body))
        if let node = strips[key]?[edge] {
            node.update(view: view, environment: environment, force: false)
            return node
        }
        let node = AnyView._makeNode(_NodeContext(view: view, parent: self, environment: environment))
        strips[key, default: [:]][edge] = node
        return node
    }

    private func stripNode(_ node: TypedNode<AnyView>) -> ViewNode? { node.layoutChildren.first }

    /// Lays the strips out beside the row content, shifted with it.
    private func layoutStrips() {
        var live: Set<ObjectIdentifier> = []
        for (index, element) in elements.enumerated() where element.kind == .row {
            let shift = swipe?.row == index ? swipe!.offset : 0
            live.insert(ObjectIdentifier(element.node))
            for edge in [HorizontalEdge.leading, .trailing] {
                guard let strip = strip(for: element, edge: edge), let target = stripNode(strip) else { continue }
                let size = target.sizeThatFits(ProposedViewSize(width: nil, height: element.frame.height))
                let cardLeft = profile.margin, cardRight = frame.width - profile.margin
                let x = edge == .trailing ? cardRight + shift : cardLeft + shift - size.width
                target.place(at: CGPoint(x: x, y: element.frame.minY), anchor: .topLeading, proposal: ProposedViewSize(width: size.width, height: element.frame.height), by: self)
                // The first declared action is the outermost: a trailing strip's cells run from
                // its far edge back, so they are placed again in reverse order.
                if edge == .trailing {
                    // The cells: each button's outermost ancestor below the stack, in declaration order.
                    var stack: ViewNode = target
                    while let modifier = stack as? any _UnaryLayoutModifier { stack = modifier.modifiedContent }
                    var cells: [ViewNode] = []
                    for button in stack.descendants(where: { $0 is ButtonHostNode }) {
                        // The outermost layout node below the first container on the way up.
                        var cell: ViewNode = button, node: ViewNode = button
                        while let parent = node.parent, parent !== stack, parent !== target {
                            if parent.isLayoutNode {
                                if parent.layoutChildren.count > 1 { break }
                                cell = parent
                            }
                            node = parent
                        }
                        if !cells.contains(where: { $0 === cell }) { cells.append(cell) }
                    }
                    var cellX = target.frame.width
                    for cell in cells {
                        cellX -= cell.frame.width
                        cell.moveFrame(toOrigin: CGPoint(x: cellX, y: cell.frame.minY))
                    }
                }
            }
        }
        for (key, byEdge) in strips where !live.contains(key) {
            for node in byEdge.values { node.unmount() }
            strips[key] = nil
        }
    }

    /// The width of a row's strip at an edge (0 without one).
    private func stripWidth(_ index: Int, _ edge: HorizontalEdge) -> CGFloat {
        guard index < elements.count, let strip = strips[ObjectIdentifier(elements[index].node)]?[edge], let target = stripNode(strip) else { return 0 }
        return target.frame.width
    }

    private func closeSwipe() {
        guard swipe != nil else { return }
        swipe = nil
        runtime.requestFullLayout()
    }

    /// Runs the outermost action of the strip at `edge` of the swiped row (a full swipe).
    private func performFirstAction(row: Int, edge: HorizontalEdge) {
        guard let strip = strips[ObjectIdentifier(elements[row].node)]?[edge] else { return }
        guard let button = strip.descendants(where: { $0 is ButtonHostNode }).first as? ButtonHostNode else { return }
        button.pressBegan()
        button.pressEnded(inside: true)
    }

    package func pressBegan(at point: CGPoint) {
        pressedRow = elements.firstIndex { $0.kind == .row && $0.frame.contains(point) }
        pressStart = point
        dragOffset = 0
        reordering = false
    }

    /// A row whose `ForEach` has `onMove` follows a vertical drag (macOS: any press on it; iOS: a
    /// press on its reorder grip in edit mode).
    package var dragAxes: Axis.Set {
        guard let index = pressedRow else { return [] }
        if swipe != nil || !actionSets(for: elements[index]).isEmpty { return canMove(elements[index]) && isEditing ? [.horizontal, .vertical] : .horizontal }
        guard canMove(elements[index]) else { return [] }
        if environment.platformProfile.isIOS {
            // Read through the profile: presses arrive outside a layout pass's metrics selection.
            let grip = elements[index].frame.maxX - environment.platformProfile.metrics.listEditGripWidth
            return isEditing && pressStart.x >= grip ? .vertical : []
        }
        return .vertical
    }

    package func pressMoved(to point: CGPoint) {
        guard let index = pressedRow else { return }
        let dx = point.x - pressStart.x, dy = point.y - pressStart.y
        let slop = environment.platformProfile.metrics.panSlop
        // A sideways drag on a row with actions swipes it; a drag along the list reorders.
        if !reordering, !actionSets(for: elements[index]).isEmpty, swipe?.dragging == true || (abs(dx) >= slop && abs(dx) > abs(dy)) {
            var state = swipe?.row == index ? swipe! : Swipe(row: index)
            if !state.dragging { state.dragging = true; state.startOffset = state.offset }
            let trailing = stripWidth(index, .trailing), leading = stripWidth(index, .leading)
            var offset = state.startOffset + dx
            state.travel = offset
            // Past the strip the row follows the finger at a third of its distance; without a
            // strip on that side it stays put.
            if offset < -trailing { offset = trailing > 0 ? -trailing + (offset + trailing) / 3 : 0 }
            if offset > leading { offset = leading > 0 ? leading + (offset - leading) / 3 : 0 }
            state.offset = offset
            swipe = state
            runtime.requestFullLayout()
            return
        }
        guard canMove(elements[index]), swipe?.dragging != true else { return }
        dragOffset = dy
        if abs(dragOffset) >= slop { reordering = true }
        if reordering { runtime.setNeedsDisplay() }
    }

    /// Ends a swipe: past `swipeFullFraction` of the row it performs the first action of that
    /// edge (when allowed), past half the strip it rests open, else it closes.
    private func finishSwipe(at point: CGPoint) {
        guard var state = swipe else { return }
        state.dragging = false
        let row = state.row
        let edge: HorizontalEdge = state.offset < 0 ? .trailing : .leading
        let width = stripWidth(row, edge)
        let sets = actionSets(for: elements[row]).filter { $0.edge == edge }
        let full = sets.contains { $0.allowsFullSwipe } && abs(state.travel) >= elements[row].frame.width * environment.platformProfile.metrics.swipeFullFraction
        if full {
            swipe = nil
            performFirstAction(row: row, edge: edge)
            runtime.requestFullLayout()
            return
        }
        if width > 0, abs(state.offset) >= width / 2 {
            state.offset = edge == .trailing ? -width : width
            state.open = true
            swipe = state
        } else {
            swipe = nil
        }
        runtime.requestFullLayout()
    }

    /// iOS edit mode with rows that can be deleted or moved shows the accessories.
    private var editingAccessories: Bool { isEditing && PlatformMetrics.listEditLeadingInset > 0 }

    private func canMove(_ element: Element) -> Bool {
        element.owner?._onMove != nil && !element.node.layoutValue(for: MoveDisabledKey.self)
    }

    private func canDelete(_ element: Element) -> Bool {
        element.owner?._onDelete != nil && !element.node.layoutValue(for: DeleteDisabledKey.self)
    }

    package var isEditing: Bool { environment.editMode?.wrappedValue.isEditing ?? false }

    /// Ends a reorder: the row lands before the row whose top the drop point passed, among the
    /// rows of the same `ForEach`.
    private func finishReorder(at point: CGPoint) {
        defer { pressedRow = nil; reordering = false; dragOffset = 0 }
        guard let index = pressedRow, let owner = elements[index].owner, let move = owner._onMove else { return }
        let siblings = elements.enumerated().filter { $0.element.kind == .row && $0.element.owner === owner }
        let from = elements[index].offset
        var destination = siblings.count
        for (_, element) in siblings where point.y < element.frame.midY {
            destination = element.offset
            break
        }
        guard destination != from && destination != from + 1 else { runtime.setNeedsDisplay(); return }
        move(IndexSet(integer: from), destination)
        runtime.setNeedsDisplay()
    }

    package func pressEnded(inside: Bool, at point: CGPoint) {
        if reordering { finishReorder(at: point); return }
        if swipe?.dragging == true { pressedRow = nil; finishSwipe(at: point); return }
        pressedRow = nil
        // An open row: a press on its strip presses that button, anywhere else closes it.
        if let state = swipe, state.open {
            let element = elements[state.row]
            let edge: HorizontalEdge = state.offset < 0 ? .trailing : .leading
            if let strip = strips[ObjectIdentifier(element.node)]?[edge], let target = stripNode(strip), target.frame.contains(point),
               let hit = target.hitTest(CGPoint(x: point.x - target.frame.minX, y: point.y - target.frame.minY), where: { $0 is _Interactive }) as? (ViewNode & _Interactive) {
                hit.pressBegan()
                hit.pressEnded(inside: true)
            }
            closeSwipe()
            return
        }
        guard inside, let element = elements.first(where: { $0.kind == .row && $0.frame.contains(point) }) else { return }
        // iOS edit mode: a press on the delete circle deletes the row.
        if isEditing, environment.platformProfile.isIOS, canDelete(element),
           point.x < element.frame.minX + profile.margin + environment.platformProfile.metrics.listEditLeadingInset {
            element.owner?._onDelete?(IndexSet(integer: element.offset))
            runtime.setNeedsDisplay()
            return
        }
        // A row that is a `NavigationLink` pushes; a selectable row toggles its selection.
        element.node.layoutValue(for: NavigationLinkActivationKey.self)?.run()
        if let selection = view.selection, let id = element.id {
            selection.toggle(id)
            runtime.setNeedsDisplay()
        }
    }

    package var semantics: SemanticsNode {
        var node = SemanticsNode(role: view.selection == nil ? .group : .list, label: "", frame: frameInRoot, identifier: identifier)
        node.isFocusable = view.selection != nil
        return node
    }
    package var exposesChildren: Bool { true }

    // MARK: Keyboard

    /// The row a Shift-extended range starts from (an index into the selectable rows).
    private var selectionAnchor: Int?

    /// Up/Down move the selection to the previous/next row (from the last selected one; from the
    /// ends when nothing is selected), Home/End to the first/last; Shift extends a range from the
    /// anchor row in a multiple selection.
    package func handleKey(_ press: KeyPress) -> Bool {
        guard let selection = view.selection, press.modifiers.shortcutModifiers.isSubset(of: [.shift]) else { return false }
        // Delete removes the selected rows through their `ForEach`'s `onDelete`.
        if press.key == .delete || press.key == .deleteForward {
            var deleted = false
            for owner in elements.compactMap(\.owner) where owner._onDelete != nil {
                let offsets = elements.filter { $0.kind == .row && $0.owner === owner && isSelected($0) && canDelete($0) }.map(\.offset)
                if !offsets.isEmpty { owner._onDelete?(IndexSet(offsets)); deleted = true }
            }
            if deleted { runtime.setNeedsDisplay() }
            return deleted
        }
        let rows = elements.filter { $0.kind == .row && $0.id != nil }
        guard !rows.isEmpty else { return false }
        let current = rows.lastIndex { selection.isSelected($0.id!) }
        let target: Int
        switch press.key {
        case .downArrow: target = current.map { min($0 + 1, rows.count - 1) } ?? 0
        case .upArrow: target = current.map { max($0 - 1, 0) } ?? rows.count - 1
        case .home: target = 0
        case .end: target = rows.count - 1
        default: return false
        }
        if press.modifiers.contains(.shift), let anchor = selectionAnchor ?? current {
            selection.select(rows[min(anchor, target)...max(anchor, target)].map { $0.id! })
        } else {
            selectionAnchor = target
            selection.select([rows[target].id!])
        }
        runtime.setNeedsDisplay()
        return true
    }
}

/// How a container styles the headers and footers of its sections.
package struct _SectionStyling: Equatable {
    package var font: Font
    package var foreground: Color
    package var footerFont: Font? = nil
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
    /// The `ForEach`'s edit actions (`onDelete`, `onMove`), by row offset.
    var _onDelete: ((IndexSet) -> Void)? { get }
    var _onMove: ((IndexSet, Int) -> Void)? { get }
}

/// `swipeActions`: transparent to layout; adds its set to the ones below it in the chain.
@MainActor
package final class SwipeActionsNode<Content: View>: UnaryLayoutModifierNode<Content, _SwipeActionsModifier> {
    override package func layoutValue<K: LayoutValueKey>(for key: K.Type) -> K.Value {
        if key == SwipeActionsKey.self, let sets = (super.layoutValue(for: SwipeActionsKey.self) + [modifier.set]) as? K.Value { return sets }
        return super.layoutValue(for: key)
    }
}
