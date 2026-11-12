// The view-side members The Composable Architecture's case studies and SwiftNavigation reach
// for in iOS code: text-level accessibility (`Text.accessibilityLabel` returns a `Text`, so it
// concatenates), localized string resources and tables, `@SceneStorage`, and preview traits
// whose modifiers are not `Sendable`.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
private struct SceneTab: View {
    @SceneStorage("tca.tab") var tab = 0
    @SceneStorage("tca.missing") var note: String?
    var body: some View { Button("tab \(tab) \(note ?? "nil")") { tab += 1 }.buttonStyle(.plain) }
}

/// A preview modifier holding a reference, so it is not `Sendable`.
private final class Counter { var value = 0 }
private struct Holding: PreviewModifier {
    let counter = Counter()
    func body(content: Content, context: Void) -> some View { content }
}

@Suite(.serialized) @MainActor struct TCAFoundationViewTests {
    private func runtime<V: View>(_ view: V) -> Runtime {
        let runtime = Runtime()
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 320, height: 300))
        return runtime
    }

    private func texts(_ runtime: Runtime) -> [String] {
        runtime.root.descendants(where: { $0 is TextNode }).compactMap { ($0 as? TextNode)?.view.resolvedString }
    }

    @Test func textLevelAccessibilityStaysText() {
        let five: Text = Text("5").accessibilityLabel("Five")
        let heading: Text = Text("Intro").accessibilityHeading(.h2)
        let r = runtime(VStack {
            five
            heading
            Text("Plain").accessibilityHeading(.unspecified)
            Text("x = 1").accessibilityTextContentType(.sourceCode).speechSpellsOutCharacters()
            Text("A") + Text("B").accessibilityLabel(Text("Bee"))
        })
        let tree = r.semanticsTree()
        let label = tree.first { $0.label == "Five" }
        #expect(label?.role == .text, "\(tree.map(\.label))")
        #expect(!tree.contains { $0.label == "5" })
        let intro = tree.first { $0.label == "Intro" }
        #expect(intro?.role == .heading && intro?.headingLevel == 2)
        #expect(tree.first { $0.label == "Plain" }?.role == .heading)
        #expect(tree.contains { $0.label == "x = 1" })
    }

    @Test func localizedResourcesAndTablesShowTheirText() {
        let resource: LocalizedStringResource = "Welcome back"
        let r = runtime(VStack {
            Text(resource)
            Text("Settings", tableName: "Main", comment: "The settings title")
        })
        #expect(texts(r) == ["Welcome back", "Settings"])
    }

    @Test func sceneStorageKeepsItsValue() throws {
        for key in ["tca.tab", "tca.missing"] { _SceneStore.defaults.removeObject(forKey: key) }
        let renderer = HeadlessRenderer(size: CGSize(width: 200, height: 100), textEngine: MonospaceTextEngine())
        renderer.mount(SceneTab()._probe("tab"))
        renderer.renderFrame()
        #expect(texts(renderer.runtime) == ["tab 0 nil"])
        let frame = try #require(renderer.probeFrames["tab"])
        renderer.runtime.pointerDown(at: CGPoint(x: frame.midX, y: frame.midY))
        renderer.runtime.pointerUp(at: CGPoint(x: frame.midX, y: frame.midY))
        renderer.renderFrame()
        #expect(_SceneStore.defaults.integer(forKey: "tca.tab") == 1)
        #expect(texts(renderer.runtime) == ["tab 1 nil"])

        // A fresh view (a reload) reads what was stored.
        renderer.mount(SceneTab())
        renderer.renderFrame()
        #expect(texts(renderer.runtime) == ["tab 1 nil"])
        _SceneStore.defaults.removeObject(forKey: "tca.tab")
    }

    @Test func previewTraitsTakeModifiersThatAreNotSendable() {
        let traits: [PreviewTrait<Preview.ViewTraits>] = [.modifier(Holding()), .portrait, .landscapeLeft]
        let preview = _Preview(name: "Held", traits: traits, file: "CoreRuntimeTests/TCAFoundationViewTests.swift", line: 1) { Text("Held") }
        #expect(preview.fixedSize == nil)
        let sized = _Preview(name: "Sized", traits: [.fixedLayout(width: 100, height: 50)], file: "x.swift", line: 2) { Text("Sized") }
        #expect(sized.fixedSize == CGSize(width: 100, height: 50))
    }
}
#endif
