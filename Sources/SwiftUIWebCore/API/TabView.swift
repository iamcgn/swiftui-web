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

// MARK: - The Tab API (iOS 18, macOS 15)

/// A type that provides content for a tab view: `Tab` and the views the builder joins.
public protocol TabContent: View {}

/// The builder of a tab view's tabs: the view builder, as every tab is a view here.
public typealias TabContentBuilder<SelectionValue> = ViewBuilder

/// A tab of a tab view: its label (a title with a symbol or image) and its content, selected by
/// its value. A tab without a value is selected by its position.
public struct Tab<Value: Hashable, Content: View, Label: View>: TabContent {
    package let value: Value?
    package let content: Content
    package let label: Label

    /// Creates a tab with a custom label.
    public init(value: Value, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.value = value
        self.content = content()
        self.label = label()
    }

    public var body: some View {
        if let value {
            content.tabItem { label }.tag(value)
        } else {
            content.tabItem { label }
        }
    }
}

extension Tab where Label == SwiftUIWebCore.Label<Text, Image> {
    /// Creates a tab with a title and a system image, selected by `value`.
    public init(_ title: LocalizedStringKey, systemImage: String, value: Value, @ViewBuilder content: () -> Content) {
        self.init(value: value, content: content) { SwiftUIWebCore.Label(title, systemImage: systemImage) }
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, systemImage: String, value: Value, @ViewBuilder content: () -> Content) {
        self.init(value: value, content: content) { SwiftUIWebCore.Label(title, systemImage: systemImage) }
    }

    /// Creates a tab with a title and a catalog image, selected by `value`.
    public init(_ title: LocalizedStringKey, image: String, value: Value, @ViewBuilder content: () -> Content) {
        self.init(value: value, content: content) { SwiftUIWebCore.Label(title, image: image) }
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, image: String, value: Value, @ViewBuilder content: () -> Content) {
        self.init(value: value, content: content) { SwiftUIWebCore.Label(title, image: image) }
    }
}

extension Tab where Value == Never {
    /// Creates a tab with a custom label, selected by its position.
    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        value = nil
        self.content = content()
        self.label = label()
    }
}

extension Tab where Value == Never, Label == SwiftUIWebCore.Label<Text, Image> {
    /// Creates a tab with a title and a system image, selected by its position.
    public init(_ title: LocalizedStringKey, systemImage: String, @ViewBuilder content: () -> Content) {
        self.init(content: content) { SwiftUIWebCore.Label(title, systemImage: systemImage) }
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, systemImage: String, @ViewBuilder content: () -> Content) {
        self.init(content: content) { SwiftUIWebCore.Label(title, systemImage: systemImage) }
    }

    public init(_ title: LocalizedStringKey, image: String, @ViewBuilder content: () -> Content) {
        self.init(content: content) { SwiftUIWebCore.Label(title, image: image) }
    }
}

// MARK: - Badges

/// `badge`: a count or a text shown on the tab's item (iOS: a red capsule on the symbol).
public struct _BadgeModifier {
    package let text: String?
    package init(text: String?) { self.text = text }
}

extension _BadgeModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        BadgeNode(context)
    }
}

extension View {
    /// Generates a badge for the view from an integer value (0 shows none).
    nonisolated public func badge(_ count: Int) -> some View {
        modifier(_BadgeModifier(text: count == 0 ? nil : "\(count)"))
    }

    /// Generates a badge for the view from a text view.
    nonisolated public func badge(_ label: Text?) -> some View {
        modifier(_BadgeModifier(text: label?.resolvedString))
    }

    /// Generates a badge for the view from a localized string key.
    nonisolated public func badge(_ key: LocalizedStringKey?) -> some View {
        modifier(_BadgeModifier(text: key?.key))
    }

