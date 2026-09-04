// GroupBox (Docs/elements/GroupBox.md): a label above a rounded card holding the content;
// styles.

/// A stylized view, with an optional label, that visually collects a logical grouping of content.
public struct GroupBox<Label: View, Content: View>: View {
    package let label: Label?
    package let content: Content

    @Environment(\.groupBoxStyle) private var style

    /// Creates a group box with a custom label.
    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.label = label()
        self.content = content()
    }

    public var body: some View {
        let configuration = GroupBoxStyleConfiguration(
            label: GroupBoxStyleConfiguration.Label(view: label.map { AnyView($0) } ?? AnyView(EmptyView()), isEmpty: label == nil),
            content: GroupBoxStyleConfiguration.Content(view: AnyView(content)))
        style.makeBodyErased(configuration)
    }
}

extension GroupBox where Label == EmptyView {
    /// Creates an unlabeled group box.
    public init(@ViewBuilder content: () -> Content) {
        label = nil
        self.content = content()
    }
}

extension GroupBox where Label == Text {
    /// Creates a group box titled by a localized string key.
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        label = Text(titleKey)
        self.content = content()
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {
        label = Text(title)
        self.content = content()
    }
}

extension GroupBox where Label == GroupBoxStyleConfiguration.Label, Content == GroupBoxStyleConfiguration.Content {
    /// Creates a group box based on a style configuration (custom styles).
    public init(_ configuration: GroupBoxStyleConfiguration) {
        label = configuration.label
        content = configuration.content
    }
}

// MARK: - Styles

/// The properties of a group box instance.
public struct GroupBoxStyleConfiguration {
    public struct Label {
        package let view: AnyView
        package let isEmpty: Bool
        package init(view: AnyView, isEmpty: Bool) {
            self.view = view
            self.isEmpty = isEmpty
        }
    }

    public struct Content {
        package let view: AnyView
        package init(view: AnyView) { self.view = view }
    }

    public let label: Label
    public let content: Content

    package init(label: Label, content: Content) {
        self.label = label
        self.content = content
    }
}

extension GroupBoxStyleConfiguration.Label: View {
    public var body: some View { view }
}

extension GroupBoxStyleConfiguration.Content: View {
    public var body: some View { view }
}

/// A type that specifies the appearance and interaction of all group boxes within a view hierarchy.
public protocol GroupBoxStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = GroupBoxStyleConfiguration
}

extension GroupBoxStyle {
    @MainActor
    package func makeBodyErased(_ configuration: Configuration) -> AnyView {
        AnyView(makeBody(configuration: configuration))
    }
}

/// The default group box style: the label in the subheadline font above a rounded card.
public struct DefaultGroupBoxStyle {
    public init() {}
}

extension DefaultGroupBoxStyle: GroupBoxStyle {
    public func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: PlatformMetrics.groupBoxLabelSpacing) {
            if !configuration.label.isEmpty {
                configuration.label.font(.subheadline).padding(.leading, PlatformMetrics.groupBoxLabelInset)
            }
            configuration.content
                .padding(PlatformMetrics.groupBoxPadding)
                .background(RoundedRectangle(cornerRadius: PlatformMetrics.groupBoxCornerRadius, style: .continuous)
                    .fill(Color.black.opacity(PlatformMetrics.groupBoxFillAlpha)))
        }
    }
}

extension GroupBoxStyle where Self == DefaultGroupBoxStyle {
    public static var automatic: DefaultGroupBoxStyle { DefaultGroupBoxStyle() }
}

package struct GroupBoxStyleKey: EnvironmentKey {
    package nonisolated(unsafe) static let defaultValue: any GroupBoxStyle = DefaultGroupBoxStyle()
}

extension EnvironmentValues {
    package var groupBoxStyle: any GroupBoxStyle {
        get { self[GroupBoxStyleKey.self] }
        set { self[GroupBoxStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets the style for group boxes within this view.
    nonisolated public func groupBoxStyle<S: GroupBoxStyle>(_ style: S) -> some View {
        environment(\.groupBoxStyle, style)
    }
}
