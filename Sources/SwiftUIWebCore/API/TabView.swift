// TabView (Docs/elements/TabView.md): the macOS tab view, a segmented tab bar over a bordered
// content box; `tabItem`, `TabViewStyle`.

/// A view that switches between multiple child views using interactive user interface elements.
public struct TabView<SelectionValue: Hashable, Content: View>: View {
    package let selection: Binding<SelectionValue>?
    package let content: Content

    /// Creates a tab view that switches by a selection binding matching the tabs' tags.
    public init(selection: Binding<SelectionValue>?, @ViewBuilder content: () -> Content) {
        self.selection = selection
        self.content = content()
    }

    public var body: some View {
        if let selection {
            _TabViewHost(selection: _TabSelection(selection), content: AnyView(content))
        } else {
            _StatefulTabView(content: AnyView(content))
        }
    }
}

extension TabView where SelectionValue == Int {
    /// Creates a tab view that keeps its own selection (the first tab at first).
    public init(@ViewBuilder content: () -> Content) {
        selection = nil
        self.content = content()
    }
}

/// A tab view without a binding keeps its own selection by tab index.
package struct _StatefulTabView: View {
    package let content: AnyView
    @State private var selection = 0

    package init(content: AnyView) { self.content = content }

    package var body: some View {
        _TabViewHost(selection: _TabSelection($selection), content: content)
    }
}

/// A tab view's selection, type-erased (a class so field reflection ignores it): the selected
/// tag, and selecting a tag.
@MainActor
package final class _TabSelection {
    package let isSelected: (AnyHashable) -> Bool
    package let select: (AnyHashable) -> Void
    /// Reads the binding (observation tracking in a view body).
    package let read: () -> Void

    package init<V: Hashable>(_ binding: Binding<V>) {
        read = { _ = binding.wrappedValue }
        isSelected = { tag in (tag.base as? V).map { $0 == binding.wrappedValue } ?? false }
        select = { tag in if let value = tag.base as? V { binding.wrappedValue = value } }
    }
}

/// The primitive: the tab bar and the selected tab's content (`TabViewNode`).
public struct _TabViewHost {
    package let selection: _TabSelection
    package let content: AnyView

    package init(selection: _TabSelection, content: AnyView) {
        self.selection = selection
        self.content = content
    }
}

extension _TabViewHost: View {
    public var body: some View {
        // Read the selection here so a change re-renders the tab view.
        selection.read()
        return _TabViewPrimitive(selection: selection, content: content)
    }
}

public struct _TabViewPrimitive {
    package let selection: _TabSelection
    package let content: AnyView
    package init(selection: _TabSelection, content: AnyView) {
        self.selection = selection
        self.content = content
    }
}

extension _TabViewPrimitive: View {
    public typealias Body = Never
    public static func _makeNode(_ context: _NodeContext<_TabViewPrimitive>) -> TypedNode<_TabViewPrimitive> {
        TabViewNode(context)
    }
}

// MARK: - tabItem

/// `tabItem`: the label of a tab (its text titles the tab bar's segment).
public struct _TabItemModifier {
    package let label: AnyView
}

extension _TabItemModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        TabItemNode(context)
    }
}

extension View {
    /// Sets the tab bar item associated with this view.
    nonisolated public func tabItem<V: View>(@ViewBuilder _ label: () -> V) -> some View {
        modifier(_TabItemModifier(label: AnyView(label())))
    }
}

// MARK: - Styles

/// A specification for the appearance and interaction of a tab view.
public protocol TabViewStyle {}

/// The default tab view style: the macOS tab view.
public struct DefaultTabViewStyle: TabViewStyle {
    public init() {}
}

extension TabViewStyle where Self == DefaultTabViewStyle {
    public static var automatic: DefaultTabViewStyle { DefaultTabViewStyle() }
}

extension View {
    /// Sets the style for the tab view within the current environment (only the default exists here).
    nonisolated public func tabViewStyle<S: TabViewStyle>(_ style: S) -> some View {
        self
    }
}
