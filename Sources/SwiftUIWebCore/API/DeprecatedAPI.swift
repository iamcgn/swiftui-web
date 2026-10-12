// The deprecated forms apps still carry (sw-app-api-gaps, decision 0021): `NavigationView`
// and its styles, `navigationBarTitle`, `ContentSizeCategory` and `sizeCategory`,
// `accessibilityEnabled`, `colorScheme(_:)`, `EnvironmentalModifier`. Each maps onto the
// current API; Apple's own deprecation messages are kept so Xcode's warnings match.
import WebFoundation

// MARK: - NavigationView

/// A view for presenting a stack of views that represents a visible path in a navigation
/// hierarchy: `NavigationStack` with the deprecated name (the column styles lay out as a stack).
@available(*, deprecated, message: "use NavigationStack or NavigationSplitView instead")
public struct NavigationView<Content: View>: View {
    private let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View { NavigationStack { content } }
}

/// A specification for the appearance and interaction of a navigation view.
public protocol NavigationViewStyle {}
public struct DefaultNavigationViewStyle: NavigationViewStyle { public init() {} }
public struct StackNavigationViewStyle: NavigationViewStyle { public init() {} }
public struct ColumnNavigationViewStyle: NavigationViewStyle { public init() {} }
public struct DoubleColumnNavigationViewStyle: NavigationViewStyle { public init() {} }

extension NavigationViewStyle where Self == DefaultNavigationViewStyle {
    public static var automatic: DefaultNavigationViewStyle { DefaultNavigationViewStyle() }
}
extension NavigationViewStyle where Self == StackNavigationViewStyle {
    public static var stack: StackNavigationViewStyle { StackNavigationViewStyle() }
}
extension NavigationViewStyle where Self == ColumnNavigationViewStyle {
    public static var columns: ColumnNavigationViewStyle { ColumnNavigationViewStyle() }
}

extension View {
    /// Sets the style for navigation views within this view (accepted: every style is the stack).
    @available(*, deprecated, message: "replace styled NavigationView with NavigationStack or NavigationSplitView instead")
    nonisolated public func navigationViewStyle<S: NavigationViewStyle>(_ style: S) -> some View { self }

    // MARK: navigationBarTitle

    /// Sets the title in the navigation bar for this view.
    @available(*, deprecated, renamed: "navigationTitle(_:)")
    nonisolated public func navigationBarTitle(_ title: Text) -> some View { navigationTitle(title) }
    @available(*, deprecated, renamed: "navigationTitle(_:)")
    nonisolated public func navigationBarTitle(_ titleKey: LocalizedStringKey) -> some View { navigationTitle(titleKey) }
    @_disfavoredOverload
    @available(*, deprecated, renamed: "navigationTitle(_:)")
    nonisolated public func navigationBarTitle<S: StringProtocol>(_ title: S) -> some View { navigationTitle(title) }
    /// Sets the title and display mode in the navigation bar for this view.
    @available(*, deprecated, message: "Use navigationTitle(_:) with navigationBarTitleDisplayMode(_:)")
    nonisolated public func navigationBarTitle(_ title: Text, displayMode: NavigationBarItem.TitleDisplayMode) -> some View {
        navigationTitle(title).navigationBarTitleDisplayMode(displayMode)
    }
    @available(*, deprecated, message: "Use navigationTitle(_:) with navigationBarTitleDisplayMode(_:)")
    nonisolated public func navigationBarTitle(_ titleKey: LocalizedStringKey, displayMode: NavigationBarItem.TitleDisplayMode) -> some View {
        navigationTitle(titleKey).navigationBarTitleDisplayMode(displayMode)
    }
    @_disfavoredOverload
    @available(*, deprecated, message: "Use navigationTitle(_:) with navigationBarTitleDisplayMode(_:)")
    nonisolated public func navigationBarTitle<S: StringProtocol>(_ title: S, displayMode: NavigationBarItem.TitleDisplayMode) -> some View {
        navigationTitle(title).navigationBarTitleDisplayMode(displayMode)
    }

    // MARK: colorScheme

    /// Sets this view's color scheme (the environment's; `preferredColorScheme` sets the window's).
    @available(*, deprecated, renamed: "preferredColorScheme(_:)")
    nonisolated public func colorScheme(_ colorScheme: ColorScheme) -> some View { environment(\.colorScheme, colorScheme) }
}

// MARK: - ContentSizeCategory

