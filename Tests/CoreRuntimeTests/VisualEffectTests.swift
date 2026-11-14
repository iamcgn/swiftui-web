// visualEffect and scrollTransition: the effects paint from the view's geometry and leave its
// layout alone, follow a scroll without a new layout, and a scroll transition's phase follows the
// view's place in the scroll view (interactively, or switching with an animation at a threshold).
import Testing
import SwiftUI
import SwiftUIWebCore

#if !os(WASI)
@Suite @MainActor struct VisualEffectTests {
    private func commands(_ r: Runtime) -> [DisplayCommand] { r.render(scale: 2).commands }

    private func opacities(_ r: Runtime) -> [Double] {
        commands(r).compactMap { if case .beginGroup(let opacity) = $0 { return opacity } else { return nil } }.sorted()
    }

    private func translations(_ r: Runtime) -> [CGPoint] {
        commands(r).compactMap { if case .concat(let t) = $0 { return CGPoint(x: t.tx, y: t.ty) } else { return nil } }
    }

    private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.01 }

    @Test func aVisualEffectPaintsFromTheViewsSizeAndLeavesLayoutAlone() {
        let r = Runtime()
        r.mount(VStack(spacing: 0) {
            Color.red.frame(width: 100, height: 40)
                .visualEffect { content, proxy in content.offset(y: proxy.size.height).opacity(0.5) }
                ._probe("moved")
            Color.blue.frame(width: 100, height: 40)._probe("below")
        })
        r.layout(in: CGSize(width: 100, height: 200))
        #expect(r.probeFrames["moved"]?.height == 40)
        #expect(r.probeFrames["below"]?.minY == (r.probeFrames["moved"]?.maxY ?? 0))
        #expect(opacities(r) == [0.5])
        #expect(translations(r).contains { $0.x == 0 && $0.y == 40 })
    }

    @Test func aVisualEffectFollowsTheScrollWithoutALayout() {
        let r = Runtime()
        r.mount(ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<10, id: \.self) { i in
                    if i == 5 {
                        Color.red.frame(height: 30).visualEffect { content, proxy in content.offset(x: proxy.frame(in: .scrollView).minY) }
                    } else {
                        Color.blue.frame(height: 30)
                    }
                }
            }
        })
        let size = CGSize(width: 100, height: 200)
        r.layout(in: size)
        #expect(translations(r).contains { $0.x == 150 })
        let generation = r.layoutGeneration
        r.scrollWheel(by: CGSize(width: 0, height: 50), at: CGPoint(x: 50, y: 50))
        r.layout(in: size)
        #expect(r.layoutGeneration == generation)
        #expect(translations(r).contains { $0.x == 100 }, "\(translations(r))")
    }

    /// Rows 30 high in a 100-high scroll view; rows 0 and 3 have the transition.
    private struct Rows: View {
        let configuration: ScrollTransitionConfiguration
        let edge: Double
        var body: some View {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(0..<10, id: \.self) { i in
                        if i == 0 || i == 3 {
                            Color.red.frame(height: 30).scrollTransition(configuration) { content, phase in
                                content.opacity(phase.isIdentity ? 1 : edge)
                            }
                        } else {
                            Color.blue.frame(height: 30)
                        }
                    }
                }
            }
        }
    }

    @Test func anInteractiveTransitionFollowsTheViewAcrossTheEdge() {
        let r = Runtime()
        r.mount(Rows(configuration: .interactive(timingCurve: .linear), edge: 0))
        let size = CGSize(width: 100, height: 100)
        r.layout(in: size)
        // Row 3 (90 to 120) is two thirds past the bottom edge; row 0 is in view.
        var faded = opacities(r)
        #expect(faded.count == 1 && near(faded[0], 1.0 / 3), "\(faded)")
        // Scrolled 10: row 0 (-10 to 20) and row 3 (80 to 110) are each a third out.
        let generation = r.layoutGeneration
        r.scrollWheel(by: CGSize(width: 0, height: 10), at: CGPoint(x: 50, y: 50))
        r.layout(in: size)
        #expect(r.layoutGeneration == generation)
        faded = opacities(r)
        #expect(faded.count == 2 && faded.allSatisfy { near($0, 2.0 / 3) }, "\(faded)")
    }

    @Test func anAnimatedTransitionSwitchesAtItsThreshold() {
        let r = Runtime()
        r.mount(Rows(configuration: .animated(.linear(duration: 1)).threshold(.visible(0.5)), edge: 0.5))
        let size = CGSize(width: 100, height: 100)
        r.layout(in: size)
        // Row 3 is less than half visible: in its bottom-trailing phase from the start.
        #expect(opacities(r) == [0.5])
        // Scrolled 30, row 3 (60 to 90) is in view: its phase animates back to identity.
        r.scrollWheel(by: CGSize(width: 0, height: 30), at: CGPoint(x: 50, y: 50))
        r.layout(in: size)
        #expect(opacities(r).contains(0.5))
        r.advanceAnimations(elapsed: 0.5)
        #expect(opacities(r).contains { near($0, 0.75) }, "\(opacities(r))")
        r.advanceAnimations(elapsed: 0.6)
        r.layout(in: size)
        #expect(!opacities(r).contains { near($0, 0.75) }, "\(opacities(r))")
    }

    @Test func theIdentityConfigurationNeverTransitions() {
        let r = Runtime()
        r.mount(Rows(configuration: .identity, edge: 0.5))
        r.layout(in: CGSize(width: 100, height: 100))
        #expect(opacities(r).isEmpty)
    }

    @Test func phasesReadAsTheirValues() {
        #expect(ScrollTransitionPhase.topLeading.value == -1 && ScrollTransitionPhase.bottomTrailing.value == 1)
        #expect(ScrollTransitionPhase.identity.isIdentity && !ScrollTransitionPhase.topLeading.isIdentity)
    }
}
#endif
