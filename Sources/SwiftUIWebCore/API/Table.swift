// Table (Docs/elements/Table.md): the macOS table with a header row, columns (key-path, custom
// content, fixed and flexible widths, sortable), alternating row bands, a selection binding and
// a sort order binding.
#if os(WASI)
import WebFoundation   // never full Foundation on wasm: it links ICU (decisions 0006, 0017)
#else
import Foundation
#endif

/// A container that presents rows of data arranged in one or more columns.
public struct Table<Value: Identifiable, Data: RandomAccessCollection>: View where Data.Element == Value, Value.ID: Hashable {
    package let data: Data
    package let columns: [TableColumn<Value>]
    package let selection: _ListSelection?
    package let sortOrder: Binding<[KeyPathComparator<Value>]>?
    /// An outline table's children key path (`Table(_:children:columns:)`).
    package var children: KeyPath<Value, [Value]?>?
    /// The outline rows the user expanded.
    @State private var expanded: Set<AnyHashable> = []
    @Environment(\._tableStyle) private var tableStyle
    @Environment(\._tableHeadersVisibility) private var headers
    @Environment(\._alternatingRowBackgrounds) private var rowBackgrounds

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

    /// Creates a table from rows declared one by one (`TableRow`).
    public init(of valueType: Value.Type, @TableColumnBuilder<Value> columns: () -> [TableColumn<Value>], @TableRowBuilder<Value> rows: () -> [TableRow<Value>]) where Data == [Value] {
        data = rows().map(\.value)
        self.columns = columns()
        selection = nil
        sortOrder = nil
    }

    public init(of valueType: Value.Type, selection: Binding<Value.ID?>, @TableColumnBuilder<Value> columns: () -> [TableColumn<Value>], @TableRowBuilder<Value> rows: () -> [TableRow<Value>]) where Data == [Value] {
        data = rows().map(\.value)
        self.columns = columns()
        self.selection = _ListSelection(single: selection)
        sortOrder = nil
    }

    /// Creates an outline table: rows with children show a disclosure triangle, their children
    /// indented when expanded.
    public init(_ data: Data, children: KeyPath<Value, [Value]?>, @TableColumnBuilder<Value> columns: () -> [TableColumn<Value>]) {
        self.data = data
        self.columns = columns()
        selection = nil
        sortOrder = nil
        self.children = children
    }

    public init(_ data: Data, children: KeyPath<Value, [Value]?>, selection: Binding<Value.ID?>, @TableColumnBuilder<Value> columns: () -> [TableColumn<Value>]) {
        self.data = data
        self.columns = columns()
        self.selection = _ListSelection(single: selection)
        sortOrder = nil
        self.children = children
    }

    public init(_ data: Data, children: KeyPath<Value, [Value]?>, selection: Binding<Set<Value.ID>>, @TableColumnBuilder<Value> columns: () -> [TableColumn<Value>]) {
        self.data = data
        self.columns = columns()
        self.selection = _ListSelection(multiple: selection)
        sortOrder = nil
        self.children = children
    }

    /// The visible rows: every top-level row and, under the expanded ones, their children.
    private func rows() -> [_TableRow] {
        var result: [_TableRow] = []
        func add(_ row: Value, level: Int) {
            let kids = children.flatMap { row[keyPath: $0] }
            let id = AnyHashable(row.id)
            result.append(_TableRow(id: id, cells: columns.map { $0.content(row) }, level: level, hasChildren: kids != nil, isExpanded: expanded.contains(id)))
            if let kids, expanded.contains(id) { for kid in kids { add(kid, level: level + 1) } }
        }
        for row in data { add(row, level: 0) }
        return result
    }

    public var body: some View {
        // Read the bindings here so observation tracks the models they come from.
        let _: Void = selection?.read() ?? ()
        let order = sortOrder?.wrappedValue ?? []
        let rows = rows()
        let options = _TableOptions(bordered: tableStyle.bordered, hidesHeaders: headers == .hidden,
                                    bands: rowBackgrounds == .enabled || ((rowBackgrounds ?? .automatic) == .automatic && tableStyle.alternatesRowBackgrounds),
                                    outline: children != nil)
        let toggle: _TableToggle? = children == nil ? nil : _TableToggle { [self] id in if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) } }
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
        return _TableHost(rows: rows, columns: descriptors, selection: selection, sort: sort, options: options, toggle: toggle)
    }
}

/// A row of a table declared by hand (`Table(of:columns:rows:)`).
public struct TableRow<Value: Identifiable> {
    package let value: Value
    public init(_ value: Value) { self.value = value }
}

/// A result builder that creates table row content from closures.
@resultBuilder
public struct TableRowBuilder<Value: Identifiable> {
    public static func buildBlock(_ rows: [TableRow<Value>]...) -> [TableRow<Value>] { rows.flatMap { $0 } }
    public static func buildExpression(_ row: TableRow<Value>) -> [TableRow<Value>] { [row] }
    public static func buildExpression(_ rows: [TableRow<Value>]) -> [TableRow<Value>] { rows }
    public static func buildOptional(_ rows: [TableRow<Value>]?) -> [TableRow<Value>] { rows ?? [] }
    public static func buildEither(first: [TableRow<Value>]) -> [TableRow<Value>] { first }
    public static func buildEither(second: [TableRow<Value>]) -> [TableRow<Value>] { second }
    public static func buildArray(_ rows: [[TableRow<Value>]]) -> [TableRow<Value>] { rows.flatMap { $0 } }
}

