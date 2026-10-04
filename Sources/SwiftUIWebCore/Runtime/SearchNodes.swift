// `searchable` and its companions (API/Searchable.swift): the searchable node registers its
// field with the runtime and gives its content `isSearching` and `dismissSearch`; the field's
// presentation (its focus) comes from the host's field or a binding. Suggestions, scopes and
// completions register alongside and the field's chrome reads them: the window toolbar on
// macOS (ToolbarNodes.swift) or the capsule at the bottom of an iOS navigation stack
// (`_IOSSearchBarView`, NavigationNodes.swift). Docs/elements/Toolbar.md, ios/search.

/// One `searchable` modifier's field.
package struct SearchSource {
    weak var node: ViewNode?
    var text: Binding<String>
    var prompt: String?
    var tokens: _SearchTokens?
    var isPresented: @MainActor () -> Bool
    var setPresented: @MainActor (Bool) -> Void
    /// `searchPresentationToolbarBehavior(.avoidHidingContent)`: the navigation bar stays while presented.
    var keepsBar: Bool

    @MainActor package var presented: Bool { isPresented() }
    @MainActor package var tokenCount: Int { tokens?.count() ?? 0 }
}

/// The searchable node, found by the navigation stack above it (iOS).
@MainActor
package protocol _SearchProviding: AnyObject {
    var searchSource: SearchSource { get }
    var isPresented: Bool { get }
    func setPresented(_ presented: Bool)
    /// A `searchSuggestions` above or below registered: the shown suggestions follow.
    func suggestionsDidChange()
}

