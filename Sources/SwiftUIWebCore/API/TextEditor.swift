// TextEditor (Docs/elements/TextEditor.md): the macOS multi-line text view. It fills its
// proposal and paints its text 5 pt in with the text view's tight line pitch; editing happens
// in the host's multi-line input (a `<textarea>` in the browser, typing in the native host).

/// The selected text of an editor (`TextEditor(text:selection:)`): a range of the text, or an
/// insertion point (an empty range).
public struct TextSelection: Equatable, Sendable {
    public enum Indices: Equatable, Sendable {
        case selection(Range<String.Index>)
        case multiSelection([Range<String.Index>])
    }
    public var indices: Indices

    public init(range: Range<String.Index>) { indices = .selection(range) }
    public init(insertionPoint: String.Index) { indices = .selection(insertionPoint..<insertionPoint) }
    public init(ranges: [Range<String.Index>]) {
        indices = ranges.count == 1 ? .selection(ranges[0]) : .multiSelection(ranges)
    }

    /// Whether the selection is an insertion point.
    public var isInsertion: Bool {
        if case .selection(let range) = indices { return range.isEmpty }
        return false
    }

    /// The first (or only) range.
    package var range: Range<String.Index>? {
        switch indices {
        case .selection(let range): return range
        case .multiSelection(let ranges): return ranges.first
        }
    }
}

/// A view that can display and edit long-form text.
public struct TextEditor: View {
    package let text: Binding<String>
    package let selection: Binding<TextSelection?>?

    /// Creates a plain text editor.
    public init(text: Binding<String>) {
        self.text = text
        selection = nil
    }

    /// Creates an editor whose selection follows (and sets) `selection`.
    public init(text: Binding<String>, selection: Binding<TextSelection?>) {
        self.text = text
        self.selection = selection
    }

    @Environment(\.textEditorStyle) private var style
    @Environment(\._scrollContentBackground) private var contentBackground
    @Environment(\._findNavigatorPresented) private var findPresented
    @Environment(\._findDisabled) private var findDisabled
    @State private var findQuery = ""
    @State private var replaceQuery = ""
    @State private var replacing = false
    @State private var match = 0

    public var body: some View {
        // Read the text (and the selection) here so observation tracks the model they come from.
        let value = text.wrappedValue
        let selected = selection?.wrappedValue
        let presented = !findDisabled && findPresented?.wrappedValue == true
        let matches = presented ? _FindBar.matches(of: findQuery, in: value) : []
        ZStack(alignment: .top) {
            _TextEditorHost(text: text, value: value, selection: selection, selected: selected, paintsBackground: contentBackground != .hidden && style._paintsBackground,
                            topInset: presented ? (replacing ? 2 * _FindBar.height : _FindBar.height) : 0,
                            highlights: matches, currentMatch: matches.indices.contains(match) ? match : nil)
            if presented {
                _FindBar(query: $findQuery, replacement: $replaceQuery, replacing: $replacing, match: $match, matchCount: matches.count,
                         done: { findPresented?.wrappedValue = false },
                         replace: { replacement in
                             guard matches.indices.contains(match) else { return }
                             var copy = value
                             copy.replaceSubrange(matches[match], with: replacement)
                             text.wrappedValue = copy
                         })
            }
        }
    }
}

package struct FindNavigatorPresentedKey: EnvironmentKey { package nonisolated(unsafe) static let defaultValue: Binding<Bool>? = nil }
package struct FindDisabledKey: EnvironmentKey { package static let defaultValue = false }
package struct ReplaceDisabledKey: EnvironmentKey { package static let defaultValue = false }

extension EnvironmentValues {
    package var _findNavigatorPresented: Binding<Bool>? {
        get { self[FindNavigatorPresentedKey.self] }
        set { self[FindNavigatorPresentedKey.self] = newValue }
    }
    package var _findDisabled: Bool {
        get { self[FindDisabledKey.self] }
        set { self[FindDisabledKey.self] = newValue }
    }
    package var _replaceDisabled: Bool {
        get { self[ReplaceDisabledKey.self] }
        set { self[ReplaceDisabledKey.self] = newValue }
    }
}

extension View {
    /// Presents the find navigator of the text editors inside: a bar at the editor's top (32 pt,
    /// measured: a search field, previous/next, Done and a Replace checkbox, 17 pt controls 8 in
    /// from the top) that highlights the matches and steps through them.
    nonisolated public func findNavigator(isPresented: Binding<Bool>) -> some View {
        environment(\._findNavigatorPresented, isPresented)
    }

    /// Prevents the find navigator from being presented (and the Find commands).
    nonisolated public func findDisabled(_ isDisabled: Bool = true) -> some View {
        environment(\._findDisabled, isDisabled)
    }

    /// Hides the Replace part of the find navigator.
    nonisolated public func replaceDisabled(_ isDisabled: Bool = true) -> some View {
        environment(\._replaceDisabled, isDisabled)
    }
}

