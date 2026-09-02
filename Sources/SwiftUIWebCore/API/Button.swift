/// A value that describes the purpose of a button.
public struct ButtonRole: Equatable, Sendable {
    package let name: String
    public static let destructive = ButtonRole(name: "destructive")
    public static let cancel = ButtonRole(name: "cancel")
}

/// Holds a button's action. A class rather than a bare closure field so the runtime's field
/// reflection stays warning-free (the runtime cannot demangle `@MainActor` function types).
package final class _ActionBox {
    package let run: @MainActor () -> Void
    package init(_ run: @escaping @MainActor () -> Void) { self.run = run }
}

/// A control that initiates an action.
public struct Button<Label: View>: View {
    package let action: _ActionBox
    package let label: Label
    package let role: ButtonRole?
    @State private var isPressed = false

    /// Creates a button that displays a custom label.
    public init(action: @escaping @MainActor () -> Void, @ViewBuilder label: () -> Label) {
        self.action = _ActionBox(action)
        self.label = label()
        self.role = nil
    }

    /// Creates a button with a specified role that displays a custom label.
    public init(role: ButtonRole?, action: @escaping @MainActor () -> Void, @ViewBuilder label: () -> Label) {
        self.action = _ActionBox(action)
        self.label = label()
        self.role = role
    }

    @Environment(\.buttonStyle) private var style

    public var body: some View {
        let configuration = ButtonStyleConfiguration(
            label: ButtonStyleConfiguration.Label(AnyView(label)), isPressed: isPressed, role: role)
        _ButtonHost(action: action, isPressed: $isPressed, label: AnyView(style.makeBodyErased(configuration)))
    }
}

extension Button where Label == Text {
    /// Creates a button that generates its label from a localized string key.
    public init(_ titleKey: LocalizedStringKey, action: @escaping @MainActor () -> Void) {
        self.init(action: action) { Text(titleKey) }
    }

    /// Creates a button that generates its label from a string.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, action: @escaping @MainActor () -> Void) {
        self.init(action: action) { Text(title) }
    }

    public init(_ titleKey: LocalizedStringKey, role: ButtonRole?, action: @escaping @MainActor () -> Void) {
        self.init(role: role, action: action) { Text(titleKey) }
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, role: ButtonRole?, action: @escaping @MainActor () -> Void) {
        self.init(role: role, action: action) { Text(title) }
    }
}

// MARK: - Styles

/// The properties of a button.
public struct ButtonStyleConfiguration {
    /// A type-erased label of a button.
    public struct Label: View {
        package let content: AnyView
        package init(_ content: AnyView) { self.content = content }
        public var body: some View { content }
    }

    public let label: Label
    public let isPressed: Bool
    public let role: ButtonRole?
}

/// A type that applies standard interaction behavior and a custom appearance to all buttons
/// within a view hierarchy.
@MainActor @preconcurrency
public protocol ButtonStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = ButtonStyleConfiguration
}

extension ButtonStyle {
    @MainActor
    package func makeBodyErased(_ configuration: Configuration) -> AnyView {
        AnyView(makeBody(configuration: configuration))
    }
}

/// The default button style, based on the button's context (bordered on macOS).
public struct DefaultButtonStyle {
    public init() {}
}

extension DefaultButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        BorderedButtonStyle().makeBody(configuration: configuration)
    }
}

/// A button style that applies standard border artwork based on the button's context.
///
/// Geometry from `button/basic` goldens (macOS 26.2): 24 pt tall, 12 pt horizontal padding,
/// label in the 13 pt point-size font (16 pt line), 6 pt corner radius, fill black at 7.5 %.
public struct BorderedButtonStyle {
    public init() {}
}

extension BorderedButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: PlatformMetrics.buttonLabelSize))
            .padding(.horizontal, PlatformMetrics.buttonHorizontalPadding)
            .frame(minHeight: PlatformMetrics.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: PlatformMetrics.buttonCornerRadius)
                    .fill(configuration.isPressed ? PlatformMetrics.buttonPressedFill : PlatformMetrics.buttonFill))
    }
}

/// A button style that applies standard border prominent artwork based on the button's context.
public struct BorderedProminentButtonStyle {
    public init() {}
}

extension BorderedProminentButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: PlatformMetrics.buttonLabelSize))
            .foregroundStyle(Color.white)
            .padding(.horizontal, PlatformMetrics.buttonHorizontalPadding)
            .frame(minHeight: PlatformMetrics.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: PlatformMetrics.buttonCornerRadius)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.8 : 1)))
    }
}

/// A button style that doesn't apply a border. On macOS the label uses the accent colour
/// (approximate: Apple's ImageRenderer cannot draw this AppKit-backed style).
public struct BorderlessButtonStyle {
    public init() {}
}

extension BorderlessButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.accentColor.opacity(configuration.isPressed ? 0.6 : 1))
    }
}

/// A button style that doesn't style or decorate its content while idle.
public struct PlainButtonStyle {
    public init() {}
}

extension PlainButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == DefaultButtonStyle {
    public static var automatic: DefaultButtonStyle { DefaultButtonStyle() }
}
extension ButtonStyle where Self == BorderedButtonStyle {
    public static var bordered: BorderedButtonStyle { BorderedButtonStyle() }
}
extension ButtonStyle where Self == BorderedProminentButtonStyle {
    public static var borderedProminent: BorderedProminentButtonStyle { BorderedProminentButtonStyle() }
}
extension ButtonStyle where Self == BorderlessButtonStyle {
    public static var borderless: BorderlessButtonStyle { BorderlessButtonStyle() }
}
extension ButtonStyle where Self == PlainButtonStyle {
    public static var plain: PlainButtonStyle { PlainButtonStyle() }
}

package struct ButtonStyleKey: EnvironmentKey {
    // `ButtonStyle` is not Sendable (as in SwiftUI); the default is an immutable value type.
    package nonisolated(unsafe) static let defaultValue: any ButtonStyle = DefaultButtonStyle()
}

extension EnvironmentValues {
    package var buttonStyle: any ButtonStyle {
        get { self[ButtonStyleKey.self] }
        set { self[ButtonStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets the style for buttons within this view to a button style with a custom appearance
    /// and standard interaction behavior.
    nonisolated public func buttonStyle<S: ButtonStyle>(_ style: S) -> some View {
        environment(\.buttonStyle, style)
    }
}

// MARK: - Interaction host

/// Primitive that owns a button's press state and activation. Transparent to layout.
public struct _ButtonHost: View {
    package let action: _ActionBox
    package let isPressed: Binding<Bool>
    package let label: AnyView

    package init(action: _ActionBox, isPressed: Binding<Bool>, label: AnyView) {
        self.action = action
        self.isPressed = isPressed
        self.label = label
    }

    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<_ButtonHost>) -> TypedNode<_ButtonHost> {
        ButtonHostNode(context)
    }
}

/// Runs an action on tap. Transparent to layout.
public struct _TapGestureModifier {
    package let count: Int
    package let action: _ActionBox
}

extension _TapGestureModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        TapGestureNode(context)
    }
}

extension View {
    /// Adds an action to perform when this view recognizes a tap gesture.
    nonisolated public func onTapGesture(count: Int = 1, perform action: @escaping @MainActor () -> Void) -> some View {
        modifier(_TapGestureModifier(count: count, action: _ActionBox(action)))
    }
}
