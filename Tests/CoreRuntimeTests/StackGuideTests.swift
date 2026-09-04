// A stack's own alignment guide is explicit only when a child's is: a padded leading-aligned
// stack inside a leading-aligned flexible frame keeps its inset (the padding shifts explicit
// guides, and an outer frame aligns them), while baseline-aligned stacks still expose the line.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct StackGuideTests {
    static let system13 = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)

    private func runtime<V: View>(_ view: V) -> Runtime {
        var entries: [String: RecordedTextEngine.Entry] = [:]
        for (word, width) in [("Hello", 31.0), ("Hg", 17.5)] {
            entries[RecordedTextEngine.key(font: Self.system13, width: nil, string: word)] = .init(width: width, height: 16, firstBaseline: 13, lastBaseline: 13)
        }
        let r = Runtime()
        r.textEngine = RecordedTextEngine(entries: entries)
        r.mount(view)
        r.layout(in: CGSize(width: 358, height: 100))
        return r
    }

    @Test func paddedStackKeepsItsInsetInAFlexibleFrame() {
        let r = runtime(VStack(alignment: .leading) { Text("Hello")._probe("text") }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)._probe("frame"))
        #expect(r.probeFrames["frame"] == CGRect(x: 0, y: 22, width: 358, height: 56))
        #expect(r.probeFrames["text"] == CGRect(x: 20, y: 42, width: 31, height: 16))
        let trailing = runtime(HStack { Text("Hello")._probe("text") }.padding(20).frame(maxWidth: .infinity, alignment: .trailing))
        #expect(abs((trailing.probeFrames["text"]?.minX ?? 0) - 307) < 1e-9)
    }

    @Test func baselineAlignedStacksStillExposeTheirLine() {
        // Text baselines are explicit, so the row's first baseline is the aligned line and a
        // sibling text in an outer baseline-aligned row lines up with it.
        let r = runtime(HStack(alignment: .firstTextBaseline, spacing: 8) {
            HStack(alignment: .firstTextBaseline) { Text("Hello")._probe("inner") }.padding(.top, 10)
            Text("Hg")._probe("outer")
        })
        #expect(r.probeFrames["inner"]?.minY == r.probeFrames["outer"]?.minY)
    }
}
#endif
