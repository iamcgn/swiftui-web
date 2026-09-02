/// A value with a modifier applied to it.
@frozen
public struct ModifiedContent<Content, Modifier> {
    /// The content that the modifier transforms into a new view or new view modifier.
    public var content: Content

    /// The view modifier.
    public var modifier: Modifier

    /// A structure that the defines the content and modifier needed to produce a new view or view
    /// modifier.
    @inlinable
    public init(content: Content, modifier: Modifier) {
        self.content = content
        self.modifier = modifier
    }
}

extension ModifiedContent: View where Content: View, Modifier: ViewModifier {
    public typealias Body = Never
}

extension ModifiedContent: ViewModifier where Content: ViewModifier, Modifier: ViewModifier {
    public typealias Body = Never
}

extension ModifiedContent: Equatable where Content: Equatable, Modifier: Equatable {}
