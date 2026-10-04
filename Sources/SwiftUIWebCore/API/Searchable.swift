// `searchable`: on macOS the search field lives in the window toolbar, so the runtime shows it
// at the trailing end of the chrome bar (Runtime/ToolbarNodes.swift) when the host paints window
// chrome; on iOS 26 a navigation stack puts it in a capsule at the bottom of the screen
// (Runtime/SearchNodes.swift, ios/search). Suggestions, scopes, tokens and completions:
// Docs/elements/Toolbar.md.

/// Where a search field goes; every placement lands in the window toolbar (macOS) or at the
/// bottom of the navigation stack (iOS) here.
public struct SearchFieldPlacement: Hashable, Sendable {
    package let name: String
    public static let automatic = SearchFieldPlacement(name: "automatic")
    public static let toolbar = SearchFieldPlacement(name: "toolbar")
    public static let sidebar = SearchFieldPlacement(name: "sidebar")
    public static let navigationBarDrawer = SearchFieldPlacement(name: "navigationBarDrawer")

    /// iOS: the field in the navigation bar's drawer; the display mode is accepted.
    public static func navigationBarDrawer(displayMode: NavigationBarDrawerDisplayMode) -> SearchFieldPlacement {
        SearchFieldPlacement(name: "navigationBarDrawer")
    }

    public enum NavigationBarDrawerDisplayMode: Hashable, Sendable {
        case automatic, always
    }
}

/// When the scope bar of `searchScopes` shows: with text in the field (iOS's automatic), or as
/// soon as the search is presented (macOS's automatic).
public struct SearchScopeActivation: Hashable, Sendable {
    package let name: String
    public static let automatic = SearchScopeActivation(name: "automatic")
    public static let onTextEntry = SearchScopeActivation(name: "onTextEntry")
    public static let onSearchPresentation = SearchScopeActivation(name: "onSearchPresentation")
}

/// Whether presenting the search hides the navigation bar (iOS): the automatic behaviour
/// hides it, `avoidHidingContent` keeps it.
public struct SearchPresentationToolbarBehavior: Hashable, Sendable {
    package let name: String
    public static let automatic = SearchPresentationToolbarBehavior(name: "automatic")
    public static let avoidHidingContent = SearchPresentationToolbarBehavior(name: "avoidHidingContent")
}

/// iOS 26: whether the field minimises to a button while the content scrolls. Accepted; the
/// field always shows in full here.
public struct SearchToolbarBehavior: Hashable, Sendable {
    package let name: String
    public static let automatic = SearchToolbarBehavior(name: "automatic")
    public static let minimize = SearchToolbarBehavior(name: "minimize")
}

/// Where search suggestions show: a menu under the field (macOS) or in place of the content
/// (iOS). `searchSuggestions(_:for:)` is accepted without effect.
public struct SearchSuggestionsPlacement: Hashable, Sendable {
    package let name: String
    public static let automatic = SearchSuggestionsPlacement(name: "automatic")
    public static let menu = SearchSuggestionsPlacement(name: "menu")
    public static let content = SearchSuggestionsPlacement(name: "content")

    public struct Set: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let menu = Set(rawValue: 1)
        public static let content = Set(rawValue: 2)
    }
}

/// Dismisses the search (`dismissSearch` environment): clears the query and ends the
/// presentation (the field loses focus).
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

package struct SearchPresentationToolbarBehaviorKey: EnvironmentKey {
    package static let defaultValue = SearchPresentationToolbarBehavior.automatic
}

package struct InSearchScopeBarKey: EnvironmentKey {
    package static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether the enclosing `searchable` is active: its field is presented (focused) or holds
    /// a query.
    public var isSearching: Bool {
        get { self[IsSearchingKey.self] }
        set { self[IsSearchingKey.self] = newValue }
    }

    /// Clears the enclosing `searchable` query and ends the search.
    public var dismissSearch: DismissSearchAction {
        get { self[DismissSearchKey.self] }
        set { self[DismissSearchKey.self] = newValue }
    }

    package var _searchPresentationToolbarBehavior: SearchPresentationToolbarBehavior {
        get { self[SearchPresentationToolbarBehaviorKey.self] }
        set { self[SearchPresentationToolbarBehaviorKey.self] = newValue }
    }

    /// Set on the segmented picker that is a search's scope bar (iOS 26's larger look).
    package var _inSearchScopeBar: Bool {
        get { self[InSearchScopeBarKey.self] }
        set { self[InSearchScopeBarKey.self] = newValue }
    }
}

