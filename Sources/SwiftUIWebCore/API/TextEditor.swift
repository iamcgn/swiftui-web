// TextEditor (Docs/elements/TextEditor.md): the macOS multi-line text view. It fills its
// proposal and paints its text 5 pt in with the text view's tight line pitch; editing happens
// in the host's multi-line input (a `<textarea>` in the browser, typing in the native host).

/// A view that can display and edit long-form text.
public struct TextEditor: View {
    package let text: Binding<String>

    /// Creates a plain text editor.
    public init(text: Binding<String>) {
        self.text = text
    }

    @Environment(\.textEditorStyle) private var style
    @Environment(\._scrollContentBackground) private var contentBackground

    public var body: some View {
        // Read the text here so observation tracks the model it comes from.
        let value = text.wrappedValue
        _TextEditorHost(text: text, value: value, paintsBackground: contentBackground != .hidden && style._paintsBackground)
    }
}

/// A specification for the appearance and interaction of a text editor.
public protocol TextEditorStyle {
    var _paintsBackground: Bool { get }
}

/// The default text editor style (a white background on macOS).
public struct AutomaticTextEditorStyle: TextEditorStyle {
    public init() {}
    public var _paintsBackground: Bool { true }
}

/// A text editor style with no decoration.
public struct PlainTextEditorStyle: TextEditorStyle {
    public init() {}
    public var _paintsBackground: Bool { false }
}

extension TextEditorStyle where Self == AutomaticTextEditorStyle {
    public static var automatic: AutomaticTextEditorStyle { AutomaticTextEditorStyle() }
}
extension TextEditorStyle where Self == PlainTextEditorStyle {
    public static var plain: PlainTextEditorStyle { PlainTextEditorStyle() }
}

package struct TextEditorStyleKey: EnvironmentKey {
    package nonisolated(unsafe) static let defaultValue: any TextEditorStyle = AutomaticTextEditorStyle()
}

package struct ScrollContentBackgroundKey: EnvironmentKey {
    package static let defaultValue = Visibility.automatic
}

extension EnvironmentValues {
    package var textEditorStyle: any TextEditorStyle {
        get { self[TextEditorStyleKey.self] }
        set { self[TextEditorStyleKey.self] = newValue }
    }

    /// `scrollContentBackground`: whether scrollable content (the text editor here) paints its
    /// default background.
    package var _scrollContentBackground: Visibility {
        get { self[ScrollContentBackgroundKey.self] }
        set { self[ScrollContentBackgroundKey.self] = newValue }
    }
}

extension View {
    /// Sets the style for text editors within this view.
    nonisolated public func textEditorStyle<S: TextEditorStyle>(_ style: S) -> some View {
        environment(\.textEditorStyle, style)
    }

    /// Specifies the visibility of the background for scrollable views within this view (the
    /// text editor honours it; lists and scroll views keep their backgrounds).
    nonisolated public func scrollContentBackground(_ visibility: Visibility) -> some View {
        environment(\._scrollContentBackground, visibility)
    }
}

/// The primitive (`TextEditorNode`).
public struct _TextEditorHost: View {
    package let text: Binding<String>
    package let value: String
    package let paintsBackground: Bool

    package init(text: Binding<String>, value: String, paintsBackground: Bool) {
        self.text = text
        self.value = value
        self.paintsBackground = paintsBackground
    }

    public typealias Body = Never
    public static func _makeNode(_ context: _NodeContext<_TextEditorHost>) -> TypedNode<_TextEditorHost> {
        TextEditorNode(context)
    }
}
