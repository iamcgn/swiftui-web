/// A type of view that generates views from an underlying collection of identified data.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
public protocol DynamicViewContent: View {
    /// The type of the underlying collection of data.
    associatedtype Data: Collection

    /// The collection of underlying data.
    var data: Data { get }
}

/// A structure that computes views on demand from an underlying collection of identified data.
///
/// Elements are identified by `ID` (an `Identifiable` element's `id`, an explicit `id:` key path,
/// or the value itself for ranges). The runtime reconciles by identity: an element whose id
/// survives an update keeps its subtree and state; an id that disappears loses both.
public struct ForEach<Data: RandomAccessCollection, ID: Hashable, Content> {
    /// The collection of underlying identified data that SwiftUI uses to create views dynamically.
    public var data: Data

    /// A function to create content on demand using the underlying data.
    public var content: (Data.Element) -> Content

    /// Extracts an element's identity.
    package let idPath: KeyPath<Data.Element, ID>

    /// The edit actions a list applies to these rows (`onDelete`, `onMove`, `editActions:`).
    package var _onDelete: ((IndexSet) -> Void)?
    package var _onMove: ((IndexSet, Int) -> Void)?

    package init(data: Data, id: KeyPath<Data.Element, ID>, content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.idPath = id
        self.content = content
    }

    package func id(of element: Data.Element) -> ID {
        element[keyPath: idPath]
    }
}

extension ForEach: View, DynamicViewContent where Content: View {
    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<ForEach<Data, ID, Content>>) -> TypedNode<ForEach<Data, ID, Content>> {
        ForEachNode(context)
    }
}

extension ForEach where ID == Data.Element.ID, Content: View, Data.Element: Identifiable {
    /// Creates an instance that uniquely identifies and creates views across updates based on
    /// the identity of the underlying data.
    public init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.init(data: data, id: \.id, content: content)
    }
}

extension ForEach where Content: View {
    /// Creates an instance that uniquely identifies and creates views across updates based on
    /// the provided key path to the underlying data's identifier.
    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.init(data: data, id: id, content: content)
    }
}

extension ForEach where Data == Range<Int>, ID == Int, Content: View {
    /// Creates an instance that computes views on demand over a given constant range.
    ///
    /// The range is read once when the view is created, so it must be constant. Use the
    /// `id:` form for a range that changes.
    public init(_ data: Range<Int>, @ViewBuilder content: @escaping (Int) -> Content) {
        self.init(data: data, id: \.self, content: content)
    }
}

// MARK: Bindings to collections

extension ForEach where Content: View {
    /// Creates an instance that uniquely identifies and creates views across updates based on
    /// the identity of the underlying data, giving the content a binding to each element.
    public init<C>(_ data: Binding<C>, @ViewBuilder content: @escaping (Binding<C.Element>) -> Content)
    where Data == LazyMapSequence<C.Indices, (C.Index, ID)>, ID == C.Element.ID,
          C: MutableCollection, C: RandomAccessCollection, C.Element: Identifiable, C.Index: Hashable
    {
        self.init(data, id: \.id, content: content)
    }

    /// Creates an instance that uniquely identifies and creates views across updates based on
    /// the provided key path to the underlying data's identifier, giving the content a binding
    /// to each element.
    public init<C>(_ data: Binding<C>, id: KeyPath<C.Element, ID>, @ViewBuilder content: @escaping (Binding<C.Element>) -> Content)
    where Data == LazyMapSequence<C.Indices, (C.Index, ID)>,
          C: MutableCollection, C: RandomAccessCollection, C.Index: Hashable
    {
        let collection = data.wrappedValue
        let pairs = collection.indices.lazy.map { index in (index, collection[index][keyPath: id]) }
        self.init(data: pairs, id: \.1, content: { pair in content(data[pair.0]) })
    }
}

// MARK: - Edit actions (Docs/elements/List.md)

extension ForEach where Content: View {
    /// Sets the deletion action: a list calls it with the offsets of the rows deleted (the Delete
    /// key on selected rows, a swipe or the edit mode on iOS). Returns the `ForEach` itself
    /// (Apple's `some DynamicViewContent`), so `onMove` chains either way.
    public func onDelete(perform action: ((IndexSet) -> Void)?) -> ForEach<Data, ID, Content> {
        var copy = self
        copy._onDelete = action
        return copy
    }