/// The tokens of a `searchable(text:tokens:)` field, type-erased for the runtime (a class so
/// the runtime's field reflection ignores it): their views in order, removal, and the addition
/// a `searchCompletion(token)` makes.
public final class _SearchTokens {
    package let count: () -> Int
    package let views: () -> [AnyView]
    package let remove: (Int) -> Void
    package let append: (Any) -> Bool

    package init(count: @escaping () -> Int, views: @escaping () -> [AnyView],
                 remove: @escaping (Int) -> Void, append: @escaping (Any) -> Bool) {
        self.count = count
        self.views = views
        self.remove = remove
        self.append = append
    }

    package static func make<C, T: View>(_ tokens: Binding<C>, @ViewBuilder token: @escaping (C.Element) -> T) -> _SearchTokens
    where C: RandomAccessCollection & RangeReplaceableCollection, C.Element: Identifiable {
        _SearchTokens(count: { tokens.wrappedValue.count },
                      views: { tokens.wrappedValue.map { AnyView(token($0)) } },
                      remove: { index in
                          var value = tokens.wrappedValue
                          guard index < value.count else { return }
                          value.remove(at: value.index(value.startIndex, offsetBy: index))
                          tokens.wrappedValue = value
                      },
                      append: { element in
                          guard let element = element as? C.Element else { return false }
                          var value = tokens.wrappedValue
                          value.append(element)
                          tokens.wrappedValue = value
                          return true
                      })
    }
}

/// Registers a search field with the runtime while the content is mounted.
public struct _SearchableModifier {
    public var text: Binding<String>
    public var prompt: String?
    public var placement: SearchFieldPlacement
    /// `searchable(text:isPresented:)`: the presentation (the field's focus) follows and drives
    /// this binding; without one the node keeps the state.
    package var isPresented: Binding<Bool>?
    /// The binding's value, read where the modifier is built (the owner's body) so observation
    /// tracks it; the node reads this and writes the binding.
    package var presentedValue: Bool?
    package var tokens: _SearchTokens?

    public init(text: Binding<String>, prompt: String?, placement: SearchFieldPlacement) {
        self.text = text
        self.prompt = prompt
        self.placement = placement
    }

    package init(text: Binding<String>, prompt: String?, placement: SearchFieldPlacement, isPresented: Binding<Bool>?, tokens: _SearchTokens?) {
        self.text = text
        self.prompt = prompt
        self.placement = placement
        self.isPresented = isPresented
        self.presentedValue = isPresented?.wrappedValue
        self.tokens = tokens
    }
}

extension _SearchableModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        SearchableNode(context)
    }
}

/// `searchSuggestions`: the suggestion views the enclosing search shows while it is presented.
/// (The conformances live in extensions so the modifiers stay free of the main actor, as
/// `_SearchableModifier` is.)
public struct _SearchSuggestionsModifier {
    package let content: AnyView
    package init(content: AnyView) { self.content = content }
}

extension _SearchSuggestionsModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        SearchSuggestionsNode(context)
    }
}

/// A scope bar's selection setter (a class so the runtime's field reflection ignores it).
public final class _SearchScopeSelection {
    package let select: (AnyHashable) -> Void
    package init(_ select: @escaping (AnyHashable) -> Void) { self.select = select }
}

/// `searchScopes`: the scope bar's options and selection.
public struct _SearchScopesModifier {
    package let selected: AnyHashable
    package let select: _SearchScopeSelection
    package let content: AnyView
    package let activation: SearchScopeActivation

    package init(selected: AnyHashable, select: _SearchScopeSelection, content: AnyView, activation: SearchScopeActivation) {
        self.selected = selected
        self.select = select
        self.content = content
        self.activation = activation
    }
}

