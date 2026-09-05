// @Namespace and matchedGeometryEffect: views sharing an id in a namespace share geometry. A
// view inserted under an animation starts from the frame the previous source had (and the
// retiring one moves to the new frame), so a view that changes place in the hierarchy glides
// there; a non-source view paints at the source's frame.

/// A property wrapper giving a view a persistent namespace for matched geometry ids.
@propertyWrapper
public struct Namespace: DynamicProperty {
    /// A namespace's identity.
    public struct ID: Hashable, Sendable {
        package let value: Int
    }

    package var box: NamespaceBox?

    public init() {}

    public var wrappedValue: ID { box?.id ?? ID(value: 0) }

    public mutating func _install(in node: ViewNode, slot: inout AnyObject?) {
        if let existing = slot as? NamespaceBox {
            box = existing
        } else {
            let created = NamespaceBox()
            slot = created
            box = created
        }
    }
}

@MainActor
package final class NamespaceBox {
    package static var next = 1
    package let id: Namespace.ID
    package init() {
        id = Namespace.ID(value: Self.next)
        Self.next += 1
    }
}

/// Which parts of the geometry a matched view takes from its source.
public struct MatchedGeometryProperties: OptionSet, Hashable, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let position = MatchedGeometryProperties(rawValue: 1)
    public static let size = MatchedGeometryProperties(rawValue: 2)
    public static let frame: MatchedGeometryProperties = [.position, .size]
}

public struct _MatchedGeometryEffect: Equatable {
    package let id: AnyHashable
    package let namespace: Namespace.ID
    package let properties: MatchedGeometryProperties
    package let anchor: UnitPoint
    package let isSource: Bool
    package var key: MatchedGeometryKey { MatchedGeometryKey(namespace: namespace, id: id) }
}

/// The identity of a matched geometry group.
public struct MatchedGeometryKey: Hashable {
    package let namespace: Namespace.ID
    package let id: AnyHashable
}

extension _MatchedGeometryEffect: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        MatchedGeometryNode(context)
    }
}

extension View {
    /// Matches this view's geometry with the other views sharing `id` in `namespace`.
    nonisolated public func matchedGeometryEffect<ID: Hashable>(id: ID, in namespace: Namespace.ID, properties: MatchedGeometryProperties = .frame,
                                                                anchor: UnitPoint = .center, isSource: Bool = true) -> some View {
        modifier(_MatchedGeometryEffect(id: AnyHashable(id), namespace: namespace, properties: properties, anchor: anchor, isSource: isSource))
    }
}
