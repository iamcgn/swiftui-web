/// The view produced by `View.id(_:)`. Changing the identifier gives the content a new
/// identity: its state is discarded and its subtree rebuilt.
@frozen
public struct IDView<Content, ID: Hashable> {
    public var content: Content
    public var id: ID

    @inlinable
    public init(_ content: Content, id: ID) {
        self.content = content
        self.id = id
    }
}

extension IDView: View where Content: View {
    public typealias Body = Never
}

extension View {
    /// Binds a view's identity to the given proxy value.
    @inlinable
    nonisolated public func id<ID: Hashable>(_ id: ID) -> some View {
        IDView(self, id: id)
    }
}
