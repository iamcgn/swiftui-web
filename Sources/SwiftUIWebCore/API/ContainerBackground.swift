// `containerBackground(_:for:)` (sw-modifiers): the background a container shows behind its
// content (a navigation stack, a tab view, a widget, a subscription store). Here the background
// is painted behind the view the modifier is on, which is the container's content area.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

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
    /// A widget's background. WidgetKit declares it on Apple's platforms; it sits here so a
    /// widget file that imports only SwiftUI (as many do) still finds it. A page shows no
    /// widgets, so a widget view previewed in an app draws it as an ordinary background.
    public static let widget = ContainerBackgroundPlacement("widget")
}

extension View {
    /// Sets the container background of the enclosing container using a view.
    nonisolated public func containerBackground<V: View>(for container: ContainerBackgroundPlacement, alignment: Alignment = .center,
                                                         @ViewBuilder content: () -> V) -> some View {
        background(alignment: alignment, content: content)
    }

    /// The URL a widget opens in its app when tapped. A page shows no widgets, so a widget view
    /// shown in the app itself keeps it and nothing opens it.
    nonisolated public func widgetURL(_ url: URL?) -> some View {
        self
    }

    /// Sets the container background of the enclosing container using a style.
    nonisolated public func containerBackground<S: ShapeStyle>(_ style: S, for container: ContainerBackgroundPlacement) -> some View {
        background(style)
    }
}