/// `searchable`: transparent to layout; registers the field, and gives its content `isSearching`
/// and `dismissSearch`. On iOS, while presented, it shows the suggestions over its content.
@MainActor
package final class SearchableNode<Content: View>: UnaryLayoutModifierNode<Content, _SearchableModifier>, _SearchProviding {
    /// The presentation when the modifier has no `isPresented` binding.
    private var presentedState = false
    /// The presentation at the last update: a change lays the stack out again (its bands move).
    private var lastPresented = false
    /// iOS: the suggestions list over the content while presented.
    package private(set) var suggestions: TypedNode<AnyView>?
    /// macOS: the suggestions in a menu under the toolbar's field while presented, opened at
    /// layout (the toolbar's field exists by then) from `menuContent`.
    package private(set) var suggestionsMenu: PresentationNode?
    private var menuContent: AnyView?

    override package init(_ context: _NodeContext<ModifiedContent<Content, _SearchableModifier>>) {
        super.init(context)
        runtime.registerSearch(self, field: searchSource)
        update(view: view, environment: environment, force: true)
    }

    package var isPresented: Bool { modifier.presentedValue ?? presentedState }

    package func setPresented(_ presented: Bool) {
        guard isPresented != presented else { return }
        if let binding = modifier.isPresented {
            binding.wrappedValue = presented
        } else {
            presentedState = presented
        }
        runtime.requestFullLayout()
    }

    package var searchSource: SearchSource {
        SearchSource(node: self, text: modifier.text, prompt: modifier.prompt, tokens: modifier.tokens,
                     isPresented: { [weak self] in self?.isPresented ?? false },
                     setPresented: { [weak self] in self?.setPresented($0) },
                     keepsBar: environment._searchPresentationToolbarBehavior == .avoidHidingContent)
    }

    override package func update(view: ModifiedContent<Content, _SearchableModifier>, environment: EnvironmentValues, force: Bool) {
        var inner = environment
        let text = view.modifier.text
        let presented = view.modifier.presentedValue ?? presentedState
        inner.isSearching = presented || !text.wrappedValue.isEmpty
        inner.dismissSearch = DismissSearchAction { [weak self] in
            text.wrappedValue = ""
            self?.setPresented(false)
        }
        super.update(view: view, environment: inner, force: force)
        runtime.registerSearch(self, field: searchSource)
        refreshSuggestions(force: force)
        if presented != lastPresented {
            lastPresented = presented
            runtime.requestFullLayout()
        }
    }

    package func suggestionsDidChange() {
        refreshSuggestions(force: false)
        runtime.requestLayout()
    }

    /// iOS: the suggestion rows replace the content while the search is presented (ios/search/active:
    /// a plain list in the accent colour); macOS shows them in a menu under the toolbar's field
    /// (approximate: the toolbar is not capturable).
    private func refreshSuggestions(force: Bool) {
        guard isPresented, let content = runtime.searchSuggestions else {
            dropSuggestions()
            return
        }
        if environment.platformProfile.isIOS {
            let view = AnyView(_SearchSuggestionsList(content: content))
            if let suggestions {
                suggestions.update(view: view, environment: environment, force: force)
            } else {
                suggestions = AnyView._makeNode(_NodeContext(view: view, parent: self, environment: environment))
            }
        } else {
            menuContent = AnyView(_SearchSuggestionsMenu(content: content))
            if let suggestionsMenu, runtime.presentations.contains(where: { $0 === suggestionsMenu }) {
                suggestionsMenu.content.update(view: menuContent!, environment: environment, force: false)
            }
        }
    }

    /// macOS: opens the menu once the toolbar's field is there to anchor it (layout time).
    private func syncMenu() {
        guard let menuContent else { return }
        if let suggestionsMenu, runtime.presentations.contains(where: { $0 === suggestionsMenu }) { return }
        let anchor = runtime.toolbar?.content.descendants(where: { $0 is any _TextInputNode }).first
        suggestionsMenu = runtime.present(kind: .menu, view: menuContent, environment: environment, anchor: anchor) { [weak self] in
            self?.setPresented(false)
        }
    }

    private func dropSuggestions() {
        suggestions?.unmount()
        suggestions = nil
        menuContent = nil
        if let suggestionsMenu {
            runtime.remove(presentation: suggestionsMenu)
            self.suggestionsMenu = nil
        }
    }

    override package func unmount() {
        dropSuggestions()
        runtime.unregisterSearch(self)
        super.unmount()
    }

    override package func placeTarget(_ target: ViewNode, in bounds: CGRect, proposal: ProposedViewSize, by placer: ViewNode) {
        super.placeTarget(target, in: bounds, proposal: proposal, by: placer)
        syncMenu()
        guard let suggestions else { return }
        for node in suggestions.layoutChildren {
            node.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size), by: placer)
        }
    }

    override package func paintTarget(_ target: ViewNode, in node: ViewNode, into list: inout DisplayList, context: PaintContext) {
        super.paintTarget(target, in: node, into: &list, context: context)
        guard let suggestions else { return }
        // The list covers the content: the window's colour, the top separator a plain list
        // lacks, then the rows.
        let bounds = context.absoluteRect(target.presentedFrame)
        list.append(.fillRect(bounds, environment.platformProfile.resolve(.windowBackground, scheme: environment.colorScheme)))
        for layer in suggestions.layoutChildren { layer.paint(into: &list, context: context.child(at: layer.presentedFrame)) }
        let inset = PlatformMetrics.searchSuggestionSeparatorInset
        list.append(.fillRect(CGRect(x: bounds.minX + inset, y: bounds.minY, width: bounds.width - 2 * inset, height: PlatformMetrics.dividerThickness),
                              environment._ink(PlatformMetrics.listSeparatorAlpha)))
    }

    /// The suggestions take the presses while they show (they are listed last, so hit testing
    /// reaches them first).
    override package var paintedChildren: [ViewNode] { super.paintedChildren + (suggestions?.layoutChildren ?? []) }
    override package var structuralChildren: [ViewNode] { [child] + (suggestions.map { [$0] } ?? []) }
    override package var nodeDescription: String { "Searchable" }
}

/// The suggestions as macOS's menu under the field shows them: a column of the rows.
struct _SearchSuggestionsMenu: View {
    let content: AnyView
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(6)
            .frame(minWidth: 180, alignment: .leading)
    }
}

/// The suggestions as iOS lists them: a plain list, its rows in the accent colour.
struct _SearchSuggestionsList: View {
    let content: AnyView
    var body: some View {
        List { content }
            .listStyle(.plain)
            .foregroundStyle(Color.accentColor)
    }
}

