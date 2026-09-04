// DisclosureGroup (Docs/elements/DisclosureGroup.md): a label row with a chevron that shows or
// hides its content; styles.

/// A view that shows or hides another content view, based on the state of a disclosure control.
public struct DisclosureGroup<Label: View, Content: View>: View {
    package let isExpanded: Binding<Bool>?
    package let label: Label
    package let content: Content

    /// Creates a disclosure group with the given label and content views, bound to an expansion state.
    public init(isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content, @ViewBuilder label: () -> Label) {
        self.isExpanded = isExpanded
        self.label = label()
        self.content = content()
    }

    /// Creates a disclosure group with its own expansion state (collapsed at first).
    public init(@ViewBuilder content: @escaping () -> Content, @ViewBuilder label: () -> Label) {
        isExpanded = nil
        self.label = label()
        self.content = content()
    }

    public var body: some View {
        if let isExpanded {
            _DisclosureGroupBody(isExpanded: isExpanded, label: AnyView(label), content: AnyView(content))
        } else {
            _StatefulDisclosureGroup(label: AnyView(label), content: AnyView(content))
        }
    }
}

extension DisclosureGroup where Label == Text {
    /// Creates a disclosure group titled by a localized string key.
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: @escaping () -> Content) {
        self.init(content: content) { Text(titleKey) }
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: @escaping () -> Content) {
        self.init(content: content) { Text(title) }
    }

    public init(_ titleKey: LocalizedStringKey, isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) {
        self.init(isExpanded: isExpanded, content: content) { Text(titleKey) }
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) {
        self.init(isExpanded: isExpanded, content: content) { Text(title) }
    }
}

/// A group without a binding keeps its own state.
package struct _StatefulDisclosureGroup: View {
    package let label: AnyView
    package let content: AnyView
    @State private var isExpanded = false

    package init(label: AnyView, content: AnyView) {
        self.label = label
        self.content = content
    }

    package var body: some View {
        _DisclosureGroupBody(isExpanded: $isExpanded, label: label, content: content)
    }
}

/// Applies the environment's style.
package struct _DisclosureGroupBody: View {
    package let isExpanded: Binding<Bool>
    package let label: AnyView
    package let content: AnyView
    @Environment(\.disclosureGroupStyle) private var style

    package init(isExpanded: Binding<Bool>, label: AnyView, content: AnyView) {
        self.isExpanded = isExpanded
        self.label = label
        self.content = content
    }

    package var body: some View {
        style.makeBodyErased(DisclosureGroupStyleConfiguration(
            label: DisclosureGroupStyleConfiguration.Label(view: label), content: DisclosureGroupStyleConfiguration.Content(view: content),
            isExpanded: isExpanded))
    }
}

// MARK: - Styles

/// The properties of a disclosure group instance.
public struct DisclosureGroupStyleConfiguration {
    public struct Label {
        package let view: AnyView
        package init(view: AnyView) { self.view = view }
    }

    public struct Content {
        package let view: AnyView
        package init(view: AnyView) { self.view = view }
    }

    public let label: Label
    public let content: Content
    /// Whether the content is shown; setting it expands or collapses the group.
    @Binding public var isExpanded: Bool

    package init(label: Label, content: Content, isExpanded: Binding<Bool>) {
        self.label = label
        self.content = content
        _isExpanded = isExpanded
    }
}

extension DisclosureGroupStyleConfiguration.Label: View {
    public var body: some View { view }
}

extension DisclosureGroupStyleConfiguration.Content: View {
    public var body: some View { view }
}

/// A type that specifies the appearance and behavior of disclosure groups within a view hierarchy.
public protocol DisclosureGroupStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = DisclosureGroupStyleConfiguration
}

extension DisclosureGroupStyle {
    @MainActor
    package func makeBodyErased(_ configuration: Configuration) -> AnyView {
        AnyView(makeBody(configuration: configuration))
    }
}

/// The default style: a full-width row (the chevron, 5, the label; 4 above and below) that
/// toggles the group, then the content centred under it.
public struct AutomaticDisclosureGroupStyle {
    public init() {}
}

extension AutomaticDisclosureGroupStyle: DisclosureGroupStyle {
    public func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 0) {
            _DisclosureRow(isExpanded: configuration.$isExpanded, label: AnyView(configuration.label))
            if configuration.isExpanded {
                VStack { configuration.content }
            }
        }
    }
}

/// The row that toggles the group: a plain button holding the chevron and the label.
package struct _DisclosureRow {
    package let isExpanded: Binding<Bool>
    package let label: AnyView
    package init(isExpanded: Binding<Bool>, label: AnyView) {
        self.isExpanded = isExpanded
        self.label = label
    }
}

extension _DisclosureRow: View {
    package var body: some View {
        let binding = isExpanded
        return Button(action: { binding.wrappedValue.toggle() }) {
            HStack(spacing: PlatformMetrics.disclosureChevronSpacing) {
                _DisclosureChevron(isExpanded: binding.wrappedValue)
                label
            }
            .padding(.vertical, PlatformMetrics.disclosureRowPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

extension DisclosureGroupStyle where Self == AutomaticDisclosureGroupStyle {
    public static var automatic: AutomaticDisclosureGroupStyle { AutomaticDisclosureGroupStyle() }
}

/// The chevron: down when expanded, pointing right when collapsed; the secondary grey.
package struct _DisclosureChevron: View {
    package let isExpanded: Bool

    package var body: some View {
        _DisclosureChevronShape(isExpanded: isExpanded)
            .stroke(style: StrokeStyle(lineWidth: PlatformMetrics.disclosureChevronStroke, lineCap: .round, lineJoin: .round))
            .foregroundColor(Color.black.opacity(PlatformMetrics.disclosureChevronAlpha))
            .frame(width: PlatformMetrics.disclosureChevronWidth, height: PlatformMetrics.disclosureChevronHeight)
    }
}

package struct _DisclosureChevronShape: Sendable {
    package let isExpanded: Bool
}

extension _DisclosureChevronShape: Shape {
    package func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = PlatformMetrics.disclosureChevronSpan, h = PlatformMetrics.disclosureChevronRise
        if isExpanded {
            path.move(to: CGPoint(x: rect.midX - w / 2, y: rect.midY - h / 2))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.midY + h / 2))
            path.addLine(to: CGPoint(x: rect.midX + w / 2, y: rect.midY - h / 2))
        } else {
            path.move(to: CGPoint(x: rect.midX - h / 2, y: rect.midY - w / 2))
            path.addLine(to: CGPoint(x: rect.midX + h / 2, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX - h / 2, y: rect.midY + w / 2))
        }
        return path
    }
}

package struct DisclosureGroupStyleKey: EnvironmentKey {
    package nonisolated(unsafe) static let defaultValue: any DisclosureGroupStyle = AutomaticDisclosureGroupStyle()
}

extension EnvironmentValues {
    package var disclosureGroupStyle: any DisclosureGroupStyle {
        get { self[DisclosureGroupStyleKey.self] }
        set { self[DisclosureGroupStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets the style for disclosure groups within this view.
    nonisolated public func disclosureGroupStyle<S: DisclosureGroupStyle>(_ style: S) -> some View {
        environment(\.disclosureGroupStyle, style)
    }
}
