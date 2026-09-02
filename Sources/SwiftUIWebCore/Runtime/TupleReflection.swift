@_spi(Reflection) import Swift

/// Per-element accessors for a tuple type `T` whose elements are all views. Built once per tuple
/// type with stdlib key-path reflection (decision 0004; verified for tuples on 2026-09-02) and
/// cached, so updating a `TupleView` does not reflect on every evaluation.
@MainActor
package struct TupleElement<T> {
    package let viewType: Any.Type
    package let make: (T, ViewNode, EnvironmentValues) -> ViewNode
    package let update: (ViewNode, T, EnvironmentValues) -> Void

    package static var all: [TupleElement<T>] {
        let key = ObjectIdentifier(T.self)
        if let cached = tupleElementCache[key] as? [TupleElement<T>] { return cached }
        var elements: [TupleElement<T>] = []
        let ok = _forEachFieldWithKeyPath(of: T.self, options: []) { _, keyPath in
            guard let viewType = type(of: keyPath).valueType as? any View.Type else {
                fatalError("TupleView element \(type(of: keyPath).valueType) is not a View")
            }
            elements.append(makeElement(viewType, keyPath: keyPath))
            return true
        }
        precondition(ok, "Could not reflect tuple type \(T.self)")
        tupleElementCache[key] = elements
        return elements
    }

    private static func makeElement(_ viewType: any View.Type, keyPath: PartialKeyPath<T>) -> TupleElement<T> {
        func open<E: View>(_: E.Type) -> TupleElement<T> {
            let typed = keyPath as! KeyPath<T, E>
            return TupleElement(
                viewType: E.self,
                make: { tuple, parent, environment in
                    E._makeNode(_NodeContext(view: tuple[keyPath: typed], parent: parent, environment: environment))
                },
                update: { node, tuple, environment in
                    (node as! TypedNode<E>).update(view: tuple[keyPath: typed], environment: environment)
                })
        }
        return open(viewType)
    }
}

@MainActor
private var tupleElementCache: [ObjectIdentifier: Any] = [:]