/// The find navigator's bar over an editor (macOS 27, measured on `texteditor/corners`): a
/// 32 pt band ending in a soft shadow, its controls 17 pt tall 8 pt from the top: the search
/// field 8.5 → 126, previous/next 135 → 171.5, Done 180 → 221.5, the Replace checkbox from 230.
/// Looks are the runtime's default-size controls in those frames (small controls are not
/// modelled); a Replace row repeats the band below with the replacement field and a button.
package struct _FindBar: View {
    package static let height: CGFloat = 32
    @Binding var query: String
    @Binding var replacement: String
    @Binding var replacing: Bool
    @Binding var match: Int
    let matchCount: Int
    let done: @MainActor @Sendable () -> Void
    let replace: @MainActor @Sendable (String) -> Void
    @Environment(\._replaceDisabled) private var replaceDisabled

    /// A small bordered control's ground: white with a light grey hairline and a soft shadow.
    static var bordered: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Color(white: 0.7), lineWidth: 0.5))
            .shadow(color: Color.black.opacity(0.1), radius: 0.5, y: 0.5)
    }

    /// The ranges of `query` in `text` (case-insensitive, as the text view finds; stdlib only,
    /// there is no `range(of:options:)` on wasm).
    package static func matches(of query: String, in text: String) -> [Range<String.Index>] {
        guard !query.isEmpty else { return [] }
        let needle = Array(query.lowercased())
        let haystack = Array(text.lowercased())
        let indices = Array(text.indices) + [text.endIndex]
        guard haystack.count == indices.count - 1, needle.count <= haystack.count else { return [] }
        var result: [Range<String.Index>] = []
        var i = 0
        while i + needle.count <= haystack.count {
            if Array(haystack[i..<(i + needle.count)]) == needle {
                result.append(indices[i]..<indices[i + needle.count])
                i += needle.count
            } else {
                i += 1
            }
        }
        return result
    }

    package var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                Color.white
                TextField("Find", text: $query).textFieldStyle(.roundedBorder).frame(width: 117.5, height: 17).offset(x: 8.5, y: 8)
                HStack(spacing: 0) {
                    Button(action: { if matchCount > 0 { match = (match - 1 + matchCount) % matchCount } }) {
                        Image(systemName: "chevron.left").foregroundStyle(.secondary).frame(width: 18.25, height: 17)
                    }
                    .buttonStyle(.plain)
                    Rectangle().fill(Color(white: 0.8)).frame(width: 0.5, height: 17)
                    Button(action: { if matchCount > 0 { match = (match + 1) % matchCount } }) {
                        Image(systemName: "chevron.right").foregroundStyle(.secondary).frame(width: 18, height: 17)
                    }
                    .buttonStyle(.plain)
                }
                .background(Self.bordered)
                .offset(x: 135, y: 8)
                Button(action: done) { Text("Done").frame(width: 41.5, height: 17) }
                    .buttonStyle(.plain)
                    .background(Self.bordered)
                    .offset(x: 180, y: 8)
                if !replaceDisabled {
                    Toggle("Replace", isOn: $replacing).toggleStyle(.checkbox).offset(x: 230, y: 8)
                }
            }
            .frame(height: Self.height)
            .background(alignment: .bottom) {
                // The band's soft bottom edge (26.5 → 31.5: white to a light grey).
                LinearGradient(colors: [Color.white.opacity(0), Color(white: 0.87)], startPoint: .top, endPoint: .bottom).frame(height: 5)
            }
            if replacing && !replaceDisabled {
                ZStack(alignment: .topLeading) {
                    Color.white
                    TextField("Replace", text: $replacement).textFieldStyle(.roundedBorder).frame(width: 117.5, height: 17).offset(x: 8.5, y: 8)
                    Button("Replace", action: { replace(replacement) }).frame(height: 17).offset(x: 135, y: 8)
                }
                .frame(height: Self.height)
            }
        }
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
    package let selection: Binding<TextSelection?>?
    /// The selection's value as the body read it (so a change re-evaluates the node).
    package let selected: TextSelection?
    package let paintsBackground: Bool
    /// The find navigator's bar above the text.
    package let topInset: CGFloat
    /// The find navigator's matches, highlighted in the text; the current one stronger.
    package let highlights: [Range<String.Index>]
    package let currentMatch: Int?

    package init(text: Binding<String>, value: String, selection: Binding<TextSelection?>? = nil, selected: TextSelection? = nil, paintsBackground: Bool,
                 topInset: CGFloat = 0, highlights: [Range<String.Index>] = [], currentMatch: Int? = nil) {
        self.text = text
        self.value = value
        self.selection = selection
        self.selected = selected
        self.paintsBackground = paintsBackground
        self.topInset = topInset
        self.highlights = highlights
        self.currentMatch = currentMatch
    }

    public typealias Body = Never
    public static func _makeNode(_ context: _NodeContext<_TextEditorHost>) -> TypedNode<_TextEditorHost> {
        TextEditorNode(context)
    }
}
