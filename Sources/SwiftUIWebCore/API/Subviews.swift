// The container APIs (sw-subviews, Docs/elements/ForEach.md): `Group(subviews:)`,
// `Group(sections:)`, `ForEach(subviews:)` and `ForEach(sections:)` hand a view's structural
// children to a transform, and `ContainerValues` carry per-child values set with
// `containerValue(_:_:)` (declared with `@Entry`) or `tag`. The children are read from the view
// value itself before any node exists: tuples by their elements, `ForEach` by its data,
// conditionals by their branch, modifiers on a container applied to each child, as SwiftUI
// resolves them. A subview's identity is its `ForEach` element's or `id(_:)`, else its index.

// MARK: - ContainerValues

/// A key for a value a container reads off its children (`@Entry` in an extension declares one).
public protocol ContainerValueKey {
    associatedtype Value
    static var defaultValue: Value { get }
}

/// Values a child view sets for the container holding it.
public struct ContainerValues {
    private var storage: [ObjectIdentifier: Any] = [:]
    /// The `tag(_:)` of the child, if any.
    package var tag: AnyHashable?

    public init() {}

    public subscript<K: ContainerValueKey>(key: K.Type) -> K.Value {
        get { (storage[ObjectIdentifier(key)] as? _ContainerBox<K.Value>)?.value ?? K.defaultValue }
        set { storage[ObjectIdentifier(key)] = _ContainerBox(value: newValue) }
    }

    /// The child's tag when it is a `V`.
    public func tag<V: Hashable>(for type: V.Type) -> V? { tag?.base as? V }
    /// Whether the child was tagged with `value`.
    public func hasTag<V: Hashable>(_ value: V) -> Bool { tag == AnyHashable(value) }
}

/// Values are stored type-erased.
private struct _ContainerBox<Value> {
    let value: Value
}

/// `containerValue(_:_:)`: sets a container value on every subview of the content.
public struct _ContainerValueWriter<Content, Value> {
    package let content: Content
    package let keyPath: WritableKeyPath<ContainerValues, Value>
    package let value: Value

    package init(content: Content, keyPath: WritableKeyPath<ContainerValues, Value>, value: Value) {
        self.content = content
        self.keyPath = keyPath
        self.value = value
    }
}

extension _ContainerValueWriter: View where Content: View {
    public var body: Content { content }
}

extension View {
    /// Sets a value in the `ContainerValues` of this view's subviews.
    nonisolated public func containerValue<V>(_ keyPath: WritableKeyPath<ContainerValues, V>, _ value: V) -> some View {
        _ContainerValueWriter(content: self, keyPath: keyPath, value: value)
    }
}

// MARK: - Subviews

/// One structural child of a view, usable as a view itself.
public struct Subview: View {
    /// The identity SwiftUI assigns: the `ForEach` element's or `id(_:)` value, else the index.
    public struct ID: Hashable, @unchecked Sendable {
        package let value: AnyHashable
        package init(value: AnyHashable) { self.value = value }
    }

    nonisolated public let id: ID
    /// The values the child set for its container.
    public let containerValues: ContainerValues
    package let content: AnyView

    package init(_ content: AnyView, id: AnyHashable, containerValues: ContainerValues) {
        self.content = content
        self.id = ID(value: id)
        self.containerValues = containerValues
    }

    public var body: AnyView { content }
}

extension Subview: Identifiable {}

/// A view's structural children.
public struct SubviewsCollection: View {
    package var elements: [Subview]

    package init(_ elements: [Subview]) { self.elements = elements }

    /// The subviews as a view: each in turn.
    public var body: some View { ForEach(elements) { $0 } }
}

extension SubviewsCollection: @preconcurrency RandomAccessCollection {
    public typealias Index = Int
    public typealias Element = Subview
    public typealias SubSequence = SubviewsCollectionSlice
    public typealias Iterator = IndexingIterator<SubviewsCollection>
    public typealias Indices = Range<Int>
    public var startIndex: Int { 0 }
    public var endIndex: Int { elements.count }
    public subscript(position: Int) -> Subview { elements[position] }
    public subscript(bounds: Range<Int>) -> SubviewsCollectionSlice { SubviewsCollectionSlice(Array(elements[bounds])) }
}

/// A slice of a `SubviewsCollection`, also a view.
public struct SubviewsCollectionSlice: View {
    package var elements: [Subview]
    package init(_ elements: [Subview]) { self.elements = elements }
    public var body: some View { ForEach(elements) { $0 } }
}

extension SubviewsCollectionSlice: @preconcurrency RandomAccessCollection {
    public typealias Index = Int
    public typealias Element = Subview
    public typealias SubSequence = SubviewsCollectionSlice
    public typealias Iterator = IndexingIterator<SubviewsCollectionSlice>
    public typealias Indices = Range<Int>
    public var startIndex: Int { 0 }
    public var endIndex: Int { elements.count }
    public subscript(position: Int) -> Subview { elements[position] }
    public subscript(bounds: Range<Int>) -> SubviewsCollectionSlice { SubviewsCollectionSlice(Array(elements[bounds])) }
}