// MARK: - Suggestions, scopes, completions

/// `searchSuggestions`: transparent; registers its content for the enclosing search.
@MainActor
package final class SearchSuggestionsNode<Content: View>: UnaryLayoutModifierNode<Content, _SearchSuggestionsModifier> {
    override package init(_ context: _NodeContext<ModifiedContent<Content, _SearchSuggestionsModifier>>) {
        super.init(context)
        runtime.registerSearchSuggestions(self, content: modifier.content)
        // A searchable below was built before the registration: it reads the rows now.
        for node in descendants(where: { $0 is any _SearchProviding }) { (node as? any _SearchProviding)?.suggestionsDidChange() }
    }

    override package func update(view: ModifiedContent<Content, _SearchSuggestionsModifier>, environment: EnvironmentValues, force: Bool) {
        // Registered before the content updates: a searchable below reads the new rows.
        runtime.registerSearchSuggestions(self, content: view.modifier.content)
        super.update(view: view, environment: environment, force: force)
    }

    override package func unmount() {
        runtime.unregisterSearchSuggestions(self)
        super.unmount()
    }
    override package var nodeDescription: String { "SearchSuggestions" }
}

/// One `searchScopes` modifier's bar.
package struct SearchScopeSource {
    weak var node: ViewNode?
    var selected: AnyHashable
    var select: _SearchScopeSelection
    var content: AnyView
    var activation: SearchScopeActivation

    /// Whether the bar shows for a search: on text entry (iOS's automatic) or on presentation
    /// (macOS's automatic).
    package func isActive(presented: Bool, text: String, isIOS: Bool) -> Bool {
        switch activation {
        case .onSearchPresentation: return presented
        case .onTextEntry: return !text.isEmpty
        default: return isIOS ? !text.isEmpty : presented
        }
    }
}

/// `searchScopes`: transparent; registers the scope bar for the enclosing search.
@MainActor
package final class SearchScopesNode<Content: View>: UnaryLayoutModifierNode<Content, _SearchScopesModifier> {
    override package init(_ context: _NodeContext<ModifiedContent<Content, _SearchScopesModifier>>) {
        super.init(context)
        register(modifier)
    }

    private func register(_ modifier: _SearchScopesModifier) {
        runtime.registerSearchScopes(self, source: SearchScopeSource(node: self, selected: modifier.selected, select: modifier.select,
                                                                     content: modifier.content, activation: modifier.activation))
    }

    override package func update(view: ModifiedContent<Content, _SearchScopesModifier>, environment: EnvironmentValues, force: Bool) {
        register(view.modifier)
        super.update(view: view, environment: environment, force: force)
    }

    override package func unmount() {
        runtime.unregisterSearchScopes(self)
        super.unmount()
    }
    override package var nodeDescription: String { "SearchScopes" }
}

@MainActor private var nextSearchCompletionIdentifier = 9_960_000

/// `searchCompletion`: the suggestion row is a button that fills the field (the text, or a token).
@MainActor
package final class SearchCompletionNode<Content: View>: UnaryLayoutModifierNode<Content, _SearchCompletionModifier>, _Interactive {
    private let identifier: Int

    override package init(_ context: _NodeContext<ModifiedContent<Content, _SearchCompletionModifier>>) {
        nextSearchCompletionIdentifier += 1
        identifier = nextSearchCompletionIdentifier
        super.init(context)
    }

    package func pressBegan() {}
    package func pressEnded(inside: Bool) {
        guard inside, environment.isEnabled else { return }
        runtime.completeSearch(with: modifier.completion)
    }

    package var semantics: SemanticsNode {
        let label = child.descendants(where: { $0 is TextNode }).compactMap { ($0 as? TextNode)?.view.resolvedString }.joined(separator: " ")
        return SemanticsNode(role: .button, label: label, frame: frameInRoot, identifier: identifier)
    }
    override package var nodeDescription: String { "SearchCompletion" }
}

// MARK: - The runtime's registries

