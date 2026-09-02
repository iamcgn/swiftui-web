// The root of the view API. Mirrors Apple's declaration, including the `@MainActor
// @preconcurrency` isolation SwiftUI has had since the iOS 18 / macOS 15 SDKs: every type that
// conforms to `View` in its primary declaration is inferred to be main-actor isolated, exactly as
// with the real framework, so unmodified app source keeps the same isolation.
//
// Library-provided view types declare their `View` conformance in an extension instead, so their
// initializers stay nonisolated and `ViewBuilder` (which is nonisolated, like Apple's) can
// construct them from any context.

/// A type that represents part of your app's user interface and provides modifiers that you use
/// to configure views.
@MainActor @preconcurrency
public protocol View {
    /// The type of view representing the body of this view.
    associatedtype Body: View

    /// The content and behavior of the view.
    @ViewBuilder @MainActor @preconcurrency var body: Self.Body { get }
}

extension View where Body == Never {
    /// Primitive views (those the runtime renders directly) have no body. The runtime never calls
    /// this; reaching it means a primitive was treated as a composite.
    public var body: Never {
        _primitiveBodyError(Self.self)
    }
}

@inline(never)
package func _primitiveBodyError(_ type: Any.Type) -> Never {
    fatalError("\(type) is a primitive view: its body must never be evaluated")
}

/// `Never` is a view so that primitive views can declare `Body = Never`, matching SwiftUI.
extension Never: View {
    public typealias Body = Never
}
