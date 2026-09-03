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
