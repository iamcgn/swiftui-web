// NavigationSplitView (Docs/elements/NavigationSplitView.md): the macOS sidebar (a rounded
// panel inset 8 pt), an optional content column, and the detail area; column widths and
// visibility.

/// A view that presents views in two or three columns, where selections in leading columns
/// control presentations in subsequent columns.
public struct NavigationSplitView<Sidebar: View, Content: View, Detail: View>: View {
    package let sidebar: Sidebar
    package let content: Content?
    package let detail: Detail
    package let visibility: Binding<NavigationSplitViewVisibility>?
    @State private var localVisibility = NavigationSplitViewVisibility.automatic

    /// Creates a two-column navigation split view.
    public init(@ViewBuilder sidebar: () -> Sidebar, @ViewBuilder detail: () -> Detail) where Content == EmptyView {
        self.sidebar = sidebar()
        self.content = nil
        self.detail = detail()
        self.visibility = nil
    }

    /// Creates a three-column navigation split view.
    public init(@ViewBuilder sidebar: () -> Sidebar, @ViewBuilder content: () -> Content, @ViewBuilder detail: () -> Detail) {
        self.sidebar = sidebar()
        self.content = content()
        self.detail = detail()
        self.visibility = nil
    }

    /// Creates a two-column navigation split view that enables programmatic control of the
    /// sidebar's visibility.
    public init(columnVisibility: Binding<NavigationSplitViewVisibility>, @ViewBuilder sidebar: () -> Sidebar,
                @ViewBuilder detail: () -> Detail) where Content == EmptyView {
        self.sidebar = sidebar()
        self.content = nil
        self.detail = detail()
        self.visibility = columnVisibility
    }

    /// Creates a three-column navigation split view that enables programmatic control of
    /// leading columns' visibility.
    public init(columnVisibility: Binding<NavigationSplitViewVisibility>, @ViewBuilder sidebar: () -> Sidebar,
                @ViewBuilder content: () -> Content, @ViewBuilder detail: () -> Detail) {
        self.sidebar = sidebar()
        self.content = content()
        self.detail = detail()
        self.visibility = columnVisibility
    }

    /// The preferred compact column is a compact-width (iOS) concern: accepted, without effect.
    public init(preferredCompactColumn: Binding<NavigationSplitViewColumn>, @ViewBuilder sidebar: () -> Sidebar,
                @ViewBuilder detail: () -> Detail) where Content == EmptyView {
        self.init(sidebar: sidebar, detail: detail)
    }

    public init(preferredCompactColumn: Binding<NavigationSplitViewColumn>, @ViewBuilder sidebar: () -> Sidebar,
                @ViewBuilder content: () -> Content, @ViewBuilder detail: () -> Detail) {
        self.init(sidebar: sidebar, content: content, detail: detail)
    }

    public init(columnVisibility: Binding<NavigationSplitViewVisibility>, preferredCompactColumn: Binding<NavigationSplitViewColumn>,
                @ViewBuilder sidebar: () -> Sidebar, @ViewBuilder detail: () -> Detail) where Content == EmptyView {
        self.init(columnVisibility: columnVisibility, sidebar: sidebar, detail: detail)
    }

    public init(columnVisibility: Binding<NavigationSplitViewVisibility>, preferredCompactColumn: Binding<NavigationSplitViewColumn>,
                @ViewBuilder sidebar: () -> Sidebar, @ViewBuilder content: () -> Content, @ViewBuilder detail: () -> Detail) {
        self.init(columnVisibility: columnVisibility, sidebar: sidebar, content: content, detail: detail)
    }

    public var body: some View {
        let binding = visibility ?? $localVisibility
        // Read the visibility inside the body so observation tracks the model it comes from.
        let value = binding.wrappedValue
        _NavigationSplitViewHost(sidebar: AnyView(sidebar), content: content.map { AnyView($0) }, detail: AnyView(detail),
                                 visibility: value, binding: _SplitVisibilityBinding(binding))
    }
}

/// The visibility of the leading columns in a navigation split view.
public struct NavigationSplitViewVisibility: Equatable, Hashable, Sendable {
    package enum Kind: Hashable, Sendable { case automatic, all, doubleColumn, detailOnly }
    package let kind: Kind

    /// Show all the columns of a three-column navigation split view.
    public static let all = NavigationSplitViewVisibility(kind: .all)
    /// Show the content column and detail area of a three-column navigation split view, or the
    /// sidebar column and detail area of a two-column navigation split view.
    public static let doubleColumn = NavigationSplitViewVisibility(kind: .doubleColumn)
    /// Hide the leading two columns of a three-column navigation split view, or the leading
    /// column of a two-column navigation split view.
    public static let detailOnly = NavigationSplitViewVisibility(kind: .detailOnly)
    /// Use the default leading column visibility for the current device (all columns here).
    public static let automatic = NavigationSplitViewVisibility(kind: .automatic)
}

/// A view that represents a column in a navigation split view.
public struct NavigationSplitViewColumn: Equatable, Hashable, Sendable {
    package enum Kind: Hashable, Sendable { case sidebar, content, detail }
    package let kind: Kind

