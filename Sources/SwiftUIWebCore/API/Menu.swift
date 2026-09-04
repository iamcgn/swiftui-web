// Menu: a pull-down button that presents its content as a menu (Docs/elements/Menu.md), the
// menu styles, `menuIndicator`, `menuOrder`, and `contextMenu` (a menu at the pointer on a
// secondary click). Menus reuse the presentation layer (`_PresentationKind.menu`/`.submenu`).
import Foundation

/// A control for presenting a menu of actions.
public struct Menu<Label: View, Content: View>: View {
    package let label: Label
    package let content: Content
    package let primaryAction: _ActionBox?

    /// Creates a menu with a custom label.
    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.label = label()
        self.content = content()
        self.primaryAction = nil
    }

    /// Creates a menu with a custom label and a primary action performed by a press on the
    /// label part of the button (a split button); the indicator part opens the menu.
    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label, primaryAction: @escaping @MainActor () -> Void) {
        self.label = label()
        self.content = content()
        self.primaryAction = _ActionBox(primaryAction)
    }

    @Environment(\.menuStyle) private var style
    @Environment(\._menuIndicator) private var indicator
    @Environment(\._inMenu) private var inMenu

    public var body: some View {
        if inMenu {
            // A menu inside a menu is a row that opens a submenu next to it.
            _SubmenuHost(label: AnyView(label), content: AnyView(content))
        } else {
            let configuration = MenuStyleConfiguration(label: AnyView(label), content: AnyView(content), primaryAction: primaryAction,
                                                       indicator: indicator != .hidden)
            style.makeBodyErased(configuration)
        }
    }
}

extension Menu where Label == Text {
    /// Creates a menu that generates its label from a localized string key.
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.init(content: content) { Text(titleKey) }
    }

    /// Creates a menu that generates its label from a string.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {
        self.init(content: content) { Text(title) }
    }

    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content, primaryAction: @escaping @MainActor () -> Void) {
        self.init(content: content, label: { Text(titleKey) }, primaryAction: primaryAction)
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content, primaryAction: @escaping @MainActor () -> Void) {
        self.init(content: content, label: { Text(title) }, primaryAction: primaryAction)
    }
}

extension Menu where Label == SwiftUIWebCore.Label<Text, Image> {
    /// Creates a menu that generates its label from a localized string key and a system image.
    public init(_ titleKey: LocalizedStringKey, systemImage: String, @ViewBuilder content: () -> Content) {
        self.init(content: content) { SwiftUIWebCore.Label(titleKey, systemImage: systemImage) }
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, systemImage: String, @ViewBuilder content: () -> Content) {
        self.init(content: content) { SwiftUIWebCore.Label(title, systemImage: systemImage) }
    }

    /// Creates a menu that generates its label from a localized string key and an image resource.
    public init(_ titleKey: LocalizedStringKey, image: String, @ViewBuilder content: () -> Content) {
        self.init(content: content) { SwiftUIWebCore.Label(titleKey, image: image) }
    }
}

extension Menu where Label == MenuStyleConfiguration.Label, Content == MenuStyleConfiguration.Content {
    /// Creates a menu based on a style configuration (custom `MenuStyle`s).
    public init(_ configuration: MenuStyleConfiguration) {
        self.label = configuration.label
        self.content = configuration.content
        self.primaryAction = configuration.primaryAction
    }
}

// MARK: - Styles

/// The properties of a menu.
public struct MenuStyleConfiguration {
    /// A type-erased label of a menu.
    public struct Label {
        package let view: AnyView
        package init(view: AnyView) { self.view = view }
    }

    /// A type-erased content of a menu.
    public struct Content {
        package let view: AnyView
        package init(view: AnyView) { self.view = view }
    }

    public let label: Label
    public let content: Content
    package let primaryAction: _ActionBox?
    package let indicator: Bool

    package init(label: AnyView, content: AnyView, primaryAction: _ActionBox?, indicator: Bool) {
        self.label = Label(view: label)
        self.content = Content(view: content)
        self.primaryAction = primaryAction
        self.indicator = indicator
    }
}

