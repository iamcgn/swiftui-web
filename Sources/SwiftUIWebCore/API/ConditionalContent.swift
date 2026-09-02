/// View content that shows one of two possible children.
///
/// Produced by `ViewBuilder.buildEither` for `if`/`else` and `switch`. As in SwiftUI, the branch
/// is part of the view's identity: switching branches tears down the state of the old one.
@frozen
public struct _ConditionalContent<TrueContent, FalseContent> {
    @frozen
    @usableFromInline
    package enum Storage {
        case trueContent(TrueContent)
        case falseContent(FalseContent)
    }

    @usableFromInline
    package let storage: Storage

    @inlinable
    package init(storage: Storage) {
        self.storage = storage
    }
}

extension _ConditionalContent: View where TrueContent: View, FalseContent: View {
    public typealias Body = Never
}

/// `Optional` is a view when its wrapped type is, so `if` without `else` works in a builder.
/// A `nil` contributes nothing to the enclosing layout.
extension Optional: View where Wrapped: View {
    public typealias Body = Never
}