/// The sizes that you can specify for content: `DynamicTypeSize` under its old name.
@available(*, deprecated, renamed: "DynamicTypeSize")
public enum ContentSizeCategory: Hashable, CaseIterable, Sendable {
    case extraSmall, small, medium, large, extraLarge, extraExtraLarge, extraExtraExtraLarge
    case accessibilityMedium, accessibilityLarge, accessibilityExtraLarge, accessibilityExtraExtraLarge, accessibilityExtraExtraExtraLarge

    /// Whether the category is one of the accessibility sizes.
    public var isAccessibilityCategory: Bool {
        switch self {
        case .accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge, .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge: return true
        default: return false
        }
    }

    package var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .extraSmall: return .xSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .extraLarge: return .xLarge
        case .extraExtraLarge: return .xxLarge
        case .extraExtraExtraLarge: return .xxxLarge
        case .accessibilityMedium: return .accessibility1
        case .accessibilityLarge: return .accessibility2
        case .accessibilityExtraLarge: return .accessibility3
        case .accessibilityExtraExtraLarge: return .accessibility4
        case .accessibilityExtraExtraExtraLarge: return .accessibility5
        }
    }

    package init(_ size: DynamicTypeSize) {
        switch size {
        case .xSmall: self = .extraSmall
        case .small: self = .small
        case .medium: self = .medium
        case .large: self = .large
        case .xLarge: self = .extraLarge
        case .xxLarge: self = .extraExtraLarge
        case .xxxLarge: self = .extraExtraExtraLarge
        case .accessibility1: self = .accessibilityMedium
        case .accessibility2: self = .accessibilityLarge
        case .accessibility3: self = .accessibilityExtraLarge
        case .accessibility4: self = .accessibilityExtraExtraLarge
        case .accessibility5: self = .accessibilityExtraExtraExtraLarge
        }
    }
}

@available(*, deprecated)
extension ContentSizeCategory: Comparable {
    public static func < (a: ContentSizeCategory, b: ContentSizeCategory) -> Bool { a.dynamicTypeSize < b.dynamicTypeSize }
}

extension EnvironmentValues {
    /// The size category: `dynamicTypeSize` under its old name.
    @available(*, deprecated, renamed: "dynamicTypeSize")
    public var sizeCategory: ContentSizeCategory {
        get { ContentSizeCategory(dynamicTypeSize) }
        set { dynamicTypeSize = newValue.dynamicTypeSize }
    }

    /// Whether the user has enabled an assistive technology (unknown in a browser: false).
    public var accessibilityEnabled: Bool {
        get { self[AccessibilityEnabledKey.self] }
        set { self[AccessibilityEnabledKey.self] = newValue }
    }
}

private struct AccessibilityEnabledKey: EnvironmentKey {
    static let defaultValue = false
}

// MARK: - EnvironmentalModifier

/// A modifier that must resolve to a concrete modifier in an environment before use.
public protocol EnvironmentalModifier: ViewModifier where Body == Never {
    associatedtype ResolvedModifier: ViewModifier
    /// Resolve to a concrete modifier using the given environment.
    func resolve(in environment: EnvironmentValues) -> ResolvedModifier
}

extension EnvironmentalModifier {
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        EnvironmentalModifierNode(context)
    }
}

/// Applies the modifier resolved in the node's environment, resolving again when it changes.
@MainActor
package final class EnvironmentalModifierNode<Content: View, Modifier: EnvironmentalModifier>: LayoutNode<ModifiedContent<Content, Modifier>> {
    private var child: TypedNode<ModifiedContent<Content, Modifier.ResolvedModifier>>!

    package init(_ context: _NodeContext<ModifiedContent<Content, Modifier>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        child = ModifiedContent<Content, Modifier.ResolvedModifier>._makeNode(_NodeContext(view: resolved(context.view, context.environment), parent: self, environment: context.environment))
    }

    private func resolved(_ view: ModifiedContent<Content, Modifier>, _ environment: EnvironmentValues) -> ModifiedContent<Content, Modifier.ResolvedModifier> {
        ModifiedContent(content: view.content, modifier: view.modifier.resolve(in: environment))
    }

    override package func update(view: ModifiedContent<Content, Modifier>, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        child.update(view: resolved(view, environment), environment: environment, force: force)
    }

    override package var structuralChildren: [ViewNode] { [child] }
    override package var layoutChildren: [ViewNode] { child.layoutChildren }
    override package var nodeDescription: String { "EnvironmentalModifier" }
}