extension MenuStyleConfiguration.Label: View {
    public var body: some View { view }
}

extension MenuStyleConfiguration.Content: View {
    public var body: some View { view }
}

/// A type that applies standard interaction behavior and a custom appearance to all menus
/// within a view hierarchy.
public protocol MenuStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = MenuStyleConfiguration
}

extension MenuStyle {
    @MainActor
    package func makeBodyErased(_ configuration: Configuration) -> AnyView {
        AnyView(makeBody(configuration: configuration))
    }
}

/// The default menu style, based on the menu's context (a pull-down button on macOS).
public struct DefaultMenuStyle {
    public init() {}
}

extension DefaultMenuStyle: MenuStyle {
    public func makeBody(configuration: Configuration) -> some View {
        _MenuHost(label: AnyView(configuration.label), content: AnyView(configuration.content), primaryAction: configuration.primaryAction,
                  indicator: configuration.indicator, bordered: true)
    }
}

/// A menu style that displays a button that toggles the display of the menu's contents when
/// pressed (the same pull-down button as the default on macOS).
public struct ButtonMenuStyle {
    public init() {}
}

extension ButtonMenuStyle: MenuStyle {
    public func makeBody(configuration: Configuration) -> some View {
        _MenuHost(label: AnyView(configuration.label), content: AnyView(configuration.content), primaryAction: configuration.primaryAction,
                  indicator: configuration.indicator, bordered: true)
    }
}

/// A menu style that displays a borderless button that toggles the display of the menu's
/// contents when pressed.
public struct BorderlessButtonMenuStyle {
    public init() {}
}

extension BorderlessButtonMenuStyle: MenuStyle {
    public func makeBody(configuration: Configuration) -> some View {
        _MenuHost(label: AnyView(configuration.label), content: AnyView(configuration.content), primaryAction: configuration.primaryAction,
                  indicator: configuration.indicator, bordered: false)
    }
}

extension MenuStyle where Self == DefaultMenuStyle {
    public static var automatic: DefaultMenuStyle { DefaultMenuStyle() }
}

extension MenuStyle where Self == ButtonMenuStyle {
    public static var button: ButtonMenuStyle { ButtonMenuStyle() }
}

extension MenuStyle where Self == BorderlessButtonMenuStyle {
    public static var borderlessButton: BorderlessButtonMenuStyle { BorderlessButtonMenuStyle() }
}

package struct MenuStyleKey: EnvironmentKey {
    // `MenuStyle` is not Sendable (as in SwiftUI); the default is an immutable value type.
    package nonisolated(unsafe) static let defaultValue: any MenuStyle = DefaultMenuStyle()
}

package struct MenuIndicatorKey: EnvironmentKey {
    package static let defaultValue: Visibility = .automatic
}

package struct InMenuKey: EnvironmentKey {
    package static let defaultValue = false
}

extension EnvironmentValues {
    package var menuStyle: any MenuStyle {
        get { self[MenuStyleKey.self] }
        set { self[MenuStyleKey.self] = newValue }
    }

    package var _menuIndicator: Visibility {
        get { self[MenuIndicatorKey.self] }
        set { self[MenuIndicatorKey.self] = newValue }
    }

    /// Whether the view is inside a presented menu: buttons and menus become rows, dividers
    /// become separators.
    package var _inMenu: Bool {
        get { self[InMenuKey.self] }
        set { self[InMenuKey.self] = newValue }
    }
}

/// The order in which a menu presents its content.
public struct MenuOrder: Equatable, Hashable, Sendable {
    package let kind: Int
    public static let automatic = MenuOrder(kind: 0)
    public static let fixed = MenuOrder(kind: 1)
    public static let priority = MenuOrder(kind: 2)
}

extension View {
    /// Sets the style for menus within this view.
    nonisolated public func menuStyle<S: MenuStyle>(_ style: S) -> some View {
        environment(\.menuStyle, style)
    }

    /// Sets the menu indicator visibility for controls within this view.
    nonisolated public func menuIndicator(_ visibility: Visibility) -> some View {
        environment(\._menuIndicator, visibility)
    }

