// `containerBackground(_:for:)` (sw-modifiers): the background a container shows behind its
// content (a navigation stack, a tab view, a widget, a subscription store). Here the background
// is painted behind the view the modifier is on, which is the container's content area.

/// The kind of container a `containerBackground` modifier is for.
public struct ContainerBackgroundPlacement: Sendable {
    package let name: String
    package init(_ name: String) { self.name = name }

    /// The background of a navigation stack or split view's columns.
    public static let navigation = ContainerBackgroundPlacement("navigation")
    /// The background of a navigation split view.
    public static let navigationSplitView = ContainerBackgroundPlacement("navigationSplitView")
    /// The background of a tab view's pages.
    public static let tabView = ContainerBackgroundPlacement("tabView")
}

extension View {
    /// Sets the container background of the enclosing container using a view.
    nonisolated public func containerBackground<V: View>(for container: ContainerBackgroundPlacement, alignment: Alignment = .center,
                                                         @ViewBuilder content: () -> V) -> some View {
        background(alignment: alignment, content: content)
    }

    /// Sets the container background of the enclosing container using a style.
    nonisolated public func containerBackground<S: ShapeStyle>(_ style: S, for container: ContainerBackgroundPlacement) -> some View {
        background(style)
    }
}