    /// Generates a badge for the view from a string.
    @_disfavoredOverload
    nonisolated public func badge<S: StringProtocol>(_ label: S?) -> some View {
        modifier(_BadgeModifier(text: label.map { String($0) }))
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
    @Environment(\._tabViewStyle) private var style

    package init(selection: _TabSelection, content: AnyView) {
        self.selection = selection
        self.content = content
    }
}

extension _TabViewHost: View {
    public var body: some View {
        // Read the selection here so a change re-renders the tab view.
        selection.read()
        if style._isPaged {
            return AnyView(_PagedTabViewPrimitive(selection: selection, content: content, showsIndex: style._indexDisplayMode.shows))
        }
        return AnyView(_TabViewPrimitive(selection: selection, content: content))
    }
}

/// The page style's primitive: the tabs side by side, one in view (`PagedTabViewNode`).
public struct _PagedTabViewPrimitive {
    package let selection: _TabSelection
    package let content: AnyView
    package let showsIndex: Bool
    package init(selection: _TabSelection, content: AnyView, showsIndex: Bool) {
        self.selection = selection
        self.content = content
        self.showsIndex = showsIndex
    }
}

extension _PagedTabViewPrimitive: View {
    public typealias Body = Never
    public static func _makeNode(_ context: _NodeContext<_PagedTabViewPrimitive>) -> TypedNode<_PagedTabViewPrimitive> {
        PagedTabViewNode(context)
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
public protocol TabViewStyle {
    /// Whether the tabs are pages scrolled side by side (`page`) rather than a bar's choices.
    var _isPaged: Bool { get }
    /// The page style's index display mode (`always` for the other styles, which show no dots).
    var _indexDisplayMode: PageTabViewStyle.IndexDisplayMode { get }
}

extension TabViewStyle {
    public var _isPaged: Bool { false }
    public var _indexDisplayMode: PageTabViewStyle.IndexDisplayMode { .never }
}

/// The default tab view style: the macOS tab view, the iOS tab bar.
public struct DefaultTabViewStyle: TabViewStyle {
    public init() {}
}

/// A tab view style that displays a tab bar when possible (the default look here).
public struct TabBarOnlyTabViewStyle: TabViewStyle {
    public init() {}
}

/// A tab view style that adapts to a sidebar (the default look here).
public struct SidebarAdaptableTabViewStyle: TabViewStyle {
    public init() {}
}

/// A tab view style that groups its sections (the default look here).
public struct GroupedTabViewStyle: TabViewStyle {
    public init() {}
}

/// A tab view style that shows the tabs as pages scrolled side by side, with a page indicator.
public struct PageTabViewStyle: TabViewStyle {
    /// Whether the page indicator shows.
    public struct IndexDisplayMode: Hashable, Sendable {
        package let shows: Bool
        /// Shows the indicator when there is more than one page.
        public static let automatic = IndexDisplayMode(shows: true)
        public static let always = IndexDisplayMode(shows: true)
        public static let never = IndexDisplayMode(shows: false)
    }

    public var indexDisplayMode: IndexDisplayMode

    public init(indexDisplayMode: IndexDisplayMode = .automatic) {
        self.indexDisplayMode = indexDisplayMode
    }

    public var _isPaged: Bool { true }
    public var _indexDisplayMode: IndexDisplayMode { indexDisplayMode }
}

extension TabViewStyle where Self == DefaultTabViewStyle {
    public static var automatic: DefaultTabViewStyle { DefaultTabViewStyle() }
}
extension TabViewStyle where Self == TabBarOnlyTabViewStyle {
    public static var tabBarOnly: TabBarOnlyTabViewStyle { TabBarOnlyTabViewStyle() }
}
extension TabViewStyle where Self == SidebarAdaptableTabViewStyle {
    public static var sidebarAdaptable: SidebarAdaptableTabViewStyle { SidebarAdaptableTabViewStyle() }
}
extension TabViewStyle where Self == GroupedTabViewStyle {
    public static var grouped: GroupedTabViewStyle { GroupedTabViewStyle() }
}
extension TabViewStyle where Self == PageTabViewStyle {
    public static var page: PageTabViewStyle { PageTabViewStyle() }
    public static func page(indexDisplayMode: PageTabViewStyle.IndexDisplayMode) -> PageTabViewStyle { PageTabViewStyle(indexDisplayMode: indexDisplayMode) }
}

package struct TabViewStyleKey: EnvironmentKey {
    package nonisolated(unsafe) static let defaultValue: any TabViewStyle = DefaultTabViewStyle()
}

extension EnvironmentValues {
    package var _tabViewStyle: any TabViewStyle {
        get { self[TabViewStyleKey.self] }
        set { self[TabViewStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets the style for the tab view within the current environment: the page style scrolls
    /// the tabs side by side; the others take the platform's bar.
    nonisolated public func tabViewStyle<S: TabViewStyle>(_ style: S) -> some View {
        environment(\._tabViewStyle, style)
    }
}
