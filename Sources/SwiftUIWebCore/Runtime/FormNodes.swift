// Form runtime: the labelled control row (label + gap + control, or label leading and control
// trailing in a grouped form) and the grouped form's cards (Docs/elements/Form.md).

@MainActor
package final class FormLabeledRowNode: LayoutNode<_FormLabeledRow> {
    package private(set) var label: TypedNode<AnyView>?
    package private(set) var content: TypedNode<AnyView>!

    package init(_ context: _NodeContext<_FormLabeledRow>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        mount(force: true)
    }

    private func mount(force: Bool) {
        if let labelView = view.label {
            if let label {
                label.update(view: labelView, environment: environment, force: force)
            } else {
                label = AnyView._makeNode(_NodeContext(view: labelView, parent: self, environment: environment))
            }
        } else {
            label?.unmount()
            label = nil
        }
        if let content {
            content.update(view: view.content, environment: environment, force: force)
        } else {
            content = AnyView._makeNode(_NodeContext(view: view.content, parent: self, environment: environment))
        }
    }

    override package func update(view: _FormLabeledRow, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        mount(force: force)
    }

    private var labelTarget: ViewNode? { label?.layoutChildren.first }
    private var contentTarget: ViewNode? { content.layoutChildren.first }

    private struct Plan {
        var labelSize: CGSize
        var contentSize: CGSize
        var contentProposal: ProposedViewSize
        var labelOrigin: CGPoint
        var contentOrigin: CGPoint
        var size: CGSize
    }

    private func plan(_ proposal: ProposedViewSize) -> Plan {
        let gap = PlatformMetrics.controlLabelSpacing
        let labelSize = labelTarget?.sizeThatFits(.unspecified) ?? .zero
        let labelWidth = labelTarget == nil ? 0 : labelSize.width + gap
        let contentProposal = ProposedViewSize(width: proposal.width.map { max(0, $0 - labelWidth) }, height: nil)
        let contentSize = contentTarget?.sizeThatFits(contentProposal) ?? .zero
        switch view.mode {
        case .centered:
            let height = max(labelSize.height, contentSize.height)
            return Plan(labelSize: labelSize, contentSize: contentSize, contentProposal: contentProposal,
                        labelOrigin: CGPoint(x: 0, y: (height - labelSize.height) / 2),
                        contentOrigin: CGPoint(x: labelWidth, y: (height - contentSize.height) / 2),
                        size: CGSize(width: labelWidth + contentSize.width, height: height))
        case .firstTextBaseline:
            let labelBaseline = labelTarget?.dimensions(in: .unspecified)[VerticalAlignment.firstTextBaseline] ?? labelSize.height
            let contentBaseline = contentTarget?.dimensions(in: contentProposal)[VerticalAlignment.firstTextBaseline] ?? contentSize.height
            let labelY = max(0, contentBaseline - labelBaseline)
            let contentY = max(0, labelBaseline - contentBaseline)
            let height = max(labelY + labelSize.height, contentY + contentSize.height)
            return Plan(labelSize: labelSize, contentSize: contentSize, contentProposal: contentProposal,
                        labelOrigin: CGPoint(x: 0, y: labelY), contentOrigin: CGPoint(x: labelWidth, y: contentY),
                        size: CGSize(width: labelWidth + contentSize.width, height: height))
        case .sliderColumns:
            return Plan(labelSize: labelSize, contentSize: contentSize, contentProposal: contentProposal,
                        labelOrigin: CGPoint(x: 0, y: PlatformMetrics.formSliderLabelTop),
                        contentOrigin: CGPoint(x: labelWidth, y: PlatformMetrics.formSliderTrackTop),
                        size: CGSize(width: labelWidth + contentSize.width, height: PlatformMetrics.formSliderRowHeight))
        case .grouped:
            // The row is as tall as its label; the control is centred on it (a switch overflows).
            let width = proposal.width ?? labelWidth + contentSize.width
            let height = labelTarget == nil ? contentSize.height : labelSize.height
            return Plan(labelSize: labelSize, contentSize: contentSize, contentProposal: contentProposal,
                        labelOrigin: CGPoint(x: 0, y: (height - labelSize.height) / 2),
                        contentOrigin: CGPoint(x: width - contentSize.width, y: (height - contentSize.height) / 2),
                        size: CGSize(width: width, height: height))
        }
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize { plan(proposal).size }

    override package func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        let plan = plan(proposal)
        var dims = ViewDimensions(size: plan.size)
        dims.explicit[HorizontalAlignment._formControlColumn.key] = view.mode == .grouped ? 0 : plan.contentOrigin.x
        if let baseline = labelTarget?.dimensions(in: .unspecified)[explicit: VerticalAlignment.firstTextBaseline] ?? labelTarget.map({ _ in plan.labelSize.height }) {
            dims.explicit[VerticalAlignment.firstTextBaseline.key] = plan.labelOrigin.y + baseline
        }
        return dims
    }

    private func snap(_ value: CGFloat) -> CGFloat { (value * 2).rounded(.toNearestOrAwayFromZero) / 2 }

    override package func layoutContents(proposal: ProposedViewSize) {
        let plan = plan(proposal)
        let root = frameInRoot.origin
        func aligned(_ origin: CGPoint) -> CGPoint {
            guard view.mode == .centered else { return origin }
            return CGPoint(x: snap(root.x + origin.x) - root.x, y: snap(root.y + origin.y) - root.y)
        }
        labelTarget?.place(at: aligned(plan.labelOrigin), anchor: .topLeading, proposal: ProposedViewSize(plan.labelSize), by: self)
        contentTarget?.place(at: aligned(plan.contentOrigin), anchor: .topLeading, proposal: plan.contentProposal, by: self)
    }

    override package var paintedChildren: [ViewNode] { [labelTarget, contentTarget].compactMap { $0 } }
    override package var structuralChildren: [ViewNode] { [label as ViewNode?, content].compactMap { $0 } }
    /// The control decides the row's spacing to its neighbours.
    override package var layoutSpacing: ViewSpacing { contentTarget?.layoutSpacing ?? ViewSpacing() }
    override package var nodeDescription: String { "FormRow" }

    override package func unmount() {
        label?.unmount()
        content.unmount()
        super.unmount()
    }
}