extension Runtime {
    package func registerSearch(_ node: ViewNode, field: SearchSource) {
        if let index = searchSources.firstIndex(where: { $0.node === node }) {
            searchSources[index] = field
        } else {
            searchSources.append(field)
        }
        requestLayout()
    }

    package func unregisterSearch(_ node: ViewNode) {
        searchSources.removeAll { $0.node === node || $0.node == nil }
        requestLayout()
    }

    /// The field the chrome shows: the first mounted `searchable`.
    package var searchField: SearchSource? { searchSources.first { $0.node?.isMounted == true } }

    /// Whether a `searchable` is mounted (hosts without chrome can show their own field).
    public var hasSearchField: Bool { searchField != nil }

    package func registerSearchSuggestions(_ node: ViewNode, content: AnyView) {
        if let index = searchSuggestionSources.firstIndex(where: { $0.node === node }) {
            searchSuggestionSources[index].content = content
        } else {
            searchSuggestionSources.append(SearchSuggestionSource(node: node, content: content))
        }
    }

    package func unregisterSearchSuggestions(_ node: ViewNode) {
        searchSuggestionSources.removeAll { $0.node === node || $0.node == nil }
    }

    /// The suggestion rows of the first mounted `searchSuggestions`.
    package var searchSuggestions: AnyView? { searchSuggestionSources.first { $0.node?.isMounted == true }?.content }

    package func registerSearchScopes(_ node: ViewNode, source: SearchScopeSource) {
        if let index = searchScopeSources.firstIndex(where: { $0.node === node }) {
            searchScopeSources[index] = source
        } else {
            searchScopeSources.append(source)
        }
        requestLayout()
    }

    package func unregisterSearchScopes(_ node: ViewNode) {
        searchScopeSources.removeAll { $0.node === node || $0.node == nil }
        requestLayout()
    }

    /// The scope bar of the first mounted `searchScopes`, when its activation says it shows.
    package var activeSearchScopes: SearchScopeSource? {
        guard let field = searchField, let scopes = searchScopeSources.first(where: { $0.node?.isMounted == true }) else { return nil }
        let isIOS = (field.node?.environment ?? rootEnvironment).platformProfile.isIOS
        return scopes.isActive(presented: field.presented, text: field.text.wrappedValue, isIOS: isIOS) ? scopes : nil
    }

    /// A suggestion was chosen: its text becomes the query, or its token joins the tokens.
    package func completeSearch(with completion: _SearchCompletion) {
        guard let field = searchField else { return }
        switch completion.kind {
        case .text(let text):
            field.text.wrappedValue = text
        case .token(let token):
            if field.tokens?.append(token) == true { field.text.wrappedValue = "" }
        }
        requestFullLayout()
    }
}

package struct SearchSuggestionSource {
    weak var node: ViewNode?
    var content: AnyView
}

// MARK: - The iOS field

/// The field at the bottom of an iOS navigation stack (ios/search): a 46 pt capsule with the
/// magnifier 20 in and the text 48 in; presented, it sits lower and narrower next to a 48 pt
/// cancel circle, and a clear circle ends the text. Tokens precede the text as grey tags. The
/// field's focus is the search's presentation.
struct _IOSSearchBarView: View {
    let source: SearchSource
    let presented: Bool
    @FocusState private var focused: Bool

