// Phase 8 step 6, sw-search: the search's presentation (its field's focus or a binding), the
// iOS field at the bottom of a navigation stack with its cancel button, suggestions replacing
// the content, completions, scopes, tokens, and the macOS toolbar's scope row and suggestion
// menu (Docs/elements/Toolbar.md).
import Testing
import SwiftUI
import SwiftUIWebHeadless

#if !os(WASI)
@Observable
private final class SearchModel {
    var query = ""
    var presented = false
    var scope = 0
    var tokens: [Fruit] = []
}

private struct Fruit: Identifiable, Hashable {
    let name: String
    var id: String { name }
}

private struct Searching: View {
    @Environment(\.isSearching) private var searching
    @Environment(\.dismissSearch) private var dismissSearch
    var body: some View {
        Button(searching ? "Searching" : "Idle") { dismissSearch() }._probe("status")
    }
}

/// The content under test: a list with a status row, searchable with suggestions and scopes.
private struct Root: View {
    let model: SearchModel
    var body: some View {
        NavigationStack {
            List {
                Searching()
                Text("Row")._probe("row")
            }
            .navigationTitle("Fruit")
            ._probe("list")
            .searchable(text: Binding(get: { model.query }, set: { model.query = $0 }),
                        tokens: Binding(get: { model.tokens }, set: { model.tokens = $0 }),
                        isPresented: Binding(get: { model.presented }, set: { model.presented = $0 }),
                        prompt: "Find fruit") { token in Text(token.name) }
            .searchScopes(Binding(get: { model.scope }, set: { model.scope = $0 }), activation: .onSearchPresentation) {
                Text("All").tag(0)
                Text("Fresh").tag(1)
            }
            .searchSuggestions {
                // Sized frames: the recorded engine knows no macOS widths, and a row must have a
                // size to be pressed.
                Text("Apple").frame(width: 80, height: 20).searchCompletion("Apple")._probe("suggest-Apple")
                Text("Banana").frame(width: 80, height: 20).searchCompletion(Fruit(name: "Banana"))._probe("suggest-Banana")
            }
        }
        ._probe("nav")
    }
}

