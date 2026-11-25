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
    package let columns: [_AnyTableColumn<Value>]
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
    public init(_ data: Data, @TableColumnBuilder<Value, Never> columns: () -> [_AnyTableColumn<Value>]) {
        self.data = data
        self.columns = columns()
        selection = nil
        sortOrder = nil
    }

    /// Creates a table with a single selection.
    public init(_ data: Data, selection: Binding<Value.ID?>, @TableColumnBuilder<Value, Never> columns: () -> [_AnyTableColumn<Value>]) {
        self.data = data
        self.columns = columns()
        self.selection = _ListSelection(single: selection)
        sortOrder = nil
    }

    /// Creates a table with a multiple selection.
    public init(_ data: Data, selection: Binding<Set<Value.ID>>, @TableColumnBuilder<Value, Never> columns: () -> [_AnyTableColumn<Value>]) {
        self.data = data
        self.columns = columns()
        self.selection = _ListSelection(multiple: selection)
        sortOrder = nil
    }

    /// Creates a sortable table.
    public init(_ data: Data, sortOrder: Binding<[KeyPathComparator<Value>]>, @TableColumnBuilder<Value, KeyPathComparator<Value>> columns: () -> [_AnyTableColumn<Value>]) {
        self.data = data
        self.columns = columns()
        selection = nil
        self.sortOrder = sortOrder
    }

    public init(_ data: Data, selection: Binding<Value.ID?>, sortOrder: Binding<[KeyPathComparator<Value>]>,
                @TableColumnBuilder<Value, KeyPathComparator<Value>> columns: () -> [_AnyTableColumn<Value>]) {
        self.data = data
        self.columns = columns()
        self.selection = _ListSelection(single: selection)
        self.sortOrder = sortOrder
    }

    public init(_ data: Data, selection: Binding<Set<Value.ID>>, sortOrder: Binding<[KeyPathComparator<Value>]>,
                @TableColumnBuilder<Value, KeyPathComparator<Value>> columns: () -> [_AnyTableColumn<Value>]) {
        self.data = data
        self.columns = columns()
        self.selection = _ListSelection(multiple: selection)
        self.sortOrder = sortOrder
    }

    /// Creates a table from rows declared one by one (`TableRow`).
    public init(of valueType: Value.Type, @TableColumnBuilder<Value, Never> columns: () -> [_AnyTableColumn<Value>], @TableRowBuilder<Value> rows: () -> [TableRow<Value>]) where Data == [Value] {
        data = rows().map(\.value)
        self.columns = columns()
        selection = nil
        sortOrder = nil
    }

    public init(of valueType: Value.Type, selection: Binding<Value.ID?>, @TableColumnBuilder<Value, Never> columns: () -> [_AnyTableColumn<Value>], @TableRowBuilder<Value> rows: () -> [TableRow<Value>]) where Data == [Value] {
        data = rows().map(\.value)
        self.columns = columns()
        self.selection = _ListSelection(single: selection)
        sortOrder = nil
    }

    public init(of valueType: Value.Type, selection: Binding<Set<Value.ID>>, @TableColumnBuilder<Value, Never> columns: () -> [_AnyTableColumn<Value>], @TableRowBuilder<Value> rows: () -> [TableRow<Value>]) where Data == [Value] {
        self.init(rows: rows(), columns: columns(), selection: _ListSelection(multiple: selection), sortOrder: nil)
    }

    /// A sortable table of declared rows. As with a collection, the rows show in the order given:
    /// sorting them by the binding's comparators is the caller's.
    public init(of valueType: Value.Type, sortOrder: Binding<[KeyPathComparator<Value>]>, @TableColumnBuilder<Value, KeyPathComparator<Value>> columns: () -> [_AnyTableColumn<Value>], @TableRowBuilder<Value> rows: () -> [TableRow<Value>]) where Data == [Value] {
        self.init(rows: rows(), columns: columns(), selection: nil, sortOrder: sortOrder)
    }

    public init(of valueType: Value.Type, selection: Binding<Value.ID?>, sortOrder: Binding<[KeyPathComparator<Value>]>, @TableColumnBuilder<Value, KeyPathComparator<Value>> columns: () -> [_AnyTableColumn<Value>], @TableRowBuilder<Value> rows: () -> [TableRow<Value>]) where Data == [Value] {
        self.init(rows: rows(), columns: columns(), selection: _ListSelection(single: selection), sortOrder: sortOrder)
    }

    public init(of valueType: Value.Type, selection: Binding<Set<Value.ID>>, sortOrder: Binding<[KeyPathComparator<Value>]>, @TableColumnBuilder<Value, KeyPathComparator<Value>> columns: () -> [_AnyTableColumn<Value>], @TableRowBuilder<Value> rows: () -> [TableRow<Value>]) where Data == [Value] {
        self.init(rows: rows(), columns: columns(), selection: _ListSelection(multiple: selection), sortOrder: sortOrder)
    }

    /// Creates a table from declared rows, the row type taken from the columns and rows.
    public init(@TableColumnBuilder<Value, Never> columns: () -> [_AnyTableColumn<Value>], @TableRowBuilder<Value> rows: () -> [TableRow<Value>]) where Data == [Value] {
        self.init(rows: rows(), columns: columns(), selection: nil, sortOrder: nil)
    }

    public init(selection: Binding<Value.ID?>, @TableColumnBuilder<Value, Never> columns: () -> [_AnyTableColumn<Value>], @TableRowBuilder<Value> rows: () -> [TableRow<Value>]) where Data == [Value] {
        self.init(rows: rows(), columns: columns(), selection: _ListSelection(single: selection), sortOrder: nil)
    }

    public init(selection: Binding<Set<Value.ID>>, @TableColumnBuilder<Value, Never> columns: () -> [_AnyTableColumn<Value>], @TableRowBuilder<Value> rows: () -> [TableRow<Value>]) where Data == [Value] {
        self.init(rows: rows(), columns: columns(), selection: _ListSelection(multiple: selection), sortOrder: nil)
    }

    public init(sortOrder: Binding<[KeyPathComparator<Value>]>, @TableColumnBuilder<Value, KeyPathComparator<Value>> columns: () -> [_AnyTableColumn<Value>], @TableRowBuilder<Value> rows: () -> [TableRow<Value>]) where Data == [Value] {
        self.init(rows: rows(), columns: columns(), selection: nil, sortOrder: sortOrder)
    }

    public init(selection: Binding<Value.ID?>, sortOrder: Binding<[KeyPathComparator<Value>]>, @TableColumnBuilder<Value, KeyPathComparator<Value>> columns: () -> [_AnyTableColumn<Value>], @TableRowBuilder<Value> rows: () -> [TableRow<Value>]) where Data == [Value] {
        self.init(rows: rows(), columns: columns(), selection: _ListSelection(single: selection), sortOrder: sortOrder)
    }

    public init(selection: Binding<Set<Value.ID>>, sortOrder: Binding<[KeyPathComparator<Value>]>, @TableColumnBuilder<Value, KeyPathComparator<Value>> columns: () -> [_AnyTableColumn<Value>], @TableRowBuilder<Value> rows: () -> [TableRow<Value>]) where Data == [Value] {
        self.init(rows: rows(), columns: columns(), selection: _ListSelection(multiple: selection), sortOrder: sortOrder)
    }

    private init(rows: [TableRow<Value>], columns: [_AnyTableColumn<Value>], selection: _ListSelection?, sortOrder: Binding<[KeyPathComparator<Value>]>?) where Data == [Value] {
        data = rows.map(\.value)
        self.columns = columns
        self.selection = selection
        self.sortOrder = sortOrder
    }

    /// Creates an outline table: rows with children show a disclosure triangle, their children
    /// indented when expanded.
    public init(_ data: Data, children: KeyPath<Value, [Value]?>, @TableColumnBuilder<Value, Never> columns: () -> [_AnyTableColumn<Value>]) {
        self.data = data
        self.columns = columns()
        selection = nil
        sortOrder = nil
        self.children = children
    }

    public init(_ data: Data, children: KeyPath<Value, [Value]?>, selection: Binding<Value.ID?>, @TableColumnBuilder<Value, Never> columns: () -> [_AnyTableColumn<Value>]) {
        self.data = data
        self.columns = columns()
        self.selection = _ListSelection(single: selection)
        sortOrder = nil
        self.children = children
    }

    public init(_ data: Data, children: KeyPath<Value, [Value]?>, selection: Binding<Set<Value.ID>>, @TableColumnBuilder<Value, Never> columns: () -> [_AnyTableColumn<Value>]) {
        self.data = data
        self.columns = columns()
        self.selection = _ListSelection(multiple: selection)
        sortOrder = nil
        self.children = children
    }

    /// The visible rows: every top-level row and, under the expanded ones, their children.
    private func rows() -> [_TableRow] {
        var result: [_TableRow] = []
        // No closures over `row`: the release wasm build's region isolation would count the
        // main-actor-isolated closures as sending the (non-Sendable) row.
        func add(_ row: Value, level: Int) {
            var kids: [Value]?
            if let children { kids = row[keyPath: children] }
            let id = AnyHashable(row.id)
            var cells: [AnyView] = []
            for column in columns { cells.append(column.content(row)) }
            result.append(_TableRow(id: id, cells: cells, level: level, hasChildren: kids != nil, isExpanded: expanded.contains(id)))
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

// MARK: - Column and row content

/// Content of a table's columns, typed by the row value and the sort comparator its columns
/// use. Primitive content (`Never`, a wrapper that forwards to its content) makes its columns
/// in `_makeContent`; other content describes them in `tableColumnBody`. `Table` itself still
/// takes the builder's `TableColumn` list.
@MainActor @preconcurrency
public protocol TableColumnContent<TableRowValue, TableColumnSortComparator> {
    associatedtype TableRowValue: Identifiable
    associatedtype TableColumnSortComparator
    associatedtype TableColumnBody: TableColumnContent
    @TableColumnBuilder<TableRowValue, TableColumnSortComparator> var tableColumnBody: TableColumnBody { get }
    nonisolated static func _makeContent(content: _GraphValue<Self>, inputs: _TableColumnInputs) -> _TableColumnOutputs
}

extension TableColumnContent {
    nonisolated public static func _makeContent(content: _GraphValue<Self>, inputs: _TableColumnInputs) -> _TableColumnOutputs {
        TableColumnBody._makeContent(content: content._map { value in
            // The body is main-actor isolated, like Apple's; content is made from a view body.
            nonisolated(unsafe) let value = value
            return _readOnMainActor { value.tableColumnBody }
        }, inputs: inputs)
    }
}

/// Content of a table's rows, typed by the row value.
@MainActor @preconcurrency
public protocol TableRowContent<TableRowValue> {
    associatedtype TableRowValue: Identifiable
    associatedtype TableRowBody: TableRowContent
    @TableRowBuilder<TableRowValue> var tableRowBody: TableRowBody { get }
}

extension Never: TableColumnContent, TableRowContent {
    public typealias TableRowValue = Never
    public typealias TableColumnSortComparator = Never
    public var tableColumnBody: Never { return fatalError() }
    public var tableRowBody: Never { return fatalError() }
    nonisolated public static func _makeContent(content: _GraphValue<Never>, inputs: _TableColumnInputs) -> _TableColumnOutputs {
        _TableColumnOutputs()
    }
}

/// A value of content being made, read when its parts are: `content[\.member]` reaches a part.
public struct _GraphValue<Value> {
    package let value: () -> Value
    package init(_ value: @escaping () -> Value) { self.value = value }
    public subscript<Member>(keyPath: KeyPath<Value, Member>) -> _GraphValue<Member> {
        _GraphValue<Member> { value()[keyPath: keyPath] }
    }
    package func _map<Member>(_ transform: @escaping (Value) -> Member) -> _GraphValue<Member> {
        _GraphValue<Member> { transform(value()) }
    }
}

/// What column content is made with (nothing yet: the table's row type is in the content's).
public struct _TableColumnInputs {
    package init() {}
}

/// The columns column content made, as `TableColumn` values of the row type.
public struct _TableColumnOutputs {
    package var columns: [Any] = []
    package init(columns: [Any] = []) { self.columns = columns }
}

/// A row of a table declared by hand (`Table(of:columns:rows:)`).
public struct TableRow<Value: Identifiable> {
    package let value: Value
    public init(_ value: Value) { self.value = value }
}

/// A result builder that creates table row content from closures.
@resultBuilder
public struct TableRowBuilder<Value: Identifiable> {
    /// Content as itself: a body that never returns (`fatalError()`) is `Never`'s.
    public static func buildExpression<Content: TableRowContent>(_ content: Content) -> Content { content }
    public static func buildBlock<Content: TableRowContent>(_ content: Content) -> Content { content }
    public static func buildBlock(_ rows: [TableRow<Value>]...) -> [TableRow<Value>] { rows.flatMap { $0 } }
    public static func buildExpression(_ row: TableRow<Value>) -> [TableRow<Value>] { [row] }
    public static func buildExpression(_ rows: [TableRow<Value>]) -> [TableRow<Value>] { rows }
    public static func buildOptional(_ rows: [TableRow<Value>]?) -> [TableRow<Value>] { rows ?? [] }
    public static func buildEither(first: [TableRow<Value>]) -> [TableRow<Value>] { first }
    public static func buildEither(second: [TableRow<Value>]) -> [TableRow<Value>] { second }
    public static func buildArray(_ rows: [[TableRow<Value>]]) -> [TableRow<Value>] { rows.flatMap { $0 } }
    /// Rows made from a collection (`ForEach(orders) { TableRow($0) }`).
    public static func buildExpression<D, I>(_ rows: ForEach<D, I, [TableRow<Value>]>) -> [TableRow<Value>] { rows.data.flatMap(rows.content) }
    /// A section of rows (`Section { ForEach(...) { TableRow($0) } }`): its rows, in place; the
    /// table draws no section header yet.
    public static func buildExpression<P, F>(_ section: Section<P, [TableRow<Value>], F>) -> [TableRow<Value>] { section.content }
}

extension ForEach where ID == Data.Element.ID, Data.Element: Identifiable {
    /// Table rows made from a collection of identified data.
    public init<V>(_ data: Data, @TableRowBuilder<V> content: @escaping (Data.Element) -> Content) where Content == [TableRow<V>] {
        self.init(data: data, id: \.id, content: content)
    }
}

extension ForEach {
    /// Table rows made from a collection, identified by a key path.
    public init<V>(_ data: Data, id: KeyPath<Data.Element, ID>, @TableRowBuilder<V> content: @escaping (Data.Element) -> Content) where Content == [TableRow<V>] {
        self.init(data: data, id: id, content: content)
    }
}

extension Section where Parent == EmptyView, Footer == EmptyView {
    /// A section of table rows.
    public init<V>(@TableRowBuilder<V> content: () -> Content) where Content == [TableRow<V>] {
        self.init(header: EmptyView(), content: content(), footer: EmptyView())
    }
}

extension Section where Parent == Text, Footer == EmptyView {
    /// A titled section of table rows.
    public init<V>(_ titleKey: LocalizedStringKey, @TableRowBuilder<V> content: () -> Content) where Content == [TableRow<V>] {
        self.init(header: Text(titleKey), content: content(), footer: EmptyView())
    }

    @_disfavoredOverload
    public init<V, S: StringProtocol>(_ title: S, @TableRowBuilder<V> content: () -> Content) where Content == [TableRow<V>] {
        self.init(header: Text(title), content: content(), footer: EmptyView())
    }
}

/// Columns made from a collection (`TableColumnForEach(data) { TableColumn(...) }`).
public struct TableColumnForEach<Data: RandomAccessCollection, ID: Hashable, RowValue: Identifiable> {
    package let columns: [_AnyTableColumn<RowValue>]

    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @TableColumnBuilder<RowValue, Never> content: (Data.Element) -> [_AnyTableColumn<RowValue>]) {
        columns = data.flatMap { content($0) }
    }

    public init(_ data: Data, @TableColumnBuilder<RowValue, Never> content: (Data.Element) -> [_AnyTableColumn<RowValue>]) where Data.Element: Identifiable, ID == Data.Element.ID {
        columns = data.flatMap { content($0) }
    }
}

extension Group {
    /// A group of columns (a `Group` inside `TableColumnBuilder`).
    public init<R: Identifiable>(@TableColumnBuilder<R, Never> content: () -> [_AnyTableColumn<R>]) where Content == [_AnyTableColumn<R>] {
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

/// A table column without its sort, content and label types: what `Table` lays out.
public struct _AnyTableColumn<RowValue: Identifiable> {
    package var title: String
    package var content: (RowValue) -> AnyView
    package var width: _TableColumnWidth = .automatic
    /// The compared key path of a sortable column, and how to build its comparator.
    package var keyPath: PartialKeyPath<RowValue>?
    package var makeComparator: ((SortOrder) -> KeyPathComparator<RowValue>)?

    package init(title: String, content: @escaping (RowValue) -> AnyView,
                 keyPath: PartialKeyPath<RowValue>? = nil, makeComparator: ((SortOrder) -> KeyPathComparator<RowValue>)? = nil) {
        self.title = title
        self.content = content
        self.keyPath = keyPath
        self.makeComparator = makeComparator
    }
}

/// A column that displays a view for each row in a table, typed like SwiftUI's by its row
/// value, the comparator that sorts by it (`Never` when it doesn't sort), its cell content and
/// its label.
public struct TableColumn<RowValue: Identifiable, Sort, Content: View, Label: View> {
    package var _column: _AnyTableColumn<RowValue>

    package init(_column: _AnyTableColumn<RowValue>) { self._column = _column }

    /// Creates a fixed-width column.
    public func width(_ width: CGFloat? = nil) -> TableColumn {
        var copy = self
        copy._column.width = width.map { .fixed($0) } ?? .automatic
        return copy
    }

    /// Creates a resizable column with the provided constraints.
    public func width(min: CGFloat? = nil, ideal: CGFloat? = nil, max: CGFloat? = nil) -> TableColumn {
        var copy = self
        copy._column.width = .flexible(min: min, ideal: ideal, max: max)
        return copy
    }
}

extension TableColumn where Sort == KeyPathComparator<RowValue>, Label == Text {
    /// Creates a sortable column with the given content.
    public init<V: Comparable>(_ titleKey: LocalizedStringKey, value: KeyPath<RowValue, V> & Sendable, @ViewBuilder content: @escaping (RowValue) -> Content) {
        self.init(_column: _AnyTableColumn(title: Text(titleKey).resolvedString, content: { AnyView(content($0)) },
                                           keyPath: value, makeComparator: { KeyPathComparator(value, order: $0) }))
    }

    public init<V: Comparable>(_ text: Text, value: KeyPath<RowValue, V> & Sendable, @ViewBuilder content: @escaping (RowValue) -> Content) {
        self.init(_column: _AnyTableColumn(title: text.resolvedString, content: { AnyView(content($0)) },
                                           keyPath: value, makeComparator: { KeyPathComparator(value, order: $0) }))
    }

    @_disfavoredOverload
    public init<S: StringProtocol, V: Comparable>(_ title: S, value: KeyPath<RowValue, V> & Sendable, @ViewBuilder content: @escaping (RowValue) -> Content) {
        self.init(_column: _AnyTableColumn(title: String(title), content: { AnyView(content($0)) },
                                           keyPath: value, makeComparator: { KeyPathComparator(value, order: $0) }))
    }
}

extension TableColumn where Sort == KeyPathComparator<RowValue>, Content == Text, Label == Text {
    /// Creates a sortable column that shows a string key path's value.
    public init(_ titleKey: LocalizedStringKey, value: KeyPath<RowValue, String> & Sendable) {
        self.init(titleKey, value: value) { Text($0[keyPath: value]) }
    }

    public init(_ text: Text, value: KeyPath<RowValue, String> & Sendable) {
        self.init(text, value: value) { Text($0[keyPath: value]) }
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, value: KeyPath<RowValue, String> & Sendable) {
        self.init(title, value: value) { Text($0[keyPath: value]) }
    }
}

extension TableColumn where Sort == Never, Label == Text {
    /// Creates an unsortable column with the given content.
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: @escaping (RowValue) -> Content) {
        self.init(_column: _AnyTableColumn(title: Text(titleKey).resolvedString, content: { AnyView(content($0)) }))
    }

    public init(_ text: Text, @ViewBuilder content: @escaping (RowValue) -> Content) {
        self.init(_column: _AnyTableColumn(title: text.resolvedString, content: { AnyView(content($0)) }))
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: @escaping (RowValue) -> Content) {
        self.init(_column: _AnyTableColumn(title: String(title), content: { AnyView(content($0)) }))
    }
}

/// A column is column content of its row value and comparator, as SwiftUI's is, so a column
/// can be passed where `TableColumnContent` is asked for, or kept in a property of
/// `some TableColumnContent<Row, Sort>` and used in a table. It makes itself as its one column.
extension TableColumn: TableColumnContent {
    public typealias TableRowValue = RowValue
    public typealias TableColumnSortComparator = Sort
    public var tableColumnBody: Never { return fatalError() }
    nonisolated public static func _makeContent(content: _GraphValue<TableColumn>, inputs: _TableColumnInputs) -> _TableColumnOutputs {
        _TableColumnOutputs(columns: [content.value()._column])
    }
}

/// A result builder that creates table column content from closures.
@resultBuilder
public struct TableColumnBuilder<RowValue: Identifiable, Sort> {
    /// Content as itself: a body that never returns (`fatalError()`) is `Never`'s.
    public static func buildExpression<Content: TableColumnContent>(_ content: Content) -> Content { content }
    public static func buildBlock<Content: TableColumnContent>(_ content: Content) -> Content { content }
    public static func buildBlock(_ columns: [_AnyTableColumn<RowValue>]...) -> [_AnyTableColumn<RowValue>] { columns.flatMap { $0 } }
    /// A column of any sort, content and label type, sortable or not: an unsortable column
    /// sits in a sortable table too.
    public static func buildExpression<S, C, L>(_ column: TableColumn<RowValue, S, C, L>) -> [_AnyTableColumn<RowValue>] { [column._column] }
    /// Other column content of the table's rows (a property of `some TableColumnContent<Row,
    /// Sort>`): the columns it makes.
    public static func buildExpression<Content: TableColumnContent>(_ content: Content) -> [_AnyTableColumn<RowValue>] where Content.TableRowValue == RowValue {
        var columns: [_AnyTableColumn<RowValue>] = []
        for column in Content._makeContent(content: _GraphValue { content }, inputs: _TableColumnInputs()).columns {
            if let column = column as? _AnyTableColumn<RowValue> { columns.append(column) }
        }
        return columns
    }
    public static func buildExpression<D, I>(_ columns: TableColumnForEach<D, I, RowValue>) -> [_AnyTableColumn<RowValue>] { columns.columns }
    public static func buildExpression(_ group: Group<[_AnyTableColumn<RowValue>]>) -> [_AnyTableColumn<RowValue>] { group.content }
    public static func buildOptional(_ columns: [_AnyTableColumn<RowValue>]?) -> [_AnyTableColumn<RowValue>] { columns ?? [] }
    public static func buildEither(first: [_AnyTableColumn<RowValue>]) -> [_AnyTableColumn<RowValue>] { first }
    public static func buildEither(second: [_AnyTableColumn<RowValue>]) -> [_AnyTableColumn<RowValue>] { second }
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
