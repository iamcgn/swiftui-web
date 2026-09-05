// `searchable`: on macOS the search field lives in the window toolbar, so the runtime shows it
// at the trailing end of the chrome bar (Runtime/ToolbarNodes.swift) when the host paints window
// chrome. Docs/elements/Toolbar.md.

/// Where a search field goes; every placement lands in the window toolbar here.
public struct SearchFieldPlacement: Hashable, Sendable {
    package let name: String
    public static let automatic = SearchFieldPlacement(name: "automatic")
    public static let toolbar = SearchFieldPlacement(name: "toolbar")
    public static let sidebar = SearchFieldPlacement(name: "sidebar")
}

/// Dismisses the search (`dismissSearch` environment): clears the query.
public struct DismissSearchAction {
    package let action: @MainActor () -> Void
    package init(_ action: @escaping @MainActor () -> Void) { self.action = action }
    @MainActor public func callAsFunction() { action() }
}

package struct IsSearchingKey: EnvironmentKey {
    package static let defaultValue = false
}

package struct DismissSearchKey: EnvironmentKey {
    // The action holds a main-actor closure (as `DismissAction` does); the default does nothing.
    package nonisolated(unsafe) static let defaultValue = DismissSearchAction {}
}

extension EnvironmentValues {
    /// Whether the enclosing `searchable` has a query (SwiftUI: whether the field is active).
    public var isSearching: Bool {
        get { self[IsSearchingKey.self] }
        set { self[IsSearchingKey.self] = newValue }
    }

    /// Clears the enclosing `searchable` query.
    public var dismissSearch: DismissSearchAction {
        get { self[DismissSearchKey.self] }
        set { self[DismissSearchKey.self] = newValue }
    }
}

/// Registers a search field with the runtime while the content is mounted.
public struct _SearchableModifier {
    public var text: Binding<String>
    public var prompt: String?
    public var placement: SearchFieldPlacement

    public init(text: Binding<String>, prompt: String?, placement: SearchFieldPlacement) {
        self.text = text
        self.prompt = prompt
        self.placement = placement
    }
}

extension _SearchableModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        SearchableNode(context)
    }
}

extension View {
    /// Marks this view as searchable: a search field in the window toolbar edits `text`.
    nonisolated public func searchable(text: Binding<String>, placement: SearchFieldPlacement = .automatic, prompt: Text? = nil) -> some View {
        modifier(_SearchableModifier(text: text, prompt: prompt?.resolvedString, placement: placement))
    }

    /// Marks this view as searchable, with a localised prompt.
    nonisolated public func searchable(text: Binding<String>, placement: SearchFieldPlacement = .automatic, prompt: LocalizedStringKey) -> some View {
        modifier(_SearchableModifier(text: text, prompt: Text(prompt).resolvedString, placement: placement))
    }

    /// Marks this view as searchable, with a prompt string.
    @_disfavoredOverload
    nonisolated public func searchable<S: StringProtocol>(text: Binding<String>, placement: SearchFieldPlacement = .automatic, prompt: S) -> some View {
        modifier(_SearchableModifier(text: text, prompt: String(prompt), placement: placement))
    }

    /// Accepted without effect: suggestions are not shown.
    nonisolated public func searchSuggestions<S: View>(@ViewBuilder _ suggestions: () -> S) -> some View { self }
}
