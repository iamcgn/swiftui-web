// Animatable views and AnimatableModifier: a change of their animatable data under an animation
// re-evaluates the body each frame with the data interpolated; without one the data jumps; a
// change mid-flight starts from what is on screen.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct AnimatableBodyTests {
    @Observable final class Model: @unchecked Sendable {
        var width: CGFloat = 40
        var progress: CGFloat = 0
    }

    /// A view whose width is its animatable data.
    struct Bar: View, Animatable {
        var width: CGFloat
        nonisolated var animatableData: CGFloat {
            get { width }
            set { width = newValue }
        }
        var body: some View { Color.red.frame(width: width, height: 10)._probe("bar") }
    }

    struct Bars: View {
        let model: Model
        var body: some View { Bar(width: model.width) }
    }

    /// A modifier that widens its content by its progress.
    struct Grow: AnimatableModifier {
        var progress: CGFloat
        nonisolated var animatableData: CGFloat {
            get { progress }
            set { progress = newValue }
        }
        func body(content: Content) -> some View { content.frame(width: 40 + progress * 100, height: 10)._probe("grown") }
    }

    struct Grown: View {
        let model: Model
        var body: some View { Color.blue.modifier(Grow(progress: model.progress)) }
    }

    /// A shape whose animatable data is how much of its width it fills.
    struct Fill: Shape {
        var fraction: CGFloat
        nonisolated var animatableData: CGFloat {
            get { fraction }
            set { fraction = newValue }
        }
        nonisolated func path(in rect: CGRect) -> Path { Path(CGRect(x: 0, y: 0, width: rect.width * fraction, height: rect.height)) }
    }

    private func runtime<V: View>(_ view: V) -> Runtime {
        let runtime = Runtime()
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 320, height: 200))
        return runtime
    }

    private func relayout(_ r: Runtime) { r.layout(in: CGSize(width: 320, height: 200)) }
    private func tick(_ r: Runtime, _ seconds: Double) {
        r.advanceAnimations(elapsed: seconds)
        relayout(r)
    }

    @Test func animatableViewsInterpolateTheirData() {
        let model = Model()
        let r = runtime(Bars(model: model))
        #expect(r.probeFrames["bar"]?.width == 40)
        withAnimation(.linear(duration: 1)) { model.width = 140 }
        relayout(r)
        #expect(r.probeFrames["bar"]?.width == 40)
        tick(r, 0.5)
        #expect(r.probeFrames["bar"]?.width == 90)
        tick(r, 0.6)
        #expect(r.probeFrames["bar"]?.width == 140)
        // Finished: the body is no longer evaluated per frame.
        #expect(!r.advanceAnimations(elapsed: 0.1))
    }

    @Test func changesWithoutAnimationJump() {
        let model = Model()
        let r = runtime(Bars(model: model))
        model.width = 140
        relayout(r)
        #expect(r.probeFrames["bar"]?.width == 140)
        #expect(!r.advanceAnimations(elapsed: 0.1))
    }

    @Test func aChangeMidFlightStartsFromWhatIsShown() {
        let model = Model()
        let r = runtime(Bars(model: model))
        withAnimation(.linear(duration: 1)) { model.width = 140 }
        relayout(r)
        tick(r, 0.5)
        #expect(r.probeFrames["bar"]?.width == 90)
        withAnimation(.linear(duration: 1)) { model.width = 40 }
        relayout(r)
        tick(r, 0.5)
        #expect(r.probeFrames["bar"]?.width == 65)
        tick(r, 0.6)
        #expect(r.probeFrames["bar"]?.width == 40)
    }

    @Test func animatableModifiersInterpolateTheirData() {
        let model = Model()
        let r = runtime(Grown(model: model))
        #expect(r.probeFrames["grown"]?.width == 40)
        withAnimation(.linear(duration: 1)) { model.progress = 1 }
        relayout(r)
        tick(r, 0.25)
        #expect(r.probeFrames["grown"]?.width == 65)
        tick(r, 1)
        #expect(r.probeFrames["grown"]?.width == 140)
        #expect(!r.advanceAnimations(elapsed: 0.1))
    }

    @Test func onlyAnimatableTypesGetTheAnimatableNodes() {
        let runtime = Runtime()
        #expect(runtime.mount(Bar(width: 40)) is AnimatableBodyNode<Bar>)
        #expect(runtime.mount(Fill(fraction: 0.5)) is AnimatableBodyNode<Fill>)
        #expect(runtime.mount(Bars(model: Model())) is CompositeNode<Bars>)
        // A shape with nothing to interpolate stays a plain composite.
        #expect(runtime.mount(Circle()) is CompositeNode<Circle>)
    }
}
#endif
