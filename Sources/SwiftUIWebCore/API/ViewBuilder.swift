/// A custom parameter attribute that constructs views from closures.
///
/// Mirrors Apple's `ViewBuilder`. `buildBlock` uses a parameter pack, so a block may contain any
/// number of child views (Apple lifted the 10-view limit the same way in the iOS 17 SDK).
@resultBuilder
public enum ViewBuilder {
    /// Builds an empty view from a block containing no statements.
    @inlinable
    public static func buildBlock() -> EmptyView {
        EmptyView()
    }

    /// Passes a single view written as a child view through unmodified.
    @inlinable
    public static func buildBlock<Content: View>(_ content: Content) -> Content {
        content
    }

    /// Builds a tuple view from two or more child views.
    @inlinable
    public static func buildBlock<each Content: View>(
        _ content: repeat each Content
    ) -> TupleView<(repeat each Content)> {
        TupleView((repeat each content))
    }

    @inlinable
    public static func buildExpression<Content: View>(_ content: Content) -> Content {
        content
    }

    /// Provides support for `if` statements in multi-statement closures, producing an optional
    /// view that is visible only when the `if` condition evaluates `true`.
    @inlinable
    public static func buildOptional<Content: View>(_ content: Content?) -> Content? {
        content
    }

    @inlinable
    public static func buildIf<Content: View>(_ content: Content?) -> Content? {
        content
    }

    /// Provides support for `if`/`else` (and `switch`) statements, producing conditional content
    /// for the `true` branch.
    @inlinable
    public static func buildEither<TrueContent: View, FalseContent: View>(
        first: TrueContent
    ) -> _ConditionalContent<TrueContent, FalseContent> {
        _ConditionalContent(storage: .trueContent(first))
    }

    /// Provides support for `if`/`else` (and `switch`) statements, producing conditional content
    /// for the `false` branch.
    @inlinable
    public static func buildEither<TrueContent: View, FalseContent: View>(
        second: FalseContent
    ) -> _ConditionalContent<TrueContent, FalseContent> {
        _ConditionalContent(storage: .falseContent(second))
    }

    /// Provides support for `if #available` statements: the wrapped view is type-erased because
    /// its type is only known inside the availability check.
    @inlinable
    public static func buildLimitedAvailability<Content: View>(_ content: Content) -> AnyView {
        AnyView(content)
    }
}