/// A section of a view: its header, content and footer subviews.
public struct SectionConfiguration: Identifiable {
    public struct ID: Hashable, @unchecked Sendable {
        package let value: AnyHashable
        package init(value: AnyHashable) { self.value = value }
    }

    public let id: ID
    public let header: SubviewsCollection
    public let content: SubviewsCollection
    public let footer: SubviewsCollection
    /// The values the section set for its container.
    public let containerValues: ContainerValues

    @MainActor package init(id: AnyHashable, header: [Subview], content: [Subview], footer: [Subview], containerValues: ContainerValues) {
        self.id = ID(value: id)
        self.header = SubviewsCollection(header)
        self.content = SubviewsCollection(content)
        self.footer = SubviewsCollection(footer)
        self.containerValues = containerValues
    }
}

/// A view's sections: each `Section` one, consecutive views outside a section gathered into one
/// without a header.
public struct SectionCollection: RandomAccessCollection {
    package var elements: [SectionConfiguration]
    package init(_ elements: [SectionConfiguration]) { self.elements = elements }
    public var startIndex: Int { 0 }
    public var endIndex: Int { elements.count }
    public subscript(position: Int) -> SectionConfiguration { elements[position] }
}

// MARK: - Resolving a view's children

/// The pieces a view resolves into: subviews, or sections for the `sections:` forms.
package enum _Structural {
    case subview(AnyView, id: AnyHashable?, values: ContainerValues)
    case section(id: AnyHashable?, header: [_Structural], content: [_Structural], footer: [_Structural], values: ContainerValues)

    /// With a container value set on every subview inside.
    func setting<V>(_ keyPath: WritableKeyPath<ContainerValues, V>, _ value: V) -> _Structural {
        switch self {
        case .subview(let view, let id, var values):
            values[keyPath: keyPath] = value
            return .subview(view, id: id, values: values)
        case .section(let id, let header, let content, let footer, var values):
            values[keyPath: keyPath] = value
            return .section(id: id, header: header.map { $0.setting(keyPath, value) }, content: content.map { $0.setting(keyPath, value) },
                            footer: footer.map { $0.setting(keyPath, value) }, values: values)
        }
    }

    func tagged(_ tag: AnyHashable?) -> _Structural {
        switch self {
        case .subview(let view, let id, var values):
            values.tag = tag
            return .subview(view, id: id, values: values)
        case .section(let id, let header, let content, let footer, var values):
            values.tag = tag
            return .section(id: id, header: header, content: content, footer: footer, values: values)
        }
    }

    /// With an identity when it has none yet.
    func identified(_ id: AnyHashable) -> _Structural {
        switch self {
        case .subview(let view, let existing, let values): return .subview(view, id: existing ?? id, values: values)
        case .section(let existing, let header, let content, let footer, let values): return .section(id: existing ?? id, header: header, content: content, footer: footer, values: values)
        }
    }

    /// Wrapped in a modifier (a modifier on a container applies to each child).
    func modified<M: ViewModifier>(by modifier: M) -> _Structural {
        switch self {
        case .subview(let view, let id, let values): return .subview(AnyView(view.modifier(modifier)), id: id, values: values)
        case .section(let id, let header, let content, let footer, let values):
            return .section(id: id, header: header.map { $0.modified(by: modifier) }, content: content.map { $0.modified(by: modifier) },
                            footer: footer.map { $0.modified(by: modifier) }, values: values)
        }
    }
}

/// Views whose children are read structurally.
@MainActor
package protocol _StructuralView {
    func _structure() -> [_Structural]
}

@MainActor
package enum _Subviews {
    /// A view's pieces: a structural view's children; a custom view's body's children when the
    /// body is a container holding several (a view whose body comes to one piece, a `Button`
    /// say, stays itself, with its state and styles); any other view one piece.
    package static func structure<V: View>(of view: V) -> [_Structural] {
        if let structural = view as? any _StructuralView { return structural._structure() }
        if V.Body.self != Never.self {
            let body = view.body
            if let structural = body as? any _StructuralView {
                let pieces = structural._structure()
                if pieces.count != 1 { return pieces }
            }
        }
        return [.subview(AnyView(view), id: nil, values: ContainerValues())]
    }

    /// The subviews of a view: sections contribute their contents (the `subviews:` forms see
    /// through sections, as SwiftUI's do).
    package static func subviews<V: View>(of view: V) -> SubviewsCollection {
        SubviewsCollection(flatten(structure(of: view)))
    }

    private static func flatten(_ pieces: [_Structural]) -> [Subview] {
        var result: [Subview] = []
        for piece in pieces {
            switch piece {
            case .subview(let view, let id, let values): result.append(Subview(view, id: id ?? AnyHashable(result.count), containerValues: values))
            case .section(_, let header, let content, let footer, _): result += flatten(header + content + footer)
            }
        }
        return result
    }

    /// The sections of a view: every `Section` one, runs of other views one without a header.
    package static func sections<V: View>(of view: V) -> SectionCollection {
        var sections: [SectionConfiguration] = []
        var loose: [Subview] = []
        func flushLoose() {
            guard !loose.isEmpty else { return }
            sections.append(SectionConfiguration(id: AnyHashable(sections.count), header: [], content: loose, footer: [], containerValues: ContainerValues()))
            loose = []
        }
        for piece in structure(of: view) {
            switch piece {
            case .subview(let view, let id, let values): loose.append(Subview(view, id: id ?? AnyHashable(loose.count), containerValues: values))
            case .section(let id, let header, let content, let footer, let values):
                flushLoose()
                sections.append(SectionConfiguration(id: id ?? AnyHashable(sections.count), header: flatten(header), content: flatten(content), footer: flatten(footer), containerValues: values))
            }
        }
        flushLoose()
        return SectionCollection(sections)
    }
}

