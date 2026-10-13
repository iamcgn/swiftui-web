// `equatable()` and `EquatableView` (decision 0021: the Countries app's query container):
// a view compared by `==` before its body is read again. The runtime compares every
// `Equatable` view that way already (`_valuesDiffer`), so the wrapper's body is its content.

/// A view type that compares itself against its previous value and prevents its child
/// updating if its new value is the same as its old value.
public struct EquatableView<Content: Equatable & View>: View {
    nonisolated(unsafe) public var content: Content
    nonisolated public init(content: Content) { self.content = content }
    public var body: some View { content }
}

extension EquatableView: Equatable {
    nonisolated public static func == (lhs: EquatableView<Content>, rhs: EquatableView<Content>) -> Bool { lhs.content == rhs.content }
}

extension View where Self: Equatable {
    /// Prevents the view from updating its child view when its new value is the same as its old value.
    nonisolated public func equatable() -> EquatableView<Self> { EquatableView(content: self) }
}
