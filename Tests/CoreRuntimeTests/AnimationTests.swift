// Animation (Phase 2): curves and springs, frame tweens under withAnimation and
// animation(_:value:), opacity and colour tweens, insertion and removal transitions.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct AnimationTests {
    @Observable final class Model: @unchecked Sendable {
        var expanded = false
        var show = true
        var faded = false
        var red = true
        var inset: CGFloat = 0
    }

    static let red = "#FF383C", blue = "#0088FF"

    private func runtime<V: View>(_ view: V) -> Runtime {
        let runtime = Runtime()
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 320, height: 200))
        return runtime
    }

    private func commands(_ r: Runtime) -> [String] { r.render(scale: 2).commands.map(\.description) }
    private func relayout(_ r: Runtime) { r.layout(in: CGSize(width: 320, height: 200)) }

    @Test func curves() {
        #expect(Animation.linear(duration: 1).value(at: 0.5) == 0.5)
        let ease = Animation.easeInOut(duration: 1)
        #expect(abs(ease.value(at: 0.5) - 0.5) < 1e-6)
        #expect(ease.value(at: 0.25) < 0.25 && ease.value(at: 0.75) > 0.75)
        #expect(ease.value(at: 2) == 1 && ease.isFinished(at: 1))
        let spring = Animation.spring(response: 0.5, dampingFraction: 1)
        #expect(spring.value(at: 0) == 0)
        #expect(abs(spring.value(at: spring.duration) - 1) < 0.002)
        let bouncy = Animation.bouncy
        #expect((1...40).map { bouncy.value(at: Double($0) * bouncy.duration / 40) }.max()! > 1)   // overshoots
        let delayed = Animation.linear(duration: 1).delay(0.5).speed(2)
        #expect(delayed.value(at: 0.5) == 0 && abs(delayed.value(at: 0.75) - 0.5) < 1e-9 && delayed.isFinished(at: 1))
        let repeated = Animation.linear(duration: 1).repeatCount(2, autoreverses: true)
        #expect(abs(repeated.value(at: 1.5) - 0.5) < 1e-9 && repeated.value(at: 3) == 0)
        #expect(!Animation.linear.repeatForever().isFinished(at: 100))
    }

    struct Growing: View {
        let model: Model
        var body: some View {
            VStack(spacing: 8) {
                Color.red.frame(width: model.expanded ? 200 : 100, height: 40)._probe("box")
                Text("Below")
            }
        }
    }

    @Test func framesTweenUnderWithAnimation() {
        let model = Model()
        let r = runtime(Growing(model: model))
        withAnimation(.linear(duration: 1)) { model.expanded = true }
        relayout(r)
        // Probes report the target; painting starts from the old frame and interpolates.
        #expect(r.probeFrames["box"] == CGRect(x: 60, y: 76, width: 200, height: 40))
        #expect(r.isAnimating)
        #expect(commands(r).contains("fillRect(110, 76, 100, 40) \(Self.red)"))
        r.advanceAnimations(elapsed: 0.5)
        #expect(commands(r).contains("fillRect(85, 76, 150, 40) \(Self.red)"))
        r.advanceAnimations(elapsed: 0.5)
        #expect(commands(r).contains("fillRect(60, 76, 200, 40) \(Self.red)"))
        #expect(!r.isAnimating)
        // Without a transaction the change snaps.
        model.expanded = false
        relayout(r)
        #expect(!r.isAnimating && commands(r).contains("fillRect(110, 76, 100, 40) \(Self.red)"))
    }

    /// Nonisolated code animates, as combine-schedulers' animated schedulers do.
    nonisolated static func animateFromNonisolatedCode(_ change: () -> Void) {
        withAnimation(.linear(duration: 1), change)
    }

    @Test func withAnimationIsCallableFromNonisolatedCode() {
        let model = Model()
        let r = runtime(Growing(model: model))
        Self.animateFromNonisolatedCode { model.expanded = true }
        relayout(r)
        #expect(r.isAnimating)
        r.advanceAnimations(elapsed: 0.5)
        #expect(commands(r).contains("fillRect(85, 76, 150, 40) \(Self.red)"))
    }

    struct Scoped: View {
        let model: Model
        var body: some View {
            HStack(spacing: 0) {
                Color.red.frame(width: 40, height: 40)._probe("plain")
                Color.blue.frame(width: 40, height: 40).padding(.leading, model.inset).animation(.linear(duration: 1), value: model.inset)._probe("moved")
            }
        }
    }

    @Test func implicitAnimationScopesItsSubtree() {
        let model = Model()
        let r = runtime(Scoped(model: model))
        model.inset = 100
        relayout(r)
        #expect(r.isAnimating)
        // The row re-centres and the red box (outside the scope) snaps to 70 with it; the blue
        // box's own frame tweens from 0 to 100 inside its padding, so it starts at 70 + 40.
        let painted = commands(r)
        #expect(painted.contains("fillRect(70, 80, 40, 40) \(Self.red)"))
        #expect(painted.contains("fillRect(110, 80, 40, 40) \(Self.blue)"))
        r.advanceAnimations(elapsed: 1)
        #expect(commands(r).contains("fillRect(210, 80, 40, 40) \(Self.blue)"))
    }

    struct Fading: View {
        let model: Model
        var body: some View {
            (model.red ? Color.red : Color.blue).frame(width: 40, height: 40).opacity(model.faded ? 0.2 : 1)
        }
    }

    @Test func opacityAndColourTween() {
        let model = Model()
        let r = runtime(Fading(model: model))
        withAnimation(.linear(duration: 1)) { model.faded = true; model.red = false }
        relayout(r)
        r.advanceAnimations(elapsed: 0.5)
        let painted = commands(r)
        #expect(painted.contains("beginGroup(opacity: 0.6)"))
        #expect(painted.contains { $0.hasPrefix("fillRect(140, 80, 40, 40) #80609E") })   // halfway from red to blue
        r.advanceAnimations(elapsed: 0.5)
        #expect(commands(r).contains("beginGroup(opacity: 0.2)") && !r.isAnimating)
    }

    struct Sliding: View {
        let model: Model
        var body: some View {
            VStack(spacing: 0) {
                Color.blue.frame(width: 40, height: 16)
                if model.show { Color.red.frame(width: 40, height: 40).transition(.move(edge: .leading))._probe("box") }
            }
        }
    }

    struct Vanishing: View {
        let model: Model
        var body: some View { VStack { if model.show { Text("Gone") } } }
    }

    @Test func transitionsInsertAndRemoveWithGhosts() {
        let model = Model()
        let r = runtime(Sliding(model: model))
        withAnimation(.linear(duration: 1)) { model.show = false }
        relayout(r)
        // Removed from layout at once (no probe), still painted as a ghost sliding out: the stack
        // shrinks from 56 to 16 tall (tweening through 36 at 82), the ghost keeps its place 16
        // below the stack's top and is half its width to the left.
        #expect(r.probeFrames["box"] == nil)
        r.advanceAnimations(elapsed: 0.5)
        var painted = commands(r)
        #expect(painted.contains("fillRect(120, 98, 40, 40) \(Self.red)"))
        r.advanceAnimations(elapsed: 0.5)
        #expect(!commands(r).contains { $0.contains(Self.red) } && !r.isAnimating)
        // Insertion slides in from the removed side while the stack grows back.
        withAnimation(.linear(duration: 1)) { model.show = true }
        relayout(r)
        painted = commands(r)
        #expect(painted.contains("fillRect(100, 108, 40, 40) \(Self.red)"))
        r.advanceAnimations(elapsed: 1)
        #expect(commands(r).contains("fillRect(140, 88, 40, 40) \(Self.red)") && !r.isAnimating)
        // A plain removal under an animation fades out.
        let fading = Model()
        let f = runtime(Vanishing(model: fading))
        withAnimation(.linear(duration: 1)) { fading.show = false }
        relayout(f)
        f.advanceAnimations(elapsed: 0.25)
        #expect(commands(f).contains("beginGroup(opacity: 0.75)"))
    }

    struct ClearButton: View {
        let model: Model
        let symbol: Bool
        var body: some View {
            VStack {
                if model.show {
                    HStack {
                        if symbol { Image(systemName: "xmark") }
                        Text("Clear")
                    }
                    .transition(.symbolEffect)
                }
            }
        }
    }

    // `symbolEffect` scales and fades the symbol images in the view, each about its own centre;
    // the text beside the symbol (and a view with no symbol) stays as it is until it leaves.
    @Test func symbolEffectTransitionsMoveOnlyTheSymbols() {
        let model = Model()
        let r = runtime(ClearButton(model: model, symbol: true))
        #expect(!commands(r).contains { $0.hasPrefix("beginGroup(") })
        withAnimation(.linear(duration: 1)) { model.show = false }
        relayout(r)
        r.advanceAnimations(elapsed: 0.5)
        var painted = commands(r)
        #expect(painted.filter { $0.hasPrefix("beginGroup(") } == ["beginGroup(opacity: 0.5)"], "\(painted)")
        #expect(painted.filter { $0.hasPrefix("concat(") }.count == 1 && painted.contains { $0.hasPrefix("concat(0.5, 0, 0, 0.5") }, "\(painted)")
        // The group and the scale close before the text draws.
        let text = painted.firstIndex { $0.hasPrefix("drawText(\"Clear") } ?? -1
        let close = painted.lastIndex { $0 == "endGroup" } ?? .max
        #expect(close < text, "\(painted)")
        r.advanceAnimations(elapsed: 0.5)
        #expect(!commands(r).contains { $0.hasPrefix("drawText(\"Clear") } && !r.isAnimating)
        // Inserted, the symbol grows in from nothing.
        withAnimation(.linear(duration: 1)) { model.show = true }
        relayout(r)
        painted = commands(r)
        #expect(painted.contains { $0.hasPrefix("drawText(\"Clear") } && !painted.contains { $0.hasPrefix("beginGroup(") && $0 != "beginGroup(opacity: 0.0)" })
        r.advanceAnimations(elapsed: 0.25)
        #expect(commands(r).contains("beginGroup(opacity: 0.25)"))
        // With no symbol inside, nothing fades or scales.
        let plain = Model()
        let p = runtime(ClearButton(model: plain, symbol: false))
        withAnimation(.linear(duration: 1)) { plain.show = false }
        relayout(p)
        p.advanceAnimations(elapsed: 0.5)
        painted = commands(p)
        #expect(!painted.contains { $0.hasPrefix("beginGroup(") || $0.hasPrefix("concat(") } && painted.contains { $0.hasPrefix("drawText(\"Clear") }, "\(painted)")
    }
}
#endif
