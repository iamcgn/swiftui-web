// Custom Layout corners (sw-custom-layout, Docs/elements/CustomLayout.md): a layout's animatable
// parameters tween under withAnimation and the tree lays out again each frame; a layout's cache
// is made once, updated when the view or its subviews change, remade for a new AnyLayout type;
// GridLayout as a layout value is held by `customlayout/grid-layout`.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct LayoutAnimationTests {
    /// A row with an animatable gap and a cache counting its lifecycle.
    struct Gapped: Layout {
        struct Cache { var made = 0; var updated = 0 }
        var gap: CGFloat
        nonisolated var animatableData: CGFloat {
            get { gap }
            set { gap = newValue }
        }
        func makeCache(subviews: Subviews) -> Cache { Self.made += 1; return Cache(made: 1) }
        func updateCache(_ cache: inout Cache, subviews: Subviews) { Self.updated += 1; cache.updated += 1 }
        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
            let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
            return CGSize(width: sizes.reduce(0) { $0 + $1.width } + gap * CGFloat(max(0, sizes.count - 1)), height: sizes.map(\.height).max() ?? 0)
        }
        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
            var x = bounds.minX
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(size))
                x += size.width + gap
            }
        }
        nonisolated(unsafe) static var made = 0
        nonisolated(unsafe) static var updated = 0
    }

    @Observable final class Model: @unchecked Sendable {
        var gap: CGFloat = 10
        var three = false
    }

    struct Row: View {
        let model: Model
        var body: some View {
            Gapped(gap: model.gap) {
                Color.red.frame(width: 20, height: 10)._probe("a")
                Color.blue.frame(width: 20, height: 10)._probe("b")
                if model.three { Color.green.frame(width: 20, height: 10)._probe("c") }
            }
            ._probe("row")
        }
    }

    private func layout(_ r: Runtime) { r.layout(in: CGSize(width: 200, height: 100)) }

    @Test func layoutParametersTweenUnderWithAnimation() {
        let model = Model()
        let r = Runtime()
        r.mount(Row(model: model))
        layout(r)
        #expect(r.probeFrames["row"]?.width == 50 && r.probeFrames["b"]?.minX == r.probeFrames["a"]!.minX + 30)
        withAnimation(.linear(duration: 1)) { model.gap = 30 }
        layout(r)
        // The layout runs at the interpolated gap: 10 at the start, 20 half way, 30 at the end.
        #expect(r.isAnimating)
        #expect(r.probeFrames["row"]?.width == 50)
        r.advanceAnimations(elapsed: 0.5)
        layout(r)
        #expect(r.probeFrames["row"]?.width == 60 && r.probeFrames["b"]?.minX == r.probeFrames["a"]!.minX + 40)
        r.advanceAnimations(elapsed: 0.5)
        layout(r)
        #expect(r.probeFrames["row"]?.width == 70 && !r.isAnimating)
        // Without a transaction the parameter snaps.
        model.gap = 0
        layout(r)
        #expect(r.probeFrames["row"]?.width == 40 && !r.isAnimating)
    }

    @Test func cachesAreMadeOnceAndUpdated() {
        Gapped.made = 0
        Gapped.updated = 0
        let model = Model()
        let r = Runtime()
        r.mount(Row(model: model))
        layout(r)
        layout(r)
        // One cache for the node, however many passes.
        #expect(Gapped.made == 1 && Gapped.updated == 0)
        // A new view value updates the cache rather than remaking it.
        model.gap = 12
        layout(r)
        #expect(Gapped.made == 1 && Gapped.updated == 1)
        // A subview appearing updates it too.
        model.three = true
        layout(r)
        #expect(Gapped.made == 1 && Gapped.updated >= 2 && r.probeFrames["row"]?.width == 84)
    }

    @Test func gridLayoutIsALayoutValue() {
        let r = Runtime()
        r.mount(AnyLayout(GridLayout(horizontalSpacing: 10, verticalSpacing: 6)) {
            GridRow {
                Color.red.frame(width: 40, height: 20)._probe("a")
                Color.blue.frame(width: 60, height: 30)._probe("b")
            }
            GridRow {
                Color.green.frame(width: 20, height: 10)._probe("c")
                Color.gray.frame(width: 20, height: 10)._probe("d")
            }
            Color.orange.frame(height: 8)._probe("wide")
        }._probe("grid"))
        r.layout(in: CGSize(width: 200, height: 100))
        let grid = r.probeFrames["grid"]!, a = r.probeFrames["a"]!, b = r.probeFrames["b"]!, c = r.probeFrames["c"]!, wide = r.probeFrames["wide"]!
        // The flexible orange view spans both columns and takes the 200: the 90 of extra spreads
        // equally, so the columns are 85 and 105 with a 10 gap; cells centre in them; rows 6 apart.
        #expect(grid.width == 200 && wide.width == 200, "\(grid) \(wide)")
        #expect(a.midX == 42.5 && b.midX == 85 + 10 + 52.5, "\(a) \(b)")
        #expect(c.midX == a.midX, "\(a) \(c)")
        #expect(c.minY == b.maxY + 6 && wide.minY == c.maxY + 6)
        var spacing = GridLayout(horizontalSpacing: 4, verticalSpacing: nil)
        spacing.animatableData = AnimatablePair(8, -1)
        #expect(spacing.horizontalSpacing == 8 && spacing.verticalSpacing == nil)
    }
}
#endif
