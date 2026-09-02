/// A view created from a Swift tuple of view values.
///
/// `ViewBuilder.buildBlock` produces one of these for blocks with two or more children. The
/// runtime treats it as a list: its children contribute directly to the enclosing layout.
@frozen
public struct TupleView<T> {
    public var value: T

    @inlinable
    public init(_ value: T) {
        self.value = value
    }
}

extension TupleView: View {
    public typealias Body = Never
}
