// Table node (Docs/elements/Table.md): a 28 pt header (titles 10 pt into their columns, 1 pt
// dividers at the end of each 3 pt intercell gap, a bottom line), 24 pt rows from 33 with cells
// 8 pt in and 4 down, alternating rounded bands running to the bottom, the selection band, and
// sorting by header presses.
#if os(WASI)
import FoundationEssentials   // never full Foundation on wasm: it links ICU (decision 0006)
#else
import Foundation
#endif

@MainActor
private var nextTableIdentifier = 9_800_000

@MainActor
package final class TableNode: LayoutNode<_TableHost>, _Interactive, _KeyHandling {
    private let identifier: Int
    private struct CellKey: Hashable { let row: AnyHashable; let column: Int }
    private var cells: [CellKey: TypedNode<AnyView>] = [:]
    private var order: [CellKey] = []
    package private(set) var columnFrames: [CGRect] = []

    package init(_ context: _NodeContext<_TableHost>) {
        nextTableIdentifier += 1
        identifier = nextTableIdentifier
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        reconcile(force: false)
    }

    override package func update(view: _TableHost, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        reconcile(force: force)
    }

    /// One node per cell, reused by row identity and column.
    private func reconcile(force: Bool) {
        var kept: [CellKey: TypedNode<AnyView>] = [:]
        order = []
        for row in view.rows {
            for (column, cell) in row.cells.enumerated() {
                let key = CellKey(row: row.id, column: column)
                if let node = cells[key] {
                    node.update(view: cell, environment: environment, force: force)
                    kept[key] = node
                } else {
                    kept[key] = AnyView._makeNode(_NodeContext(view: cell, parent: self, environment: environment))
                }
                order.append(key)
            }
        }
        for (key, node) in cells where kept[key] == nil { node.unmount() }
        cells = kept
    }

    // MARK: Layout

    /// The content frames of the columns across `width` (NSTableView's layout, measured in
    /// `Docs/elements/Table.md`): every column has an ideal pitch (its SwiftUI width plus the 14 pt
    /// cell insets and the 3 pt intercell spacing; 117 for automatic columns) and the pitches fill
    /// the width less the 15 pt margins, the surplus shared equally by the growable columns in
    /// half points. Ideals that do not fit shrink by 15 pt in all, shared by the non-fixed columns,
    /// as long as the ideals themselves fit the width; otherwise the columns keep their ideals and
    /// overflow. A frame is a column's content: its pitch less the intercell spacing.
    package static func columnFrames(_ columns: [_TableColumnDescriptor], width: CGFloat) -> [CGRect] {
        let extra = PlatformMetrics.tableCellInset + PlatformMetrics.tableCellTrailingInset + PlatformMetrics.tableIntercellSpacing
        func half(_ value: CGFloat) -> CGFloat { (value * 2 + 0.5).rounded(.down) / 2 }
        struct Column { var ideal: CGFloat; var min: CGFloat; var max: CGFloat; var fixed: Bool }
        let specs = columns.map { column -> Column in
            switch column.width {
            case .fixed(let value): return Column(ideal: value + extra, min: value + extra, max: value + extra, fixed: true)
            case .flexible(let min, let ideal, let max):
                let idealPitch = (ideal ?? PlatformMetrics.tableColumnIdealWidth) + extra
                return Column(ideal: idealPitch, min: Swift.min((min ?? PlatformMetrics.tableColumnMinWidth) + extra, idealPitch),
                              max: Swift.max(max.map { $0 + extra } ?? .infinity, idealPitch), fixed: false)
            case .automatic:
                return Column(ideal: PlatformMetrics.tableColumnIdealWidth + extra, min: PlatformMetrics.tableColumnMinWidth + extra, max: .infinity, fixed: false)
            }
        }
        var pitches = specs.map(\.ideal)
        let idealTotal = pitches.reduce(0, +)
        let available = width - PlatformMetrics.tableLeadingMargin - PlatformMetrics.tableTrailingMargin
        if idealTotal <= available {
            var remaining = available - idealTotal
            var open = specs.indices.filter { specs[$0].max > specs[$0].ideal }
            while remaining > 0, !open.isEmpty {
                let share = half(remaining / CGFloat(open.count))
                var next: [Int] = []
                for index in open {
                    let room = specs[index].max - pitches[index]
                    let grow = Swift.min(share, room)
                    pitches[index] += grow
                    remaining -= grow
                    if pitches[index] < specs[index].max { next.append(index) }
                }
                if next.count == open.count, share <= 0 { break }
                open = next
            }
        } else if idealTotal <= width {
            let shrinkable = specs.indices.filter { !specs[$0].fixed }
            if !shrinkable.isEmpty {
                let share = half((PlatformMetrics.tableLeadingMargin + PlatformMetrics.tableTrailingMargin) / CGFloat(shrinkable.count))
                for index in shrinkable { pitches[index] = Swift.max(specs[index].min, pitches[index] - share) }
            }
        }
        var x = PlatformMetrics.tableLeadingMargin
        return pitches.map { pitch in
            defer { x += pitch }
            return CGRect(x: x, y: 0, width: pitch - PlatformMetrics.tableIntercellSpacing, height: PlatformMetrics.tableHeaderHeight)
        }
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        CGSize(width: proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? PlatformMetrics.tableIdealSize.width,
               height: proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? PlatformMetrics.tableIdealSize.height)
    }

    package func rowFrame(_ index: Int) -> CGRect {
        CGRect(x: 0, y: PlatformMetrics.tableHeaderHeight + PlatformMetrics.tableRowsTop + CGFloat(index) * PlatformMetrics.tableRowHeight,
               width: frame.width, height: PlatformMetrics.tableRowHeight)
    }

    override package func layoutContents(proposal: ProposedViewSize) {
        columnFrames = Self.columnFrames(view.columns, width: frame.width)
        for (rowIndex, row) in view.rows.enumerated() {
            let rowFrame = rowFrame(rowIndex)
            for column in row.cells.indices where column < columnFrames.count {
                guard let cell = cells[CellKey(row: row.id, column: column)] else { continue }
                let area = CGRect(x: columnFrames[column].minX + PlatformMetrics.tableCellInset, y: rowFrame.minY + PlatformMetrics.tableCellTop,
                                  width: max(0, columnFrames[column].width - PlatformMetrics.tableCellInset - PlatformMetrics.tableCellTrailingInset),
                                  height: rowFrame.height - 2 * PlatformMetrics.tableCellTop)
                for node in cell.layoutChildren {
                    let size = node.sizeThatFits(ProposedViewSize(area.size))
                    node.place(at: CGPoint(x: area.minX, y: area.minY), anchor: .topLeading, proposal: ProposedViewSize(width: area.width, height: size.height), by: self)
                }
            }
        }
    }

    override package var paintedChildren: [ViewNode] { order.compactMap { cells[$0] }.flatMap(\.layoutChildren) }
    override package var structuralChildren: [ViewNode] { order.compactMap { cells[$0] } }
    override package var nodeDescription: String { "Table" }

    override package func unmount() {
        for node in cells.values { node.unmount() }
        super.unmount()
    }

    // MARK: Painting

    override package func paint(into list: inout DisplayList, context: PaintContext) {
        let bounds = absoluteBounds(context)
        let ink = environment; let black = { (alpha: Double) in ink._ink(alpha) }
        list.append(.fillRect(bounds, environment._controlBackground))
        // Row bands: every second slot to the bottom, and the selected rows.
        let bandInset = PlatformMetrics.tableBandInset
        var index = 0
        while rowFrame(index).minY < frame.height {
            let row = context.absoluteRect(rowFrame(index)).insetBy(dx: bandInset, dy: 0)
            let selected = index < view.rows.count && (view.selection?.isSelected(view.rows[index].id) ?? false)
            if selected {
                list.append(.fillRRect(row, cornerRadius: PlatformMetrics.tableBandCornerRadius, black(PlatformMetrics.tableSelectionAlpha)))
            } else if index % 2 == 1 {
                list.append(.fillRRect(row, cornerRadius: PlatformMetrics.tableBandCornerRadius, black(PlatformMetrics.tableBandAlpha)))
            }
            index += 1
        }
        // Header: titles (bold when sorted, with a chevron), dividers and the bottom line. A header
        // cell runs to the next column; the last one ends with its content, and its divider is
        // drawn only when the intercell gap after it fits before the trailing margin.
        let headerLine = CGRect(x: bounds.minX, y: bounds.minY + PlatformMetrics.tableHeaderHeight - 1, width: bounds.width, height: 1)
        list.append(.fillRect(headerLine, black(PlatformMetrics.tableLineAlpha)))
        let primary = Color.primary.resolve(in: environment)
        let dividerY = bounds.minY + PlatformMetrics.tableDividerInset
        let dividerHeight = PlatformMetrics.tableHeaderHeight - 2 * PlatformMetrics.tableDividerInset
        for (index, (column, frame)) in zip(view.columns, columnFrames).enumerated() {
            let rect = context.absoluteRect(frame)
            let isLast = index == columnFrames.count - 1
            let cellEnd = isLast ? rect.maxX : rect.maxX + PlatformMetrics.tableIntercellSpacing
            let font = _fontFor(size: PlatformMetrics.buttonLabelSize, weight: column.sortOrder == nil ? .regular : .bold)
            let line = environment.platformProfile.systemFontMetrics(for: font).lineHeight
            list.withSavedState { list in
                list.append(.clipRect(CGRect(x: rect.minX, y: rect.minY, width: cellEnd - rect.minX, height: rect.height)))
                _drawText(column.title, font: font, lineTop: CGPoint(x: rect.minX + PlatformMetrics.tableHeaderTitleInset, y: rect.minY + (rect.height - line) / 2),
                          color: primary, into: &list)
            }
            if let order = column.sortOrder {
                let size = PlatformMetrics.tableChevronSize
                let right = cellEnd - PlatformMetrics.tableChevronTrailing
                let top = rect.minY + (rect.height - size.height) / 2
                var chevron = Path()
                let apexY = order == .forward ? top : top + size.height, baseY = order == .forward ? top + size.height : top
                chevron.move(to: CGPoint(x: right - size.width, y: baseY))
                chevron.addLine(to: CGPoint(x: right - size.width / 2, y: apexY))
                chevron.addLine(to: CGPoint(x: right, y: baseY))
                list.append(.strokePath(chevron, style: StrokeStyle(lineWidth: PlatformMetrics.tableChevronStroke, lineCap: .round, lineJoin: .round),
                                        Color.secondary.resolve(in: environment)))
                if index == 0 {
                    // The sorted first column also draws a divider inside its leading edge.
                    list.append(.fillRect(CGRect(x: rect.minX + 1, y: dividerY, width: 1, height: dividerHeight), black(PlatformMetrics.tableLineAlpha)))
                }
            }
            let trailingRoom = bounds.maxX - PlatformMetrics.tableTrailingMargin
            if !isLast || rect.maxX + PlatformMetrics.tableIntercellSpacing < trailingRoom {
                let divider = CGRect(x: cellEnd - 1, y: dividerY, width: 1, height: dividerHeight)
                if divider.maxX <= bounds.maxX {
                    list.append(.fillRect(divider, black(PlatformMetrics.tableLineAlpha)))
                }
            }
        }
        list.withSavedState { list in
            list.append(.clipRect(context.absoluteRect(CGRect(x: 0, y: PlatformMetrics.tableHeaderHeight, width: frame.width, height: max(0, frame.height - PlatformMetrics.tableHeaderHeight)))))
            paintChildren(into: &list, context: context)
        }
    }

    // MARK: Interaction

    package func pressBegan() {}
    package func pressEnded(inside: Bool) {}

    package func pressEnded(inside: Bool, at point: CGPoint) {
        guard inside, environment.isEnabled else { return }
        if point.y < PlatformMetrics.tableHeaderHeight {
            if let sort = view.sort, let index = columnFrames.firstIndex(where: { point.x >= $0.minX && point.x < $0.maxX + PlatformMetrics.tableIntercellSpacing }), view.columns[index].sortable {
                sort.sort(index)
                runtime.setNeedsDisplay()
            }
            return
        }
        guard let selection = view.selection else { return }
        for index in view.rows.indices where rowFrame(index).contains(point) {
            selection.toggle(view.rows[index].id)
            selectionAnchor = index
            runtime.focus(semanticsIdentifier: identifier)
            runtime.setNeedsDisplay()
            return
        }
    }

    private var selectionAnchor: Int?

    /// Up/Down move the selection, Shift extends it, Home/End jump.
    package func handleKey(_ press: KeyPress) -> Bool {
        guard let selection = view.selection, press.modifiers.shortcutModifiers.isSubset(of: [.shift]), !view.rows.isEmpty else { return false }
        let ids = view.rows.map(\.id)
        let current = ids.lastIndex { selection.isSelected($0) }
        let target: Int
        switch press.key {
        case .downArrow: target = current.map { min($0 + 1, ids.count - 1) } ?? 0
        case .upArrow: target = current.map { max($0 - 1, 0) } ?? ids.count - 1
        case .home: target = 0
        case .end: target = ids.count - 1
        default: return false
        }
        if press.modifiers.contains(.shift), let anchor = selectionAnchor ?? current {
            selectionAnchor = anchor
            selection.select(Array(ids[min(anchor, target)...max(anchor, target)]))
        } else {
            selectionAnchor = target
            selection.select([ids[target]])
        }
        runtime.setNeedsDisplay()
        return true
    }

    package var semantics: SemanticsNode {
        var node = SemanticsNode(role: view.selection == nil ? .group : .list, label: view.columns.map(\.title).joined(separator: ", "), frame: frameInRoot, identifier: identifier)
        node.isFocusable = view.selection != nil
        return node
    }
    package var exposesChildren: Bool { true }
}