// MARK: - Grouped cards

@MainActor
package final class FormGroupedNode: LayoutNode<_FormGroupedContent> {
    package private(set) var content: TypedNode<AnyView>!

    package struct Card {
        package var header: ViewNode?
        package var rows: [ViewNode]
        package var footer: ViewNode?
        package var frame: CGRect = .zero
        package var rowFrames: [CGRect] = []
    }

    package private(set) var cards: [Card] = []

    package init(_ context: _NodeContext<_FormGroupedContent>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        content = AnyView._makeNode(_NodeContext(view: context.view.content, parent: self, environment: environment))
    }

    override package func update(view: _FormGroupedContent, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        content.update(view: view.content, environment: environment, force: force)
    }

    /// Sections become cards; loose rows share one card.
    private func collect() -> [Card] {
        var cards: [Card] = []
        var loose: [ViewNode] = []
        func flushLoose() {
            if !loose.isEmpty { cards.append(Card(header: nil, rows: loose, footer: nil)); loose = [] }
        }
        func walk(_ node: ViewNode) {
            if let section = node as? any _SectionNodeProviding {
                flushLoose()
                cards.append(Card(header: section._headerNode.layoutChildren.first, rows: section._contentNode.layoutChildren,
                                  footer: section._footerNode.layoutChildren.first))
                return
            }
            if node.isLayoutNode { loose.append(node); return }
            for structural in node.structuralChildren { walk(structural) }
        }
        walk(content)
        flushLoose()
        return cards
    }

    private struct Plan {
        var cards: [Card]
        var size: CGSize
    }

    private func plan(width: CGFloat) -> Plan {
        var cards = collect()
        var y: CGFloat = 0
        let pad = PlatformMetrics.formGroupedRowPadding
        for index in cards.indices {
            if index > 0 { y += PlatformMetrics.formGroupedSectionSpacing }
            if let header = cards[index].header {
                let size = header.sizeThatFits(ProposedViewSize(width: width - 2 * pad, height: nil))
                y += size.height + PlatformMetrics.formGroupedHeaderSpacing
            }
            let top = y
            var rowFrames: [CGRect] = []
            for (rowIndex, row) in cards[index].rows.enumerated() {
                if rowIndex > 0 { y += PlatformMetrics.formGroupedSeparatorHeight }
                let size = row.sizeThatFits(ProposedViewSize(width: width - 2 * pad, height: nil))
                let height = max(PlatformMetrics.formGroupedRowMinimumHeight, size.height + 2 * pad)
                rowFrames.append(CGRect(x: 0, y: y, width: width, height: height))
                y += height
            }
            cards[index].rowFrames = rowFrames
            cards[index].frame = CGRect(x: 0, y: top, width: width, height: y - top)
            if let footer = cards[index].footer {
                let size = footer.sizeThatFits(ProposedViewSize(width: width - 2 * pad, height: nil))
                y += PlatformMetrics.formGroupedHeaderSpacing + size.height
            }
        }
        return Plan(cards: cards, size: CGSize(width: width, height: y))
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? PlatformMetrics.listIdealWidth
        return plan(width: width).size
    }

    override package func layoutContents(proposal: ProposedViewSize) {
        let plan = plan(width: frame.width)
        cards = plan.cards
        let pad = PlatformMetrics.formGroupedRowPadding
        for card in cards {
            if let header = card.header {
                let size = header.sizeThatFits(ProposedViewSize(width: frame.width - 2 * pad, height: nil))
                header.place(at: CGPoint(x: pad, y: card.frame.minY - PlatformMetrics.formGroupedHeaderSpacing - size.height),
                             anchor: .topLeading, proposal: ProposedViewSize(size), by: self)
            }
            for (row, cell) in zip(card.rows, card.rowFrames) {
                let proposal = ProposedViewSize(width: cell.width - 2 * pad, height: nil)
                let size = row.sizeThatFits(proposal)
                row.place(at: CGPoint(x: pad, y: cell.midY - size.height / 2), anchor: .topLeading, proposal: proposal, by: self)
            }
            if let footer = card.footer {
                let size = footer.sizeThatFits(ProposedViewSize(width: frame.width - 2 * pad, height: nil))
                footer.place(at: CGPoint(x: pad, y: card.frame.maxY + PlatformMetrics.formGroupedHeaderSpacing),
                             anchor: .topLeading, proposal: ProposedViewSize(size), by: self)
            }
        }
    }

    override package var paintedChildren: [ViewNode] {
        cards.flatMap { [$0.header].compactMap { $0 } + $0.rows + [$0.footer].compactMap { $0 } }
    }
    override package var structuralChildren: [ViewNode] { [content] }
    override package var nodeDescription: String { "GroupedForm" }

    override package func paint(into list: inout DisplayList, context: PaintContext) {
        let pad = PlatformMetrics.formGroupedRowPadding
        for card in cards {
            list.append(.fillRRect(context.absoluteRect(card.frame), cornerRadius: PlatformMetrics.formGroupedCardCornerRadius,
                                   RGBA(red: 0, green: 0, blue: 0, alpha: PlatformMetrics.formGroupedCardFill)))
            for cell in card.rowFrames.dropLast() {
                let line = CGRect(x: cell.minX + pad, y: cell.maxY, width: cell.width - 2 * pad, height: PlatformMetrics.formGroupedSeparatorHeight)
                list.append(.fillRect(context.absoluteRect(line), RGBA(red: 0, green: 0, blue: 0, alpha: PlatformMetrics.formGroupedSeparatorAlpha)))
            }
        }
        for child in paintedChildren { child.paint(into: &list, context: context.child(at: child.presentedFrame)) }
    }
}