extension _SearchScopesModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        SearchScopesNode(context)
    }
}

/// What choosing a suggestion does: sets the query, or adds a token (a class so the runtime's
/// field reflection ignores it).
public final class _SearchCompletion {
    package enum Kind {
        case text(String)
        case token(Any)
    }
    package let kind: Kind
    package init(_ kind: Kind) { self.kind = kind }
}

/// `searchCompletion`: a suggestion row that fills the field when chosen.
public struct _SearchCompletionModifier {
    package let completion: _SearchCompletion
    package init(completion: _SearchCompletion) { self.completion = completion }
}

extension _SearchCompletionModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        SearchCompletionNode(context)
    }
}

extension View {
    /// Marks this view as searchable: a search field in the window toolbar (macOS) or at the
    /// bottom of the navigation stack (iOS) edits `text`.
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

    /// Marks this view as searchable; `isPresented` follows and drives the search's presentation
    /// (the field's focus).
    nonisolated public func searchable(text: Binding<String>, isPresented: Binding<Bool>, placement: SearchFieldPlacement = .automatic, prompt: Text? = nil) -> some View {
        modifier(_SearchableModifier(text: text, prompt: prompt?.resolvedString, placement: placement, isPresented: isPresented, tokens: nil))
    }

    nonisolated public func searchable(text: Binding<String>, isPresented: Binding<Bool>, placement: SearchFieldPlacement = .automatic, prompt: LocalizedStringKey) -> some View {
        modifier(_SearchableModifier(text: text, prompt: Text(prompt).resolvedString, placement: placement, isPresented: isPresented, tokens: nil))
    }

    @_disfavoredOverload
    nonisolated public func searchable<S: StringProtocol>(text: Binding<String>, isPresented: Binding<Bool>, placement: SearchFieldPlacement = .automatic, prompt: S) -> some View {
        modifier(_SearchableModifier(text: text, prompt: String(prompt), placement: placement, isPresented: isPresented, tokens: nil))
    }

    /// Marks this view as searchable with tokens shown before the text, each as `token` makes it.
    nonisolated public func searchable<C, T: View>(text: Binding<String>, tokens: Binding<C>, placement: SearchFieldPlacement = .automatic,
                                                   prompt: Text? = nil, @ViewBuilder token: @escaping (C.Element) -> T) -> some View
    where C: RandomAccessCollection & RangeReplaceableCollection, C.Element: Identifiable {
        modifier(_SearchableModifier(text: text, prompt: prompt?.resolvedString, placement: placement, isPresented: nil,
                                     tokens: _SearchTokens.make(tokens, token: token)))
    }

    nonisolated public func searchable<C, T: View>(text: Binding<String>, tokens: Binding<C>, placement: SearchFieldPlacement = .automatic,
                                                   prompt: LocalizedStringKey, @ViewBuilder token: @escaping (C.Element) -> T) -> some View
    where C: RandomAccessCollection & RangeReplaceableCollection, C.Element: Identifiable {
        modifier(_SearchableModifier(text: text, prompt: Text(prompt).resolvedString, placement: placement, isPresented: nil,
                                     tokens: _SearchTokens.make(tokens, token: token)))
    }

    @_disfavoredOverload
    nonisolated public func searchable<C, T: View, S: StringProtocol>(text: Binding<String>, tokens: Binding<C>, placement: SearchFieldPlacement = .automatic,
                                                                      prompt: S, @ViewBuilder token: @escaping (C.Element) -> T) -> some View
    where C: RandomAccessCollection & RangeReplaceableCollection, C.Element: Identifiable {
        modifier(_SearchableModifier(text: text, prompt: String(prompt), placement: placement, isPresented: nil,
                                     tokens: _SearchTokens.make(tokens, token: token)))
    }

