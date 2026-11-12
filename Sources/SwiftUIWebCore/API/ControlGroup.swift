// ControlGroup: related controls shown together. Outside a menu the automatic and navigation
// styles lay the controls out in a row; the menu styles put them in a menu under the group's
// label (`compactMenu` and `palette` show as that menu too).

/// A container view that displays semantically-related controls in a visually-appropriate
/// manner for the context.
public struct ControlGroup<Content: View>: View {
    package let content: Content
    package let label: AnyView?

    @Environment(\._controlGroupStyle) private var style
    /// Made from a style's configuration: laid out in the automatic style.
    package var fromConfiguration = false

    /// Creates a new control group with the specified children.
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
        label = nil
    }

    public var body: some View {
        let configuration = ControlGroupStyleConfiguration(
            content: ControlGroupStyleConfiguration.Content(view: AnyView(content)),
            label: ControlGroupStyleConfiguration.Label(view: label ?? AnyView(EmptyView()), isEmpty: label == nil))
        (fromConfiguration ? AutomaticControlGroupStyle() : style).makeBodyErased(configuration)
    }
}

/// The content of a labeled control group: the controls (the label is the group's).
public struct LabeledControlGroupContent<Content: View, Label: View>: View {
    package let content: Content
    package let label: Label

    public var body: some View { content }
}

extension ControlGroup {
    /// Creates a new control group with the specified content and a label.
    public init<C: View, L: View>(@ViewBuilder content: () -> C, @ViewBuilder label: () -> L) where Content == LabeledControlGroupContent<C, L> {
        let made = label()
        self.content = LabeledControlGroupContent(content: content(), label: made)
        self.label = AnyView(made)
    }

    /// Creates a new control group with the specified content that generates its label from a
    /// localized string key.
    public init<C: View>(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> C) where Content == LabeledControlGroupContent<C, Text> {
        self.init(content: content, label: { Text(titleKey) })
    }

    /// Creates a new control group with the specified content that generates its label from a
    /// string.
    @_disfavoredOverload
    public init<C: View, S: StringProtocol>(_ title: S, @ViewBuilder content: () -> C) where Content == LabeledControlGroupContent<C, Text> {
        self.init(content: content, label: { Text(title) })
    }

    /// Creates a new control group with the specified content, labeled by a title and a system
    /// image.
    public init<C: View>(_ titleKey: LocalizedStringKey, systemImage: String, @ViewBuilder content: () -> C)
        where Content == LabeledControlGroupContent<C, Label<Text, Image>> {
        self.init(content: content, label: { Label(titleKey, systemImage: systemImage) })
    }

    /// Creates a new control group with the specified content, labeled by a title and an image
    /// from the app's catalog.
    public init<C: View>(_ titleKey: LocalizedStringKey, image: String, @ViewBuilder content: () -> C)
        where Content == LabeledControlGroupContent<C, Label<Text, Image>> {
        self.init(content: content, label: { Label(titleKey, image: image) })
    }
}

extension ControlGroup where Content == ControlGroupStyleConfiguration.Content {
    /// Creates a control group based on a style configuration (custom styles).
    public init(_ configuration: ControlGroupStyleConfiguration) {
        content = configuration.content
        label = configuration.label.isEmpty ? nil : AnyView(configuration.label)
        fromConfiguration = true
    }
}

// MARK: - Styles

/// The properties of a control group.
public struct ControlGroupStyleConfiguration {
    /// The controls in the group.
    public struct Content: View {
        package let view: AnyView
        package init(view: AnyView) { self.view = view }
        public var body: some View { view }
    }

    /// The group's label, if it has one.
    public struct Label: View {
        package let view: AnyView
        package let isEmpty: Bool
        package init(view: AnyView, isEmpty: Bool) {
            self.view = view
            self.isEmpty = isEmpty
        }
        public var body: some View { view }
    }

    public let content: Content
    public let label: Label

    package init(content: Content, label: Label) {
        self.content = content
        self.label = label
    }
}

/// Defines the implementation of all control groups within a view hierarchy.
@MainActor @preconcurrency
public protocol ControlGroupStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = ControlGroupStyleConfiguration
}

extension ControlGroupStyle {
    @MainActor
    package func makeBodyErased(_ configuration: Configuration) -> AnyView {
        AnyView(makeBody(configuration: configuration))
    }
}

/// The default control group style: the controls in a row.
public struct AutomaticControlGroupStyle: ControlGroupStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        HStack { configuration.content }
    }
}

/// The control group style for a navigation bar or toolbar: the controls in a row.
public struct NavigationControlGroupStyle: ControlGroupStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        HStack { configuration.content }
    }
}

/// A control group style that presents its content as a menu under the group's label.
public struct MenuControlGroupStyle: ControlGroupStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        Menu { configuration.content } label: { configuration.label }
    }
}

/// A control group style that presents its content as a compact menu (shown as a menu here).
public struct CompactMenuControlGroupStyle: ControlGroupStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        Menu { configuration.content } label: { configuration.label }
    }
}

/// A control group style that presents its content as a palette (shown as a menu here).
public struct PaletteControlGroupStyle: ControlGroupStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        Menu { configuration.content } label: { configuration.label }
    }
}

extension ControlGroupStyle where Self == AutomaticControlGroupStyle {
    public static var automatic: AutomaticControlGroupStyle { AutomaticControlGroupStyle() }
}

extension ControlGroupStyle where Self == NavigationControlGroupStyle {
    public static var navigation: NavigationControlGroupStyle { NavigationControlGroupStyle() }
}

extension ControlGroupStyle where Self == MenuControlGroupStyle {
    public static var menu: MenuControlGroupStyle { MenuControlGroupStyle() }
}

extension ControlGroupStyle where Self == CompactMenuControlGroupStyle {
    public static var compactMenu: CompactMenuControlGroupStyle { CompactMenuControlGroupStyle() }
}

extension ControlGroupStyle where Self == PaletteControlGroupStyle {
    public static var palette: PaletteControlGroupStyle { PaletteControlGroupStyle() }
}

package struct ControlGroupStyleKey: EnvironmentKey {
    package nonisolated(unsafe) static let defaultValue: any ControlGroupStyle = MainActor.assumeIsolated { AutomaticControlGroupStyle() }
}

extension EnvironmentValues {
    package var _controlGroupStyle: any ControlGroupStyle {
        get { self[ControlGroupStyleKey.self] }
        set { self[ControlGroupStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets the style for control groups within this view.
    nonisolated public func controlGroupStyle<S: ControlGroupStyle>(_ style: S) -> some View {
        environment(\._controlGroupStyle, style)
    }
}