    /// Sets the preferred order of items for menus presented from this view (menus always
    /// present in fixed order here).
    nonisolated public func menuOrder(_ order: MenuOrder) -> some View {
        self
    }

    /// Adds a context menu to a view: a secondary click (right click) presents `menuItems` at
    /// the pointer.
    nonisolated public func contextMenu<M: View>(@ViewBuilder menuItems: () -> M) -> some View {
        modifier(_ContextMenuModifier(content: AnyView(menuItems())))
    }

    /// Adds a context menu with a preview (the preview is not shown here).
    nonisolated public func contextMenu<M: View, P: View>(@ViewBuilder menuItems: () -> M, @ViewBuilder preview: () -> P) -> some View {
        modifier(_ContextMenuModifier(content: AnyView(menuItems())))
    }
}

// MARK: - Primitives

/// The pull-down button: its label, the content presented on a press, an optional primary
/// action (split button), the indicator and the bordered look.
public struct _MenuHost {
    package let label: AnyView
    package let content: AnyView
    package let primaryAction: _ActionBox?
    package let indicator: Bool
    package let bordered: Bool

    package init(label: AnyView, content: AnyView, primaryAction: _ActionBox?, indicator: Bool, bordered: Bool) {
        self.label = label
        self.content = content
        self.primaryAction = primaryAction
        self.indicator = indicator
        self.bordered = bordered
    }
}

extension _MenuHost: View {
    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<_MenuHost>) -> TypedNode<_MenuHost> {
        MenuButtonNode(context)
    }
}

/// A menu row that opens a submenu.
public struct _SubmenuHost {
    package let label: AnyView
    package let content: AnyView

    package init(label: AnyView, content: AnyView) {
        self.label = label
        self.content = content
    }
}

extension _SubmenuHost: View {
    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<_SubmenuHost>) -> TypedNode<_SubmenuHost> {
        SubmenuRowNode(context)
    }
}

/// Presents a menu on a secondary click. Transparent to layout.
public struct _ContextMenuModifier {
    package let content: AnyView
}

extension _ContextMenuModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        ContextMenuNode(context)
    }
}

/// A presented menu's content: the items in a column with the menu's vertical padding; buttons
/// dismiss every open menu after their action.
package struct _MenuContent: View {
    package let content: AnyView

    package init(content: AnyView) { self.content = content }

    package var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.vertical, PlatformMetrics.menuVerticalPadding)
            .environment(\._inMenu, true)
            ._dismissesOnActivation()
    }
}

/// A menu item's row: the label after the check column, a submenu chevron at the trailing edge,
/// at least the menu's minimum width and row height.
package struct _MenuRowLabel: View {
    package let label: AnyView
    package let submenu: Bool

    package init(label: AnyView, submenu: Bool) {
        self.label = label
        self.submenu = submenu
    }

    package var body: some View {
        // The label after the check column; a submenu's chevron overlays the trailing edge so
        // the row keeps the label's ideal width and spans the menu when placed.
        label
            .padding(.leading, PlatformMetrics.menuCheckWidth)
            .padding(.trailing, PlatformMetrics.menuTrailingPadding + (submenu ? PlatformMetrics.menuSubmenuChevronGap + PlatformMetrics.menuSubmenuChevronSize.width : 0))
            .frame(minWidth: PlatformMetrics.menuMinimumWidth, minHeight: PlatformMetrics.menuRowHeight, alignment: .leading)
            .overlay(alignment: .trailing) {
                if submenu {
                    _MenuChevron().stroke(style: StrokeStyle(lineWidth: PlatformMetrics.menuSubmenuChevronStroke, lineCap: .round, lineJoin: .round))
                        .frame(width: PlatformMetrics.menuSubmenuChevronSize.width, height: PlatformMetrics.menuSubmenuChevronSize.height)
                        .padding(.trailing, PlatformMetrics.menuTrailingPadding)
                }
            }
            .font(.system(size: PlatformMetrics.buttonLabelSize))
    }
}

/// A right-pointing chevron filling its rect.
package struct _MenuChevron: Sendable {
    package init() {}
}

extension _MenuChevron: Shape {
    package func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return path
    }
}
