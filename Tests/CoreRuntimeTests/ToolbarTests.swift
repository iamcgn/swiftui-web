// Phase 6: `toolbar` items collected on the runtime; hosts painting chrome get a 52 pt bar with
// the title and the items, and the content is laid out below it.
import Testing
import SwiftUI
import SwiftUIWebHeadless

#if !os(WASI)
@MainActor private final class Counter { var taps = 0 }

@Suite @MainActor struct ToolbarTests {
    private static let bold13 = ResolvedFont(family: "system", size: 13, weight: .semibold, italic: false, textStyle: nil)
    private static let bold15 = ResolvedFont(family: "system", size: 15, weight: .semibold, italic: false, textStyle: nil)

    private func runtime<V: View>(_ view: V, chrome: Bool = true) -> Runtime {
        var entries: [String: RecordedTextEngine.Entry] = [:]
        for (word, width) in [("Action", 44.0), ("Back", 30.0), ("One", 26.0), ("Two", 28.0)] {
            entries[RecordedTextEngine.key(font: Self.bold13, width: nil, string: word)] = .init(width: width, height: 16, firstBaseline: 13, lastBaseline: 13)
        }
        entries[RecordedTextEngine.key(font: Self.bold15, width: nil, string: "Title")] = .init(width: 40, height: 18, firstBaseline: 15, lastBaseline: 15)
        let regular13 = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)
        for (word, width) in [("Find", 28.0), ("Idle", 26.0), ("Searching", 60.0), ("ap", 14.0)] {
            entries[RecordedTextEngine.key(font: regular13, width: nil, string: word)] = .init(width: width, height: 16, firstBaseline: 13, lastBaseline: 13)
        }
        let runtime = Runtime()
        runtime.textEngine = RecordedTextEngine(entries: entries)
        runtime.paintsWindowChrome = chrome
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 400, height: 200))
        return runtime
    }

    @Test func itemsAreCollectedAndTheBarLaysOutAboveTheContent() {
        let counter = Counter()
        let runtime = runtime(Color.red._probe("content").navigationTitle("Title").toolbar {
            ToolbarItem(placement: .navigation) { Button("Back") { counter.taps += 10 } }
            ToolbarItem(placement: .primaryAction) { Button("Action") { counter.taps += 1 } }
            ToolbarItemGroup { Button("One") {}; Button("Two") {} }
        })
        #expect(runtime.toolbarItems.map(\.placement) == [.navigation, .primaryAction, .automatic])
        #expect(runtime.toolbarFrame == CGRect(x: 0, y: 0, width: 400, height: 52))
        #expect(runtime.probeFrames["content"] == CGRect(x: 0, y: 52, width: 400, height: 148))
        // The bar paints its background and hairline, then the platters and labels.
        let commands = runtime.render(scale: 2).commands.map(\.description)
        #expect(commands.contains("fillRect(0, 0, 400, 52) #FFFFFF") && commands.contains("fillRect(0, 51.5, 400, 0.5) #000000@0.12"))
        #expect(commands.contains { $0.hasPrefix("drawText(\"Title\"") } && commands.contains { $0.hasPrefix("drawText(\"Action\"") })
        // Leading item after the 8 pt margin, trailing items right-aligned 8 pt apart; 36 pt platters centred.
        let semantics = runtime.semanticsTree()
        let back = semantics.first { $0.label == "Back" }!.frame
        let action = semantics.first { $0.label == "Action" }!.frame
        let two = semantics.first { $0.label == "Two" }!.frame
        #expect(back.minX == 8 && back.midY == 26 && back.height == 36)
        #expect(two.maxX == 392 && action.maxX + 8 <= two.minX)
        // The bar's buttons are hit tested before the content and take clicks.
        let actionCentre = CGPoint(x: action.midX, y: action.midY)
        runtime.pointerDown(at: actionCentre)
        runtime.pointerUp(at: actionCentre)
        #expect(counter.taps == 1)
        #expect(runtime.interactiveNode(at: CGPoint(x: 200, y: 100)) == nil)
    }

    @Test func searchableShowsAFieldInTheBarAndFiltersThroughItsBinding() {
        @MainActor final class Model: ObservableObject { @Published var query = "" }
        // `isSearching` is read inside the searchable view, as in SwiftUI.
        struct Status: View {
            @Environment(\.isSearching) private var searching
            var body: some View { Text(searching ? "Searching" : "Idle") }
        }
        struct Root: View {
            @ObservedObject var model: Model
            var body: some View {
                VStack { Status() }.searchable(text: $model.query, prompt: "Find")
            }
        }
        let model = Model()
        let runtime = runtime(Root(model: model))
        #expect(runtime.hasSearchField && runtime.toolbarFrame != nil)
        // The field's text line sits at the trailing end of the bar (10 pt inside its capsule),
        // centred on the bar, with the prompt as its placeholder.
        let field = runtime.semanticsTree().first { $0.role == .textField }
        #expect(field?.label == "Find" && field.map { $0.frame.maxX == 382 && $0.frame.midY == 26 } == true)
        // Typing through the host's hook edits the binding; the content reads isSearching.
        var commands = runtime.render(scale: 2).commands.map(\.description)
        #expect(commands.contains { $0.hasPrefix("drawText(\"Idle\"") })
        runtime.textField(field!.identifier, didChange: "ap")
        runtime.layout(in: CGSize(width: 400, height: 200))
        #expect(model.query == "ap")
        commands = runtime.render(scale: 2).commands.map(\.description)
        #expect(commands.contains { $0.hasPrefix("drawText(\"Searching\"") })
        // Without chrome the field is not shown but the modifier still registers.
        let plain = self.runtime(Root(model: model), chrome: false)
        #expect(plain.hasSearchField && plain.toolbarFrame == nil && !plain.semanticsTree().contains { $0.role == .textField })
    }

    @Test func noChromeNoBar() {
        let runtime = runtime(Color.red._probe("content").toolbar { ToolbarItem { Button("Action") {} } }, chrome: false)
        #expect(runtime.toolbarItems.count == 1 && runtime.toolbarFrame == nil)
        #expect(runtime.probeFrames["content"] == CGRect(x: 0, y: 0, width: 400, height: 200))
        #expect(!runtime.render(scale: 2).commands.map(\.description).contains { $0.hasPrefix("drawText(\"Action\"") })
    }

    @Test func hiddenToolbarAndUnmountedItems() {
        struct Host: View {
            @Binding var shown: Bool
            @Binding var hidden: Bool
            var body: some View {
                VStack {
                    if shown { Color.red.toolbar { ToolbarItem { Button("Action") {} } } }
                    Color.blue
                }
                .toolbar(hidden ? .hidden : .visible, for: .windowToolbar)
            }
        }
        @MainActor final class Model: ObservableObject { @Published var shown = true; @Published var hidden = false }
        let model = Model()
        struct Root: View {
            @ObservedObject var model: Model
            var body: some View { Host(shown: $model.shown, hidden: $model.hidden) }
        }
        let runtime = runtime(Root(model: model))
        #expect(runtime.toolbarFrame != nil)
        model.hidden = true
        runtime.layout(in: CGSize(width: 400, height: 200))
        #expect(runtime.toolbarFrame == nil)
        model.hidden = false
        model.shown = false
        runtime.layout(in: CGSize(width: 400, height: 200))
        #expect(runtime.toolbarItems.isEmpty && runtime.toolbarFrame == nil)
        // Accepted modifiers change nothing.
        _ = Color.red.toolbarBackground(.hidden, for: .windowToolbar).toolbarRole(.editor).toolbarTitleDisplayMode(.inline)
    }
}
#endif
