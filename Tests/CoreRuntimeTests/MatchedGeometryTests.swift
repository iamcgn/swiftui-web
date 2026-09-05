// @Namespace and matchedGeometryEffect: a view arriving under an animation glides from the
// frame its predecessor had, the predecessor's ghost glides to it, non-sources paint at the
// source's frame.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct MatchedGeometryTests {
    @Observable final class Model: @unchecked Sendable {
        var top = true
    }

    static let red = "#FF383C"

    private func runtime<V: View>(_ view: V) -> Runtime {
        let runtime = Runtime()
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 320, height: 200))
        return runtime
    }

    private func commands(_ r: Runtime) -> [String] { r.render(scale: 2).commands.map(\.description) }
    private func relayout(_ r: Runtime) { r.layout(in: CGSize(width: 320, height: 200)) }

    struct Hero: View {
        let model: Model
        @Namespace private var space
        var body: some View {
            VStack(spacing: 0) {
                if model.top {
                    Color.red.frame(width: 40, height: 40).matchedGeometryEffect(id: "box", in: space)._probe("top")
                }
                Color.clear.frame(width: 200, height: 100)
                if !model.top {
                    Color.red.frame(width: 80, height: 40).matchedGeometryEffect(id: "box", in: space)._probe("bottom")
                }
            }
        }
    }

    @Test func namespacesAreDistinctAndStable() {
        final class Seen { var ids: [Namespace.ID] = [] }
        struct Pair: View {
            let seen: Seen
            @Namespace var a
            @Namespace var b
            var body: some View {
                seen.ids += [a, b]
                return Color.clear
            }
        }
        let seen = Seen()
        let r = runtime(Pair(seen: seen))
        relayout(r)
        #expect(seen.ids.count >= 2 && seen.ids[0] != seen.ids[1])
        // Re-evaluations keep the same ids.
        #expect(seen.ids.count < 4 || (seen.ids[2] == seen.ids[0] && seen.ids[3] == seen.ids[1]))
    }

    @Test func arrivingViewGlidesFromItsPredecessor() {
        let model = Model()
        let r = runtime(Hero(model: model))
        #expect(r.probeFrames["top"] == CGRect(x: 140, y: 30, width: 40, height: 40))
        withAnimation(.linear(duration: 1)) { model.top = false }
        relayout(r)
        #expect(r.probeFrames["bottom"] == CGRect(x: 120, y: 130, width: 80, height: 40))
        #expect(r.isAnimating)
        // Half-way both the arriving box and the ghost of the old one sit between the two frames.
        r.advanceAnimations(elapsed: 0.5)
        let mid = commands(r)
        let reds = mid.filter { $0.hasPrefix("fillRect(") && $0.hasSuffix(Self.red) }
        // Origins follow the tween; the sizes scale through concat ops (80 → 60 and 40 → 60).
        #expect(reds == ["fillRect(130, 80, 80, 40) \(Self.red)", "fillRect(130, 80, 40, 40) \(Self.red)"])
        #expect(mid.filter { $0.hasPrefix("concat(") }.count == 2)
        r.advanceAnimations(elapsed: 0.5)
        r.advanceAnimations(elapsed: 0.01)
        let end = commands(r)
        #expect(end == ["fillRect(120, 130, 80, 40) \(Self.red)"])
        #expect(!r.isAnimating)
    }

    struct Shadow: View {
        @Namespace private var space
        var body: some View {
            ZStack(alignment: .topLeading) {
                Color.red.frame(width: 40, height: 40).matchedGeometryEffect(id: "s", in: space)
                    .padding(EdgeInsets(top: 30, leading: 100, bottom: 0, trailing: 0))
                Color.blue.matchedGeometryEffect(id: "s", in: space, isSource: false)._probe("follower")
            }
            .frame(width: 200, height: 100, alignment: .topLeading)
        }
    }

    @Test func followerContentTakesTheSourceFrame() {
        let r = runtime(Shadow())
        // The follower's own slot fills the stack (as a Color would); its content is laid out at
        // the source's size on the source's centre (measured on matched/anchors).
        #expect(r.probeFrames["follower"] == CGRect(x: 60, y: 50, width: 200, height: 100))
        let blue = commands(r).filter { $0.hasPrefix("fillRect(") && $0.hasSuffix("#0088FF") }
        #expect(blue == ["fillRect(160, 80, 40, 40) #0088FF"])
    }
}
#endif