    /// Tokens and a presentation binding.
    nonisolated public func searchable<C, T: View>(text: Binding<String>, tokens: Binding<C>, isPresented: Binding<Bool>, placement: SearchFieldPlacement = .automatic,
                                                   prompt: Text? = nil, @ViewBuilder token: @escaping (C.Element) -> T) -> some View
    where C: RandomAccessCollection & RangeReplaceableCollection, C.Element: Identifiable {
        modifier(_SearchableModifier(text: text, prompt: prompt?.resolvedString, placement: placement, isPresented: isPresented,
                                     tokens: _SearchTokens.make(tokens, token: token)))
    }

    nonisolated public func searchable<C, T: View>(text: Binding<String>, tokens: Binding<C>, isPresented: Binding<Bool>, placement: SearchFieldPlacement = .automatic,
                                                   prompt: LocalizedStringKey, @ViewBuilder token: @escaping (C.Element) -> T) -> some View
    where C: RandomAccessCollection & RangeReplaceableCollection, C.Element: Identifiable {
        modifier(_SearchableModifier(text: text, prompt: Text(prompt).resolvedString, placement: placement, isPresented: isPresented,
                                     tokens: _SearchTokens.make(tokens, token: token)))
    }

    /// Tokens with suggested ones: the suggestions are accepted without effect (the suggestion
    /// rows of `searchSuggestions` show instead).
    nonisolated public func searchable<C, T: View>(text: Binding<String>, tokens: Binding<C>, suggestedTokens: Binding<C>, placement: SearchFieldPlacement = .automatic,
                                                   prompt: Text? = nil, @ViewBuilder token: @escaping (C.Element) -> T) -> some View
    where C: RandomAccessCollection & RangeReplaceableCollection, C.Element: Identifiable {
        modifier(_SearchableModifier(text: text, prompt: prompt?.resolvedString, placement: placement, isPresented: nil,
                                     tokens: _SearchTokens.make(tokens, token: token)))
    }

    /// The suggestions the enclosing search shows while it is presented: in place of the content
    /// on iOS, in a menu under the field on macOS. Rows with `searchCompletion` fill the field.
    nonisolated public func searchSuggestions<S: View>(@ViewBuilder _ suggestions: () -> S) -> some View {
        modifier(_SearchSuggestionsModifier(content: AnyView(suggestions())))
    }

    /// Accepted without effect: the suggestions keep their platform's placement.
    nonisolated public func searchSuggestions(_ visibility: Visibility, for placement: SearchSuggestionsPlacement.Set) -> some View { self }

    /// Choosing this suggestion sets the search text to `completion`.
    nonisolated public func searchCompletion(_ completion: String) -> some View {
        modifier(_SearchCompletionModifier(completion: _SearchCompletion(.text(completion))))
    }

    /// Choosing this suggestion adds `token` to the search's tokens.
    nonisolated public func searchCompletion<T: Identifiable>(_ token: T) -> some View {
        modifier(_SearchCompletionModifier(completion: _SearchCompletion(.token(token))))
    }

    /// A scope bar for the enclosing search: a segmented control of the `scopes` (tagged as a
    /// picker's options) shown while the search is active.
    nonisolated public func searchScopes<V: Hashable, S: View>(_ scope: Binding<V>, @ViewBuilder scopes: () -> S) -> some View {
        searchScopes(scope, activation: .automatic, scopes)
    }

    nonisolated public func searchScopes<V: Hashable, S: View>(_ scope: Binding<V>, activation: SearchScopeActivation, @ViewBuilder _ scopes: () -> S) -> some View {
        modifier(_SearchScopesModifier(selected: AnyHashable(scope.wrappedValue),
                                       select: _SearchScopeSelection { if let value = $0.base as? V { scope.wrappedValue = value } },
                                       content: AnyView(scopes()), activation: activation))
    }

    /// Whether presenting the search hides the navigation bar (iOS).
    nonisolated public func searchPresentationToolbarBehavior(_ behavior: SearchPresentationToolbarBehavior) -> some View {
        environment(\._searchPresentationToolbarBehavior, behavior)
    }

    /// Accepted without effect (iOS 26: the field never minimises here).
    nonisolated public func searchToolbarBehavior(_ behavior: SearchToolbarBehavior) -> some View { self }
}
