// List looks (Docs/elements/List.md): scrolling to a row through a ScrollViewReader, an outline
// row disclosing its children on a press, and section separators the modifiers hide.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct ListLooksTests {
    struct Node: Identifiable, Sendable {
        let id: String
        let children: [Node]?
    }

    @Observable final class Model: @unchecked Sendable {
        var proxy: ScrollViewProxy?
    }

    private func engine() -> RecordedTextEngine {
        var entries: [String: RecordedTextEngine.Entry] = [:]
        let font = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)
        for (word, width) in [("Fruits", 34.5), ("Apple", 35.0), ("Banana", 45.0), ("Water", 36.0)] + (1...12).map({ ("Row \($0)", 40.0) }) {
            for w: CGFloat? in [nil, 0, 320, 288, 279, 266, 275] {
                entries[RecordedTextEngine.key(font: font, width: w, string: word)] = .init(width: width, height: 16, firstBaseline: 13, lastBaseline: 13)
            }
        }
        return RecordedTextEngine(entries: entries)
    }

    private func runtime<V: View>(_ view: V) -> Runtime {
        let runtime = Runtime()
        runtime.textEngine = engine()
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 320, height: 100))
        return runtime
    }

    private func relayout(_ r: Runtime) { r.layout(in: CGSize(width: 320, height: 100)) }

    struct Scrolling: View {
        let model: Model
        var body: some View {
            ScrollViewReader { proxy in
                List {
                    ForEach(1...12, id: \.self) { index in Text("Row \(index)").id(index)._probe("row\(index)") }
                }
                .onAppear { model.proxy = proxy }
            }
        }
    }

    @Test func scrollToReachesAListRow() {
        let model = Model()
        let r = runtime(Scrolling(model: model))
        #expect(model.proxy != nil)
        let before = r.probeFrames["row10"]!
        model.proxy?.scrollTo(10, anchor: .top)
        relayout(r)
        let after = r.probeFrames["row10"]!
        #expect(after.minY < before.minY)
        // Clamped to the end: the last row's bottom sits at the viewport's bottom.
        #expect(r.probeFrames["row12"]!.maxY <= 100)
    }

    struct Outline: View {
        var body: some View {
            List([Node(id: "Fruits", children: [Node(id: "Apple", children: nil), Node(id: "Banana", children: nil)]), Node(id: "Water", children: nil)], children: \.children) { node in
                Text(node.id)._probe(node.id)
            }
        }
    }

    @Test func outlineRowsDiscloseOnAPress() {
        let r = runtime(Outline())
        // Collapsed: the rows sit 9 in for the chevron column; no children.
        #expect(r.probeFrames["Fruits"]!.minX == 25 && r.probeFrames["Apple"] == nil)
        let fruits = r.probeFrames["Fruits"]!
        r.pointerDown(at: CGPoint(x: 18, y: fruits.midY)); r.pointerUp(at: CGPoint(x: 18, y: fruits.midY))
        relayout(r)
        // Expanded: the children follow, a level (13) deeper; Water moves down.
        #expect(r.probeFrames["Apple"]!.minX == 38 && r.probeFrames["Banana"]!.minX == 38)
        #expect(r.probeFrames["Water"]!.minY > r.probeFrames["Banana"]!.minY)
        r.pointerDown(at: CGPoint(x: 18, y: fruits.midY)); r.pointerUp(at: CGPoint(x: 18, y: fruits.midY))
        relayout(r)
        #expect(r.probeFrames["Apple"] == nil)
    }
}
#endif
