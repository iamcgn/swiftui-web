/// A view that doesn't contain any content.
@frozen
public struct EmptyView: Sendable {
    @inlinable
    public init() {}
}

extension EmptyView: View {
    public typealias Body = Never
}
