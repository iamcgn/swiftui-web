/// A type of view that generates views from an underlying collection of identified data.
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