/// Columns made from a collection (`TableColumnForEach(data) { TableColumn(...) }`).
public struct TableColumnForEach<Data: RandomAccessCollection, ID: Hashable, RowValue: Identifiable> {
    package let columns: [TableColumn<RowValue>]

    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @TableColumnBuilder<RowValue> content: (Data.Element) -> [TableColumn<RowValue>]) {
        columns = data.flatMap { content($0) }
    }

    public init(_ data: Data, @TableColumnBuilder<RowValue> content: (Data.Element) -> [TableColumn<RowValue>]) where Data.Element: Identifiable, ID == Data.Element.ID {
        columns = data.flatMap { content($0) }
    }
}

extension Group {
    /// A group of columns (a `Group` inside `TableColumnBuilder`).
    public init<R: Identifiable>(@TableColumnBuilder<R> content: () -> [TableColumn<R>]) where Content == [TableColumn<R>] {
        self.init(_content: content())
    }
}

// MARK: - Styles and modifiers

/// The look of a table: the inset style with its bands, or the bordered one.
public struct TableStyle: Hashable, Sendable {
    package let bordered: Bool
    package let alternatesRowBackgrounds: Bool
    package init(bordered: Bool, alternatesRowBackgrounds: Bool) {
        self.bordered = bordered
        self.alternatesRowBackgrounds = alternatesRowBackgrounds
    }
    public static let automatic = TableStyle(bordered: false, alternatesRowBackgrounds: true)
    public static let inset = TableStyle(bordered: false, alternatesRowBackgrounds: true)
    public static let bordered = TableStyle(bordered: true, alternatesRowBackgrounds: true)
    public static func inset(alternatesRowBackgrounds: Bool) -> TableStyle { TableStyle(bordered: false, alternatesRowBackgrounds: alternatesRowBackgrounds) }
    public static func bordered(alternatesRowBackgrounds: Bool) -> TableStyle { TableStyle(bordered: true, alternatesRowBackgrounds: alternatesRowBackgrounds) }
}

package struct TableStyleKey: EnvironmentKey { package static let defaultValue = TableStyle.automatic }
package struct TableHeadersKey: EnvironmentKey { package static let defaultValue = Visibility.automatic }

extension EnvironmentValues {
    package var _tableStyle: TableStyle {
        get { self[TableStyleKey.self] }
        set { self[TableStyleKey.self] = newValue }
    }
    package var _tableHeadersVisibility: Visibility {
        get { self[TableHeadersKey.self] }
        set { self[TableHeadersKey.self] = newValue }
    }
}

extension View {
    /// Sets the style for tables within this view (`.inset`, `.bordered`, with or without bands).
    nonisolated public func tableStyle(_ style: TableStyle) -> some View { environment(\._tableStyle, style) }
    /// Shows or hides the column headers of tables within this view.
    nonisolated public func tableColumnHeaders(_ visibility: Visibility) -> some View { environment(\._tableHeadersVisibility, visibility) }
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
    public static func buildExpression<D, I>(_ columns: TableColumnForEach<D, I, RowValue>) -> [TableColumn<RowValue>] { columns.columns }
    public static func buildExpression(_ group: Group<[TableColumn<RowValue>]>) -> [TableColumn<RowValue>] { group.content }
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

/// One row: its identity and a cell view per column; an outline row's level, whether it has
/// children and whether it is expanded.
public struct _TableRow {
    package let id: AnyHashable
    package let cells: [AnyView]
    package var level = 0
    package var hasChildren = false
    package var isExpanded = false
    package init(id: AnyHashable, cells: [AnyView], level: Int = 0, hasChildren: Bool = false, isExpanded: Bool = false) {
        self.id = id
        self.cells = cells
        self.level = level
        self.hasChildren = hasChildren
        self.isExpanded = isExpanded
    }
}

/// A table's looks: the bordered style, hidden headers, bands, outline rows.
public struct _TableOptions: Equatable, Sendable {
    package var bordered = false
    package var hidesHeaders = false
    package var bands = true
    package var outline = false
    package init(bordered: Bool = false, hidesHeaders: Bool = false, bands: Bool = true, outline: Bool = false) {
        self.bordered = bordered
        self.hidesHeaders = hidesHeaders
        self.bands = bands
        self.outline = outline
    }
}

/// Expanding or collapsing an outline row (a class so field reflection ignores it).
@MainActor
package final class _TableToggle {
    package let toggle: (AnyHashable) -> Void
    package init(toggle: @escaping (AnyHashable) -> Void) { self.toggle = toggle }
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
    package var options = _TableOptions()
    package var toggle: _TableToggle?

    package init(rows: [_TableRow], columns: [_TableColumnDescriptor], selection: _ListSelection?, sort: _TableSort?, options: _TableOptions = _TableOptions(), toggle: _TableToggle? = nil) {
        self.rows = rows
        self.columns = columns
        self.selection = selection
        self.sort = sort
        self.options = options
        self.toggle = toggle
    }

    public typealias Body = Never
    public static func _makeNode(_ context: _NodeContext<_TableHost>) -> TypedNode<_TableHost> {
        TableNode(context)
    }
}