    /// Sets the move action: a list calls it with the offsets of the rows dragged and the
    /// destination offset.
    public func onMove(perform action: ((IndexSet, Int) -> Void)?) -> ForEach<Data, ID, Content> {
        var copy = self
        copy._onMove = action
        return copy
    }

    /// Insertion by drop is not offered here: the action is kept for API compatibility.
    public func onInsert(of supportedContentTypes: [UTType], perform action: @escaping (Int, [Any]) -> Void) -> ForEach<Data, ID, Content> {
        self
    }
}

/// The edit operations a binding-backed `ForEach` or `List` performs on its collection.
public struct EditActions<Data>: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static var delete: EditActions<Data> { EditActions(rawValue: 1) }
    public static var move: EditActions<Data> { EditActions(rawValue: 2) }
    public static var all: EditActions<Data> { [.delete, .move] }
}

extension ForEach where Content: View {
    /// A binding-backed collection whose rows can be deleted and moved through the binding.
    public init<C>(_ data: Binding<C>, editActions: EditActions<C>, @ViewBuilder content: @escaping (Binding<C.Element>) -> Content)
    where Data == LazyMapSequence<C.Indices, (C.Index, ID)>, ID == C.Element.ID,
          C: MutableCollection, C: RandomAccessCollection, C: RangeReplaceableCollection, C.Element: Identifiable, C.Index: Hashable
    {
        self.init(data, id: \.id, editActions: editActions, content: content)
    }

    public init<C>(_ data: Binding<C>, id: KeyPath<C.Element, ID>, editActions: EditActions<C>, @ViewBuilder content: @escaping (Binding<C.Element>) -> Content)
    where Data == LazyMapSequence<C.Indices, (C.Index, ID)>,
          C: MutableCollection, C: RandomAccessCollection, C: RangeReplaceableCollection, C.Index: Hashable
    {
        self.init(data, id: id, content: content)
        if editActions.contains(.delete) { _onDelete = { offsets in data.wrappedValue.remove(atOffsets: offsets) } }
        if editActions.contains(.move) { _onMove = { offsets, destination in data.wrappedValue.move(fromOffsets: offsets, toOffset: destination) } }
    }
}

// More constrained than Apple's SwiftUI declarations of the same names (`MutableCollection`),
// so these win the overload when the SDK's module is visible beside this one on macOS.
extension RangeReplaceableCollection where Self: MutableCollection, Self: RandomAccessCollection {
    /// Removes the elements at the offsets (the collection's positions counted from the start).
    public mutating func remove(atOffsets offsets: IndexSet) {
        for offset in offsets.sorted(by: >) where offset >= 0 && offset < count {
            remove(at: index(startIndex, offsetBy: offset))
        }
    }
}

extension MutableCollection where Self: RangeReplaceableCollection, Self: RandomAccessCollection {
    /// Moves the elements at the offsets so that they sit before the element at `destination`
    /// (SwiftUI's `onMove` convention: the destination is counted before the removal).
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted()
        guard !moving.isEmpty else { return }
        let elements = moving.map { self[index(startIndex, offsetBy: $0)] }
        let before = moving.filter { $0 < destination }.count
        var remaining = Array(self)
        for offset in moving.reversed() where offset < remaining.count { remaining.remove(at: offset) }
        let insertAt = Swift.max(0, Swift.min(remaining.count, destination - before))
        remaining.insert(contentsOf: elements, at: insertAt)
        replaceSubrange(startIndex..<endIndex, with: remaining)
    }
}

/// `deleteDisabled` / `moveDisabled`: rows a list must not delete or move.
package struct DeleteDisabledKey: LayoutValueKey {
    package static let defaultValue = false
}
package struct MoveDisabledKey: LayoutValueKey {
    package static let defaultValue = false
}

extension View {
    /// Keeps a list from deleting this row.
    nonisolated public func deleteDisabled(_ isDisabled: Bool) -> some View { layoutValue(key: DeleteDisabledKey.self, value: isDisabled) }
    /// Keeps a list from moving this row.
    nonisolated public func moveDisabled(_ isDisabled: Bool) -> some View { layoutValue(key: MoveDisabledKey.self, value: isDisabled) }
}