extension TupleView: _StructuralView {
    package func _structure() -> [_Structural] {
        TupleElement<T>.all.flatMap { $0.structure(value) }
    }
}

extension Group: _StructuralView where Content: View {
    package func _structure() -> [_Structural] { _Subviews.structure(of: content) }
}

extension _ConditionalContent: _StructuralView where TrueContent: View, FalseContent: View {
    package func _structure() -> [_Structural] {
        switch storage {
        case .trueContent(let view): return _Subviews.structure(of: view)
        case .falseContent(let view): return _Subviews.structure(of: view)
        }
    }
}

extension Optional: _StructuralView where Wrapped: View {
    package func _structure() -> [_Structural] { map { _Subviews.structure(of: $0) } ?? [] }
}

extension EmptyView: _StructuralView {
    package func _structure() -> [_Structural] { [] }
}

extension ForEach: _StructuralView where Content: View {
    package func _structure() -> [_Structural] {
        data.flatMap { element in
            let id = AnyHashable(element[keyPath: idPath])
            return _Subviews.structure(of: content(element)).map { $0.identified(id) }
        }
    }
}

extension Section: _StructuralView where Parent: View, Content: View, Footer: View {
    package func _structure() -> [_Structural] {
        [.section(id: nil, header: _Subviews.structure(of: header), content: _Subviews.structure(of: content), footer: _Subviews.structure(of: footer), values: ContainerValues())]
    }
}

extension IDView: _StructuralView where Content: View {
    package func _structure() -> [_Structural] { _Subviews.structure(of: content).map { $0.identified(AnyHashable(id)) } }
}

extension _ContainerValueWriter: _StructuralView where Content: View {
    package func _structure() -> [_Structural] { _Subviews.structure(of: content).map { $0.setting(keyPath, value) } }
}

extension AnyView: _StructuralView {
    package func _structure() -> [_Structural] {
        var visitor = _StructureVisitor()
        return storage.visit(&visitor)
    }
}

private struct _StructureVisitor: _AnyViewVisitor {
    @MainActor mutating func visit<V: View>(_ view: V) -> [_Structural] { _Subviews.structure(of: view) }
}

extension SubviewsCollection: _StructuralView {
    package func _structure() -> [_Structural] { elements.map { .subview($0.content, id: $0.id.value, values: $0.containerValues) } }
}

extension SubviewsCollectionSlice: _StructuralView {
    package func _structure() -> [_Structural] { elements.map { .subview($0.content, id: $0.id.value, values: $0.containerValues) } }
}

extension ModifiedContent: _StructuralView where Content: View, Modifier: ViewModifier {
    /// A modifier on a container applies to each child; a tag sets the children's tag.
    package func _structure() -> [_Structural] {
        let pieces = _Subviews.structure(of: content)
        if let tag = modifier as? _LayoutValueModifier<TagKey> { return pieces.map { $0.tagged(tag.value) } }
        guard content is any _StructuralView else { return [.subview(AnyView(self), id: nil, values: ContainerValues())] }
        return pieces.map { $0.modified(by: modifier) }
    }
}

// MARK: - The container initialisers

extension Group where Content: View {
    /// A group of the subviews of `view`, arranged by `transform`.
    @MainActor
    public init<V: View>(subviews view: V, @ViewBuilder transform: @escaping (SubviewsCollection) -> Content) {
        self.init(_content: transform(_Subviews.subviews(of: view)))
    }

    /// A group of the sections of `view`, arranged by `transform`.
    @MainActor
    public init<V: View>(sections view: V, @ViewBuilder transform: @escaping (SectionCollection) -> Content) {
        self.init(_content: transform(_Subviews.sections(of: view)))
    }
}

extension ForEach where Data == SubviewsCollection, ID == Subview.ID, Content: View {
    /// Each subview of `view` through `content`.
    @MainActor
    public init<V: View>(subviews view: V, @ViewBuilder content: @escaping (Subview) -> Content) {
        self.init(_Subviews.subviews(of: view), id: \.id, content: content)
    }
}

extension ForEach where Data == SectionCollection, ID == SectionConfiguration.ID, Content: View {
    /// Each section of `view` through `content`.
    @MainActor
    public init<V: View>(sections view: V, @ViewBuilder content: @escaping (SectionConfiguration) -> Content) {
        self.init(_Subviews.sections(of: view), id: \.id, content: content)
    }
}
