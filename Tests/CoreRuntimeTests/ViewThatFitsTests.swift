// Phase 8 step 6, sw-viewthatfits: the first candidate whose ideal size fits on the chosen
// axes, the last otherwise; only it is laid out, painted and probed (Docs/elements/Layout.md).
import Testing
import SwiftUI
import SwiftUIWebHeadless

#if !os(WASI)
@Observable private final class Model { var width: CGFloat = 200 }

private struct Fitting: View {
    let model: Model
    var body: some View {
        ViewThatFits {
            Color.red.frame(width: 150, height: 20)._probe("wide")
            Color.blue.frame(width: 80, height: 20)._probe("medium")
            Color.green.frame(width: 30, height: 20)._probe("narrow")
        }
        .frame(width: model.width)
        ._probe("fits")
    }
}

@Suite @MainActor struct ViewThatFitsTests {
    private func runtime<V: View>(_ view: V) -> Runtime {
        let runtime = Runtime()
        runtime.textEngine = RecordedTextEngine(entries: [:])
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 300, height: 100))
        return runtime
    }

    @Test func picksTheFirstCandidateThatFitsAndFollowsTheProposal() {
        let model = Model()
        let runtime = runtime(Fitting(model: model))
        #expect(runtime.root.descendants(where: { $0.nodeDescription == "ViewThatFits" }).count == 1)
        // 200 fits the wide one; only it is probed and painted.
        #expect(runtime.probeFrames["wide"]?.width == 150 && runtime.probeFrames["medium"] == nil && runtime.probeFrames["narrow"] == nil)
        #expect(runtime.probeFrames["fits"]?.size == CGSize(width: 200, height: 20))
        #expect(runtime.render(scale: 2).commands.map(\.description).filter { $0.hasPrefix("fillRect") }.count == 1)
        model.width = 100
        runtime.layout(in: CGSize(width: 300, height: 100))
        #expect(runtime.probeFrames["wide"] == nil && runtime.probeFrames["medium"]?.width == 80)
        // Nothing fits in 10: the last candidate.
        model.width = 10
        runtime.layout(in: CGSize(width: 300, height: 100))
        #expect(runtime.probeFrames["narrow"]?.width == 30 && runtime.probeFrames["medium"] == nil)
    }

    @Test func constrainedAxesOnly() {
        // Vertical only: a 20 pt tall candidate fits a 30 pt frame whatever its width.
        let vertical = runtime(ViewThatFits(in: .vertical) {
            Color.red.frame(width: 500, height: 20)._probe("tall")
            Color.blue.frame(width: 10, height: 10)._probe("small")
        }.frame(width: 50, height: 30))
        #expect(vertical.probeFrames["tall"] != nil && vertical.probeFrames["small"] == nil)
        // Both axes: the 500 wide one no longer fits.
        let both = runtime(ViewThatFits {
            Color.red.frame(width: 500, height: 20)._probe("tall")
            Color.blue.frame(width: 10, height: 10)._probe("small")
        }.frame(width: 50, height: 30))
        #expect(both.probeFrames["tall"] == nil && both.probeFrames["small"] != nil)
    }
}
#endif