    private var text: String { source.text.wrappedValue }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: PlatformMetrics.searchCancelGap) {
                field
                    .padding(.top, presented ? PlatformMetrics.searchPresentedFieldTop : PlatformMetrics.searchFieldTop)
                if presented {
                    Button(action: cancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: PlatformMetrics.searchCancelGlyphSize, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(width: PlatformMetrics.searchCancelDiameter, height: PlatformMetrics.searchCancelDiameter)
                            .background(Circle().fill(Color(PlatformMetrics.searchFieldFill))
                                .shadow(color: Color.black.opacity(PlatformMetrics.searchFieldShadowAlpha),
                                        radius: PlatformMetrics.searchFieldShadowRadius, y: PlatformMetrics.searchFieldShadowOffset))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel")
                }
            }
            .padding(.horizontal, presented ? PlatformMetrics.searchPresentedFieldInset : PlatformMetrics.searchFieldInset)
            Spacer(minLength: 0)
        }
        .onChange(of: focused) { _, now in
            if now != presented { source.setPresented(now) }
        }
        .onChange(of: presented, initial: true) { _, now in
            if focused != now { focused = now }
        }
    }

    private var field: some View {
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: PlatformMetrics.searchMagnifierSize))
                .foregroundStyle(.secondary)
                .frame(width: PlatformMetrics.searchTextInset - PlatformMetrics.searchMagnifierInset, alignment: .leading)
            if let tokens = source.tokens, tokens.count() > 0 {
                HStack(spacing: PlatformMetrics.searchTokenGap) {
                    ForEach(Array(tokens.views().enumerated()), id: \.offset) { entry in
                        _SearchTokenTag(content: entry.element)
                    }
                }
                .padding(.trailing, PlatformMetrics.searchTokenTextGap)
            }
            TextField(source.prompt ?? "Search", text: source.text)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($focused)
                .frame(height: PlatformMetrics.searchTextLineHeight, alignment: .top)
            if presented && !text.isEmpty {
                Button(action: { source.text.wrappedValue = "" }) {
                    Image(systemName: "xmark")
                        .font(.system(size: PlatformMetrics.searchClearGlyphSize, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: PlatformMetrics.searchClearDiameter, height: PlatformMetrics.searchClearDiameter)
                        .background(Circle().fill(Color(PlatformMetrics.searchTokenFill)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear text")
            }
        }
        .padding(.leading, PlatformMetrics.searchMagnifierInset)
        .padding(.trailing, presented ? PlatformMetrics.searchClearTrailing : PlatformMetrics.searchMagnifierInset)
        .frame(maxWidth: .infinity)
        .frame(height: PlatformMetrics.searchFieldHeight)
        .background(Capsule().fill(Color(PlatformMetrics.searchFieldFill))
            .shadow(color: Color.black.opacity(PlatformMetrics.searchFieldShadowAlpha),
                    radius: PlatformMetrics.searchFieldShadowRadius, y: PlatformMetrics.searchFieldShadowOffset))
    }

    private func cancel() {
        source.text.wrappedValue = ""
        source.setPresented(false)
    }
}

/// A token in the field: its view in white on a grey tag.
struct _SearchTokenTag: View {
    let content: AnyView
    var body: some View {
        content
            .font(.body)
            .foregroundStyle(.white)
            .padding(.horizontal, PlatformMetrics.searchTokenPadding)
            .frame(height: PlatformMetrics.searchTokenHeight)
            .background(RoundedRectangle(cornerRadius: PlatformMetrics.searchTokenCornerRadius, style: .continuous)
                .fill(Color(PlatformMetrics.searchTokenFill)))
    }
}

/// The scope bar under a presented iOS search (ios/search/active `present`): a 44 pt band in a
/// light tint holding a 32 pt segmented control 16 in.
struct _IOSSearchScopeBarView: View {
    let scopes: SearchScopeSource

    var body: some View {
        VStack(spacing: 0) {
            _SearchScopePicker(scopes: scopes)
                .environment(\._inSearchScopeBar, true)
                .padding(.horizontal, PlatformMetrics.searchScopeInset)
                .padding(.top, PlatformMetrics.searchScopeBarTop)
                .shadow(color: Color.black.opacity(PlatformMetrics.searchScopeShadowAlpha),
                        radius: PlatformMetrics.searchScopeShadowRadius, y: PlatformMetrics.searchScopeShadowOffset)
            Spacer(minLength: 0)
        }
        .frame(height: PlatformMetrics.searchScopeBandHeight)
        .background(Color.primary.opacity(PlatformMetrics.searchScopeBandInk))
    }
}

/// The scopes as a segmented picker over the source's selection.
struct _SearchScopePicker: View {
    let scopes: SearchScopeSource

    var body: some View {
        Picker("", selection: Binding<AnyHashable>(get: { scopes.selected }, set: { scopes.select.select($0) })) {
            scopes.content
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

extension Color {
    /// A measured colour as a view colour.
    package init(_ rgba: RGBA) {
        self.init(red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }
}
