/// A type-erased view.
///
/// An `AnyView` allows changing the type of view used in a given view hierarchy. Whenever the
/// type of view used with an `AnyView` changes, the old hierarchy is destroyed and a new hierarchy
/// is created for the new type.
@frozen
public struct AnyView {
    @usableFromInline
    package var storage: AnyViewStorageBase

    /// Creates an instance that type-erases `view`.
    public init<V: View>(_ view: V) {
        if let erased = view as? AnyView {
            self = erased
        } else {
            storage = AnyViewStorage(view)
        }
    }

    /// Creates an instance that type-erases `view`.
    @_alwaysEmitIntoClient
    public init<V: View>(erasing view: V) {
        self.init(view)
    }

    /// Creates an instance from an untyped value, if that value is a view.
    public init?(_fromValue value: Any) {
        guard let view = value as? any View else { return nil }
        self.init(_opening: view)
    }

    private init(_opening view: any View) {
        self.init(view)
    }

    /// The dynamic type of the wrapped view. Used by the runtime to decide whether the wrapped
    /// hierarchy must be rebuilt.
    package var viewType: Any.Type {
        storage.viewType
    }

    /// Opens the type-erased view for a generic visitor.
    package func visit<Visitor: _AnyViewVisitor>(_ visitor: inout Visitor) -> Visitor.Result {
        storage.visit(&visitor)
    }
}

extension AnyView: View {
    public typealias Body = Never
}

/// A visitor that can receive the concrete view stored in an `AnyView`.
package protocol _AnyViewVisitor {
    associatedtype Result
    mutating func visit<V: View>(_ view: V) -> Result
}

@usableFromInline
package class AnyViewStorageBase {
    @usableFromInline
    package init() {}

    package var viewType: Any.Type {
        fatalError("AnyViewStorageBase is abstract")
    }

    package func visit<Visitor: _AnyViewVisitor>(_ visitor: inout Visitor) -> Visitor.Result {
        fatalError("AnyViewStorageBase is abstract")
    }
}

package final class AnyViewStorage<V: View>: AnyViewStorageBase {
    package let view: V

    package init(_ view: V) {
        self.view = view
        super.init()
    }

    package override var viewType: Any.Type {
        V.self
    }

    package override func visit<Visitor: _AnyViewVisitor>(_ visitor: inout Visitor) -> Visitor.Result {
        visitor.visit(view)
    }
}
