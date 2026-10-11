/// A container view that arranges other views in a two dimensional layout.
///
/// Rules measured in `Docs/elements/Grid.md`: a column is as wide as its widest rigid cell,
/// columns with flexible cells share the proposed width equally, a flexible cell spanning
/// columns makes the grid fill its proposal and spreads the extra width equally over the spanned
/// columns, rows are spaced by their cells' spacing preferences (8.15 under text, 4.74 above it)
/// and columns 8 pt apart, and cells align by the grid's alignment, a column alignment or their
/// own anchor.
public struct Grid<Content: View>: View {
    package let alignment: Alignment
    package let horizontalSpacing: CGFloat?
    package let verticalSpacing: CGFloat?
    package let content: Content

    /// Creates a grid with the specified spacing, alignment, and child view.
    public init(alignment: Alignment = .center, horizontalSpacing: CGFloat? = nil, verticalSpacing: CGFloat? = nil,
                @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
        self.content = content()
    }

    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<Grid<Content>>) -> TypedNode<Grid<Content>> {
        GridNode(context)
    }
}

/// A horizontal row in a two dimensional grid container.
public struct GridRow<Content: View>: View {
    package let alignment: VerticalAlignment?
    package let content: Content

    /// Creates a horizontal row of child views with an optional alignment.
    public init(alignment: VerticalAlignment? = nil, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.content = content()
    }

    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<GridRow<Content>>) -> TypedNode<GridRow<Content>> {
        GridRowNode(context)
    }
}

// MARK: - Cell modifiers

package struct GridCellColumnsKey: LayoutValueKey {
    package static let defaultValue = 1
}

package struct GridColumnAlignmentKey: LayoutValueKey {
    package static let defaultValue: HorizontalAlignment? = nil
}

package struct GridCellAnchorKey: LayoutValueKey {
    package static let defaultValue: UnitPoint? = nil
}

package struct GridCellUnsizedAxesKey: LayoutValueKey {
    package static let defaultValue: Axis.Set = []
}

extension View {
    /// Tells a view that acts as a cell in a grid to span the specified number of columns.
    nonisolated public func gridCellColumns(_ count: Int) -> some View {
        layoutValue(key: GridCellColumnsKey.self, value: max(count, 1))
    }

    /// Overrides the default horizontal alignment of the grid column that the view appears in.
    nonisolated public func gridColumnAlignment(_ guide: HorizontalAlignment) -> some View {
        layoutValue(key: GridColumnAlignmentKey.self, value: guide)
    }

    /// Specifies a custom alignment anchor for a view that acts as a grid cell.
    nonisolated public func gridCellAnchor(_ anchor: UnitPoint) -> some View {
        layoutValue(key: GridCellAnchorKey.self, value: anchor)
    }

    /// Asks grid layouts not to offer the view extra size in the specified axes.
    nonisolated public func gridCellUnsizedAxes(_ axes: Axis.Set) -> some View {
        layoutValue(key: GridCellUnsizedAxesKey.self, value: axes)
    }
}

// MARK: - GridLayout

/// The grid as a `Layout` value (`AnyLayout(GridLayout())`, sw-custom-layout): the subviews are
/// the rows' cells, grouped by the `GridRow` each sits in; a subview outside a row is a row of
/// its own spanning every column, as in `Grid`.
public struct GridLayout: Layout {
    nonisolated public var alignment: Alignment
    nonisolated public var horizontalSpacing: CGFloat?
    nonisolated public var verticalSpacing: CGFloat?

    nonisolated public init(alignment: Alignment = .center, horizontalSpacing: CGFloat? = nil, verticalSpacing: CGFloat? = nil) {
        self.alignment = alignment
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }

    public static var layoutProperties: LayoutProperties { LayoutProperties() }

    /// The spacings animate; `nil` (the default spacing) is kept as it is.
    nonisolated public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(horizontalSpacing ?? -1, verticalSpacing ?? -1) }
        set {
            if horizontalSpacing != nil || newValue.first >= 0 { horizontalSpacing = newValue.first < 0 ? nil : newValue.first }
            if verticalSpacing != nil || newValue.second >= 0 { verticalSpacing = newValue.second < 0 ? nil : newValue.second }
        }
    }

    @MainActor private var planner: _GridPlanner { _GridPlanner(alignment: alignment, horizontalSpacing: horizontalSpacing, verticalSpacing: verticalSpacing) }

    /// Rows from the subviews: consecutive cells of one `GridRow` form a row, a cell outside any
    /// row a row of its own.
    @MainActor private func rows(_ subviews: Subviews) -> ([_GridPlanner.Row], Int) {
        var rows: [_GridPlanner.Row] = []
        var current: (row: ViewNode, cells: [_GridPlanner.Cell], column: Int)?
        func flush() {
            if let current { rows.append(_GridPlanner.Row(cells: current.cells, alignment: (current.row as? any _GridRowProviding)?._rowAlignment)) }
            current = nil
        }
        for subview in subviews {
            var ancestor = subview.node.parent
            var rowNode: ViewNode?
            while let node = ancestor, node !== subview.container {
                if node is any _GridRowProviding { rowNode = node; break }
                ancestor = node.parent
            }
            guard let rowNode else {
                flush()
                rows.append(_GridPlanner.Row(cells: [_GridPlanner.makeCell(subview.node, column: 0, span: 0)], alignment: nil))
                continue
            }
            if current?.row !== rowNode { flush(); current = (rowNode, [], 0) }
            let span = subview[GridCellColumnsKey.self]
            current!.cells.append(_GridPlanner.makeCell(subview.node, column: current!.column, span: span))
            current!.column += span
        }
        flush()
        let columns = _GridPlanner.resolveColumns(&rows)
        return (rows, columns)
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let (rows, columns) = rows(subviews)
        return planner.plan(rows: rows, columns: columns, proposal: proposal).size
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let (rows, columns) = rows(subviews)
        let plan = planner.plan(rows: rows, columns: columns, proposal: ProposedViewSize(width: bounds.width, height: proposal.height))
        var frames: [ObjectIdentifier: CGRect] = [:]
        for row in plan.rows { for cell in row.cells { frames[ObjectIdentifier(cell.node)] = cell.frame } }
        for subview in subviews {
            guard let frame = frames[ObjectIdentifier(subview.node)] else { continue }
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }
}
