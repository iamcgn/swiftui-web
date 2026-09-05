// symbolEffect: indefinite effects run while active on the animation clock, discrete ones play
// once per value change, effects removed stop.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct SymbolEffectTests {
    @Observable final class Model: @unchecked Sendable {
        var active = false
        var taps = 0
    }

    private func runtime<V: View>(_ view: V) -> Runtime {
        let runtime = Runtime()
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 200, height: 100))
        return runtime
    }

    private func commands(_ r: Runtime) -> [String] { r.render(scale: 2).commands.map(\.description) }
    private func relayout(_ r: Runtime) { r.layout(in: CGSize(width: 200, height: 100)) }
    private func opacityGroups(_ r: Runtime) -> [String] { commands(r).filter { $0.hasPrefix("beginGroup(opacity:") } }
    private func concats(_ r: Runtime) -> [String] { commands(r).filter { $0.hasPrefix("concat(") } }

    struct Pulsing: View {
        let model: Model
        var body: some View { Image(systemName: "star").symbolEffect(.pulse, isActive: model.active) }
    }

    @Test func indefiniteEffectRunsWhileActive() {
        let model = Model()
        let r = runtime(Pulsing(model: model))
        #expect(opacityGroups(r).isEmpty)
        #expect(!r.advanceAnimations(elapsed: 0.1))
        model.active = true
        relayout(r)
        #expect(r.advanceAnimations(elapsed: 0.5))          // frames keep coming
        #expect(opacityGroups(r) == ["beginGroup(opacity: 0.4)"])   // dimmest half-way through the pulse
        r.advanceAnimations(elapsed: 0.5)
        #expect(opacityGroups(r).isEmpty)                    // back to full at the end of the cycle
        model.active = false
        relayout(r)
        #expect(!r.advanceAnimations(elapsed: 0.3) && opacityGroups(r).isEmpty)
    }

    struct Bouncing: View {
        let model: Model
        var body: some View { Image(systemName: "star").symbolEffect(.bounce, options: .repeat(2), value: model.taps) }
    }

    @Test func discreteEffectPlaysPerChange() {
        let model = Model()
        let r = runtime(Bouncing(model: model))
        #expect(concats(r).isEmpty && !r.advanceAnimations(elapsed: 0.1))
        model.taps += 1
        relayout(r)
        r.advanceAnimations(elapsed: 0.25)
        #expect(!concats(r).isEmpty)                         // mid-bounce: scaled and lifted
        r.advanceAnimations(elapsed: 0.5)
        #expect(!concats(r).isEmpty)                         // second repetition
        r.advanceAnimations(elapsed: 0.3)
        #expect(concats(r).isEmpty)                          // both plays done (2 × 0.5 s)
        #expect(!r.advanceAnimations(elapsed: 0.1))
    }

    struct Removed: View {
        let model: Model
        var body: some View {
            HStack { Image(systemName: "star").symbolEffectsRemoved() }.symbolEffect(.pulse, isActive: model.active)
        }
    }

    @Test func effectsRemovedStop() {
        let model = Model()
        model.active = true
        let r = runtime(Removed(model: model))
        #expect(!r.advanceAnimations(elapsed: 0.5) && opacityGroups(r).isEmpty)
    }
}
#endif
