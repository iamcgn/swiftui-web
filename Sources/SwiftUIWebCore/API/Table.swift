// Table (Docs/elements/Table.md): the macOS table with a header row, columns (key-path, custom
// content, fixed and flexible widths, sortable), alternating row bands, a selection binding and
// a sort order binding.
#if os(WASI)
import FoundationEssentials   // never full Foundation on wasm: it links ICU (decision 0006)
#else
import Foundation
#endif

/// A container that presents rows of data arranged in one or more columns.
public struct Table<Value: Identifiable, Data: RandomAccessCollection>: View where Data.Element == Value, Value.ID: Hashable {
    package let data: Data
    package let columns: [TableColumn<Value>]
    package let selection: _ListSelection?
    package let sortOrder: Binding<[KeyPathComparator<Value>]>?

    /// Creates a table that computes its rows from a collection.
    public init(_ data: Data, @TableColumnBuilder<Value> columns: () -> [TableColumn<Value>]) {
        self.data = data
        self.columns = columns()
        selection = nil
        sortOrder = nil
    }

    /// Creates a table with a single selection.
    public init(_ data: Data, selection: Binding<Value.ID?>, @TableColumnBuilder<Value> columns: () -> [TableColumn<Value>]) {
        self.data = data
        self.columns = columns()
        self.selection = _ListSelection(single: selection)
        sortOrder = nil
    }

    /// Creates a table with a multiple selection.
    public init(_ data: Data, selection: Binding<Set<Value.ID>>, @TableColumnBuilder<Value> columns: () -> [TableColumn<Value>]) {
        self.data = data
        self.columns = columns()
        self.selection = _ListSelection(multiple: selection)
        sortOrder = nil
    }

    /// Creates a sortable table.
    public init(_ data: Data, sortOrder: Binding<[KeyPathComparator<Value>]>, @TableColumnBuilder<Value> columns: () -> [TableColumn<Value>]) {
        self.data = data
        self.columns = columns()
        selection = nil
        self.sortOrder = sortOrder
    }

    public init(_ data: Data, selection: Binding<Value.ID?>, sortOrder: Binding<[KeyPathComparator<Value>]>,
                @TableColumnBuilder<Value> columns: () -> [TableColumn<Value>]) {
        self.data = data
        self.columns = columns()
        self.selection = _ListSelection(single: selection)
        self.sortOrder = sortOrder
    }

    public init(_ data: Data, selection: Binding<Set<Value.ID>>, sortOrder: Binding<[KeyPathComparator<Value>]>,
                @TableColumnBuilder<Value> columns: () -> [TableColumn<Value>]) {
        self.data = data
        self.columns = columns()
        self.selection = _ListSelection(multiple: selection)
        self.sortOrder = sortOrder
    }

    public var body: some View {
        // Read the bindings here so observation tracks the models they come from.
        let _: Void = selection?.read() ?? ()
        let order = sortOrder?.wrappedValue ?? []
        let rows = data.map { row in _TableRow(id: AnyHashable(row.id), cells: columns.map { $0.content(row) }) }
        let descriptors = columns.enumerated().map { index, column -> _TableColumnDescriptor in
            let sorted = column.keyPath.flatMap { keyPath in order.first.flatMap { $0.keyPath == keyPath ? $0.order : nil } }
            return _TableColumnDescriptor(title: column.title, width: column.width, sortable: column.keyPath != nil, sortOrder: sorted, index: index)
        }
        let sort = sortOrder.map { binding in
            _TableSort { index in
                guard let keyPath = columns[index].keyPath, let make = columns[index].makeComparator else { return }
                let current = binding.wrappedValue.first
                let order: SortOrder = current?.keyPath == keyPath && current?.order == .forward ? .reverse : .forward
                binding.wrappedValue = [make(order)]
            }
        }
        return _TableHost(rows: rows, columns: descriptors, selection: selection, sort: sort)
    }
}

/// A column that displays a view for each row in a table.
public struct TableColumn<RowValue: Identifiable> {
    package var title: String
    package var content: (RowValue) -> AnyView
    package var width: _TableColumnWidth = .automatic
    /// The compared key path of a sortable column, and how to build its comparator.
    package var keyPath: PartialKeyPath<RowValue>?
    package var makeComparator: ((SortOrder) -> KeyPathComparator<RowValue>)?

    /// Creates a sortable column with the given content.
    public init<V: Comparable, Content: View>(_ titleKey: LocalizedStringKey, value: KeyPath<RowValue, V> & Sendable, @ViewBuilder content: @escaping (RowValue) -> Content) {
        title = Text(titleKey).resolvedString
        self.content = { AnyView(content($0)) }
        keyPath = value
        makeComparator = { KeyPathComparator(value, order: $0) }
    }