@Suite @MainActor struct SearchTests {
    private static let body = ResolvedFont(family: "system", size: 17, weight: .regular, italic: false, textStyle: .body, profile: "iOS")
    private static let macBody = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: .body)
    private let size = CGSize(width: 320, height: 480)

    private func runtime<V: View>(_ view: V, iOS: Bool = true, chrome: Bool = false) -> Runtime {
        var environment = EnvironmentValues()
        if iOS { environment.platformProfile = .iOS }
        let runtime = Runtime(environment: environment)
        var entries: [String: RecordedTextEngine.Entry] = [:]
        for word in ["Row", "Searching", "Idle", "Find fruit", "Apple", "Banana", "All", "Fresh", "Fruit"] {
            entries[RecordedTextEngine.key(font: Self.body, width: nil, string: word)] = .init(width: 40, height: 24.5, firstBaseline: 18.5, lastBaseline: 18.5)
            entries[RecordedTextEngine.key(font: Self.macBody, width: nil, string: word)] = .init(width: 40, height: 16, firstBaseline: 13, lastBaseline: 13)
        }
        runtime.textEngine = RecordedTextEngine(entries: entries)
        runtime.paintsWindowChrome = chrome
        runtime.mount(view)
        runtime.layout(in: size)
        return runtime
    }

    private func field(_ runtime: Runtime) -> SemanticsNode? { runtime.semanticsTree().first { $0.role == .textField } }
    private func buttons(_ runtime: Runtime) -> [SemanticsNode] { runtime.semanticsTree().filter { $0.role == .button } }
    private func press(_ runtime: Runtime, _ point: CGPoint) {
        runtime.pointerDown(at: point)
        runtime.pointerUp(at: point)
        runtime.layout(in: size)
    }

    @Test func theFieldTakesABandAtTheBottomAndFocusPresentsTheSearch() {
        let model = SearchModel()
        let runtime = runtime(Root(model: model))
        // At rest: the list ends 76 above the window's bottom under the large title; the field
        // carries the prompt and sits in the band.
        #expect(runtime.probeFrames["list"] == CGRect(x: 0, y: 116.5, width: 320, height: 287.5))
        let field = try! #require(self.field(runtime))
        #expect(field.label == "Find fruit" && field.frame.minY > 404 && field.frame.minX == 76)
        #expect(buttons(runtime).map(\.label) == ["Idle"])
        // Pressing the field focuses it: the search presents, the bar hides and the scope bar
        // (on presentation) takes a band under the 10 pt inset; the cancel button appears.
        press(runtime, CGPoint(x: field.frame.midX, y: field.frame.midY))
        #expect(model.presented)
        #expect(runtime.probeFrames["list"] == CGRect(x: 0, y: 54, width: 320, height: 366))
        let suggestion = try! #require(runtime.probeFrames["suggest-Apple"])
        #expect(suggestion.minX == 16 && suggestion.minY > 54 && suggestion.maxY < 54 + 56)
        #expect(buttons(runtime).map(\.label).contains("Searching"))
        // The presented field is narrower, next to the 48 pt cancel circle.
        let presented = try! #require(self.field(runtime))
        #expect(presented.frame.minX == 60 && presented.frame.minY > 420)
        let cancel = try! #require(buttons(runtime).first { $0.label == "Cancel" })
        #expect(cancel.frame.minX == 260 && cancel.frame.minY == 420)
        // Cancel ends the search and clears the text.
        model.query = "an"
        runtime.layout(in: size)
        press(runtime, CGPoint(x: cancel.frame.midX, y: cancel.frame.midY))
        #expect(!model.presented && model.query.isEmpty)
        #expect(runtime.probeFrames["list"] == CGRect(x: 0, y: 116.5, width: 320, height: 287.5))
        #expect(runtime.probeFrames["suggest-Apple"] == nil)
    }

    @Test func completionsFillTheFieldAndScopesSelect() {
        let model = SearchModel()
        model.presented = true
        let runtime = runtime(Root(model: model))
        // A text completion sets the query; a token completion adds the token and clears it.
        let apple = try! #require(runtime.probeFrames["suggest-Apple"])
        press(runtime, CGPoint(x: apple.midX, y: apple.midY))
        #expect(model.query == "Apple")
        let banana = try! #require(runtime.probeFrames["suggest-Banana"])
        press(runtime, CGPoint(x: banana.midX, y: banana.midY))
        #expect(model.tokens == [Fruit(name: "Banana")] && model.query.isEmpty)
        // The token shows in the field before the text, and the text moves after it.
        #expect(runtime.render(scale: 2).commands.map(\.description).contains { $0.hasPrefix("drawText(\"Banana\"") })
        // The scope bar: its second segment selects scope 1.
        press(runtime, CGPoint(x: 240, y: 28))
        #expect(model.scope == 1)
        // dismissSearch from inside the content ends the presentation.
        let status = try! #require(buttons(runtime).first { $0.label == "Searching" })
        _ = status
        model.presented = false
        runtime.layout(in: size)
        #expect(runtime.probeFrames["list"]?.minY == 116.5)
    }

    @Test func keepingTheBarAndTextEntryActivation() {
        struct Kept: View {
            let model: SearchModel
            var body: some View {
                NavigationStack {
                    List { Text("Row")._probe("row") }
                        .navigationTitle("Fruit")
                        ._probe("list")
                        .searchable(text: Binding(get: { model.query }, set: { model.query = $0 }),
                                    isPresented: Binding(get: { model.presented }, set: { model.presented = $0 }))
                        .searchScopes(Binding(get: { model.scope }, set: { model.scope = $0 })) { Text("All").tag(0); Text("Fresh").tag(1) }
                        .searchPresentationToolbarBehavior(.avoidHidingContent)
                }
            }
        }
        let model = SearchModel()
        model.presented = true
        let runtime = runtime(Kept(model: model))
        // The bar stays; the scopes (automatic = on text entry on iOS) wait for text.
        #expect(runtime.probeFrames["list"] == CGRect(x: 0, y: 116.5, width: 320, height: 303.5))
        model.query = "a"
        runtime.layout(in: size)
        #expect(runtime.probeFrames["list"] == CGRect(x: 0, y: 160.5, width: 320, height: 259.5))
    }

    @Test func macOSToolbarGrowsAScopeRowAndOpensASuggestionMenu() {
        let model = SearchModel()
        let runtime = runtime(Root(model: model), iOS: false, chrome: true)
        #expect(runtime.toolbarFrame?.height == 52)
        model.presented = true
        runtime.layout(in: CGSize(width: 320, height: 480))
        // Presented: the scope row under the bar, and the suggestions in a menu.
        #expect(runtime.toolbarFrame?.height == 82)
        #expect(runtime.presentations.count == 1 && runtime.presentations[0].kind == .menu)
        let apple = try! #require(runtime.probeFrames["suggest-Apple"])
        press(runtime, CGPoint(x: apple.midX, y: apple.midY))
        #expect(model.query == "Apple")
        model.presented = false
        runtime.layout(in: CGSize(width: 320, height: 480))
        #expect(runtime.presentations.isEmpty && runtime.toolbarFrame?.height == 52)
    }
}
#endif