    public static let sidebar = NavigationSplitViewColumn(kind: .sidebar)
    public static let content = NavigationSplitViewColumn(kind: .content)
    public static let detail = NavigationSplitViewColumn(kind: .detail)
}

/// Type-erased access to the visibility binding (a class so field reflection ignores it).
@MainActor
package final class _SplitVisibilityBinding {
    package let get: () -> NavigationSplitViewVisibility
    package let set: (NavigationSplitViewVisibility) -> Void

    package init(_ binding: Binding<NavigationSplitViewVisibility>) {
        get = { binding.wrappedValue }
        set = { binding.wrappedValue = $0 }
    }
}

/// The primitive a `NavigationSplitView` resolves to (`NavigationSplitViewNode`).
public struct _NavigationSplitViewHost: View {
    package let sidebar: AnyView
    package let content: AnyView?
    package let detail: AnyView
    package let visibility: NavigationSplitViewVisibility
    package let binding: _SplitVisibilityBinding

    package init(sidebar: AnyView, content: AnyView?, detail: AnyView, visibility: NavigationSplitViewVisibility, binding: _SplitVisibilityBinding) {
        self.sidebar = sidebar
        self.content = content
        self.detail = detail
        self.visibility = visibility
        self.binding = binding
    }

    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<_NavigationSplitViewHost>) -> TypedNode<_NavigationSplitViewHost> {
        NavigationSplitViewNode(context)
    }
}

// MARK: - Column widths

/// A column's width: fixed, or an ideal clamped to a range.
package struct _SplitColumnWidth: Equatable {
    package var min: CGFloat?
    package var ideal: CGFloat?
    package var max: CGFloat?

    /// The width the column takes given the platform default.
    package func resolved(default fallback: CGFloat) -> CGFloat {
        var width = ideal ?? fallback
        if let min { width = Swift.max(width, min) }
        if let max { width = Swift.min(width, max) }
        return width
    }
}

/// A `navigationSplitViewColumnWidth` modifier: transparent for layout, read by the enclosing
/// split view.
public struct _NavigationSplitViewColumnWidthModifier {
    package let width: _SplitColumnWidth
    package init(width: _SplitColumnWidth) { self.width = width }
}

extension _NavigationSplitViewColumnWidthModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        SplitColumnWidthNode(context)
    }
}

extension View {
    /// Sets a fixed, preferred width for the column containing this view.
    nonisolated public func navigationSplitViewColumnWidth(_ width: CGFloat) -> some View {
        modifier(_NavigationSplitViewColumnWidthModifier(width: _SplitColumnWidth(min: width, ideal: width, max: width)))
    }

    /// Sets a flexible, preferred width for the column containing this view.
    nonisolated public func navigationSplitViewColumnWidth(min: CGFloat? = nil, ideal: CGFloat, max: CGFloat? = nil) -> some View {
        modifier(_NavigationSplitViewColumnWidthModifier(width: _SplitColumnWidth(min: min, ideal: ideal, max: max)))
    }
}

// MARK: - Styles

/// A type that specifies the appearance and interaction of navigation split views within a
/// view hierarchy.
public protocol NavigationSplitViewStyle {}

/// A navigation split style that resolves its appearance automatically based on the current
/// context.
public struct AutomaticNavigationSplitViewStyle: NavigationSplitViewStyle {
    public init() {}
}

/// A navigation split style that reduces the size of the detail content to make room when
/// showing the leading column or columns.
public struct BalancedNavigationSplitViewStyle: NavigationSplitViewStyle {
    public init() {}
}

/// A navigation split style that attempts to maintain the size of the detail content when
/// hiding or showing the leading columns.
public struct ProminentDetailNavigationSplitViewStyle: NavigationSplitViewStyle {
    public init() {}
}

extension NavigationSplitViewStyle where Self == AutomaticNavigationSplitViewStyle {
    public static var automatic: AutomaticNavigationSplitViewStyle { AutomaticNavigationSplitViewStyle() }
}
extension NavigationSplitViewStyle where Self == BalancedNavigationSplitViewStyle {
    public static var balanced: BalancedNavigationSplitViewStyle { BalancedNavigationSplitViewStyle() }
}
extension NavigationSplitViewStyle where Self == ProminentDetailNavigationSplitViewStyle {
    public static var prominentDetail: ProminentDetailNavigationSplitViewStyle { ProminentDetailNavigationSplitViewStyle() }
}

extension View {
    /// Sets the style for navigation split views within this view (every style is the macOS
    /// look here).
    nonisolated public func navigationSplitViewStyle<S: NavigationSplitViewStyle>(_ style: S) -> some View {
        self
    }
}

// MARK: - Environment

package struct SidebarColumnKey: EnvironmentKey {
    package static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether the view is in a split view's sidebar column (lists default to the sidebar
    /// style, transparent over the panel).
    package var _inSidebarColumn: Bool {
        get { self[SidebarColumnKey.self] }
        set { self[SidebarColumnKey.self] = newValue }
    }
}