    @_disfavoredOverload
    public init<S: StringProtocol, V: Comparable, Content: View>(_ title: S, value: KeyPath<RowValue, V> & Sendable, @ViewBuilder content: @escaping (RowValue) -> Content) {
        self.title = String(title)
        self.content = { AnyView(content($0)) }
        keyPath = value
        makeComparator = { KeyPathComparator(value, order: $0) }
    }

    /// Creates a sortable column that shows a string key path's value.
    public init(_ titleKey: LocalizedStringKey, value: KeyPath<RowValue, String> & Sendable) {
        self.init(titleKey, value: value) { Text($0[keyPath: value]) }
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, value: KeyPath<RowValue, String> & Sendable) {
        self.init(title, value: value) { Text($0[keyPath: value]) }
    }

    /// Creates an unsortable column with the given content.
    public init<Content: View>(_ titleKey: LocalizedStringKey, @ViewBuilder content: @escaping (RowValue) -> Content) {
        title = Text(titleKey).resolvedString
        self.content = { AnyView(content($0)) }
    }

    @_disfavoredOverload
    public init<S: StringProtocol, Content: View>(_ title: S, @ViewBuilder content: @escaping (RowValue) -> Content) {
        self.title = String(title)
        self.content = { AnyView(content($0)) }
    }

    /// Creates a fixed-width column.
    public func width(_ width: CGFloat? = nil) -> TableColumn<RowValue> {
        var copy = self
        copy.width = width.map { .fixed($0) } ?? .automatic
        return copy
    }

    /// Creates a resizable column with the provided constraints.
    public func width(min: CGFloat? = nil, ideal: CGFloat? = nil, max: CGFloat? = nil) -> TableColumn<RowValue> {
        var copy = self
        copy.width = .flexible(min: min, ideal: ideal, max: max)
        return copy
    }
}

/// A result builder that creates table column content from closures.
@resultBuilder
public struct TableColumnBuilder<RowValue: Identifiable> {
    public static func buildBlock(_ columns: TableColumn<RowValue>...) -> [TableColumn<RowValue>] { columns }
    public static func buildBlock(_ columns: [TableColumn<RowValue>]...) -> [TableColumn<RowValue>] { columns.flatMap { $0 } }
    public static func buildExpression(_ column: TableColumn<RowValue>) -> [TableColumn<RowValue>] { [column] }
    public static func buildOptional(_ columns: [TableColumn<RowValue>]?) -> [TableColumn<RowValue>] { columns ?? [] }
    public static func buildEither(first: [TableColumn<RowValue>]) -> [TableColumn<RowValue>] { first }
    public static func buildEither(second: [TableColumn<RowValue>]) -> [TableColumn<RowValue>] { second }
}

/// A column's width: fixed (plus the cell padding), flexible within a range, or automatic.
public enum _TableColumnWidth: Equatable, Sendable {
    case automatic
    case fixed(CGFloat)
    case flexible(min: CGFloat?, ideal: CGFloat?, max: CGFloat?)
}

// MARK: - Primitives

/// One row: its identity and a cell view per column.
public struct _TableRow {
    package let id: AnyHashable
    package let cells: [AnyView]
    package init(id: AnyHashable, cells: [AnyView]) {
        self.id = id
        self.cells = cells
    }
}

/// A column without its row type: the title, width, and whether and how it is sorted.
public struct _TableColumnDescriptor: Equatable {
    package let title: String
    package let width: _TableColumnWidth
    package let sortable: Bool
    package let sortOrder: SortOrder?
    package let index: Int
    package init(title: String, width: _TableColumnWidth, sortable: Bool, sortOrder: SortOrder?, index: Int) {
        self.title = title
        self.width = width
        self.sortable = sortable
        self.sortOrder = sortOrder
        self.index = index
    }
}

/// Sorting by a column (a class so field reflection ignores it): toggles the column's order.
@MainActor
package final class _TableSort {
    package let sort: (Int) -> Void
    package init(sort: @escaping (Int) -> Void) { self.sort = sort }
}

/// The primitive (`TableNode`).
public struct _TableHost: View {
    package let rows: [_TableRow]
    package let columns: [_TableColumnDescriptor]
    package let selection: _ListSelection?
    package let sort: _TableSort?

    package init(rows: [_TableRow], columns: [_TableColumnDescriptor], selection: _ListSelection?, sort: _TableSort?) {
        self.rows = rows
        self.columns = columns
        self.selection = selection
        self.sort = sort
    }

    public typealias Body = Never
    public static func _makeNode(_ context: _NodeContext<_TableHost>) -> TypedNode<_TableHost> {
        TableNode(context)
    }
}
