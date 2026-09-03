/// A control that displays an editable text interface.
///
/// macOS geometry measured in `Docs/elements/TextField.md`: the rounded-border field (default) is
/// 24 pt tall with the text 6 pt in on a 17 pt baseline, a white fill with a 1 pt border outside
/// it; the plain style is the bare text line. Editing happens in a transparent `<input>` the
/// browser host keeps over the field (typing, IME, caret and selection are the browser's); the
/// runtime paints text, placeholder and bullets.
public struct TextField<Label: View>: View {
    package let text: Binding<String>
    package let label: Label
    package let prompt: Text?
    package let isSecure: Bool

    /// Creates a text field with a text label generated from a localized title string.
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>, prompt: Text? = nil) where Label == Text {
        self.init(text: text, prompt: prompt, isSecure: false) { Text(titleKey) }
    }

    /// Creates a text field with a text label generated from a title string.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, text: Binding<String>, prompt: Text? = nil) where Label == Text {
        self.init(text: text, prompt: prompt, isSecure: false) { Text(title) }
    }

    /// Creates a text field with a custom label (the prompt, or the label's text, is the placeholder).
    public init(text: Binding<String>, prompt: Text? = nil, @ViewBuilder label: () -> Label) {
        self.init(text: text, prompt: prompt, isSecure: false, label: label)
    }

    /// Creates a text field that can grow along `axis` (stub: always a single line).
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>, axis: Axis) where Label == Text {
        self.init(titleKey, text: text)
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, text: Binding<String>, axis: Axis) where Label == Text {
        self.init(title, text: text)
    }

    package init(text: Binding<String>, prompt: Text?, isSecure: Bool, @ViewBuilder label: () -> Label) {
        self.text = text
        self.prompt = prompt
        self.isSecure = isSecure
        self.label = label()
    }

    @Environment(\.textFieldStyle) private var style

    public var body: some View {
        _TextFieldCore(text: text, placeholder: prompt?.resolvedString ?? _labelString, isSecure: isSecure, style: style)
    }

    private var _labelString: String {
        if let text = label as? Text { return text.resolvedString }
        return ""
    }
}

/// A control into which people securely enter private text.
public struct SecureField<Label: View>: View {
    package let field: TextField<Label>

    public init(_ titleKey: LocalizedStringKey, text: Binding<String>, prompt: Text? = nil) where Label == Text {
        field = TextField(text: text, prompt: prompt, isSecure: true) { Text(titleKey) }
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, text: Binding<String>, prompt: Text? = nil) where Label == Text {
        field = TextField(text: text, prompt: prompt, isSecure: true) { Text(title) }
    }

    public init(text: Binding<String>, prompt: Text? = nil, @ViewBuilder label: () -> Label) {
        field = TextField(text: text, prompt: prompt, isSecure: true, label: label)
    }

    public var body: some View { field }
}

// MARK: - Styles

/// A specification for the appearance and interaction of a text field.
public protocol TextFieldStyle: Sendable {
    /// The style's bezel (macOS): rounded (the default), square (drawn like rounded on macOS 26)
    /// or none.
    var _bezel: _TextFieldBezel { get }
}

/// How a text field is drawn.
public enum _TextFieldBezel: Sendable, Equatable {
    case rounded, square, plain
}

/// The default text field style (rounded border on macOS).
public struct DefaultTextFieldStyle: TextFieldStyle {
    public init() {}
    public var _bezel: _TextFieldBezel { .rounded }
}

/// A text field style with a system-defined rounded border.
public struct RoundedBorderTextFieldStyle: TextFieldStyle {
    public init() {}
    public var _bezel: _TextFieldBezel { .rounded }
}

/// A text field style with a system-defined square border.
public struct SquareBorderTextFieldStyle: TextFieldStyle {
    public init() {}
    public var _bezel: _TextFieldBezel { .square }
}

/// A text field style with no decoration.
public struct PlainTextFieldStyle: TextFieldStyle {
    public init() {}
    public var _bezel: _TextFieldBezel { .plain }
}

extension TextFieldStyle where Self == DefaultTextFieldStyle {
    public static var automatic: DefaultTextFieldStyle { DefaultTextFieldStyle() }
}
extension TextFieldStyle where Self == RoundedBorderTextFieldStyle {
    public static var roundedBorder: RoundedBorderTextFieldStyle { RoundedBorderTextFieldStyle() }
}
extension TextFieldStyle where Self == SquareBorderTextFieldStyle {
    public static var squareBorder: SquareBorderTextFieldStyle { SquareBorderTextFieldStyle() }
}
extension TextFieldStyle where Self == PlainTextFieldStyle {
    public static var plain: PlainTextFieldStyle { PlainTextFieldStyle() }
}

package struct TextFieldStyleKey: EnvironmentKey {
    package static let defaultValue: any TextFieldStyle = DefaultTextFieldStyle()
}

extension EnvironmentValues {
    package var textFieldStyle: any TextFieldStyle {
        get { self[TextFieldStyleKey.self] }
        set { self[TextFieldStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets the style for text fields within this view.
    nonisolated public func textFieldStyle<S: TextFieldStyle>(_ style: S) -> some View {
        environment(\.textFieldStyle, style)
    }
}

// MARK: - Submit

/// The types of triggers that result in a submit action.
public struct SubmitTriggers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let text = SubmitTriggers(rawValue: 1 << 0)
    public static let search = SubmitTriggers(rawValue: 1 << 1)
}

package struct SubmitActionKey: EnvironmentKey {
    package nonisolated(unsafe) static let defaultValue: _ActionBox? = nil
}

extension EnvironmentValues {
    /// The action text fields run when the user presses Return.
    package var submitAction: _ActionBox? {
        get { self[SubmitActionKey.self] }
        set { self[SubmitActionKey.self] = newValue }
    }
}

extension View {
    /// Adds an action to perform when the user submits a value to this view (Return in a field).
    nonisolated public func onSubmit(_ action: @escaping @MainActor () -> Void) -> some View {
        environment(\.submitAction, _ActionBox(action))
    }

    /// Adds an action to perform when the user submits a value through one of the triggers.
    nonisolated public func onSubmit(of triggers: SubmitTriggers, _ action: @escaping @MainActor () -> Void) -> some View {
        environment(\.submitAction, _ActionBox(action))
    }

    /// Sets whether to disable autocorrection for this view. Stored only.
    nonisolated public func autocorrectionDisabled(_ disable: Bool = true) -> some View { self }
}

// MARK: - Primitive

/// The laid-out and painted field; the host's `<input>` mirrors it through the semantics tree.
public struct _TextFieldCore: View {
    package let text: Binding<String>
    package let placeholder: String
    package let isSecure: Bool
    package let style: any TextFieldStyle

    package init(text: Binding<String>, placeholder: String, isSecure: Bool, style: any TextFieldStyle) {
        self.text = text
        self.placeholder = placeholder
        self.isSecure = isSecure
        self.style = style
    }

    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<_TextFieldCore>) -> TypedNode<_TextFieldCore> {
        TextFieldNode(context)
    }
}
