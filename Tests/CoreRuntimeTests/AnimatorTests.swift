// PhaseAnimator and KeyframeAnimator: phases step under their animations on the animation
// clock, triggered runs return to the first phase, keyframe tracks evaluate per frame.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct AnimatorTests {
    @Observable final class Model: @unchecked Sendable {
        var pulses = 0
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
    private func tick(_ r: Runtime, _ seconds: Double) {
        r.advanceAnimations(elapsed: seconds)
        relayout(r)
    }

    struct Cycling: View {
        var body: some View {
            PhaseAnimator([false, true], content: { wide in
                Color.red.frame(width: wide ? 200 : 100, height: 40)._probe("box")
            }, animation: { _ in .linear(duration: 1) })
        }
    }

    @Test func phasesCycleOnTheClock() {
        let r = runtime(Cycling())
        // The first phase shows on appear; the first frame starts the step to the second.
        #expect(r.probeFrames["box"] == CGRect(x: 110, y: 80, width: 100, height: 40))
        #expect(!r.isAnimating)
        tick(r, 0.01)
        #expect(r.isAnimating)
        #expect(r.probeFrames["box"] == CGRect(x: 60, y: 80, width: 200, height: 40))
        tick(r, 0.5)
        #expect(commands(r).contains("fillRect(85, 80, 150, 40) \(Self.red)"))
        // The step ends and the next one back to the first phase starts in the same frame.
        tick(r, 0.5)
        #expect(r.probeFrames["box"] == CGRect(x: 110, y: 80, width: 100, height: 40))
        #expect(commands(r).contains("fillRect(60, 80, 200, 40) \(Self.red)"))
        tick(r, 0.5)
        #expect(commands(r).contains("fillRect(85, 80, 150, 40) \(Self.red)"))
    }

    struct Triggered: View {
        let model: Model
        var body: some View {
            Color.red.frame(width: 40, height: 40)
                .phaseAnimator([0, 1, 2], trigger: model.pulses, content: { view, phase in
                    view.padding(.leading, CGFloat(phase) * 100)._probe("padded")
                }, animation: { _ in .linear(duration: 1) })
        }
    }

    @Test func triggeredRunReturnsToTheFirstPhase() {
        let model = Model()
        let r = runtime(Triggered(model: model))
        #expect(r.probeFrames["padded"] == CGRect(x: 140, y: 80, width: 40, height: 40))
        #expect(!r.isAnimating)
        model.pulses += 1
        relayout(r)
        #expect(r.isAnimating)
        #expect(r.probeFrames["padded"] == CGRect(x: 90, y: 80, width: 140, height: 40))   // phase 1: 100 pt of padding
        tick(r, 1)
        tick(r, 0.01)
        #expect(r.probeFrames["padded"] == CGRect(x: 40, y: 80, width: 240, height: 40))   // phase 2
        tick(r, 1)
        tick(r, 0.01)
        #expect(r.probeFrames["padded"] == CGRect(x: 140, y: 80, width: 40, height: 40))   // back to phase 0
        tick(r, 1)
        tick(r, 0.01)
        #expect(!r.isAnimating)
        #expect(r.probeFrames["padded"] == CGRect(x: 140, y: 80, width: 40, height: 40))
    }

    struct Values: Animatable {
        var width: CGFloat = 40
        var opacity: Double = 1
        var animatableData: AnimatablePair<CGFloat, Double> {
            get { AnimatablePair(width, opacity) }
            set { width = newValue.first; opacity = newValue.second }
        }
    }

    @Test func keyframeTimelineEvaluates() {
        let timeline = KeyframeTimeline(initialValue: Values()) {
            KeyframeTrack(\.width) {
                LinearKeyframe(140, duration: 1)
                MoveKeyframe(200)
                CubicKeyframe(100, duration: 1)
            }
            KeyframeTrack(\.opacity) {
                LinearKeyframe(0, duration: 0.5, timingCurve: .easeInOut)
                SpringKeyframe(1, duration: 0.5)
            }
        }
        #expect(timeline.duration == 2)
        #expect(timeline.value(time: 0).width == 40)
        #expect(timeline.value(time: 0.5).width == 90)
        #expect(timeline.value(time: 1).width == 200)                 // the move lands at once
        let mid = timeline.value(time: 1.5).width
        #expect(mid > 100 && mid < 200)                                // cubic descends smoothly
        #expect(timeline.value(time: 2).width == 100)
        #expect(timeline.value(time: 3).width == 100)                 // holds past the end
        #expect(abs(timeline.value(time: 0.25).opacity - 0.5) < 1e-6)
        #expect(timeline.value(time: 0.5).opacity == 0)
        #expect(abs(timeline.value(time: 1).opacity - 1) < 0.01)
        #expect(timeline.value(progress: 0.25).width == 90)
    }

    struct Keyframed: View {
        let model: Model
        var body: some View {
            Color.red.frame(width: 40, height: 40)
                .keyframeAnimator(initialValue: Values(), trigger: model.pulses, content: { view, value in
                    view.frame(width: value.width)._probe("box")
                }) { _ in
                    KeyframeTrack(\.width) {
                        LinearKeyframe(140, duration: 1)
                        LinearKeyframe(40, duration: 1)
                    }
                }
        }
    }

    @Test func keyframeAnimatorFollowsTheClock() {
        let model = Model()
        let r = runtime(Keyframed(model: model))
        #expect(r.probeFrames["box"] == CGRect(x: 140, y: 80, width: 40, height: 40))
        model.pulses += 1
        relayout(r)
        tick(r, 0.5)
        #expect(r.probeFrames["box"] == CGRect(x: 115, y: 80, width: 90, height: 40))
        tick(r, 0.5)
        #expect(r.probeFrames["box"] == CGRect(x: 90, y: 80, width: 140, height: 40))
        tick(r, 1)
        #expect(r.probeFrames["box"] == CGRect(x: 140, y: 80, width: 40, height: 40))
        // Finished: no frame subscribers remain.
        #expect(!r.advanceAnimations(elapsed: 0.1))
    }

    struct Repeating: View {
        var body: some View {
            Color.red.frame(width: 40, height: 40)
                .keyframeAnimator(initialValue: Values(), repeating: true, content: { view, value in
                    view.frame(width: value.width)._probe("box")
                }) { _ in
                    KeyframeTrack(\.width) { LinearKeyframe(140, duration: 1) }
                }
        }
    }

    @Test func repeatingKeyframesWrap() {
        let r = runtime(Repeating())
        tick(r, 0.5)
        #expect(r.probeFrames["box"] == CGRect(x: 115, y: 80, width: 90, height: 40))
        tick(r, 1)
        #expect(r.probeFrames["box"] == CGRect(x: 115, y: 80, width: 90, height: 40))
        #expect(r.advanceAnimations(elapsed: 0.1))
    }
}
#endif
