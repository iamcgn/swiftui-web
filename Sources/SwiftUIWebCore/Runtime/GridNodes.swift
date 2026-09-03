// Grid runtime: rows of cells laid out on shared columns (Docs/elements/Grid.md).

/// A grid row: transparent for layout, its cells are its content's layout children.
@MainActor
package protocol _GridRowProviding: AnyObject {
    var _rowAlignment: VerticalAlignment? { get }
    var _cellNodes: [ViewNode] { get }
}

@MainActor
package final class GridRowNode<Content: View>: TypedNode<GridRow<Content>>, _GridRowProviding {
    package private(set) var child: TypedNode<Content>!

    init(_ context: _NodeContext<GridRow<Content>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        child = Content._makeNode(_NodeContext(view: context.view.content, parent: self, environment: context.environment))
    }

    override package func update(view: GridRow<Content>, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        child.update(view: view.content, environment: environment, force: force)
    }

    package var _rowAlignment: VerticalAlignment? { view.alignment }
    package var _cellNodes: [ViewNode] { child.layoutChildren }

    override package var structuralChildren: [ViewNode] { [child] }
    override package var layoutChildren: [ViewNode] { child.layoutChildren }
    override package var nodeDescription: String { "GridRow" }
}

@MainActor
package final class GridNode<Content: View>: LayoutNode<Grid<Content>> {
    package private(set) var child: TypedNode<Content>!

    package struct Cell {
        package let node: ViewNode
        package let column: Int
        package let span: Int
        package let ideal: CGSize
        package let flexibleWidth: Bool
        package let sizedHorizontally: Bool
        package let sizedVertically: Bool
        package var frame: CGRect = .zero
    }

    package struct Row {
        package var cells: [Cell]
        package let alignment: VerticalAlignment?
        package var y: CGFloat = 0
        package var height: CGFloat = 0
    }

    package private(set) var rows: [Row] = []

    package init(_ context: _NodeContext<Grid<Content>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        child = Content._makeNode(_NodeContext(view: context.view.content, parent: self, environment: context.environment))
    }

    override package func update(view: Grid<Content>, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        child.update(view: view.content, environment: environment, force: force)
    }

    // MARK: Collecting

    /// Rows of cells: a `GridRow`'s cells, or a lone layout child as a row spanning every column.
    private func collect() -> ([Row], columns: Int) {
        var rows: [Row] = []
        func makeCell(_ node: ViewNode, column: Int, span: Int) -> Cell {
            let unsized = node.layoutValue(for: GridCellUnsizedAxesKey.self)
            let ideal = node.sizeThatFits(.unspecified)
            let wide = node.sizeThatFits(ProposedViewSize(width: ideal.width + 1000, height: nil)).width
            return Cell(node: node, column: column, span: span, ideal: ideal, flexibleWidth: wide > ideal.width + 0.5,
                        sizedHorizontally: !unsized.contains(.horizontal), sizedVertically: !unsized.contains(.vertical))
        }
        func walk(_ node: ViewNode, wrap: (ViewNode) -> ViewNode) {
            if let row = node as? any _GridRowProviding {
                var cells: [Cell] = []
                var column = 0
                for cellNode in row._cellNodes.map(wrap) {
                    let span = cellNode.layoutValue(for: GridCellColumnsKey.self)
                    cells.append(makeCell(cellNode, column: column, span: span))
                    column += span
                }
                rows.append(Row(cells: cells, alignment: row._rowAlignment))
                return
            }
            // A modifier on a row applies to each of its cells through the modifier's proxies.
            if let modifier = node as? any _UnaryLayoutModifier, modifier.modifiedContent.descendants(where: { $0 is any _GridRowProviding }).first != nil,
               !(modifier.modifiedContent.layoutChildren.count == 1 && modifier.modifiedContent.layoutChildren.first === modifier.modifiedContent) {
                var proxies: [ObjectIdentifier: ViewNode] = [:]
                for (target, proxy) in zip(modifier.targets, node.layoutChildren) { proxies[ObjectIdentifier(target)] = proxy }
                walk(modifier.modifiedContent) { wrap(proxies[ObjectIdentifier($0)] ?? $0) }
                return
            }
            if node.isLayoutNode {
                rows.append(Row(cells: [makeCell(wrap(node), column: 0, span: 0)], alignment: nil))   // span 0: every column
                return
            }
            for structural in node.structuralChildren { walk(structural, wrap: wrap) }
        }
        walk(child) { $0 }
        let columns = max(1, rows.map { $0.cells.reduce(0) { $0 + max($1.span, 1) } }.max() ?? 1)
        for index in rows.indices {
            for cellIndex in rows[index].cells.indices where rows[index].cells[cellIndex].span == 0 {
                let cell = rows[index].cells[cellIndex]
                rows[index].cells[cellIndex] = Cell(node: cell.node, column: 0, span: columns, ideal: cell.ideal, flexibleWidth: cell.flexibleWidth,
                                                    sizedHorizontally: cell.sizedHorizontally, sizedVertically: cell.sizedVertically)
            }
        }
        return (rows, columns)
    }

    // MARK: Planning

    private struct Plan {
        var rows: [Row]
        var columnWidths: [CGFloat]
        var columnGaps: [CGFloat]
        var size: CGSize
    }

    private func plan(proposal: ProposedViewSize) -> Plan {
        var (rows, columns) = collect()
        guard !rows.isEmpty else { return Plan(rows: [], columnWidths: [], columnGaps: [], size: .zero) }

        // Column gaps: explicit, else the widest horizontal spacing distance between neighbours.
        var gaps = Array(repeating: view.horizontalSpacing ?? PlatformMetrics.defaultSpacing, count: max(columns - 1, 0))
        if view.horizontalSpacing == nil {
            for row in rows {
                for (a, b) in zip(row.cells, row.cells.dropFirst()) where a.column + a.span - 1 < columns - 1 {
                    let gap = a.column + a.span - 1
                    gaps[gap] = max(gaps[gap], a.node.layoutSpacing.distance(to: b.node.layoutSpacing, along: .horizontal))
                }
            }
        }

        // Rigid column widths from single-column sized cells; flexibility from flexible ones.
        var rigid = Array(repeating: CGFloat(0), count: columns)
        var flexible = Array(repeating: false, count: columns)
        var flexibleSpans: [(column: Int, span: Int)] = []
        var rigidSpans: [(column: Int, span: Int, width: CGFloat)] = []
        for row in rows {
            for cell in row.cells where cell.sizedHorizontally {
                if cell.span == 1 {
                    if cell.flexibleWidth { flexible[cell.column] = true } else { rigid[cell.column] = max(rigid[cell.column], cell.ideal.width) }
                } else if cell.flexibleWidth {
                    flexibleSpans.append((cell.column, cell.span))
                } else {
                    rigidSpans.append((cell.column, cell.span, cell.ideal.width))
                }
            }
        }
        func gapsWithin(_ column: Int, _ span: Int) -> CGFloat { (column..<(column + span - 1)).reduce(0) { $0 + gaps[$1] } }
        var widths = rigid
        // A rigid spanning cell wider than its columns spreads the extra equally over them.
        for span in rigidSpans {
            let have = (span.column..<(span.column + span.span)).reduce(0) { $0 + widths[$1] } + gapsWithin(span.column, span.span)
            if span.width > have {
                let extra = (span.width - have) / CGFloat(span.span)
                for c in span.column..<(span.column + span.span) { widths[c] += extra }
            }
        }
        let totalGaps = gaps.reduce(0, +)
        if let available = proposal.width.flatMap({ $0.isFinite ? $0 - totalGaps : nil }) {
            let flexibleColumns = flexible.indices.filter { flexible[$0] }
            if !flexibleColumns.isEmpty {
                // Flexible columns share what the rigid ones leave, each keeping at least its rigid width.
                var remaining = available - widths.indices.filter { !flexible[$0] }.reduce(0) { $0 + widths[$1] }
                var left = flexibleColumns.count
                for c in flexibleColumns.sorted(by: { widths[$0] < widths[$1] }) {
                    let width = max(widths[c], remaining / CGFloat(left))
                    widths[c] = width
                    remaining -= width
                    left -= 1
                }
            } else if let span = flexibleSpans.first {
                // A flexible spanning cell fills the proposal; the extra spreads equally over its columns.
                let used = widths.reduce(0, +)
                if available > used {
                    let extra = (available - used) / CGFloat(span.span)
                    for c in span.column..<(span.column + span.span) { widths[c] += extra }
                }
            }
        }
        let columnX: [CGFloat] = widths.indices.map { c in (0..<c).reduce(0) { $0 + widths[$1] + gaps[$1] } }
        let totalWidth = widths.reduce(0, +) + totalGaps

        // Rows: cell sizes for their column widths, heights and vertical guides.
        var y: CGFloat = 0
        for index in rows.indices {
            let guide = (rows[index].alignment ?? view.alignment.vertical).key
            var rowGuide: CGFloat = 0
            var dims: [ViewDimensions] = []
            var cellWidths: [CGFloat] = []
            for cell in rows[index].cells {
                let width = (cell.column..<(cell.column + cell.span)).reduce(0) { $0 + widths[$1] } + gapsWithin(cell.column, cell.span)
                let d = cell.node.dimensions(in: ProposedViewSize(width: width, height: nil))
                dims.append(d)
                cellWidths.append(width)
                rowGuide = max(rowGuide, d[guide])
            }
            var height: CGFloat = 0
            for (cell, d) in zip(rows[index].cells, dims) {
                height = max(height, rowGuide - d[guide] + (cell.sizedVertically ? d.height : cell.ideal.height))
            }
            if index > 0 {
                let gap: CGFloat
                if let explicit = view.verticalSpacing {
                    gap = explicit
                } else {
                    // The widest spacing distance between the cells stacked in each column.
                    var widest: CGFloat = 0
                    for below in rows[index].cells {
                        for above in rows[index - 1].cells where above.column < below.column + below.span && below.column < above.column + above.span {
                            widest = max(widest, above.node.layoutSpacing.distance(to: below.node.layoutSpacing, along: .vertical))
                        }
                    }
                    gap = widest
                }
                y += gap
            }
            rows[index].y = y
            rows[index].height = height
            for (cellIndex, cell) in rows[index].cells.enumerated() {
                let d = dims[cellIndex]
                let cellWidth = cellWidths[cellIndex]
                let size = CGSize(width: d.width, height: cell.sizedVertically ? d.height : cell.ideal.height)
                let x: CGFloat, cellY: CGFloat
                if let anchor = cell.node.layoutValue(for: GridCellAnchorKey.self) {
                    x = columnX[cell.column] + (cellWidth - size.width) * anchor.x
                    cellY = y + (height - size.height) * anchor.y
                } else {
                    let horizontal = (cell.span == 1 ? columnAlignment(for: cell.column, in: rows) : nil) ?? view.alignment.horizontal
                    x = columnX[cell.column] + cellWidth * Self.fraction(of: horizontal) - d[horizontal.key]
                    cellY = y + rowGuide - d[guide]
                }
                rows[index].cells[cellIndex].frame = CGRect(x: x, y: cellY, width: size.width, height: size.height)
            }
            y += height
        }
        return Plan(rows: rows, columnWidths: widths, columnGaps: gaps, size: CGSize(width: totalWidth, height: y))
    }

    /// A `gridColumnAlignment` set on any cell of the column.
    private func columnAlignment(for column: Int, in rows: [Row]) -> HorizontalAlignment? {
        for row in rows {
            for cell in row.cells where cell.column == column && cell.span == 1 {
                if let alignment = cell.node.layoutValue(for: GridColumnAlignmentKey.self) { return alignment }
            }
        }
        return nil
    }

    /// Where a horizontal alignment sits across a width (leading 0, centre ½, trailing 1).
    private static func fraction(of alignment: HorizontalAlignment) -> CGFloat {
        if alignment == .leading { return 0 }
        if alignment == .trailing { return 1 }
        return 0.5
    }

    // MARK: Layout

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize { plan(proposal: proposal).size }

    override package func layoutContents(proposal: ProposedViewSize) {
        let plan = plan(proposal: ProposedViewSize(width: frame.width, height: proposal.height))
        rows = plan.rows
        for row in rows {
            for cell in row.cells {
                cell.node.place(at: cell.frame.origin, anchor: .topLeading, proposal: ProposedViewSize(cell.frame.size), by: self)
            }
        }
    }

    override package var paintedChildren: [ViewNode] { rows.flatMap { $0.cells.map(\.node) } }
    override package var structuralChildren: [ViewNode] { [child] }
    override package var nodeDescription: String { "Grid" }
}
