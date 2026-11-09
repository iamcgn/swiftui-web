// `@Previewable` (Docs/coverage.md: 3 apps): a variable a `#Preview` body declares with it
// becomes a stored property of the preview's own view, so its `@State` lasts across updates
// and the rest of the body (several statements, through the view builder) reads it.
import Testing
import SwiftUI
import SwiftUIWebHeadless

#if !os(WASI)   // as PreviewTests: no MonospaceTextEngine and no conformance scan on wasm
#Preview("Previewable") {
    @Previewable @State var count = 3
    let label = "Count"
    Text("\(label) \(count)")
}

#Preview("Previewable return") {
    @Previewable @State var count = 4
    let label = "Returned"
    return Text("\(label) \(count)")
        .padding()
}

@Suite @MainActor struct PreviewableTests {
    @Test func previewableStateRenders() {
        #if canImport(MachO)
        let previews = _PreviewRegistry.all.filter { $0.name == "Previewable" }
        #expect(previews.count == 1)
        guard let preview = previews.first else { return }
        let r = Runtime()
        r.textEngine = MonospaceTextEngine()
        r.mount(preview.makeView())
        r.layout(in: CGSize(width: 200, height: 100))
        #expect(r.render(scale: 1).commands.map(\.description).contains { $0.hasPrefix("drawText(\"Count 3\"") })
        // A body that ends in an explicit `return` (no view builder) renders the same way.
        let returning = _PreviewRegistry.all.filter { $0.name == "Previewable return" }
        #expect(returning.count == 1)
        if let preview = returning.first {
            let q = Runtime()
            q.textEngine = MonospaceTextEngine()
            q.mount(preview.makeView())
            q.layout(in: CGSize(width: 200, height: 100))
            #expect(q.render(scale: 1).commands.map(\.description).contains { $0.hasPrefix("drawText(\"Returned 4\"") })
        }
        #endif
        // A body of several statements passes through the view builder.
        let built = _Preview(name: nil, traits: [], file: "PreviewableTests.swift", line: 1) {
            let word = "Built"
            Text(word)
        }
        let b = Runtime()
        b.textEngine = MonospaceTextEngine()
        b.mount(built.makeView())
        b.layout(in: CGSize(width: 200, height: 100))
        #expect(b.render(scale: 1).commands.map(\.description).contains { $0.hasPrefix("drawText(\"Built\"") })
    }
}
#endif
